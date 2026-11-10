"""Step 6's ear test: Room's voice. Plays the same answer in several voices, one after another, through the
assistant's own speaker (player.py), and shows how long each took to make.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.tts_test
  … --text "Your own sentence"      … --only kokoro

Voices: Sarvam Bulbul (Indian English, online, ~₹1–3 per 1,000 characters — "sarvamKey" in config.json) and Kokoro
(on the Surface, free; the first run downloads it, ~120 MB). Press Enter between voices.
"""
import argparse
import base64
import io
import json
import os
import time
import wave

import numpy as np

TEXT = ("It's twenty seven degrees and cloudy in Bangalore right now, with rain likely around six. "
        "I've turned the bedroom lights down to thirty percent.")
KDIR = os.path.expanduser("~/.local/share/room/assistant/kokoro")
KURL = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"

VOICES = [
    ("sarvam", "bulbul:v3", "priya"), ("sarvam", "bulbul:v3", "kavya"), ("sarvam", "bulbul:v3", "aditya"),
    ("sarvam", "bulbul:v3", "shubh"), ("sarvam", "bulbul:v4-flash", "simran_en_customer"),
    ("sarvam", "bulbul:v4-flash", "shubh_enhi_ads"),
    ("kokoro", "en-gb", "bf_emma"), ("kokoro", "en-us", "af_heart"), ("kokoro", "en-us", "am_michael"),
]


def sarvam(text, model, speaker, key):
    import requests
    t = time.time()
    r = requests.post("https://api.sarvam.ai/text-to-speech", headers={"api-subscription-key": key},
                      json={"text": text, "language_code": "en-IN", "model": model, "speaker": speaker,
                            "speech_sample_rate": 24000}, timeout=30)
    if r.status_code != 200:
        raise RuntimeError(f"{r.status_code} {r.text[:200]}")
    took = time.time() - t
    with wave.open(io.BytesIO(base64.b64decode(r.json()["audios"][0]))) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
        return a, w.getframerate(), took


_K = None


def kokoro(text, lang, voice):
    global _K
    if _K is None:
        import urllib.request
        os.makedirs(KDIR, exist_ok=True)
        for f in ("kokoro-v1.0.int8.onnx", "voices-v1.0.bin"):
            p = os.path.join(KDIR, f)
            if not os.path.exists(p):
                print(f"  downloading {f}…", flush=True)
                urllib.request.urlretrieve(f"{KURL}/{f}", p + ".part"); os.rename(p + ".part", p)
        from kokoro_onnx import Kokoro
        _K = Kokoro(os.path.join(KDIR, "kokoro-v1.0.int8.onnx"), os.path.join(KDIR, "voices-v1.0.bin"))
    t = time.time()
    a, sr = _K.create(text, voice=voice, speed=1.0, lang=lang)
    return np.asarray(a, dtype=np.float32), sr, time.time() - t


def speed():
    """Kokoro's two builds on this processor: int8 (smaller) vs full precision — on CPUs without int8 instructions
    (this i5) the full one can be the faster. Times the first clause alone (what decides when Room starts talking)
    and the whole answer."""
    import urllib.request
    from kokoro_onnx import Kokoro
    first = "It's twenty seven degrees and cloudy in Bangalore right now,"
    for f in ("kokoro-v1.0.int8.onnx", "kokoro-v1.0.fp16.onnx", "kokoro-v1.0.onnx"):
        p = os.path.join(KDIR, f)
        if not os.path.exists(p):
            print(f"  downloading {f}…", flush=True)
            try:
                urllib.request.urlretrieve(f"{KURL}/{f}", p + ".part"); os.rename(p + ".part", p)
            except Exception as e:
                print(f"  ✗ {f}: {e}"); continue
        k = Kokoro(p, os.path.join(KDIR, "voices-v1.0.bin"))
        k.create("Warm up.", voice="af_heart", lang="en-us")
        res = []
        for text in (first, TEXT):
            t = time.time(); a, sr = k.create(text, voice="af_heart", lang="en-us"); took = time.time() - t
            res.append(f"{took:.2f} s for {len(a) / sr:.1f} s ({len(a) / sr / took:.1f}×)")
        print(f"{f:24s} first clause {res[0]} · whole answer {res[1]}", flush=True)


def main():
    if "--speed" in __import__("sys").argv:
        return speed()
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", default=TEXT)
    ap.add_argument("--only", default="")
    ap.add_argument("--speed", action="store_true")
    o = ap.parse_args()
    cfg = json.load(open(os.path.expanduser("~/.config/room/config.json")))
    key = cfg.get("sarvamKey") or (cfg.get("voiceSettings") or {}).get("sarvamKey")
    from assistant.player import Player
    pl = Player(); pl.start()
    print(f"“{o.text}”  ({len(o.text)} characters)\n")
    for i, (eng, model, voice) in enumerate(v for v in VOICES if not o.only or v[0] == o.only):
        input(f"{i + 1}. {eng} · {model} · {voice} — Enter to play… ")
        try:
            a, sr, took = sarvam(o.text, model, voice, key) if eng == "sarvam" else kokoro(o.text, model, voice)
        except Exception as e:
            print(f"   ✗ {e}\n"); continue
        dur = len(a) / sr
        print(f"   made in {took:.2f} s for {dur:.1f} s of speech"
              + (f" ({dur / took:.1f}× faster than it plays)" if eng == "kokoro" else "") + "\n", flush=True)
        pl.begin(); pl.feed(a, sr); pl.end(); pl.wait_done(); time.sleep(0.3)
    pl.close()


if __name__ == "__main__":
    main()
