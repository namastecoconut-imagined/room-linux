"""Echo cancelling, worked out on echo_live's recordings (no new recording needed): where the music really is in the
mic, and which way of cancelling it helps — so the live canceller can be set from facts, not guesses.

  assistant/.venv/bin/python -u -m assistant.bench.echo_check ~/room-echo-live/<time>
"""
import json
import os
import sys
import wave

import numpy as np

from ..echo import LinearAEC
from ..listen import FRAME, RATE, Wake


def load(p):
    with wave.open(p) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768


def peaks(m, r, most=0.8):
    n = len(m)
    G = np.fft.rfft(m, 2 * n) * np.conj(np.fft.rfft(r, 2 * n)); G /= np.abs(G) + 1e-9
    cc = np.fft.irfft(G)[:int(most * RATE)]
    out, c = [], cc.copy()
    for _ in range(3):
        i = int(np.argmax(c)); out.append((i * 1000 // RATE, float(c[i]))); c[max(0, i - 160):i + 160] = 0
    floor = float(np.percentile(np.abs(cc), 99))
    return out, floor


def run(m, r, shift_ms, tail_ms):
    sh = int(shift_ms / 1000 * RATE)
    rr = np.concatenate([np.zeros(sh, np.float32), r])[:len(m)]
    a = LinearAEC(tail_ms=tail_ms); o = np.zeros_like(m)
    for i in range(0, len(m) - a.B + 1, a.B):
        o[i:i + a.B] = a.process(m[i:i + a.B], rr[i:i + a.B])
    return o, a.resets


def db(x):
    return 10 * np.log10(float(np.mean(x ** 2)) + 1e-12)


def main():
    folder = os.path.expanduser(sys.argv[1])
    m, r = load(os.path.join(folder, "mic.wav")), load(os.path.join(folder, "playing.wav"))
    info = json.load(open(os.path.join(folder, "info.json")))
    beeps = info["beeps"]; n = min(len(m), len(r)); m, r = m[:n], r[:n]
    print(f"{n / RATE:.0f} s · playing {db(r):.1f} dB · mic {db(m):.1f} dB")
    print("Where the music is in the mic (GCC-PHAT, 4 s windows: the three strongest delays, and the noise floor):")
    found = []
    for s in range(0, n - 4 * RATE, 4 * RATE):
        pk, fl = peaks(m[s:s + 4 * RATE], r[s:s + 4 * RATE])
        print(f"  {s // RATE:3d}–{s // RATE + 4:3d} s: " + "  ".join(f"{d:4d} ms ({v:.3f})" for d, v in pk) + f"   floor {fl:.3f}")
        found.append(pk[0][0])
    best = int(np.median(found))
    music = np.concatenate([np.arange(0, int(19 * RATE))] + [np.arange(int((b - 1.2) * RATE), int((b - 0.1) * RATE)) for b in beeps[1:]])
    music = music[music < n]
    w = Wake()

    def score(x):
        out = []
        for b in beeps:
            s, e = int((b + 0.1) * RATE), min(n, int((b + 3.9) * RATE))
            w.reset(); seg = (np.clip(x[s:e], -1, 1) * 32767).astype(np.int16)
            out.append(max(w.score(seg[k:k + FRAME]) for k in range(0, len(seg) - FRAME + 1, FRAME)))
        return out
    rows = [("raw mic", m, 0)]
    for shift, tail in ((max(0, best - 30), 200), (0, 200), (0, 600)):
        o, resets = run(m, r, shift, tail)
        rows.append((f"delay {shift} ms + {tail} ms tail", o, resets))
    print(f"\nMost windows say {best} ms. Cancelling it different ways (music between lines · Alexa per line):")
    for name, x, resets in rows:
        sc = score(x)
        print(f"  {name:26s} music {db(x[music]):6.1f} dB · caught {sum(v >= 0.5 for v in sc)}/{len(sc)} · "
              + " ".join(f"{v:.2f}" for v in sc) + (f" · {resets} restarts" if resets else ""))


if __name__ == "__main__":
    main()
