"""Which mic does Deepgram hear best? Records you from every mic at once — the Surface's plain mic, your noise-
suppressed one, Room's echo-cancelled one — and sends each recording to Deepgram the way Room does. Twice: once in
quiet, once with sound playing from the Surface (that's where echo cancelling should show). Prints how loud each one
is, whether it clipped, and what Deepgram heard. Recordings are kept in ~/room-mic-compare."""
import json
import os
import subprocess
import sys
import time

import numpy as np
import requests

RATE = 16000
SAY = "Alexa, turn off the lights. Alexa, play something chill on Spotify. Alexa, set a timer for five minutes."
OUT = os.path.expanduser("~/room-mic-compare")
HERE = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(os.path.expanduser("~/.config/room/config.json")))
KEY = cfg.get("deepgramKey", "")
sys.path.insert(0, HERE)
from ears import KEYTERMS  # noqa: E402


def sources():
    nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True).stdout or "[]")
    default = ""
    for n in nodes:
        if n.get("type") == "PipeWire:Interface:Metadata" and (n.get("props") or {}).get("metadata.name") == "default":
            for m in n.get("metadata") or []:
                if m.get("key") == "default.audio.source":
                    default = (m.get("value") or {}).get("name", "")
    out = []
    for n in nodes:
        p = (n.get("info") or {}).get("props") or {}
        if p.get("media.class") == "Audio/Source":
            out.append((p.get("node.name", ""), p.get("node.description") or p.get("node.name", "")))
    out.sort(key=lambda x: (x[0] != default, x[0]))
    return out, default


def record(names, sec, tag):
    procs = {}
    for name, _ in names:
        f = os.path.join(OUT, f"{tag}-{name.replace('/', '_')}.raw")
        procs[name] = (subprocess.Popen(f"pw-record --target '{name}' --raw --rate {RATE} --channels 1 --format s16 - "
                                        f"2>/dev/null | head -c {RATE * 2 * sec} > '{f}'", shell=True), f)
    return procs


def deepgram(pcm: bytes) -> str:
    import io, wave
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(pcm)
    p = [("model", "nova-3"), ("language", cfg.get("voiceSettings", {}).get("language", "en-IN"))] + [("keyterm", k) for k in KEYTERMS]
    r = requests.post("https://api.deepgram.com/v1/listen", params=p, data=b.getvalue(),
                      headers={"Authorization": f"Token {KEY}", "Content-Type": "audio/wav"}, timeout=30)
    try:
        return r.json()["results"]["channels"][0]["alternatives"][0]["transcript"]
    except Exception:
        return f"(error {r.status_code})"


def report(procs, tag):
    for name, (p, f) in procs.items():
        p.wait()
        b = open(f, "rb").read()
        x = np.frombuffer(b, "<i2").astype(float) / 32768 if b else np.zeros(1)
        import wave
        with wave.open(f[:-4] + ".wav", "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(b)
        os.remove(f)
        win = np.sqrt(np.mean(x[: len(x) // 1600 * 1600].reshape(-1, 1600) ** 2, 1)) if len(x) >= 1600 else np.array([0.0])
        db = lambda v: 20 * np.log10(max(v, 1e-6))
        speech, floor = np.percentile(win, 90), np.percentile(win, 10)
        clip = 100 * np.mean(np.abs(x) > 0.98)
        print(f"  {name}")
        print(f"     speech {db(speech):6.1f} dB · background {db(floor):6.1f} dB · gap {db(speech) - db(floor):4.1f} dB"
              f" · peak {np.abs(x).max():.2f}{'  · CLIPPING ' + f'{clip:.2f}%' if clip > 0.01 else ''}")
        print(f"     heard: {deepgram(b)!r}")


def main():
    os.makedirs(OUT, exist_ok=True)
    names, default = sources()
    if not names:
        print("No mics found"); return
    print("Mics:")
    for n, d in names:
        print(f"  • {d}  [{n}]{'  ← the default' if n == default else ''}")
    print()
    for tag, sound in (("quiet", False), ("with-sound", True)):
        input(f"{'Round 1 — in quiet' if not sound else 'Round 2 — with sound playing from the Surface (talk over it)'}."
              f" Press Enter, then say:\n   “{SAY}”\n")
        procs = record(names, 9, tag)
        if sound:
            for _ in range(3):
                subprocess.Popen(["pw-play", "--volume", "0.6", os.path.join(HERE, "cues", "alarm.wav")])
                time.sleep(3.0)
        print("   recording 9 s…")
        report(procs, tag)
        print()
    print(f"Recordings are in {OUT} (play one with: pw-play <file>)")


if __name__ == "__main__":
    main()
