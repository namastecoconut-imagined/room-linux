"""Can the Surface make speech itself with a light voice engine? Piper (small neural voices, built for cheap devices):
its English voices in two sizes ("low" and "medium", the size your own voice would be trained at), timed on Room's
kind of answers with Room, the cats and the assistant running — then one answer played, to hear what a Piper voice is
like (an ordinary ready-made voice, not yours). "Speed" is how long it takes over how long the speech is: 0.3 or less
is the bar (with room to spare for the cats and the rest).

Set up and run by scripts/piper-speed.sh (everything in ~/piper-test; nothing in Room changes).
"""
import os
import sys
import time
import wave

import numpy as np
import onnxruntime
from piper import PiperVoice

T = os.environ.get("PIPER_DIR") or os.path.expanduser("~/piper-test")
THREADS = int(os.environ.get("THREADS", "2"))
LINES = ["Lights at thirty.",
         "It's twenty seven degrees and partly cloudy in Bangalore right now, with rain likely around four.",
         "Ten minutes on the timer. I'll count. It's the most exciting thing I'll do all day.",
         "You have two reminders today: water the plants at six, and call the bank before it closes."]


def load(name):
    v = PiperVoice.load(os.path.join(T, name + ".onnx"))
    o = onnxruntime.SessionOptions()                    # as the assistant would run it: a few threads, no spinning
    o.intra_op_num_threads = THREADS; o.inter_op_num_threads = 1
    o.add_session_config_entry("session.intra_op.allow_spinning", "0")
    v.session = onnxruntime.InferenceSession(os.path.join(T, name + ".onnx"), sess_options=o, providers=["CPUExecutionProvider"])
    return v


def say(v, text):
    t0, first, chunks = time.perf_counter(), None, []
    for c in v.synthesize(text):
        if first is None:
            first = time.perf_counter() - t0
        chunks.append(c.audio_int16_bytes)
    took = time.perf_counter() - t0
    pcm = b"".join(chunks)
    return took, first, len(pcm) / 2 / v.config.sample_rate, pcm


def main():
    print(f"onnxruntime {onnxruntime.__version__} · {THREADS} threads", flush=True)
    sample = None
    for name in sys.argv[1:]:
        v = load(name)
        say(v, "Warm up.")
        tot_t = tot_d = 0.0
        print(f"\n— {name} ({os.path.getsize(os.path.join(T, name + '.onnx')) // 2**20} MB) —", flush=True)
        for line in LINES:
            took, first, dur, pcm = say(v, line)
            tot_t += took; tot_d += dur
            print(f"  {took:.2f} s to make {dur:.1f} s · speed {took / dur:.2f} · first sound after {first:.2f} s", flush=True)
            if name.endswith("medium") and line == LINES[1]:
                sample = (pcm, v.config.sample_rate)
        s = tot_t / tot_d
        v_ = "GO" if s <= 0.3 else "BORDERLINE" if s <= 0.5 else "NO-GO"
        print(f"  Verdict, {name}: {v_} — speed {s:.2f} over all four lines", flush=True)
    if sample:
        p = os.path.join(T, "sample.wav")
        with wave.open(p, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(sample[1]); w.writeframes(sample[0])
        print(f"\nA Piper voice (ready-made, medium size) — playing: {p}", flush=True)


if __name__ == "__main__":
    main()
