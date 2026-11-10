"""Echo cancelling, live: runs the assistant's own mic path (assistant/echo.py, exactly as the assistant does) while
music plays, records the raw mic, what it was taking out, and the cleaned mic side by side, and scores "Alexa" on
both — so when it doesn't wake over music we can see which part is at fault.

  cd ~/room && assistant/.venv/bin/python -u -m assistant.bench.echo_live

Play music at your usual volume first (on whichever speaker you use). The assistant is paused while it runs.
20 s of just music (the canceller settles in), then after each beep say "Alexa" (10×).
"""
import json
import os
import subprocess
import threading
import time
import wave

import numpy as np

from ..echo import EchoCanceller
from ..listen import FRAME, RATE, Mic, Wake
from .record_wake import beep_file

OUT = os.path.expanduser("~/room-echo-live")


def save(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(np.asarray(x, np.int16).astype("<i2").tobytes())


def main():
    folder = os.path.join(OUT, time.strftime("%Y%m%d-%H%M")); os.makedirs(folder, exist_ok=True)
    was = subprocess.run(["systemctl", "--user", "is-active", "room-assistant"], capture_output=True, text=True).stdout.strip()
    if was == "active":
        subprocess.run(["systemctl", "--user", "stop", "room-assistant"]); print("(the assistant is paused while this runs)")
    raw, clean, refd = [], [], []
    ec = EchoCanceller()
    orig = ec.process

    def process(f):                       # the same as the assistant, keeping a copy of each side
        out = orig(f)
        raw.append(f.copy()); clean.append(out.copy())
        refd.append((np.clip(ec.hist[-len(f):], -1, 1) * 32767).astype(np.int16))
        return out
    ec.process = process
    mic = Mic(0.65, echo=False); mic.echo = ec
    beeps = []
    try:
        mic.start()
        input("Play music at your usual volume, then press Enter… ")
        stop = threading.Event()

        def drain():
            while not stop.is_set():
                try: mic.q.get(timeout=0.5)
                except Exception: pass
        threading.Thread(target=drain, daemon=True).start()
        n0 = len(raw)
        for s in range(20, 0, -1):
            print(f"  just music… {s:2d} s", end="\r", flush=True); time.sleep(1)
        print()
        for i in range(10):
            beeps.append((len(raw) - n0) * FRAME / RATE)
            subprocess.run(["pw-play", "--volume", "0.5", beep_file()], stderr=subprocess.DEVNULL)
            print(f"  {i + 1:2d}/10  say \"Alexa\"", flush=True); time.sleep(4)
        time.sleep(1); stop.set(); mic.stop(); ec.close()
    finally:
        if was == "active":
            subprocess.run(["systemctl", "--user", "start", "room-assistant"]); print("(the assistant is back on)")
    r = np.concatenate(raw[n0:]); c = np.concatenate(clean[n0:]); f = np.concatenate(refd[n0:])
    save(os.path.join(folder, "mic.wav"), r); save(os.path.join(folder, "cleaned.wav"), c); save(os.path.join(folder, "playing.wav"), f)
    json.dump({"beeps": beeps, "shift_ms": ec.shift * 1000 // RATE, "taps": list(ec.taps)}, open(os.path.join(folder, "info.json"), "w"))
    db = lambda x: 10 * np.log10(float(np.mean((x.astype(np.float32) / 32768) ** 2)) + 1e-12)
    music = np.concatenate([np.arange(0, int(19 * RATE))] + [np.arange(int((b - 1.2) * RATE), int((b - 0.1) * RATE)) for b in beeps[1:]])
    music = music[music < len(r)]
    print(f"\nplaying {db(f[music]):.1f} dB · music in the mic {db(r[music]):.1f} dB → cleaned {db(c[music]):.1f} dB "
          f"· delay followed: {ec.shift * 1000 // RATE + 30} ms · outputs: {', '.join(ec.taps)}")
    w = Wake()
    for i, b in enumerate(beeps):
        s, e = int((b + 0.1) * RATE), min(len(r), int((b + 3.9) * RATE))
        sc = []
        for x in (r, c):
            w.reset(); seg = x[s:e]
            sc.append(max(w.score(seg[k:k + FRAME]) for k in range(0, len(seg) - FRAME + 1, FRAME)))
        print(f"  {i + 1:2d}  Alexa  raw mic {sc[0]:.2f}  ·  cleaned {sc[1]:.2f}")
    print(f"\nSaved in {folder} (mic.wav, cleaned.wav, playing.wav)")


if __name__ == "__main__":
    main()
