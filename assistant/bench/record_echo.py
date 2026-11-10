"""Echo-cancelling test, step 1: recordings. While music plays, it records the raw mic AND what the Surface is
sending out — the monitor of every real output (the Surface's speakers, a Bluetooth speaker) — at the same time, so
aec_eval can take the music back out of the mic afterwards and show how much it helped, on exactly the same moments.

  cd ~/room && assistant/.venv/bin/python -u -m assistant.bench.record_echo

The assistant is paused while it records (so it doesn't wake and duck the music) and started again after.
Two parts, each started with Enter (skip one by typing s):
  1. music on the SURFACE'S SPEAKERS at your usual volume — after each beep, say the line shown (10×)
  2. music on the BLUETOOTH SPEAKER at your usual volume — the same (10×)
Saved in ~/room-echo-test/<time>/, then scored by aec_eval.
"""
import json
import os
import subprocess
import sys
import time

from .record_wake import RATE, beep_file, levels

OUT = os.path.expanduser("~/room-echo-test")
LINES = ["Alexa, turn off the lights", "Alexa, what's the weather tomorrow", "Alexa, play some Arijit Singh",
         "Alexa, set a timer for ten minutes", "Alexa, make it cozy", "Alexa, volume down",
         "Alexa, gaana band karo", "Alexa, what time is it", "Alexa, next song", "Alexa, remind me to call mom at six"]


def nodes():
    ns = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
    mic, outs = None, []
    for n in ns:
        p = (n.get("info") or {}).get("props") or {}
        if n.get("type") != "PipeWire:Interface:Node":
            continue
        name = p.get("node.name", "")
        if p.get("media.class") == "Audio/Source" and name.startswith("alsa_input") and not mic:
            mic = name
        if p.get("media.class") == "Audio/Sink" and (name.startswith("bluez_output")
                                                      or (name.startswith("alsa_output") and "hdmi" not in name)):
            outs.append(name)
    return mic, outs


def record(folder, tag, prompts=10, gap=6.5):
    mic, outs = nodes()
    procs = [subprocess.Popen(["pw-record", "--target", mic, "--rate", str(RATE), "--channels", "1", "--format", "s16",
                               os.path.join(folder, f"{tag}_mic.wav")], stderr=subprocess.DEVNULL)]
    for i, o in enumerate(outs):        # what each output is playing (its monitor)
        kind = "bt" if o.startswith("bluez") else "surface"
        procs.append(subprocess.Popen(["pw-record", "--target", o, "-P", "{ stream.capture.sink = true }", "--rate",
                                       str(RATE), "--channels", "1", "--format", "s16",
                                       os.path.join(folder, f"{tag}_ref_{kind}.wav")], stderr=subprocess.DEVNULL))
    print(f"  recording the mic ({mic}) and what's playing on: {', '.join(outs)}")
    t0 = time.time()
    time.sleep(3.0)
    beeps = []
    for i in range(prompts):
        line = LINES[i % len(LINES)]
        beeps.append({"at": round(time.time() - t0, 3), "said": line})
        subprocess.run(["pw-play", "--volume", "0.5", beep_file()], stderr=subprocess.DEVNULL)
        print(f"  {i + 1:2d}/{prompts}  say: \"{line}\"", flush=True)
        time.sleep(gap)
    time.sleep(1.0)
    for p in procs:
        p.terminate(); p.wait()
    return beeps


def main():
    mic, outs = nodes()
    if not mic:
        sys.exit("No mic found")
    folder = os.path.join(OUT, time.strftime("%Y%m%d-%H%M"))
    os.makedirs(folder, exist_ok=True)
    was = subprocess.run(["systemctl", "--user", "is-active", "room-assistant"], capture_output=True, text=True).stdout.strip()
    if was == "active":
        subprocess.run(["systemctl", "--user", "stop", "room-assistant"])
        print("(the assistant is paused while this records)")
    plan = {}
    try:
        for tag, where in (("surface", "the SURFACE'S SPEAKERS (no Bluetooth speaker connected)"),
                           ("bt", "the BLUETOOTH SPEAKER")):
            a = input(f"\nPlay music on {where} at your usual volume, stand where you usually talk to Room. "
                      f"Enter to start (s to skip)… ")
            if a.strip().lower() == "s":
                continue
            plan[tag] = record(folder, tag)
    finally:
        if was == "active":
            subprocess.run(["systemctl", "--user", "start", "room-assistant"])
            print("(the assistant is back on)")
    with open(os.path.join(folder, "prompts.json"), "w") as f:
        json.dump(plan, f)
    print("\nLevels:")
    for name in sorted(os.listdir(folder)):
        if name.endswith(".wav"):
            print(f"  {name:22s} {levels(os.path.join(folder, name))}")
    print(f"\n✓ Saved in {folder}\n  Score it:  assistant/.venv/bin/python -u -m assistant.bench.aec_eval {folder}")


if __name__ == "__main__":
    main()
