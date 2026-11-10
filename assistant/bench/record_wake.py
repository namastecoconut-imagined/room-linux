"""Step 3's recordings: you saying "Alexa", captured by BOTH mics at once — the raw Surface mic and the
noise-suppressed "Surface Mic" — so every wake-word engine can be tried on exactly the same moments, over and over,
without you having to say it again.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.record_wake

Three parts, each started with Enter:
  1. quiet room — after each beep say "Alexa" once, normally (10×)
  2. music on the Bluetooth speaker at your usual volume — after each beep, "Alexa" (20×)
  3. the same music, nobody talking, for 3 minutes (to count false alarms)
Stand where you'd normally talk to it. Saved in ~/room-wake-test/<time>/, then scored by wake_eval.
"""
import json
import math
import os
import struct
import subprocess
import sys
import time
import wave

RATE = 16000
OUT = os.path.expanduser("~/room-wake-test")


def sources():
    nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
    raw = ns = None
    for n in nodes:
        p = (n.get("info") or {}).get("props") or {}
        if p.get("media.class") != "Audio/Source":
            continue
        name = p.get("node.name", "")
        if name.startswith("alsa_input") and not raw:
            raw = (name, n["id"])
        if name == "surface_mic_ns" or "noise" in (p.get("node.description") or "").lower():
            ns = (name, n["id"])
    return raw, ns


def beep_file():
    p = "/tmp/room-wake-beep.wav"
    if not os.path.exists(p):
        with wave.open(p, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
            n = int(RATE * 0.12)
            w.writeframes(b"".join(struct.pack("<h", int(9000 * math.sin(2 * math.pi * 880 * i / RATE)
                                                         * min(1, i / 200, (n - i) / 200))) for i in range(n)))
    return p


def record(folder, tag, seconds=None, prompts=0, gap=4.0):
    raw, ns = sources()
    procs = {}
    for label, src in (("raw", raw), ("ns", ns)):
        if src:
            f = os.path.join(folder, f"{tag}_{label}.wav")
            procs[label] = subprocess.Popen(["pw-record", "--target", src[0], "--rate", str(RATE), "--channels", "1",
                                             "--format", "s16", f], stderr=subprocess.DEVNULL)
    t0 = time.time()
    time.sleep(1.5)
    beeps = []
    if prompts:
        for i in range(prompts):
            beeps.append(round(time.time() - t0, 3))
            subprocess.run(["pw-play", "--volume", "0.5", beep_file()], stderr=subprocess.DEVNULL)
            print(f"  {i + 1:2d}/{prompts}  say \"Alexa\"", flush=True)
            time.sleep(gap)
    else:
        end = time.time() + seconds
        while time.time() < end:
            print(f"  {int(end - time.time()):3d} s left — don't say \"Alexa\"", end="\r", flush=True)
            time.sleep(1)
        print()
    time.sleep(1.0)
    for p in procs.values():
        p.terminate(); p.wait()
    return beeps


def levels(path):
    import array
    with wave.open(path) as w:
        a = array.array("h", w.readframes(w.getnframes()))
    if not a:
        return "empty"
    peak = max(abs(min(a)), max(a))
    clipped = sum(1 for x in a if abs(x) >= 32000)
    return f"peak {20 * math.log10(max(peak, 1) / 32768):5.1f} dBFS · clipped samples {clipped}"


def main():
    raw, ns = sources()
    print("Mics found:", "raw =", raw[0] if raw else "none", "· noise-suppressed =", ns[0] if ns else "none")
    if raw:
        print("  raw mic level:", subprocess.run(["wpctl", "get-volume", str(raw[1])], capture_output=True,
                                                 text=True).stdout.strip())
    if not raw and not ns:
        sys.exit("No mic found")
    folder = os.path.join(OUT, time.strftime("%Y%m%d-%H%M"))
    os.makedirs(folder, exist_ok=True)
    plan = {}
    input("\n1/3 Quiet room, no music. Stand where you usually talk to it. Press Enter, then say \"Alexa\" after "
          "each beep… ")
    plan["quiet"] = record(folder, "quiet", prompts=10)
    input("\n2/3 Now play music on the Bluetooth speaker at your usual volume. Press Enter, then \"Alexa\" after each "
          "beep… ")
    plan["music"] = record(folder, "music", prompts=20)
    input("\n3/3 Keep the music on. Press Enter and don't say \"Alexa\" for 3 minutes (talking otherwise is fine)… ")
    plan["musiconly"] = record(folder, "musiconly", seconds=180)
    with open(os.path.join(folder, "prompts.json"), "w") as f:
        json.dump(plan, f)
    print("\nLevels:")
    for name in sorted(os.listdir(folder)):
        if name.endswith(".wav"):
            print(f"  {name:22s} {levels(os.path.join(folder, name))}")
    print(f"\n✓ Saved in {folder}\n  Score it:  assistant/.venv/bin/python -m assistant.bench.wake_eval {folder}")


if __name__ == "__main__":
    main()
