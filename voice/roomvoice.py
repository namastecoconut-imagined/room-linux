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
# with Deepgram: a lenient local trigger, then Deepgram checks it really was "Alexa" before Room reacts
CANDIDATE = float(CFG.get("wakeCandidate", 0.12))
WAKE_RE = re.compile(r"\b(alexa|alexis|alexia|alexi|alex|lexa|elexa|alaxa|alyssa|alexis's|elexa|a lexa)\b", re.I)
CONFIDENT = float(CFG.get("wakeConfident", 0.2))   # from here Room opens at once (no asking Deepgram first)          # above this, wake straight away without asking Deepgram
DG_LISTEN = CFG.get("deepgramListenURL", "wss://api.deepgram.com/v1/listen")
DG_SPEAK = CFG.get("deepgramSpeakURL", "https://api.deepgram.com/v1/speak")
# one kept-alive connection for the voice: from India a fresh TLS handshake to Deepgram costs ~0.5 s per answer
HTTP = requests.Session()


def warm_speech():
    """Open (or keep open) the connection to Deepgram's voice while the person is still talking."""
    def go():
        try:
            HTTP.head(DG_SPEAK.rsplit("/v1/", 1)[0] + "/", timeout=4)
        except Exception:
            pass
    if DG_KEY:
        threading.Thread(target=go, daemon=True).start()
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
            t0 = time.time()
            r = HTTP.post(DG_SPEAK,
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
                        log(f"aura: first sound in {time.time() - t0:.2f} s")
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


def dg_url(words):
    params = [("model", CFG.get("deepgramModel", "nova-3")), ("language", CFG.get("language", "en-IN")), ("encoding", "linear16"),
              ("sample_rate", str(RATE)), ("channels", "1"), ("interim_results", "true"),
              ("endpointing", str(CFG.get("endpointMs", 500))), ("utterance_end_ms", "1000"), ("vad_events", "true")]
    params += [("keyterm", w) for w in (["Alexa", "set a timer", "timer", "minutes", "lights", "living room", "bedroom", "cozy", "make it cozy",
                                         "dim", "brightness", "percent", "weather", "Spotify", "play", "pause"] + list(words))[:50]]
    from urllib.parse import urlencode
    return DG_LISTEN + "?" + urlencode(params)


class Warm:
    """One Deepgram connection kept open and ready (KeepAlive every few seconds, no audio — nothing to pay for), so a
    "maybe Alexa" starts streaming at once instead of first spending ~0.5 s connecting from India to Deepgram."""

    def __init__(self):
        self.lock = threading.Lock()
        self.spare = None            # (ctx, ws, url, opened_at)
        self.words: list[str] = []
        self.need = threading.Event()  # set when the spare's been taken — open the next one straight away
        if DG_KEY:
            threading.Thread(target=self._keep, daemon=True).start()

    def take(self, words):
        with self.lock:
            sp, self.spare = self.spare, None
        self.need.set()
        if sp and sp[2] == dg_url(words) and time.time() - sp[3] < 480:
            return sp
        if sp:
            threading.Thread(target=self._close, args=(sp,), daemon=True).start()
        return None

    @staticmethod
    def _close(sp):
        try:
            sp[1].send(json.dumps({"type": "CloseStream"})); sp[0].__exit__(None, None, None)
        except Exception:
            pass

    def _keep(self):
        from websockets.sync.client import connect
        while True:
            with self.lock:
                sp = self.spare
            try:
                if sp is None or time.time() - sp[3] > 420 or sp[2] != dg_url(self.words):
                    url = dg_url(self.words)
                    ctx = connect(url, additional_headers={"Authorization": f"Token {DG_KEY}"}, open_timeout=5, max_size=None)
                    ws = ctx.__enter__()
                    with self.lock:
                        old, self.spare = self.spare, (ctx, ws, url, time.time())
                    if old:
                        self._close(old)
                else:
                    sp[1].send(json.dumps({"type": "KeepAlive"}))
            except Exception as e:
                log("deepgram warm:", repr(e))
                with self.lock:
                    self.spare = None
                time.sleep(10)
            self.need.wait(3)
            self.need.clear()


WARM = None
BACKLOG = None          # the mic's queue: how far behind the processing is (each item is 80 ms of sound)


def behind() -> str:
    n = BACKLOG.qsize() if BACKLOG is not None else 0
    return f" · {n * 80} ms behind the mic" if n else ""

_DANGLE = {"in", "on", "at", "to", "for", "of", "the", "a", "an", "and", "or", "but", "with", "from", "my", "is", "set",
           "play", "turn", "what's", "what", "how", "about", "by", "into", "some", "until", "till"}


def wake_only(text: str) -> bool:
    """Just "Alexa" so far (maybe with Room's own voice before it) — the request is still to come."""
    return bool(WAKE_RE.search(text or "")) and not Ears.strip_wake(text)


def dangling(text: str) -> bool:
    """Ends mid-sentence ("what's the weather tomorrow in"), or nothing yet after "Alexa" — wait for the rest. (Ending
    the stream there and opening a new one lost whatever was said in between — "what's the weather" of "…tomorrow".)"""
    if wake_only(text):
        return True
    w = re.sub(r"[^a-z' ]", "", (text or "").lower()).split()
    return bool(w) and w[-1] in _DANGLE and not (text or "").rstrip().endswith((".", "?", "!"))


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
        self.url = dg_url(words)
        self.spare = WARM.take(words) if WARM else None
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
            t = self.text()
            if not t and getattr(self, "last_interim", ""):
                t = self.last_interim           # Deepgram sometimes finalises a weak line as nothing — keep its guess
            self.on_done(t, self)

    def _run(self):
        from websockets.sync.client import connect
        t0 = time.time()
        try:
            if self.spare:
                ctx, ws = self.spare[0], self.spare[1]
            else:
                ctx = connect(self.url, additional_headers={"Authorization": f"Token {DG_KEY}"}, open_timeout=4, max_size=None)
                ws = ctx.__enter__()
        except Exception as e:
            log("deepgram connect:", repr(e))
            self.failed = True
            self._finish()
            return
        log("deepgram: ready connection" if self.spare else f"deepgram: connected in {time.time() - t0:.2f} s")
        self.opened.set()

        def sender():
            try:
                while not self.done:
                    try:
                        b = self.q.get(timeout=2)
                    except queue.Empty:
                        ws.send(json.dumps({"type": "KeepAlive"})); continue
                    if b is None:
                        ws.send(json.dumps({"type": "Finalize"}))
                        time.sleep(1.2)
                        ws.send(json.dumps({"type": "CloseStream"}))
                        return
                    ws.send(b)
                ws.send(json.dumps({"type": "CloseStream"}))     # given up on: let it go now, not in 10 s
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
                        if t:
                            self.last_interim = " ".join([*self.finals, t])
                    if self.text():
                        self.on_partial(self.text(), self)
                    if m.get("from_finalize") and self.finals:
                        break
                    if m.get("speech_final") and self.finals and not dangling(self.text()):
                        break                       # a pause after a whole sentence (not "…tomorrow in")
                elif kind == "UtteranceEnd" and self.finals and not dangling(self.text()):
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
        self.ring: list[np.ndarray] = []           # the last 2 s of sound (so a confirmed "Alexa" isn't cut off)
        self.confirming = False
        self.confirm_started = 0.0
        self.last_candidate = -10.0
        self.speaker = Speaker()
        self.state = "idle"            # idle · listening · thinking
        self.rec: list[np.ndarray] = []
        self.heard_speech = False
        self.quiet_since = 0.0
        self.started = 0.0
        self.last_wake = -10.0
        self.words: list[str] = []
        self.listen_after_speaking = False
        self.barge = False
        self.need_wake_word = False
        self.cues = os.path.join(DATA, "cues"); os.makedirs(self.cues, exist_ok=True)
        # the phone's own chimes (listen · done · miss); generated tones only if they're missing
        here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cues")
        self.chimes = {n: os.path.join(here, n + ".wav") for n in ("listen", "done", "miss")}
        if not os.path.exists(self.chimes["listen"]):
            self.chimes["listen"] = tone(os.path.join(self.cues, "on.wav"), [660, 990])
        self.wait = 6.0

    # ---------------------------------------------------------------- listening
    # ---------------------------------------------------------------- "Alexa?" — checked by Deepgram
    def start_confirm(self):
        """A maybe-"Alexa" from the local detector: stream the last 2 s and what follows to Deepgram, quietly. Only if the
        words start with Alexa does Room wake (tone, screen); the same stream then carries on with the command."""
        self.confirming = True
        self.confirmed = False
        self.confirm_started = self.clock
        self.barge = self.speaker.busy           # Room is talking: its own voice is in what's heard
        self.need_wake_word = self.barge         # …so only what comes after "Alexa" counts
        self.dg = Deepgram(self.words, self._confirm_partial, self._dg_done)
        for c in self.ring:
            self.dg.push(c)

    def _confirm_partial(self, text, src=None):
        if src is not None and src is not self.dg:
            return                                  # an older stream, still finishing — not this turn
        if self.confirming and not self.confirmed:
            first = text if self.barge else " ".join(text.split()[:4])
            if WAKE_RE.search(first):
                self.confirmed = True
                self.confirming = False
                log(f"wake: confirmed ({text!r}) {self.clock - self.confirm_started:.1f} s after the first hint{behind()}")
                emit(ev="wake")
                self.begin_listening(keep=True)
            return
        if getattr(self, "need_wake_word", False) and not WAKE_RE.search(text):
            return                                  # still only the room / Room's own voice before "Alexa"
        cmd = self.strip_wake(text)
        if cmd:
            emit(ev="partial", text=cmd)

    @staticmethod
    def strip_wake(text):
        """What was said after the (last) "Alexa" — anything before it is the room, or Room's own voice."""
        ms = list(re.finditer(r"\b(?:(?:hey|okay|ok|hi)\s+)?(?:alexa|alexis|alexia|alexi|alex|lexa|elexa|alaxa|alyssa)\b[\s,.!?]*", text, re.I))
        return (text[ms[-1].end():] if ms else text).strip()

    def chime(self, name):
        f = self.chimes.get(name)
        if f and os.path.exists(f):
            subprocess.Popen(["pw-play", "--volume", "0.9", f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def begin_listening(self, keep=False, preroll=False, follow=False):
        self.speaker.stop()
        # after a question the mic just stays open for a few seconds — no chime, no wake word (like the phone)
        if not follow:
            self.chime("listen")
        self.wait = 8.0 if follow else 6.0
        self.state = "listening"
        self.rec_pre = list(self.ring[-25:])            # the 2 s before (the "Alexa"), for the saved recording
        self.provisional = False
        self.spoke_at = getattr(self, "clock", 0.0)
        self.rec = []
        self.heard_speech = False
        self.started = getattr(self, "clock", 0.0)
        self.quiet_since = 0.0
        self.vad.reset_states()
        self.confirming = False
        if not keep:
            self.need_wake_word = False
            if self.dg:
                self.dg.done = True; self.dg.close()
            self.dg = None
            if DG_KEY:
                self.dg = Deepgram(self.words, self._confirm_partial, self._dg_done)
                self.confirmed = True                # tapped (or clearly heard): nothing to check
                if preroll:                          # "Alexa, turn off…" in one breath: the start is already said
                    for c in self.ring[-12:]:
                        self.dg.push(c)
        warm_speech()
        emit(ev="listening", follow=follow)

    def keep_turn(self, text):
        """Keep what the panel heard for each request (exactly what went to recognition), so it can be listened to:
        ~/room-heard/<time> <what it understood>.wav — the last 15. "keepAudio": false in config.json turns it off."""
        if CFG.get("keepAudio") is False or not self.rec:
            return
        try:
            d = os.path.expanduser("~/room-heard"); os.makedirs(d, exist_ok=True)
            slug = re.sub(r"[^a-z0-9 ']+", "", (text or "nothing heard").lower())[:50].strip() or "nothing heard"
            path = os.path.join(d, time.strftime("%H-%M-%S ") + slug + ".wav")
            with wave.open(path, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
                w.writeframes(np.concatenate(getattr(self, "rec_pre", []) + self.rec).astype("<i2").tobytes())
            for old in sorted(os.listdir(d))[:-15]:
                os.unlink(os.path.join(d, old))
        except Exception as e:
            log("keep audio:", e)

    def _dg_done(self, text, src=None):
        if src is not None and src is not self.dg:
            return                                  # an older stream finishing late — must not end this one
        dg = self.dg
        if self.confirming and not getattr(self, "confirmed", False):
            # it wasn't "Alexa" after all — drop it quietly
            log(f"wake: not Alexa ({text!r})")
            self.confirming = False
            self.dg = None
            return
        if getattr(self, "need_wake_word", False) and text and not WAKE_RE.search(text):
            text = ""                               # nothing after a wake word — it was only the room talking
        cmd = self.strip_wake(text)
        if not cmd and text and self.state == "listening" and not getattr(dg, "failed", False):
            # just "Alexa" — now listen for what comes next
            self.dg = None
            self.dg = Deepgram(self.words, self._confirm_partial, self._dg_done)
            self.confirmed = True
            self.started = self.clock
            return
        text = cmd if cmd else text
        if getattr(dg, "failed", False):
            # Deepgram couldn't be reached — carry on listening the offline way (pause detection, then whisper);
            # what's been recorded so far is kept
            self.dg = None
            log("deepgram unreachable — listening offline")
            return
        self.dg = None
        self.state = "idle"
        self.keep_turn(text)
        emit(ev="heard", text=text, quiet=bool(getattr(self, "provisional", False) and not text))

    # ---------------------------------------------------------------- the mic, evened out
    # The Surface's mic is quiet from across a room. An even level (below) lifts it so the wake word, the
    # pause detection and whisper all get speech at a useful level; `ref` is a slowly-falling peak of what's heard.
    ref = 0.05
    floor = 0.002
    target_set = bool(CFG.get("mic"))              # a mic chosen in config is left alone
    def even(self, pcm: np.ndarray) -> np.ndarray:
        x = pcm.astype(np.float32) / 32768
        # the mic can sit far off zero (a DC offset) — take it out so loudness means sound
        self.dc = getattr(self, "dc", float(np.mean(x))) * 0.95 + float(np.mean(x)) * 0.05
        x = x - self.dc
        # an even voice level, inside Room only (the system's mic slider is never touched): speech is brought to about
        # −20 dB whether you're at the panel or across the room. The boost drops at once when you're close and loud (so
        # nothing distorts), creeps back up slowly, and only moves on speech — silence never gets turned up into hiss.
        rms = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
        pk = float(np.max(np.abs(x))) if len(x) else 0.0
        self.floor = min(rms, self.floor * 1.002 + 1e-6) if rms > 0 else self.floor     # background noise
        g = getattr(self, "g", 3.0)
        top = float(CFG.get("maxGain", 8.0))
        if rms > max(self.floor * 3, 0.0015):
            # follows the voice's loudness (not single peaks — a loud "Alexa" or a tap on the keyboard used to drop the
            # boost for seconds and leave the question after it too quiet); the soft limiter below catches peaks
            want = float(np.clip(0.1 / rms, 1.0, top))
            g += (want - g) * (0.35 if want < g else 0.08)
        self.g = g
        self.gain = g
        y = x * g
        y = np.where(np.abs(y) < 0.8, y, np.sign(y) * (0.8 + 0.2 * np.tanh((np.abs(y) - 0.8) / 0.2)))
        out = (y * 32767).astype(np.int16)
        self.plain = out
        return self.clean(out)

    def clean(self, pcm: np.ndarray) -> np.ndarray:
        """Noise suppression — what Windows' Realtek/Intel mic processing did and Linux doesn't: the fan, the street
        and the room's hum are taken out (WebRTC's suppressor, the one in video calls), the voice is left. 10 ms at a
        time. "noiseSuppression" in config.json: 0 off … 4 strongest (2 by default)."""
        ns = getattr(self, "ns", None)
        if ns is None:
            lvl = int(CFG.get("noiseSuppression", 2))
            try:
                from webrtc_noise_gain import AudioProcessor
                ns = AudioProcessor(0, lvl) if lvl > 0 else False
                log(f"mic: noise suppression level {lvl}" if ns else "mic: noise suppression off")
            except Exception as e:
                ns = False
                log("mic: no noise suppression —", repr(e))
            self.ns = ns
        if not ns:
            return pcm
        b = pcm.tobytes()
        return np.frombuffer(b"".join(ns.Process10ms(b[i:i + 320]).audio for i in range(0, len(b) - 319, 320)), dtype=np.int16)

    @staticmethod
    def pin_input():
        """Set the mic's levels once, so nothing moves them around. micVolume (0–1, PipeWire's software level — 1.0 is
        untouched; anything lower throws signal away) and micBoost (0–3: the codec's own preamp, +10 dB a step,
        before any noise is added) in config.json — scripts/mic-tune.sh measures and sets both."""
        if CFG.get("micVolume") is not False:
            v = float(CFG.get("micVolume", 1.0))
            try:
                subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", f"{v:.2f}"], timeout=3)
                log(f"mic input fixed at {int(v * 100)}%")
            except Exception as e:
                log("mic input:", e)
        # PipeWire sets the codec's own controls from its volume, so these go after it (and win)
        time.sleep(0.5)
        if CFG.get("micCapture") is not None:
            c = int(CFG["micCapture"])
            try:
                subprocess.run(["amixer", "-q", "-c", "0", "cset", "name=Capture Volume", f"{c},{c}"], timeout=3)
                log(f"mic capture {(c - 67) * 0.5:+.1f} dB")
            except Exception as e:
                log("mic capture:", e)
        if CFG.get("micBoost") is not None:
            b = int(CFG["micBoost"])
            try:
                subprocess.run(["amixer", "-q", "-c", "0", "cset", "name=Internal Mic Boost Volume", f"{b},{b}"], timeout=3)
                log(f"mic boost +{b * 10} dB")
            except Exception as e:
                log("mic boost:", e)

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
        pcm = self.even(raw)                          # cleaned (noise suppressed): for the wake word and the screen
        plain = self.plain                            # evened but not suppressed: for recognition (suppression's
                                                      # artefacts cost Deepgram more words than the noise does)
        level = float(np.sqrt(np.mean((pcm.astype(np.float32) / 32768) ** 2))) / max(self.gain, 1.0)
        self.level_n = getattr(self, "level_n", 0) + 1
        if self.level_n % 2 == 0:                     # ~6 a second is plenty for the screen
            emit(ev="level", v=round(level, 5))
        heard_wake, score = self.wake.hit(pcm)
        self.ring.append(plain)
        if len(self.ring) > 25:
            self.ring.pop(0)
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
        if DG_KEY and not self.wake.pv:
            # lenient local trigger → Deepgram decides
            # while Room talks, its own voice scores up to ~0.3 — so only a clear "Alexa" (0.6+) wakes it at once then
            if (score >= (0.6 if self.speaker.busy else CONFIDENT) and self.state == "idle"
                    and not (self.speaker.busy and CFG.get("bargeIn") is False) and now - self.last_wake > 1.5):
                # clearly "Alexa" — wake at once (and if a check was under way, it becomes the command stream)
                self.last_wake = now
                talking = self.speaker.busy
                self.wake.reset()
                emit(ev="wake")
                # under 0.5 it's very likely, not certain: if nothing at all is said, close without a sound
                provisional = score < 0.5
                if self.confirming and self.dg:
                    self.confirmed = True; self.confirming = False
                    log(f"wake: sure ({score:.2f})")
                    self.begin_listening(keep=True)
                else:
                    self.begin_listening(preroll=True)
                    self.need_wake_word = talking        # its own voice is in the pre-roll: only what follows "Alexa"
                self.provisional = provisional
                log(f"wake: {score:.2f}{' (provisional)' if provisional else ''}{behind()}")
                return
            if self.speaker.busy and CFG.get("bargeIn") is False:
                return                                  # interrupting by voice switched off
            if (score >= (max(0.35, CANDIDATE * 2) if self.speaker.busy else CANDIDATE) and not self.confirming and self.state in ("idle",) and now - self.last_candidate > 2):
                self.last_candidate = now
                self.start_confirm()
                return
            if self.confirming and not self.dg:
                self.confirming = False
            elif self.confirming:
                self.dg.push(plain)
                if now - self.confirm_started > 4:            # no "Alexa" in time
                    self.dg.done = True; self.dg.close(); self.dg = None
                    self.confirming = False
                return
        elif heard_wake and now - self.last_wake > 1.5:
            self.last_wake = now
            self.wake.reset()
            emit(ev="wake")
            self.begin_listening()
            return
        if self.state != "listening":
            return
        dg = self.dg                                 # (Deepgram's thread can finish it at any moment)
        if dg:
            # live recognition: everything after "Alexa" streams straight to Deepgram (no waiting for the tone);
            # it decides when you've finished. A copy is kept in case it can't be reached.
            dg.push(plain)
            self.rec.append(plain)
            # our own ear for "they've stopped": Deepgram's can wait seconds when the room isn't quiet. After ~0.7 s
            # without speech (and not mid-sentence — "…tomorrow in"), ask Deepgram to finish now.
            vp = float(self.vad.predict(pcm, frame_size=480))
            if vp > 0.4:
                self.spoke_at = now
            said = dg.text()
            quiet = now - getattr(self, "spoke_at", now)
            if (said and now - self.started > 1.0
                    and (quiet > 0.7 and not dangling(said) or quiet > (self.wait - 1 if wake_only(said) else 2.0))
                    and not getattr(dg, "closing", False)):
                dg.closing = True
                dg.close()
            # a "maybe Alexa" that nobody follows up within 2.5 s: it was the room — close quietly, soon
            if self.provisional and not said and now - self.started > 2.5 and getattr(self, "spoke_at", 0) <= self.started + 0.3:
                dg.close()
                self.started = now + 999
                return
            if now - self.started > 10 or (now - self.started > self.wait and not said):
                dg.close()
                self.started = now + 999            # don't ask twice
            return
        if now - self.started < 0.35:
            return                                  # the start tone is still playing — don't send it to whisper
        self.rec.append(plain)
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
        nothing = not self.heard_speech and now - self.started > self.wait - 1
        too_long = now - self.started > 8
        if long_pause or nothing or too_long:
            audio = np.concatenate(self.rec) if self.rec else np.zeros(0, np.int16)
            self.state = "thinking"
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
        self.keep_turn(text)
        emit(ev="heard", text=text)

    # ---------------------------------------------------------------- commands from Room
    def command(self, c: dict):
        cmd = c.get("cmd")
        if cmd == "listen":
            self.begin_listening(follow=bool(c.get("follow")))
        elif cmd == "chime":
            self.chime(c.get("name", ""))
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
            if WARM:
                WARM.words = self.words

    def _spoken(self):
        emit(ev="spoken")
        if self.listen_after_speaking:
            self.listen_after_speaking = False
            self.begin_listening()


def main():
    for tool in ("pw-record", "pw-play"):
        if not shutil.which(tool):
            emit(ev="error", msg=f"{tool} is missing"); return
    global WARM
    WARM = Warm() if DG_KEY else None
    try:
        Ears.pin_input()
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
    # both of the Surface's mics, steered at whoever's talking (voice/beam.py); "beam": false → one mixed channel
    ch = 2 if CFG.get("beam", True) else 1
    # small buffers: the sound reaches the wake word ~40 ms after it's spoken, not after pw-record's default wait
    lat = ["--latency", "40ms"] if "--latency" in helptext else []
    cmd = ["pw-record", *raw, *lat, "--rate", str(RATE), "--channels", str(ch), "--format", "s16", "-"]
    beam = None
    if ch == 2:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from beam import Beam
        beam = Beam()
    if target:
        cmd[1:1] = ["--target", target]
    log("mic:", target or "default", "· two mics, steered" if beam else "")
    emit(ev="ready", mic=target or "default")
    while True:
        rec = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        n = CHUNK * 2 * ch
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
        global BACKLOG
        BACKLOG = qa

        def reader(proc=rec, swap=swap):
            while True:
                b = proc.stdout.read(n)
                if not b or len(b) < n:
                    qa.put(None); return
                a = np.frombuffer(b, dtype=">i2" if swap else "<i2").astype(np.int16)
                qa.put(beam.mix(a.reshape(-1, 2)) if beam else a)
        threading.Thread(target=reader, daemon=True).start()
        slow, count, behind_said = 0.0, 0, 0.0
        while True:
            chunk = qa.get()
            if chunk is None:
                break
            if qa.qsize() > 4 and ears.state == "idle" and not ears.confirming:
                # fallen behind (the Surface was busy): drop the old sound so "Alexa" is heard now, not seconds late
                dropped = 0
                while qa.qsize() > 1:
                    c = qa.get()
                    if c is None:
                        qa.put(None); break
                    dropped += 1
                log(f"caught up — skipped {dropped * 80} ms of old sound")
                ears.wake.reset()
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
                if beam and DEBUG:
                    log(f"steering: {beam.lag:+d} samples")
                slow, count = 0.0, 0
        log("mic stopped — reopening in 2 s")
        time.sleep(2)


if __name__ == "__main__":
    main()
