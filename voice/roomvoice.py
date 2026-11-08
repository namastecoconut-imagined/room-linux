"""Room's ears and voice — a separate process so a mic or model problem can never take the panel down.

Started by Room (room/voice.py) with its own Python (voice/.venv). Talks over stdin/stdout, one JSON object a line.

  out → {"ev": "ready"} · {"ev": "level", "v": 0..1} · {"ev": "wake"} · {"ev": "listening"} · {"ev": "thinking"}
        {"ev": "heard", "text": "..."} · {"ev": "speaking"} · {"ev": "spoken"} · {"ev": "error", "msg": "..."}
  in  ← {"cmd": "listen"} (tap to talk) · {"cmd": "say", "text": "...", "listen": false} · {"cmd": "cancel"}
        {"cmd": "words", "words": ["Living room", ...]} (names whisper should expect)

Hearing: the mic (the echo-cancelled one when PipeWire's echo-cancel is set up, so music playing from the Surface is
taken out) is read with pw-record at 16 kHz. openWakeWord's "alexa" model listens all the time, also while Room is
talking — saying "Alexa" again cuts the answer off. After the wake word: a soft tone, then what's said is recorded
until a pause (Silero VAD), up to 8 s, and sent to whisper.cpp's server on 127.0.0.1:8910.
Speaking: Kokoro (voice af_heart unless set), sentence by sentence so the first words start quickly, through pw-play.
"""
import io
import json
import math
import os
import queue
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import wave

import numpy as np
import requests

RATE = 16000
CHUNK = 1280                                   # 80 ms — what openWakeWord wants
DATA = os.path.expanduser(os.environ.get("ROOM_VOICE_DATA", "~/.local/share/room/voice"))
CFG = json.loads(os.environ.get("ROOM_VOICE_CFG", "{}"))
WAKE_THRESHOLD = float(CFG.get("wakeThreshold", 0.5))
VOICE = CFG.get("voice", "af_heart")
WHISPER = CFG.get("whisperURL", "http://127.0.0.1:8910/inference")
DEBUG = os.environ.get("ROOM_VOICE_DEBUG") == "1"        # a line a second: mic level, gain, wake-word score


def emit(**ev):
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


def log(*a):
    print("[voice]", *a, file=sys.stderr, flush=True)


def tone(path, notes, length=0.16, vol=0.22, rate=24000):
    """A soft little earcon (written once)."""
    if os.path.exists(path):
        return path
    frames = []
    for i, f in enumerate(notes):
        n = int(rate * length)
        for k in range(n):
            t = k / rate
            env = min(1, t / 0.01) * math.exp(-t * 9)
            frames.append(struct.pack("<h", int(32000 * vol * env * math.sin(2 * math.pi * f * t))))
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(b"".join(frames))
    return path


def mic_target():
    """The plain mic. The echo-cancelled one (room-ec-source) only when asked for with "echoCancel": true — on the
    Surface its sound came out distorted (clipping), so it stays off until it's tuned."""
    if CFG.get("mic"):
        return CFG["mic"]
    if CFG.get("echoCancel") is not True:
        return None
    try:
        out = subprocess.run(["pw-cli", "ls", "Node"], capture_output=True, text=True, timeout=5).stdout
        if "room-ec-source" in out:
            return "room-ec-source"
    except Exception:
        pass
    return None


