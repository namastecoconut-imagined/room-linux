"""Step 2's test: does a long answer, arriving unevenly over the network, play without a single gap?

It makes 20 s of speech-like sound (a voice-pitched hum in syllables) at 24 kHz — Deepgram/Sarvam/ElevenLabs send
24 kHz — and feeds it in 50–200 ms pieces at a given speed with random hold-ups, like a slow Wi-Fi. Then it reports
how often the player ran out (starved — a short pause, by design) and how often the sound system missed a block
(xruns — a crackle; must be 0).

  .venv/bin/python -m assistant.bench.play_test                 # arriving at 1.2× real time, hold-ups to 0.25 s
  .venv/bin/python -m assistant.bench.play_test --speed 1.0 --jitter 0.4
  .venv/bin/python -m assistant.bench.play_test --old           # the old way (a pipe into pw-play), to compare
"""
import argparse
import random
import subprocess
import time

import numpy as np

RATE = 24000


def speechlike(seconds=20.0):
    t = np.arange(int(RATE * seconds)) / RATE
    pitch = 140 + 25 * np.sin(2 * np.pi * 0.7 * t)
    phase = 2 * np.pi * np.cumsum(pitch) / RATE
    x = 0.30 * np.sin(phase) + 0.15 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    syll = np.clip(np.sin(2 * np.pi * 3.3 * t), 0, None) ** 0.7 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.31 * t) ** 2)
    return (x * syll).astype(np.float32)


def pieces(x, speed, jitter, seed=1):
    """(delay before this piece, piece) — on average `speed`× real time, with random hold-ups up to `jitter` s."""
    rnd = random.Random(seed)
    i = 0
    while i < len(x):
        n = int(RATE * rnd.uniform(0.05, 0.2))
        wait = n / RATE / speed
        if rnd.random() < 0.15:
            wait += rnd.uniform(0, jitter)
        yield wait, x[i:i + n]
        i += n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speed", type=float, default=1.2)
    ap.add_argument("--jitter", type=float, default=0.25)
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--old", action="store_true")
    a = ap.parse_args()
    x = speechlike(a.seconds)
    t0 = time.time()
    if a.old:
        p = subprocess.Popen(["pw-play", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16", "-"],
                             stdin=subprocess.PIPE)
        for wait, piece in pieces(x, a.speed, a.jitter):
            time.sleep(wait)
            p.stdin.write((piece * 32767).astype("<i2").tobytes())
        p.stdin.close(); p.wait()
        print(f"old way done in {time.time() - t0:.1f} s — listen for gaps (pw-top's ERR for pw-play counts them)")
        return
    from assistant.player import Player
    pl = Player()
    pl.start()
    pl.begin()
    for wait, piece in pieces(x, a.speed, a.jitter):
        time.sleep(wait)
        pl.feed(piece, RATE)
    pl.end()
    pl.wait_done()
    time.sleep(0.3)
    s = pl.stats()
    pl.close()
    ok = s["xruns"] == 0
    print(f"{'✓' if ok else '✗'} {a.seconds:.0f} s of speech at {a.speed}× with hold-ups up to {a.jitter} s: "
          f"done in {time.time() - t0:.1f} s · ran out {s['starved']}× (short pauses) · sound-system misses {s['xruns']}")


if __name__ == "__main__":
    main()
