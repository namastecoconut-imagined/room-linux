"""Step 3's score: every wake-word engine × every mic, on the same recordings (from record_wake).

  assistant/.venv/bin/python -m assistant.bench.wake_eval ~/room-wake-test/<time>

For each recording it reports, per engine and threshold: how many of your "Alexa"s were caught (a detection within
3.8 s after the beep), and false alarms (detections anywhere else — the music-only part is all false alarms).
Also each "Alexa"'s best score, so near-misses show. Engines: openWakeWord's stock "alexa", and any LiveKit
WakeWord model (*.onnx with a `chunk` input) in assistant/models.
"""
import glob
import json
import os
import sys
import wave

import numpy as np

MODELS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")   # assistant/models
FRAME = 1280                       # 80 ms at 16 kHz
THRESHOLDS = (0.3, 0.5, 0.7)


def load(path):
    with wave.open(path) as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")


def engines():
    out = {}
    oww = os.path.join(MODELS, "alexa_v0.1.onnx")
    if os.path.exists(oww):
        def run_oww(audio):
            from openwakeword.model import Model
            m = Model(wakeword_models=[oww], inference_framework="onnx",
                      melspec_model_path=os.path.join(MODELS, "melspectrogram.onnx"),
                      embedding_model_path=os.path.join(MODELS, "embedding_model.onnx"))
            return [max(m.predict(audio[i:i + FRAME]).values()) for i in range(0, len(audio) - FRAME + 1, FRAME)]
        out["openWakeWord alexa"] = run_oww
    for f in sorted(glob.glob(os.path.join(MODELS, "*.onnx"))):
        base = os.path.basename(f)
        if base in ("alexa_v0.1.onnx", "melspectrogram.onnx", "embedding_model.onnx", "silero_vad.onnx") \
                or "alexa" not in base.lower():
            continue                # only "Alexa" models (a "hey jarvis" model can't be scored on "Alexa"s)
        def run_lk(audio, f=f):
            from livekit.wakeword import WakeWordModel
            m = WakeWordModel(models=[f])
            return [max(m.predict(audio[i:i + FRAME]).values()) for i in range(0, len(audio) - FRAME + 1, FRAME)]
        out[f"LiveKit {os.path.splitext(base)[0]}"] = run_lk
    return out


def detections(scores, thr, refractory=1.5):
    hits, last = [], -9.0
    for i, s in enumerate(scores):
        t = (i + 1) * FRAME / 16000
        if s >= thr and t - last > refractory:
            hits.append(t); last = t
    return hits


def main():
    folder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else sorted(glob.glob(os.path.expanduser("~/room-wake-test/*")))[-1]
    plan = json.load(open(os.path.join(folder, "prompts.json")))
    eng = engines()
    if not eng:
        sys.exit(f"No wake-word models in {MODELS}")
    print(f"Recordings: {folder}\n")
    summary = []
    for part in ("quiet", "music", "musiconly"):
        beeps = plan.get(part, [])
        for mic in ("raw", "ns"):
            f = os.path.join(folder, f"{part}_{mic}.wav")
            if not os.path.exists(f):
                continue
            audio = load(f)
            hours = len(audio) / 16000 / 3600
            for name, run in eng.items():
                sc = run(audio)
                best = []
                for b in beeps:
                    a, z = int((b + 0.2) * 16000 / FRAME), int((b + 3.8) * 16000 / FRAME)
                    best.append(max(sc[a:z]) if sc[a:z] else 0.0)
                line = f"{part:9s} {'raw mic' if mic == 'raw' else 'noise-suppressed':16s} {name:24s}"
                for thr in THRESHOLDS:
                    d = detections(sc, thr)
                    caught = sum(1 for b in beeps if any(b + 0.2 <= t <= b + 3.8 for t in d))
                    false = sum(1 for t in d if not any(b + 0.2 <= t <= b + 3.8 for b in beeps))
                    line += f" | ≥{thr}: " + (f"{caught:2d}/{len(beeps)} caught, " if beeps else "") + f"{false} false"
                    summary.append((part, mic, name, thr, caught, len(beeps), false, hours))
                print(line)
                if beeps:
                    print(f"{'':51s}best score per \"Alexa\": " + " ".join(f"{s:.2f}" for s in best))
        print()


if __name__ == "__main__":
    main()