class Speaker:
    """Kokoro, sentence by sentence; pw-play for output. stop() cuts it off at once."""

    def __init__(self):
        from kokoro_onnx import Kokoro
        self.k = Kokoro(os.path.join(DATA, "kokoro.onnx"), os.path.join(DATA, "voices.bin"))
        self.lang = "en-gb" if VOICE.startswith("b") else "en-us"
        self.proc = None
        self.gen = 0
        self.busy = False
        self.lock = threading.Lock()

    def say(self, text, done):
        self.stop()
        self.gen += 1
        g = self.gen
        threading.Thread(target=self._run, args=(text, g, done), daemon=True).start()

    def _run(self, text, g, done):
        import soundfile as sf
        self.busy = True
        parts = [p.strip() for p in re.split(r"(?<=[.!?])\s+", text) if p.strip()]
        q: queue.Queue = queue.Queue(maxsize=2)

        def synth():
            for p in parts:
                if g != self.gen:
                    break
                try:
                    a, sr = self.k.create(p, voice=VOICE, speed=float(CFG.get("speed", 1.05)), lang=self.lang)
                    f = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
                    sf.write(f.name, a, sr); q.put(f.name)
                except Exception as e:
                    log("tts:", e)
            q.put(None)

        threading.Thread(target=synth, daemon=True).start()
        first = True
        while True:
            f = q.get()
            if f is None or g != self.gen:
                if f:
                    os.unlink(f)
                break
            if first:
                emit(ev="speaking"); first = False
            with self.lock:
                self.proc = subprocess.Popen(["pw-play", f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.proc.wait()
            os.unlink(f)
        self.busy = False
        if g == self.gen:
            done()

    def stop(self):
        self.gen += 1
        with self.lock:
            if self.proc and self.proc.poll() is None:
                self.proc.terminate()


class Ears:
    def __init__(self):
        from openwakeword.model import Model
        from openwakeword.vad import VAD
        mdir = os.path.join(DATA, "oww")
        self.wake = Model(wakeword_models=[os.path.join(mdir, "alexa_v0.1.onnx")], inference_framework="onnx",
                          melspec_model_path=os.path.join(mdir, "melspectrogram.onnx"),
                          embedding_model_path=os.path.join(mdir, "embedding_model.onnx"))
        self.vad = VAD(model_path=os.path.join(mdir, "silero_vad.onnx"))
        self.speaker = Speaker()
        self.state = "idle"            # idle · listening · thinking
        self.rec: list[np.ndarray] = []
        self.heard_speech = False
        self.quiet_since = 0.0
        self.started = 0.0
        self.last_wake = -10.0
        self.words: list[str] = []
        self.listen_after_speaking = False
        self.cues = os.path.join(DATA, "cues"); os.makedirs(self.cues, exist_ok=True)
        self.cue_on = tone(os.path.join(self.cues, "on.wav"), [660, 990])
        self.cue_off = tone(os.path.join(self.cues, "off.wav"), [990, 660], vol=0.15)

    # ---------------------------------------------------------------- listening
    def begin_listening(self):
        self.speaker.stop()
        subprocess.Popen(["pw-play", self.cue_on], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.state = "listening"
        self.rec = []
        self.heard_speech = False
        self.started = getattr(self, "clock", 0.0)
        self.quiet_since = 0.0
        self.vad.reset_states()
        emit(ev="listening")

    # ---------------------------------------------------------------- the mic, evened out
    # The Surface's mic is quiet from across a room. A slow automatic gain lifts it (up to 10×) so the wake word, the
    # pause detection and whisper all get speech at a useful level; `ref` is a slowly-falling peak of what's heard.
    ref = 0.05
    floor = 0.002
    target_set = bool(CFG.get("mic"))              # a mic chosen in config is left alone
    def even(self, pcm: np.ndarray) -> np.ndarray:
        x = pcm.astype(np.float32) / 32768
        # the mic can sit far off zero (a DC offset) — take it out so loudness means sound
        self.dc = getattr(self, "dc", float(np.mean(x))) * 0.95 + float(np.mean(x)) * 0.05
        x = x - self.dc
        # clipping: the Surface's mic input is set too hot — turn it down a step (PipeWire's input volume) until it
        # stops, rather than hand distorted sound to the wake word and whisper
        clipped = float(np.mean(np.abs(x) > 0.97))
        self.clips = getattr(self, "clips", 0) + (1 if clipped > 0.01 else 0)
        self.chunks = getattr(self, "chunks", 0) + 1
        if self.chunks >= 25:                       # every 2 s
            if self.clips >= 5 and not self.target_set and self._input_volume() > 0.35:
                subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", "0.1-"], timeout=3)
                out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"], capture_output=True, text=True, timeout=3).stdout.strip()
                log(f"mic was clipping — input turned down ({out})")
            self.clips = 0; self.chunks = 0
        pk = float(np.max(np.abs(x))) if len(x) else 0.0
        self.ref = max(pk, self.ref * 0.998, 0.004)
        g = float(np.clip(0.35 / self.ref, 1.0, float(CFG.get("maxGain", 10))))
        rms = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
        self.floor = min(rms, self.floor * 1.002 + 1e-6) if rms > 0 else self.floor     # background noise
        self.gain = g
        return (np.clip(x * g, -1, 1) * 32767).astype(np.int16)

    def _input_volume(self) -> float:
        try:
            out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"], capture_output=True, text=True, timeout=3).stdout
            return float(out.split()[1])
        except Exception:
            return 0.0

    def feed(self, raw: np.ndarray):
        # time is counted in audio, not on the wall clock (the same either way live, and testable from a file)
        self.clock = getattr(self, "clock", 0.0) + len(raw) / RATE
        now = self.clock
        pcm = self.even(raw)
        level = float(np.sqrt(np.mean((pcm.astype(np.float32) / 32768) ** 2))) / max(self.gain, 1.0)
        self.level_n = getattr(self, "level_n", 0) + 1
        if self.level_n % 2 == 0:                     # ~6 a second is plenty for the screen
            emit(ev="level", v=round(level, 5))
        score = max(self.wake.predict(pcm).values() or [0])
        if DEBUG:
            self.dbg = getattr(self, "dbg", []) + [(level, score)]
            if len(self.dbg) >= 12:                   # about once a second
                lv = max(x[0] for x in self.dbg); sc = max(x[1] for x in self.dbg)
                log(f"mic {lv:.4f} · gain ×{self.gain:.1f} · wake {sc:.2f} · state {self.state}")
                self.dbg = []
        # a line in the log now and then about how close the wake word came (helps tune it)
        self.best = max(getattr(self, "best", 0.0), score)
        if now - getattr(self, "said_at", 0.0) > 60:
            self.said_at = now
            if self.best > 0.05:
                log(f"wake: best {self.best:.2f} in the last minute · gain ×{self.gain:.1f} · noise {self.floor:.4f}")
            self.best = 0.0
        if score >= WAKE_THRESHOLD and now - self.last_wake > 1.5:
            self.last_wake = now
            self.wake.reset()
            emit(ev="wake")
            self.begin_listening()
            return
        if self.state != "listening":
            return
        self.rec.append(pcm)
        vp = float(self.vad.predict(pcm, frame_size=480))
        rms = float(np.sqrt(np.mean((pcm.astype(np.float32) / 32768) ** 2)))
        self.max_vad = max(getattr(self, "max_vad", 0.0), vp)
        self.max_rms = max(getattr(self, "max_rms", 0.0), rms)
        # speech: Silero says so (or half-says so while it's clearly louder than the room) — loudness alone isn't
        # enough, the Surface's mic is noisy
        speech = vp > 0.35 or (vp > 0.12 and rms > max(0.02, self.floor * self.gain * 6))
        if speech:
            self.heard_speech = True
            self.quiet_since = 0.0
        elif self.heard_speech and not self.quiet_since:
            self.quiet_since = now
        long_pause = self.heard_speech and self.quiet_since and now - self.quiet_since > 0.8
        nothing = not self.heard_speech and now - self.started > 5
        too_long = now - self.started > 8
        if long_pause or nothing or too_long:
            audio = np.concatenate(self.rec) if self.rec else np.zeros(0, np.int16)
            self.state = "thinking"
            subprocess.Popen(["pw-play", self.cue_off], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            log(f"heard {len(audio) / RATE:.1f} s · speech {'yes' if self.heard_speech else 'no'} · vad max {self.max_vad:.2f}"
                f" · loudest {self.max_rms:.3f} · gain ×{self.gain:.1f} · noise {self.floor:.4f}")
            self.max_vad = 0.0; self.max_rms = 0.0
            if nothing and len(audio) and float(np.sqrt(np.mean((audio.astype(np.float32) / 32768) ** 2))) > 0.01:
                nothing = False          # something was said even if it never looked like speech — let whisper decide
            if nothing:
                self.state = "idle"
                emit(ev="heard", text="")
                return
            emit(ev="thinking")
            threading.Thread(target=self.transcribe, args=(audio,), daemon=True).start()

    def transcribe(self, audio: np.ndarray):
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(audio.tobytes())
        prompt = "Alexa. " + ", ".join(self.words) + "." if self.words else ""
        text = ""
        t0 = time.time()
        try:
            r = requests.post(WHISPER, files={"file": ("a.wav", buf.getvalue(), "audio/wav")},
                              data={"response_format": "json", "temperature": "0.0", "prompt": prompt}, timeout=20)
            text = (r.json().get("text") or "").strip()
            text = re.sub(r"\[.*?\]|\(.*?\)", "", text).strip()     # [BLANK_AUDIO], (music)…
            log(f"whisper ({time.time() - t0:.1f} s): {text!r}")
            lines = [l.strip() for l in text.splitlines() if l.strip()]
            if len(lines) > 1 and all(l.lower() == lines[0].lower() for l in lines):
                lines = lines[:1]
            text = " ".join(lines)
        except Exception as e:
            emit(ev="error", msg="Speech recognition isn't running (whisper)")
            log("whisper:", e)
        self.state = "idle"
        emit(ev="heard", text=text)

    # ---------------------------------------------------------------- commands from Room
    def command(self, c: dict):
        cmd = c.get("cmd")
        if cmd == "listen":
            self.begin_listening()
        elif cmd == "say":
            self.listen_after_speaking = bool(c.get("listen"))
            self.speaker.say(c.get("text", ""), self._spoken)
        elif cmd == "cancel":
            self.speaker.stop()
            self.state = "idle"
        elif cmd == "words":
            self.words = [w for w in c.get("words", []) if isinstance(w, str)][:40]

    def _spoken(self):
        emit(ev="spoken")
        if self.listen_after_speaking:
            self.listen_after_speaking = False
            self.begin_listening()


def main():
    for tool in ("pw-record", "pw-play"):
        if not shutil.which(tool):
            emit(ev="error", msg=f"{tool} is missing"); return
    try:
        ears = Ears()
    except Exception as e:
        emit(ev="error", msg=f"Voice couldn't start: {e}")
        log("start:", repr(e))
        return

    def stdin_loop():
        for line in sys.stdin:
            try:
                ears.command(json.loads(line))
            except Exception as e:
                log("cmd:", e)
        os._exit(0)                                   # Room went away
    threading.Thread(target=stdin_loop, daemon=True).start()

    target = mic_target()
    # raw little-endian samples on stdout. Without --raw, pw-record writes stdout as an .au file — big-endian — which
    # read as little-endian is loud noise (what the Surface heard at first)
    helptext = subprocess.run(["pw-record", "--help"], capture_output=True, text=True).stdout + \
               subprocess.run(["pw-record", "--help"], capture_output=True, text=True).stderr
    raw = ["--raw"] if "--raw" in helptext else []
    cmd = ["pw-record", *raw, "--rate", str(RATE), "--channels", "1", "--format", "s16", "-"]
    if target:
        cmd[1:1] = ["--target", target]
    log("mic:", target or "default")
    emit(ev="ready", mic=target or "default")
    while True:
        rec = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        n = CHUNK * 2
        swap = False
        if not raw:
            head = rec.stdout.read(24)                       # an .au header? (magic, data offset, …)
            if head[:4] == b".snd":
                swap = True
                rec.stdout.read(max(0, int.from_bytes(head[4:8], "big") - 24))
            log("mic stream:", "au, big-endian" if swap else "raw")
        while True:
            b = rec.stdout.read(n)
            if not b or len(b) < n:
                break
            try:
                ears.feed(np.frombuffer(b, dtype=">i2" if swap else "<i2").astype(np.int16))
            except Exception as e:
                log("feed:", repr(e))
        log("mic stopped — reopening in 2 s")
        time.sleep(2)


if __name__ == "__main__":
    main()
