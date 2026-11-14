"""Record your character voice for Room, one line at a time, on the Surface's own microphone — the files come out
named and matched to their lines, the way Piper's training wants them (LJSpeech: wavs/0001.wav … and metadata.csv).

  cd ~/room && assistant/.venv/bin/python -m assistant.voice.record

For each line: Enter starts, Enter stops; it plays the take back; then Enter keeps it, r redoes it, p plays it again.
Before recording: s skips the line, b goes back one, g 120 goes to line 120, q stops (you can carry on later — it starts
at the first line not yet recorded). Recordings go to ~/voice-recordings (nothing in Room changes).

Keep the same room, distance (about 30 cm from the Surface), energy and character in every take. No music.
"""
import os
import subprocess
import sys
import tempfile
import time
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
LINES = os.path.join(HERE, "lines.txt")
OUT = os.path.expanduser(os.environ.get("VOICE_DIR", "~/voice-recordings"))
RATE = 22050                                     # Piper's medium voices
FAKE = os.environ.get("FAKE") == "1"             # (checks without a microphone)


def lines():
    out = []
    for row in open(LINES, encoding="utf-8"):
        if "|" in row:
            i, t = row.rstrip("\n").split("|", 1)
            out.append((i, t))
    return out


def wav_path(i):
    return os.path.join(OUT, "wavs", f"{i}.wav")


def record():
    """Records until Enter; returns the samples (float, -1…1)."""
    if FAKE:
        input(); t = np.arange(int(RATE * 2.5)) / RATE
        x = 0.3 * np.sin(2 * np.pi * 180 * t) * (np.abs(np.sin(2 * np.pi * 2 * t)) > 0.2)
        return np.concatenate([np.zeros(RATE // 2), x, np.zeros(RATE // 2)]).astype(np.float32)
    f = tempfile.NamedTemporaryFile(suffix=".raw", delete=False); f.close()
    p = subprocess.Popen(["pw-record", "--rate", str(RATE), "--channels", "1", "--format", "s16", "--raw", f.name],
                         stderr=subprocess.DEVNULL)
    try:
        input()
    finally:
        time.sleep(0.25)                          # (the end of the last word)
        p.terminate(); p.wait(3)
    x = np.fromfile(f.name, dtype="<i2").astype(np.float32) / 32768
    os.unlink(f.name)
    return x


def trim(x):
    """The silence before and after taken off (a little kept), the Enter key's click with it."""
    n = int(RATE * 0.02)
    if len(x) < n * 4:
        return x, 0.0
    e = np.sqrt(np.convolve(x ** 2, np.ones(n) / n, mode="same"))
    floor = np.percentile(e, 10)
    on = np.where(e > max(floor * 4, 0.01))[0]
    if not len(on):
        return x[:0], 0.0
    a = max(0, on[0] - int(RATE * 0.15)); b = min(len(x), on[-1] + int(RATE * 0.25))
    a = max(a, int(RATE * 0.12))                  # (the click of the Enter that started it)
    return x[a:b], float(np.abs(x).max())


def play(x):
    if FAKE or not len(x):
        return
    f = tempfile.NamedTemporaryFile(suffix=".wav", delete=False); f.close()
    save(f.name, x)
    subprocess.run(["pw-play", f.name], stderr=subprocess.DEVNULL)
    os.unlink(f.name)


def save(p, x):
    with wave.open(p, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def write_metadata(ls):
    rows = [f"{i}|{t}" for i, t in ls if os.path.exists(wav_path(i))]
    with open(os.path.join(OUT, "metadata.csv"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + ("\n" if rows else ""))
    return len(rows)


def main():
    was = None
    if not FAKE:                                  # playback as loud as Room's answers (the speaker put back after)
        try:
            was = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True).stdout.split()[1]
            subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.86"])
        except Exception:
            was = None
    try:
        session()
    finally:
        if was:
            subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", was])


def session():
    ls = lines()
    os.makedirs(os.path.join(OUT, "wavs"), exist_ok=True)
    k = next((n for n, (i, _) in enumerate(ls) if not os.path.exists(wav_path(i))), len(ls))
    print(__doc__.split("\n\n")[1] + "\n", flush=True)
    while 0 <= k < len(ls):
        i, t = ls[k]
        done = sum(os.path.exists(wav_path(j)) for j, _ in ls)
        mark = " (recorded — Enter records it again)" if os.path.exists(wav_path(i)) else ""
        print(f"\n[{k + 1}/{len(ls)} · {done} done]{mark}\n   {t}\n", flush=True)
        c = input("   Enter: record · s skip · b back · g N go to · q stop  ").strip().lower()
        if c == "q":
            break
        if c == "s":
            k += 1; continue
        if c == "b":
            k = max(0, k - 1); continue
        if c.startswith("g"):
            try:
                k = max(0, min(len(ls) - 1, int(c[1:].strip()) - 1))
            except ValueError:
                pass
            continue
        while True:
            print("   ● recording — Enter to stop", flush=True)
            x, peak = trim(record())
            secs = len(x) / RATE
            warn = ("  ⚠ nothing heard" if secs < 0.3 else "  ⚠ too loud (it clipped) — a little further away" if peak > 0.97
                    else "  ⚠ quite quiet — a little closer or louder" if peak < 0.08 else "")
            print(f"   {secs:.1f} s{warn}", flush=True)
            play(x)
            a = input("   Enter: keep · r redo · p play again  ").strip().lower()
            while a == "p":
                play(x); a = input("   Enter: keep · r redo · p play again  ").strip().lower()
            if a == "r":
                continue
            if secs >= 0.3:
                save(wav_path(i), x)
            break
        k += 1
    n = write_metadata(ls)
    print(f"\n{n} of {len(ls)} lines recorded · {OUT}", flush=True)


if __name__ == "__main__":
    main()
