"""Ear test: a "mad scientist" voice without a new service — a deep Sarvam voice, made lower and rougher on the
Surface just before it plays. Each variant says the same line; pick the one that sounds most like a cranky genius.
Nothing in the assistant changes.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.rough_test
  … --text "Your own line"      … --only 3,5      … --no-wait

How: Sarvam says the line faster (its "pace"), then it's played lower — lowering a voice slows it down, so the speed
comes back to normal and the pitch stays down (no heavy processing). Then grit: a soft overdrive (raspy), and a
little vocal fry (a fast flutter in loudness). About ₹1 for a whole run.
"""
import argparse
import json
import os
import time

import numpy as np

TEXT = "Lights at thirty. Behold my genius, applied to a light switch. Riveting work. Truly what I was built for."
RATE = 24000

# (voice, semitones down, grit 0–1, fry 0–1)
VARIANTS = [
    ("dev_en_conversational", 0, 0.0, 0.0),
    ("dev_en_conversational", 3, 0.0, 0.0),
    ("dev_en_conversational", 3, 0.5, 0.0),
    ("dev_en_conversational", 4, 0.7, 0.4),
    ("deven_en_conversation", 3, 0.6, 0.3),
    ("shubh_en_narration_gentle", 3, 0.6, 0.3),
    ("varun_en_suspense", 2, 0.5, 0.3),
    ("ojas_en_social", 4, 0.7, 0.5),
]


def key():
    cfg = json.load(open(os.path.expanduser("~/.config/room/config.json")))
    return cfg.get("sarvamKey") or (cfg.get("voiceSettings") or {}).get("sarvamKey")


def fetch(http, k, text, speaker, pace):
    r = http.post("https://api.sarvam.ai/text-to-speech/stream", timeout=30,
                  headers={"api-subscription-key": k, "Content-Type": "application/json"},
                  json={"text": text, "language_code": "en-IN", "model": "bulbul:v4-flash", "speaker": speaker,
                        "pace": round(pace, 3), "output_audio_codec": "linear16", "speech_sample_rate": RATE,
                        "enable_preprocessing": True})
    if r.status_code != 200:
        raise RuntimeError(f"Sarvam {r.status_code}: {r.text[:200]}")
    b = r.content
    if b[:4] == b"RIFF":
        i = b.find(b"data")
        b = b[i + 8:] if i >= 0 else b[44:]
    b = b[:len(b) - len(b) % 2]
    return np.frombuffer(b, dtype="<i2").astype(np.float32) / 32768


def rough(x, semis, grit, fry):
    """Lower by `semis` (x was made 2^(semis/12) faster, so the speed comes back), then overdrive and fry."""
    if semis:
        import soxr
        r = 2 ** (semis / 12)
        x = soxr.resample(x, RATE, RATE * r)              # more samples played at RATE: slower and lower
    if grit:
        d = 1 + 6 * grit
        x = np.tanh(x * d * 3) / np.tanh(d * 3) * 0.6 + x * 0.4      # raspy: the peaks folded over
        y = np.copy(x); y[1:] = x[1:] - 0.85 * x[:-1]                  # a touch more edge (the hiss of a rasp)
        x = x + 0.25 * grit * y
    if fry:
        t = np.arange(len(x)) / RATE
        x = x * (1 - 0.35 * fry * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 34 * t))) * (np.abs(x) > 0.02))
    from ..tts import Leveller
    return Leveller().whole(x.astype(np.float32))         # as loud as the assistant's answers


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", default=TEXT)
    ap.add_argument("--only", default="")
    ap.add_argument("--no-wait", action="store_true")
    a = ap.parse_args()
    import requests
    from ..player import Player
    k = key()
    if not k:
        raise SystemExit("no sarvamKey in ~/.config/room/config.json")
    only = {int(v) for v in a.only.split(",") if v.strip()}
    http = requests.Session()
    player = Player(); player.start()
    import subprocess
    from ..duck import Duck
    duck = Duck(0.86); duck.down()                        # the speaker up as for an answer (it was at the music's level)
    try:
        run(a, only, http, k, player)
    finally:
        duck.up(); time.sleep(1)
        player.close()


def run(a, only, http, k, player):
    for i, (voice, semis, grit, fry) in enumerate(VARIANTS, 1):
        if only and i not in only:
            continue
        name = voice.split("_")[0].title()
        print(f"{i}. {name} ({voice}) · {semis} semitones lower · grit {grit} · fry {fry}", flush=True)
        try:
            t0 = time.time()
            x = rough(fetch(http, k, a.text, voice, 2 ** (semis / 12)), semis, grit, fry)
            print(f"   made in {time.time() - t0:.2f} s · {len(x) / RATE:.1f} s long", flush=True)
            player.begin(); player.feed(x, RATE); player.end(); player.wait_done()
        except Exception as e:
            print(f"   ✗ {e}", flush=True)
        if not a.no_wait:
            input("   (Enter for the next one) ")


if __name__ == "__main__":
    main()
