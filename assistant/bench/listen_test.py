"""Steps 3–5 together, live: say "Alexa", then a request — it prints what it heard and how long each part took.

  cd ~/room && assistant/.venv/bin/python -m assistant.bench.listen_test

Try it with music on (it should turn the music down the moment it hears "Alexa", and back up after), with a pause
after "Alexa", and with pauses mid-sentence — any request it cut short shows as words missing at the end. Each
request's audio is kept in ~/room-listen-test/ to look at. Ctrl+C to stop.
"""
import json
import os
import subprocess
import time
import wave

from assistant.duck import Duck
from assistant.listen import RATE, VAD, Listener, Mic, Wake, sarvam
from assistant.bench.record_wake import beep_file

OUT = os.path.expanduser("~/room-listen-test")


def main():
    cfg = json.load(open(os.path.expanduser("~/.config/room/config.json")))
    key = cfg.get("sarvamKey") or (cfg.get("voiceSettings") or {}).get("sarvamKey")
    os.makedirs(OUT, exist_ok=True)
    mic = Mic(float(cfg.get("assistantMicLevel", 0.65)))
    mic.start()
    ears = Listener(mic, Wake(), VAD())
    duck = Duck()
    print("\nSay \"Alexa\"… (Ctrl+C to stop)\n", flush=True)
    n = 0
    try:
        while True:
            score = ears.wait_wake()
            t_wake = time.time()
            duck.down()
            subprocess.Popen(["pw-play", "--volume", "0.5", beep_file()], stderr=subprocess.DEVNULL)
            n += 1
            print(f"#{n} Alexa ({score:.2f}) — listening…", flush=True)
            audio, info = ears.record()
            if audio is None:
                print(f"   nothing said within {Listener.ONSET:.0f} s\n", flush=True)
                duck.up(); continue
            path = os.path.join(OUT, f"{time.strftime('%H%M%S')}.wav")
            with wave.open(path, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(audio.tobytes())
            t = time.time()
            try:
                words = sarvam(audio, key) if key else "(no sarvamKey)"
            except Exception as e:
                words = f"[{e}]"
            print(f"   “{words}”\n   you started {info['onset']} s after Alexa, spoke {info['spoke']} s · "
                  f"words {time.time() - t:.2f} s after the end · {time.time() - t_wake:.1f} s from Alexa\n", flush=True)
            duck.up()
    except KeyboardInterrupt:
        duck.up(); time.sleep(0.5)
        mic.stop()


if __name__ == "__main__":
    main()
