"""Teach Room's "Alexa" your voice (run by scripts/train-alexa.sh, over SSH, standing where you'd talk to it).

openWakeWord's "custom verifier": a small model trained on *your* "Alexa"s and on your ordinary talk. The stock
detector still listens as before; whenever it's even slightly reminded of "Alexa" (score ≥ 0.15 instead of the
usual 0.4), the verifier — which knows how you say it — makes the call. Your near-misses get through; other
voices and words that only sound a bit like it don't.

Records through the same mic Room listens to, so it learns what Room hears.
Saved as ~/.local/share/room/voice/alexa_verifier.pkl; Room uses it from its next start. Delete that file (or set
"wakeVerifier": false in voiceSettings) to go back.
"""
import glob
import os
import pickle
import subprocess
import sys
import time
import wave

import numpy as np

DATA = os.path.expanduser("~/.local/share/room/voice")
WORK = os.path.join(DATA, "alexa-training")
OUT = os.path.join(DATA, "alexa_verifier.pkl")
HUSH = os.path.expanduser("~/.local/state/room/wake-paused")       # Room doesn't answer "Alexa" while this exists
CUES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cues")
RATE = 16000


def mic():
    return None          # the default mic — the one Room listens to


def record(path, seconds, target):
    cmd = ["pw-record", "--rate", str(RATE), "--channels", "1", "--format", "s16"]
    if target:
        cmd += ["--target", target]
    p = subprocess.Popen(cmd + [path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(seconds)
    p.terminate()
    p.wait()


def beep():
    f = os.path.join(CUES, "listen.wav")
    if os.path.exists(f):
        subprocess.run(["pw-play", f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def split(path, into, seconds=2.0):
    """A long recording → 2 s clips (the verifier learns from short pieces)."""
    w = wave.open(path)
    a = np.frombuffer(w.readframes(w.getnframes()), "<i2")
    n = int(seconds * RATE)
    base = os.path.splitext(os.path.basename(path))[0]
    for i in range(0, len(a) - n + 1, n):
        with wave.open(os.path.join(into, f"{base}-{i // n:02d}.wav"), "wb") as o:
            o.setnchannels(1); o.setsampwidth(2); o.setframerate(RATE)
            o.writeframes(a[i:i + n].tobytes())


def ask(msg):
    input(f"\n{msg}\n  Press Enter when ready… ")


def main():
    target = mic()
    os.makedirs(os.path.dirname(HUSH), exist_ok=True)
    open(HUSH, "w").close()
    pos, neg = os.path.join(WORK, "alexa"), os.path.join(WORK, "other")
    for d in (pos, neg):
        os.makedirs(d, exist_ok=True)
        for f in glob.glob(os.path.join(d, "*.wav")):
            os.remove(f)
    print("Recording through the mic Room listens to. Room won't answer \"Alexa\" until this finishes.")
    try:
        # ---- your "Alexa"s
        plan = [(8, "Stand where you usually talk to it. After each beep, say \"Alexa\" once, normally."),
                (6, "Now from across the room (or wherever it struggles). After each beep, \"Alexa\"."),
                (6, "Now a bit quieter or more casual — the way you'd say it half-asleep. After each beep, \"Alexa\"."),
                (8, "Now put music on at your usual volume (on the speaker you normally use), stand where you usually "
                    "talk, and say \"Alexa\" after each beep — over the music.")]
        n = 0
        for count, msg in plan:
            ask(msg)
            for _ in range(count):
                n += 1
                print(f"  {n:2d}/28  say it after the beep…", flush=True)
                beep()
                record(os.path.join(pos, f"alexa-{n:02d}.wav"), 2.2, target)
                time.sleep(0.4)
        # ---- everything that isn't "Alexa"
        ask("Now 30 seconds of ordinary talk — read something aloud, chat, say words like \"Alexander\", \"Alexis\", "
            "\"election\", \"a lexicon\" — anything except \"Alexa\". Starts after the beep.")
        beep(); record(os.path.join(WORK, "talk.wav"), 30, target); split(os.path.join(WORK, "talk.wav"), neg)
        ask("Keep the music on: 20 seconds of just the room and the music. Don't speak.")
        beep(); record(os.path.join(WORK, "room.wav"), 20, target); split(os.path.join(WORK, "room.wav"), neg)
        print("\nRecorded. Learning your voice (a minute)…", flush=True)

        # ---- train
        from openwakeword.model import Model
        from openwakeword.custom_verifier_model import get_reference_clip_features, train_verifier_model
        d = os.path.join(DATA, "oww")
        oww = Model(wakeword_models=[os.path.join(d, "alexa_v0.1.onnx")], inference_framework="onnx",
                    melspec_model_path=os.path.join(d, "melspectrogram.onnx"),
                    embedding_model_path=os.path.join(d, "embedding_model.onnx"))
        name = "alexa_v0.1"
        p_feats, used = [], 0
        for f in sorted(glob.glob(os.path.join(pos, "*.wav"))):
            oww.reset()
            x = get_reference_clip_features(f, oww, name, threshold=0.2, N=5)     # your near-misses count too
            if len(x):
                used += 1
                p_feats.append(x)
        if used < 5:
            print(f"\n✗ Only {used} of 28 recordings sounded like \"Alexa\" to the detector at all — too few to learn "
                  "from. Check the mic level, move closer, and run this again.")
            return 1
        n_feats = []
        for f in sorted(glob.glob(os.path.join(neg, "*.wav"))):
            oww.reset()
            x = get_reference_clip_features(f, oww, name, threshold=0.0, N=1)
            if len(x):
                n_feats.append(x)
        P, N = np.vstack(p_feats), np.vstack(n_feats)
        model = train_verifier_model(np.vstack((P, N)), np.array([1] * len(P) + [0] * len(N)))
        pickle.dump(model, open(OUT, "wb"))
        print(f"\n✓ Learnt from {used} of your 28 \"Alexa\"s and {len(glob.glob(os.path.join(neg, '*.wav')))} clips of "
              f"other sound. Saved — Room uses it from its next start (restarting it now).")
        return 0
    finally:
        try:
            os.remove(HUSH)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    sys.exit(main())
