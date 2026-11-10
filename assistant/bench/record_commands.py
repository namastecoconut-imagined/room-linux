"""Step 4's recordings: 30 commands as you'd say them to Room (commands.txt — English, names, Hinglish), on both mics
at once, so every speech-to-text option is scored on exactly the same audio.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.record_commands

For each one: it shows the command, you press Enter, it beeps, you say it (6 s). Say it the way you naturally would
to the panel, from where you'd stand. Quiet room (when Room listens, music will be turned down). Saved in
~/room-stt-test/<time>/, then scored by stt_eval.
"""
import json
import os
import subprocess
import time

from .record_wake import beep_file, levels, sources

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser("~/room-stt-test")


def main():
    raw, ns = sources()
    lines = [l.strip() for l in open(os.path.join(HERE, "commands.txt")) if l.strip()]
    folder = os.path.join(OUT, time.strftime("%Y%m%d-%H%M"))
    os.makedirs(folder, exist_ok=True)
    print(f"{len(lines)} commands. Quiet room, no music. Stand where you'd talk to the panel.\n")
    for i, text in enumerate(lines):
        input(f"\n{i + 1:2d}/{len(lines)}   “{text}”   — Enter, then say it after the beep… ")
        procs = []
        for label, src in (("raw", raw), ("ns", ns)):
            if src:
                procs.append(subprocess.Popen(["pw-record", "--target", src[0], "--rate", "16000", "--channels", "1",
                                               "--format", "s16", os.path.join(folder, f"{i:02d}_{label}.wav")],
                                              stderr=subprocess.DEVNULL))
        time.sleep(0.4)
        subprocess.run(["pw-play", "--volume", "0.5", beep_file()], stderr=subprocess.DEVNULL)
        time.sleep(6)
        for p in procs:
            p.terminate(); p.wait()
    json.dump(lines, open(os.path.join(folder, "commands.json"), "w"), ensure_ascii=False)
    print("\nLevels (first and last):")
    for name in sorted(f for f in os.listdir(folder) if f.endswith(".wav"))[:2] + sorted(os.listdir(folder))[-3:-1]:
        if name.endswith(".wav"):
            print(f"  {name:12s} {levels(os.path.join(folder, name))}")
    print(f"\n✓ Saved in {folder}\n  Score it:  assistant/.venv/bin/python -m assistant.bench.stt_eval {folder}")


if __name__ == "__main__":
    main()
