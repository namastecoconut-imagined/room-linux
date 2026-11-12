"""Does the wake word resting in a quiet room (listen.Rest) miss any "Alexa"? Replays your recorded "Alexa"s (from
record_wake, in ~/room-wake-test) through Room's own wake word twice — always listening, and resting as it does now —
and compares what each caught. Changes nothing; about two minutes.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.rest_eval [folder]

Fair to the resting one: the beep before each "Alexa" is replaced with the room's own hum from just before it (a
beep would wake it up early and make it look better than it is). And harder than life: in the quiet room, each
"Alexa" is also replayed 6 and 12 dB quieter — about two and four times as far away — with the room's hum under it
kept at its usual level (the quiet start of the recording, mixed back in), so the voice stands out less.
How much of a real day it rests shows in the assistant's own log, every 10 minutes ("wake word: listened …").
"""
import glob
import json
import os
import sys
import wave

import numpy as np

from assistant.listen import FRAME, RATE, Rest, Wake

THRESHOLD = 0.5
REFRACTORY = 2.0            # as wait_wake: a second "Alexa" within 2 s isn't a new one


def load(path):
    with wave.open(path) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32)


def prepare(audio, beeps, gain_db):
    a = audio.copy()
    g = 10 ** (gain_db / 20)
    hum = audio[: int(max(0.5, (beeps[0] if beeps else 1.5) - 0.1) * RATE)]      # the quiet room before the first beep
    for b in beeps:
        i, n = int(b * RATE), int(0.3 * RATE)
        if i - n >= 0 and i + n <= len(a):
            a[i:i + n] = a[i - n:i]                     # the beep → the room just before it
        if gain_db:
            z = min(len(a), int((b + 3.8) * RATE))
            fill = np.resize(hum, z - (i + n))          # the voice quieter, the room's hum kept at its level
            a[i + n:z] = a[i + n:z] * g + fill * np.sqrt(max(0.0, 1 - g * g))
    return np.clip(a, -32768, 32767).astype(np.int16)


def run(audio, resting):
    wake, rest = Wake(), (Rest() if resting else None)
    if rest:
        rest.again()
    hits, last = [], -9.0
    for k in range(0, len(audio) - FRAME + 1, FRAME):
        f = audio[k:k + FRAME]
        t = (k + FRAME) / RATE
        frames, fresh = rest.step(f) if rest else ([f], False)
        if fresh:
            wake.reset()
        for g in frames:
            if wake.score(g) >= THRESHOLD and t - last > REFRACTORY:
                hits.append(t); last = t; wake.reset()
                break
    return hits


def main():
    folder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else (sorted(glob.glob(os.path.expanduser("~/room-wake-test/*"))) or [""])[-1]
    if not folder or not os.path.exists(os.path.join(folder, "prompts.json")):
        sys.exit("No recordings in ~/room-wake-test — make some with: assistant/.venv/bin/python -m assistant.bench.record_wake")
    plan = json.load(open(os.path.join(folder, "prompts.json")))
    print(f"Recordings: {folder} (raw mic) · \"Alexa\" counts at {THRESHOLD}\n")
    bad = 0
    for part, label in (("quiet", "quiet room"), ("music", "music playing"), ("musiconly", "music, nobody saying it")):
        f = os.path.join(folder, f"{part}_raw.wav")
        if not os.path.exists(f):
            continue
        audio, beeps = load(f), plan.get(part, [])
        for gain in ((0, -6, -12) if part == "quiet" else (0,)):
            a = prepare(audio, beeps, gain)
            line = f"  {label:24s} {('as said' if gain == 0 else f'{-gain} dB quieter'):13s}"
            res = {}
            for resting in (False, True):
                hits = run(a, resting)
                caught = sum(1 for b in beeps if any(b + 0.2 <= t <= b + 3.8 for t in hits))
                false = sum(1 for t in hits if not any(b + 0.2 <= t <= b + 3.8 for b in beeps))
                res[resting] = (caught, false)
                line += (f" | {'resting' if resting else 'always'}: "
                         + (f"{caught:2d}/{len(beeps)} caught, " if beeps else "") + f"{false} false")
            if res[True][0] < res[False][0]:
                bad += 1; line += "   ✗ resting missed some"
            print(line, flush=True)
    print("\n" + ("✓ Resting caught every \"Alexa\" that always-listening caught." if not bad
                  else f"✗ Resting missed some in {bad} case(s) — the bars need lowering (listen.Rest)."))


if __name__ == "__main__":
    main()
