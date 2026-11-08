"""Could recognition run on the Surface? Runs local speech models (faster-whisper, on the CPU) over what Room kept in
~/room-heard (turn it on with `room-heard on`, talk to Room a few times) and prints each one's words and time next to
what Deepgram heard. Nothing here changes Room."""
import glob
import json
import os
import time
import wave

import numpy as np
from faster_whisper import WhisperModel

MODELS = ["tiny.en", "base.en", "small.en", "distil-small.en"]
files = sorted(glob.glob(os.path.expanduser("~/room-heard/*.wav")))
if not files:
    raise SystemExit("Nothing in ~/room-heard yet — run `room-heard on` and talk to Room a few times first.")
clips = []
for f in files:
    with wave.open(f) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float32) / 32768
    try:
        dg = json.load(open(f[:-4] + ".txt")).get("full", "")
    except Exception:
        dg = ""
    clips.append((os.path.basename(f), x, dg))
print(f"{len(clips)} recordings · {sum(len(c[1]) for c in clips) / 16000:.0f} s of audio · {os.cpu_count()} CPU threads\n")
for name in MODELS:
    t = time.time()
    try:
        m = WhisperModel(name, device="cpu", compute_type="int8", cpu_threads=os.cpu_count() or 4)
    except Exception as e:
        print(f"{name}: couldn't load ({e})"); continue
    print(f"== {name}  (loaded in {time.time() - t:.1f} s)")
    total = 0.0
    for fn, x, dg in clips:
        t = time.time()
        segs, _ = m.transcribe(x, language="en", beam_size=1, vad_filter=False, without_timestamps=True,
                               initial_prompt="Alexa, turn off the lights. Play something chill on Spotify. Set a timer for five minutes. Make it cozy.")
        text = " ".join(s.text.strip() for s in segs)
        took = time.time() - t
        total += took
        print(f"  {fn}  {took:4.1f} s  local: {text!r}")
        print(f"  {'':>8}          deepgram: {dg!r}")
    print(f"  → {total / len(clips):.2f} s per request on average (Deepgram's words are ready as you finish)\n")
