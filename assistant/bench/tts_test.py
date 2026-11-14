"""Ear test: Room's voice from Sarvam (Bulbul, streamed) next to the current one made on the Surface (Kokoro
"Heart"). The same answer in each voice, played through the assistant's own kind of speaker (player.py), with how
long each took to start talking and to finish making. Nothing in the assistant changes; it keeps running.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.tts_test
  … --text "Your own sentence"      … --only 3,5      … --no-wait (play them all without pressing Enter)

Sarvam is paid per character ("sarvamKey" in config.json): one run of every voice is about 1,400 characters, under
₹2. Press Enter between voices; the numbers are listed at the end to paste back.
"""
import argparse
import json
import os
import time

import numpy as np

TEXT = ("It's twenty seven degrees and partly cloudy in Bangalore right now, with rain likely around four. "
        "I've turned the living room down to thirty percent.")
RATE = 24000

# (model, speaker): Sarvam's English (India) voices worth hearing, then the current voice for comparison
VOICES = [
    ("bulbul:v4-flash", "simran_en_conversation"), ("bulbul:v4-flash", "ishita_en_customer"),
    ("bulbul:v4-flash", "roopa_en_conversational"), ("bulbul:v4-flash", "neha_en_customer"),
    ("bulbul:v4-flash", "amelia_en_conversational"), ("bulbul:v4-flash", "dev_en_conversational"),
    ("bulbul:v4-flash", "shubh_en_narration"), ("bulbul:v3", "ishita"), ("bulbul:v3", "shubh"),
    ("kokoro", "af_heart"),
]
PRICE = {"bulbul:v4-flash": 10, "bulbul:v3": 30}          # ₹ per 10,000 characters, pay as you go


def key():
    p = os.path.expanduser("~/.config/room/config.json")
    cfg = json.load(open(p))
    return cfg.get("sarvamKey") or (cfg.get("voiceSettings") or {}).get("sarvamKey")


def sarvam(http, k, text, model, speaker, player):
    """Streams the speech, feeding the speaker as it arrives. Returns (first audio s, all made s, audio s)."""
    t0 = time.time()
    r = http.post("https://api.sarvam.ai/text-to-speech/stream", stream=True, timeout=30,
                  headers={"api-subscription-key": k, "Content-Type": "application/json"},
                  json={"text": text, "language_code": "en-IN", "model": model, "speaker": speaker,
                        "output_audio_codec": "linear16", "speech_sample_rate": RATE, "enable_preprocessing": True})
    if r.status_code != 200:
        raise RuntimeError(f"Sarvam {r.status_code}: {r.text[:200]}")
    first, n, left, head = None, 0, b"", True
    for chunk in r.iter_content(chunk_size=4800):
        if not chunk:
            continue
        b = left + chunk
        if head:                                    # (a WAV header, if it comes with one)
            head = False
            if b[:4] == b"RIFF":
                i = b.find(b"data")
                b = b[i + 8:] if i >= 0 else b[44:]
        cut = len(b) - len(b) % 2
        left = b[cut:]
        if cut:
            if first is None:
                first = time.time() - t0
            player.feed(b[:cut], RATE)
            n += cut // 2
    return first or 0.0, time.time() - t0, n / RATE


_K = None


def kokoro(text, voice, player):
    global _K
    if _K is None:
        import onnxruntime as ort
        from kokoro_onnx import Kokoro
        d = os.path.expanduser("~/.local/share/room/assistant/kokoro")
        o = ort.SessionOptions(); o.intra_op_num_threads = max(1, (os.cpu_count() or 4) // 2 - 1); o.inter_op_num_threads = 1
        _K = Kokoro.from_session(ort.InferenceSession(os.path.join(d, "kokoro-v1.0.fp16.onnx"), sess_options=o,
                                                      providers=["CPUExecutionProvider"]), os.path.join(d, "voices-v1.0.bin"))
    t0 = time.time()
    a, sr = _K.create(text, voice=voice, speed=1.0, lang="en-us")
    took = time.time() - t0
    player.feed(np.asarray(a, dtype=np.float32), sr)
    return took, took, len(a) / sr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", default=TEXT)
    ap.add_argument("--only", default="", help="voice numbers, e.g. 1,3")
    ap.add_argument("--no-wait", action="store_true")
    a = ap.parse_args()
    import requests
    from ..player import Player
    k = key()
    if not k:
        raise SystemExit("no sarvamKey in ~/.config/room/config.json")
    only = {int(x) for x in a.only.split(",") if x.strip()}
    http = requests.Session()
    http.head("https://api.sarvam.ai/", timeout=5)          # (the connection's open before the clock starts, as in use)
    player = Player()
    player.start()
    rows = []
    print(f"“{a.text}” ({len(a.text)} characters)\n", flush=True)
    for i, (model, speaker) in enumerate(VOICES, 1):
        if only and i not in only:
            continue
        name = f"{i:2}. {speaker} ({'on the Surface, now' if model == 'kokoro' else model})"
        print(name, flush=True)
        player.begin()
        try:
            first, made, dur = (kokoro(a.text, speaker, player) if model == "kokoro"
                                else sarvam(http, k, a.text, model, speaker, player))
        except Exception as e:
            print(f"    ✗ {e}\n", flush=True); rows.append(f"{name}: failed"); continue
        player.end(); player.wait_done()
        cost = f" · ₹{len(a.text) * PRICE[model] / 10000:.2f} this answer" if model in PRICE else ""
        line = f"talking after {first:.2f} s · all made in {made:.2f} s · {dur:.1f} s of speech{cost}"
        print("    " + line, flush=True)
        rows.append(f"{name}: {line}")
        if not a.no_wait:
            input("    (Enter for the next voice) ")
        print()
    player.close()
    print("\n".join(["", "Results:"] + rows))


if __name__ == "__main__":
    main()
