"""Step 4's score: speech-to-text options on your 30 recorded commands (from record_commands), both mics.

  assistant/.venv/bin/python -m assistant.bench.stt_eval ~/room-stt-test/<time>
  … --engines parakeet,whisper-turbo          (just some of them)

On the Surface itself (free, offline):  parakeet (NVIDIA Parakeet TDT 0.6B v3, int8) · whisper-small ·
whisper-turbo (Whisper large-v3-turbo, int8). Online (only if their key is in ~/.config/room/config.json):
assemblyai ("assemblyaiKey", Universal-3.6 Pro realtime, streamed as live audio) · sarvam ("sarvamKey").

Reports per engine and mic: word error rate over all 30, how many came out exactly right, the median time to
the words after you'd finished (for the Surface ones: how long the Surface took), and every miss side by side.
The first run downloads the Surface models (~0.6–1.6 GB each) into ~/.cache.
"""
import json
import os
import re
import statistics
import time
import wave

import numpy as np

CFG = json.load(open(os.path.expanduser("~/.config/room/config.json"))) if os.path.exists(
    os.path.expanduser("~/.config/room/config.json")) else {}
KEYTERMS = ["Alexa", "Aviral", "Arpit", "Arijit Singh", "Prateek Kuhad", "Diljit Dosanjh", "Kabira", "Spotify", "lo-fi"]

ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()


def num(n: int) -> str:
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    return str(n)


def norm(s: str) -> list[str]:
    s = s.lower().replace("%", " percent ").replace("-", " ").replace("’", "'")
    s = re.sub(r"(\d+):(\d\d)", lambda m: f"{m.group(1)} {m.group(2)}", s)
    s = re.sub(r"\d+", lambda m: " " + num(int(m.group())) + " ", s)
    s = re.sub(r"\b(a\.?m\.?|p\.?m\.?)\b", " ", s)
    s = re.sub(r"[^a-z ]", " ", s.replace("'", ""))          # "Aviral's" = "Avirals"
    return s.split()


def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)], len(r)


def load(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")


# ---------------------------------------------------------------- the engines: path → (text, seconds after you stopped)
def parakeet():
    import onnx_asr
    m = onnx_asr.load_model("nemo-parakeet-tdt-0.6b-v3", quantization="int8")
    def run(path):
        t = time.time(); txt = m.recognize(path); return str(txt), time.time() - t
    return run


def whisper(size):
    def make():
        from faster_whisper import WhisperModel
        m = WhisperModel(size, device="cpu", compute_type="int8", cpu_threads=4)
        def run(path):
            t = time.time()
            segs, _ = m.transcribe(path, language="en", beam_size=1, vad_filter=True,
                                   initial_prompt="Smart home commands: " + ", ".join(KEYTERMS) + ".")
            txt = " ".join(s.text.strip() for s in segs)
            return txt, time.time() - t
        return run
    return make


def assemblyai():
    key = CFG.get("assemblyaiKey")
    if not key:
        return None
    from urllib.parse import quote
    from websockets.sync.client import connect
    def run(path):
        a = load(path)
        url = ("wss://streaming.assemblyai.com/v3/ws?sample_rate=16000&encoding=pcm_s16le&format_turns=true"
               "&speech_model=" + CFG.get("assemblyaiModel", "universal-3-6-pro") +
               "&keyterms_prompt=" + quote(json.dumps(KEYTERMS)))
        out, finals = [], {}
        with connect(url, additional_headers={"Authorization": key}, open_timeout=10) as ws:
            step = 800                                   # 50 ms, sent in real time like a live mic
            for i in range(0, len(a), step):
                ws.send(a[i:i + step].tobytes())
                time.sleep(0.05)
            stopped = time.time()
            ws.send(json.dumps({"type": "Terminate"}))
            while True:
                try:
                    m = json.loads(ws.recv(timeout=8))
                except Exception:
                    break
                if m.get("type") == "Turn" and m.get("end_of_turn"):
                    finals[m.get("turn_order", len(finals))] = m.get("transcript", "")
                if m.get("type") == "Termination":
                    break
                if m.get("type") == "Error" or m.get("error"):
                    raise RuntimeError(str(m)[:200])
        out = " ".join(finals[k] for k in sorted(finals))
        return out, time.time() - stopped
    return run


def sarvam():
    key = CFG.get("sarvamKey") or (CFG.get("voiceSettings") or {}).get("sarvamKey")
    if not key:
        return None
    import requests
    def run(path):
        t = time.time()
        r = requests.post("https://api.sarvam.ai/speech-to-text", headers={"api-subscription-key": key},
                          files={"file": open(path, "rb")},
                          data={"model": "saarika:v2.5", "language_code": "en-IN"}, timeout=30)
        return (r.json().get("transcript") or f"[{r.status_code}]"), time.time() - t
    return run


ENGINES = {"parakeet": parakeet, "whisper-small": whisper("small"), "whisper-turbo": whisper("large-v3-turbo"),
           "assemblyai": assemblyai, "sarvam": sarvam}


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", nargs="?")
    ap.add_argument("--engines", default=",".join(ENGINES))
    o = ap.parse_args()
    folder = os.path.expanduser(o.folder) if o.folder else sorted(
        __import__("glob").glob(os.path.expanduser("~/room-stt-test/*")))[-1]
    names = o.engines.split(",")
    refs = json.load(open(os.path.join(folder, "commands.json")))
    print(f"Recordings: {folder} · {len(refs)} commands\n")
    table = []
    for name in names:
        try:
            run = ENGINES[name]()
        except Exception as e:
            print(f"✗ {name}: couldn't start — {e!r}\n"); continue
        if run is None:
            print(f"– {name}: no key in config.json, skipped\n"); continue
        for mic in ("ns", "raw"):
            errs = words = exact = 0
            times, misses = [], []
            for i, ref in enumerate(refs):
                f = os.path.join(folder, f"{i:02d}_{mic}.wav")
                if not os.path.exists(f):
                    continue
                try:
                    hyp, sec = run(f)
                except Exception as e:
                    hyp, sec = f"[error {e!r}]"[:80], 0.0
                e, n = wer(ref, hyp)
                errs += e; words += n; times.append(sec); exact += e == 0
                if e:
                    misses.append(f"     {ref}  →  {hyp}")
            if not words:
                continue
            w = 100 * errs / words
            table.append((name, mic, w, exact, len(times), statistics.median(times)))
            print(f"{name:14s} {'noise-suppressed' if mic == 'ns' else 'raw mic':16s} WER {w:5.1f}% · "
                  f"{exact}/{len(times)} exactly right · median {statistics.median(times):.2f} s")
            print("\n".join(misses) + "\n" if misses else "")
    if table:
        print("Summary (lower WER is better):")
        for name, mic, w, exact, n, t in sorted(table, key=lambda r: r[2]):
            print(f"  {name:14s} {mic:4s}  WER {w:5.1f}%  {exact:2d}/{n} exact  {t:.2f} s")


if __name__ == "__main__":
    main()
