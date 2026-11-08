"""Room's ears and voice — a separate process so a mic or model problem can never take the panel down.

Started by Room (room/assistant.py) with its own Python (voice/.venv). Talks over stdin/stdout, one JSON object a line.

  out → {"ev": "ready"} · {"ev": "level", "v": rms} · {"ev": "wake"} · {"ev": "listening"} · {"ev": "partial", "text"}
        {"ev": "thinking"} · {"ev": "heard", "text": "..."} · {"ev": "speaking"} · {"ev": "spoken"} · {"ev": "error"}
  in  ← {"cmd": "listen"} (tap to talk) · {"cmd": "say", "text": "...", "listen": false} · {"cmd": "cancel"}
        {"cmd": "words", "words": ["Living room", ...]} (names to expect)

Set up like the iPhone panel, where it felt quick: the heavy lifting isn't done on the Surface.
  • Wake word "Alexa": Picovoice Porcupine (built for far-field, tiny on the CPU) when there's a picovoiceKey;
    openWakeWord's "alexa" model otherwise. It listens all the time, also while Room talks ("Alexa" cuts an answer off).
  • Hearing what's said: Deepgram's live recognition when there's a deepgramKey — the sound streams from the moment
    "Alexa" is heard, words come back while you talk, and Deepgram says when you've finished (like Apple's recogniser
    on the phone). Without a key (or offline): Silero VAD + whisper.cpp on 127.0.0.1:8910.
  • Speaking: Deepgram's Aura voice, streamed straight to the speaker (starts in ~0.2 s, even loudness); Kokoro
    (af_heart) when there's no key or no internet.
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
# "Alexa" from across the room scores lower than up close; 0.35 still ignores ordinary talk (it scored ~0 in tests)
WAKE_THRESHOLD = float(CFG.get("wakeThreshold", 0.35))
VOICE = CFG.get("voice", "af_heart")                    # Kokoro (offline) voice
DG_KEY = CFG.get("deepgramKey") or ""
PV_KEY = CFG.get("picovoiceKey") or ""
DG_VOICE = CFG.get("auraVoice", "aura-2-thalia-en")
DG_LISTEN = CFG.get("deepgramListenURL", "wss://api.deepgram.com/v1/listen")
DG_SPEAK = CFG.get("deepgramSpeakURL", "https://api.deepgram.com/v1/speak")
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


def louder(x: np.ndarray) -> np.ndarray:
    """Room's voice, made louder for the Surface's small speakers: gain (×2.5 by default, 'loudness' scales it) with a
    soft limiter, so peaks round off instead of crackling. Float in, float out (−1…1)."""
    g = 2.5 * float(CFG.get("loudness", 1.0))
    return np.tanh(x * g) / np.tanh(g) if g > 1 else x * g


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
    """Deepgram Aura, streamed into pw-play; Kokoro sentence by sentence when that isn't possible. stop() cuts it off."""

    def __init__(self):
        self.k = None
        self.lang = "en-gb" if VOICE.startswith("b") else "en-us"
        self.proc = None
        self.gen = 0
        self.busy = False
        self.lock = threading.Lock()

    def _kokoro(self):
        if self.k is None:
            from kokoro_onnx import Kokoro
            self.k = Kokoro(os.path.join(DATA, "kokoro.onnx"), os.path.join(DATA, "voices.bin"))
        return self.k

    def say(self, text, done):
        self.stop()
        self.gen += 1
        g = self.gen
        threading.Thread(target=self._say, args=(text, g, done), daemon=True).start()

    def _say(self, text, g, done):
        if DG_KEY and self._deepgram(text, g):
            self.busy = False
            if g == self.gen:
                done()
            return
        self._run(text, g, done)

    def _deepgram(self, text, g) -> bool:
        """Aura, streamed: playback starts with the first bytes. False if it couldn't be reached (→ Kokoro)."""
        self.busy = True
        try:
            r = requests.post(DG_SPEAK,
                              params={"model": DG_VOICE, "encoding": "linear16", "sample_rate": 24000, "container": "none"},
                              headers={"Authorization": f"Token {DG_KEY}", "Content-Type": "application/json"},
                              json={"text": text}, stream=True, timeout=(3, 15))
            if r.status_code != 200:
                log(f"aura: {r.status_code} {r.text[:200]}")
                return False
        except Exception as e:
            log("aura:", repr(e))
            return False
        with self.lock:
            if g != self.gen:
                return True
            self.proc = subprocess.Popen(["pw-play", "--raw", "--rate", "24000", "--channels", "1", "--format", "s16", "-"],
                                         stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        first = True
        odd = b""
        try:
            for chunk in r.iter_content(chunk_size=4800):
                if g != self.gen:
                    break
                if chunk:
                    if first:
                        emit(ev="speaking"); first = False
                    chunk = odd + chunk
                    cut = len(chunk) // 2 * 2
                    chunk, odd = chunk[:cut], chunk[cut:]
                    x = np.frombuffer(chunk, dtype="<i2").astype(np.float32) / 32768
                    self.proc.stdin.write((louder(x) * 32000).astype("<i2").tobytes())
        except Exception as e:
            if g == self.gen:
                log("aura play:", repr(e))
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        self.proc.wait()
        return True

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
                    a, sr = self._kokoro().create(p, voice=VOICE, speed=float(CFG.get("speed", 1.05)), lang=self.lang)
                    f = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
                    # Kokoro comes out quiet: every sentence to the same loudness (by its average, not its peak, so a
                    # short "Okay." isn't louder than a long answer)
                    rms = float(np.sqrt(np.mean(a ** 2))) if len(a) else 0.0
                    if rms > 0:
                        a = louder(np.clip(a * (0.1 / rms), -1, 1))
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
                self.proc.kill()


class Wake:
    """'Alexa': Porcupine with a picovoiceKey (512-sample frames), openWakeWord otherwise. hit(pcm) → (heard, score)."""

    def __init__(self):
        self.pv = None
        if PV_KEY:
            try:
                import pvporcupine
                self.pv = pvporcupine.create(access_key=PV_KEY, keywords=["alexa"],
                                             sensitivities=[float(CFG.get("wakeSensitivity", 0.6))])
                self.buf = np.zeros(0, np.int16)
                log("wake word: Porcupine")
            except Exception as e:
                log("porcupine:", repr(e), "— using openWakeWord")
                self.pv = None
        if not self.pv:
            from openwakeword.model import Model
            mdir = os.path.join(DATA, "oww")
            self.oww = Model(wakeword_models=[os.path.join(mdir, "alexa_v0.1.onnx")], inference_framework="onnx",
                             melspec_model_path=os.path.join(mdir, "melspectrogram.onnx"),
                             embedding_model_path=os.path.join(mdir, "embedding_model.onnx"))
            log("wake word: openWakeWord")

    def hit(self, pcm: np.ndarray):
        if self.pv:
            self.buf = np.concatenate([self.buf, pcm])
            heard = False
            n = self.pv.frame_length
            while len(self.buf) >= n:
                if self.pv.process(self.buf[:n].tolist()) >= 0:
                    heard = True
                self.buf = self.buf[n:]
            return heard, 1.0 if heard else 0.0
        score = max(self.oww.predict(pcm).values() or [0])
        return score >= WAKE_THRESHOLD, score

    def reset(self):
        if not self.pv:
            self.oww.reset()


class Deepgram:
    """One live recognition: audio goes in as it's heard, words come back as they're recognised. on_partial(text) while
    talking; on_done(text) once — when Deepgram says the speaker finished, or close() is called."""

    def __init__(self, words, on_partial, on_done):
        self.q: queue.Queue = queue.Queue()
        self.on_partial, self.on_done = on_partial, on_done
        self.finals: list[str] = []
        self.interim = ""
        self.done = False
        self.opened = threading.Event()
        params = [("model", CFG.get("deepgramModel", "nova-3")), ("language", "en"), ("encoding", "linear16"),
                  ("sample_rate", str(RATE)), ("channels", "1"), ("interim_results", "true"), ("smart_format", "true"),
                  ("endpointing", str(CFG.get("endpointMs", 400))), ("utterance_end_ms", "1000"), ("vad_events", "true")]
        params += [("keyterm", w) for w in (["Alexa"] + list(words))[:50]]
        from urllib.parse import urlencode
        self.url = DG_LISTEN + "?" + urlencode(params)
        threading.Thread(target=self._run, daemon=True).start()

    def push(self, pcm: np.ndarray):
        if not self.done:
            self.q.put(pcm.tobytes())

    def close(self):
        """Out of time: ask for what's been heard so far."""
        self.q.put(None)

    def text(self):
        return " ".join([*self.finals, self.interim]).strip()

    def _finish(self):
        if not self.done:
            self.done = True
            self.on_done(" ".join(self.finals).strip() or self.interim.strip())

    def _run(self):
        from websockets.sync.client import connect
        t0 = time.time()
        try:
            ctx = connect(self.url, additional_headers={"Authorization": f"Token {DG_KEY}"}, open_timeout=4, max_size=None)
            ws = ctx.__enter__()
        except Exception as e:
            log("deepgram connect:", repr(e))
            self.failed = True
            self._finish()
            return
        log(f"deepgram: connected in {time.time() - t0:.2f} s")
        self.opened.set()

        def sender():
            try:
                while not self.done:
                    try:
                        b = self.q.get(timeout=5)
                    except queue.Empty:
                        ws.send(json.dumps({"type": "KeepAlive"})); continue
                    if b is None:
                        ws.send(json.dumps({"type": "Finalize"}))
                        time.sleep(1.2)
                        ws.send(json.dumps({"type": "CloseStream"}))
                        return
                    ws.send(b)
            except Exception:
                pass
        threading.Thread(target=sender, daemon=True).start()
        try:
            for msg in ws:
                if isinstance(msg, bytes):
                    continue
                m = json.loads(msg)
                kind = m.get("type")
                if kind == "Results":
                    alt = (m.get("channel", {}).get("alternatives") or [{}])[0]
                    t = (alt.get("transcript") or "").strip()
                    if m.get("is_final"):
                        if t:
                            self.finals.append(t)
                        self.interim = ""
                    else:
                        self.interim = t
                    if self.text():
                        self.on_partial(self.text())
                    if (m.get("speech_final") or m.get("from_finalize")) and self.finals:
                        break
                elif kind == "UtteranceEnd" and self.finals:
                    break
        except Exception as e:
            log("deepgram:", repr(e))
        log(f"deepgram: {self.text()!r} in {time.time() - t0:.1f} s")
        self._finish()
        try:
            self.done = True
            ws.send(json.dumps({"type": "CloseStream"}))
            ctx.__exit__(None, None, None)
        except Exception:
            pass


class Ears:
    def __init__(self):
        from openwakeword.vad import VAD
        mdir = os.path.join(DATA, "oww")
        self.wake = Wake()
        self.vad = VAD(model_path=os.path.join(mdir, "silero_vad.onnx"))
        self.dg: Deepgram | None = None
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
        self.dg = None
        if DG_KEY:
            self.dg = Deepgram(self.words, lambda t: emit(ev="partial", text=t), self._dg_done)
        emit(ev="listening")

    def _dg_done(self, text):
        dg = self.dg
        if getattr(dg, "failed", False):
            # Deepgram couldn't be reached — carry on listening the offline way (pause detection, then whisper);
            # what's been recorded so far is kept
            self.dg = None
            log("deepgram unreachable — listening offline")
            return
        self.dg = None
        if self.state == "listening":
            subprocess.Popen(["pw-play", self.cue_off], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.state = "idle"
        emit(ev="heard", text=text)

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
        heard_wake, score = self.wake.hit(pcm)
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
        if 0.15 <= score < WAKE_THRESHOLD and now - getattr(self, "miss_at", -9) > 2:
            self.miss_at = now
            log(f"wake: near miss {score:.2f}")
        if heard_wake and now - self.last_wake > 1.5:
            self.last_wake = now
            self.wake.reset()
            emit(ev="wake")
            self.begin_listening()
            return
        if self.state != "listening":
            return
        if self.dg:
            # live recognition: everything after "Alexa" streams straight to Deepgram (no waiting for the tone);
            # it decides when you've finished. A copy is kept in case it can't be reached.
            self.dg.push(pcm)
            self.rec.append(pcm)
            if now - self.started > 10 or (now - self.started > 6 and not self.dg.text()):
                self.dg.close()
                self.started = now + 999            # don't ask twice
            return
        if now - self.started < 0.35:
            return                                  # the start tone is still playing — don't send it to whisper
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
        try:                                         # the last thing heard, to listen back to: pw-play ~/.local/state/room/last-heard.wav
            p = os.path.expanduser("~/.local/state/room/last-heard.wav")
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(buf.getvalue())
        except Exception:
            pass
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
            if self.dg:
                self.dg.done = True; self.dg.close(); self.dg = None
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
        # the mic is read on its own thread, straight into a queue, so pw-record never waits on us — if the wake word
        # or the screen ever make processing late, the sound arrives late but whole (no gaps, which whisper hears as
        # noise)
        qa: queue.Queue = queue.Queue()

        def reader(proc=rec, swap=swap):
            while True:
                b = proc.stdout.read(n)
                if not b or len(b) < n:
                    qa.put(None); return
                qa.put(np.frombuffer(b, dtype=">i2" if swap else "<i2").astype(np.int16))
        threading.Thread(target=reader, daemon=True).start()
        slow, count, behind_said = 0.0, 0, 0.0
        while True:
            chunk = qa.get()
            if chunk is None:
                break
            t0 = time.time()
            try:
                ears.feed(chunk)
            except Exception as e:
                log("feed:", repr(e))
            slow += time.time() - t0; count += 1
            if count >= 375:                             # every 30 s of sound
                avg = slow / count * 1000
                if avg > 40 or qa.qsize() > 6:
                    log(f"working {avg:.0f} ms per 80 ms of sound · {qa.qsize()} waiting")
                slow, count = 0.0, 0
        log("mic stopped — reopening in 2 s")
        time.sleep(2)


if __name__ == "__main__":
    main()
