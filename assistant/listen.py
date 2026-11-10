"""The assistant's ears: the raw Surface mic → the wake word → (music down) → your request, recorded until you've
finished → Sarvam's words.

Built on step 3 and 4's measurements on this Surface:
  • the RAW mic, held at 65 % (100 % clipped — 47,000 clipped samples in 3 minutes of music; the noise-suppressed
    "Surface Mic" was no better for the wake word, and worse for every speech-to-text option);
  • Sarvam, sent the whole request once you've finished (7.1 % word errors, all the Hinglish right, 0.4 s) — not
    streamed: its live guesses were the garbage on screen last time;
  • you've finished when, after you've started talking, there's END_QUIET of silence (Silero VAD); before you
    start, it waits up to ONSET for you (a pause after "Alexa" is fine).

Wake word: Room's own "Alexa" (assistant/models/alexa.onnx, LiveKit WakeWord); openWakeWord's stock "alexa" only
if that's missing.
"""
import io
import json
import os
import queue
import subprocess
import threading
import time
import wave

import numpy as np

MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")     # ship with Room (assistant/models)
RATE, FRAME = 16000, 1280                          # 80 ms frames


def log(*a):
    print("[assistant]", *a, flush=True)


# ---------------------------------------------------------------- the mic
EARS = "room-assistant-ears"


class Mic:
    """The raw Surface mic at a fixed level, 80 ms frames (int16) on a queue — with what Room is playing (music, its
    own voice) taken back out first (assistant/echo.py; "assistant": {"echoCancel": false} in config.json turns it
    off).

    With echo cancelling it records one two-channel stream that nothing links by itself: Room links the mic into the
    left channel and the Surface's own speakers' monitor into the right, so the two arrive in step, sample for sample.
    The monitor link is passive — it never wakes a sleeping speaker or keeps it on. A Bluetooth speaker is never linked:
    with one in the stream PipeWire got killed every 8 s (no sound, the speaker dropped), and on the Xiaomi "Alexa" is
    10/10 without cancelling anyway. If PipeWire still restarts twice in 3 min with this on, echo cancelling turns itself
    off until the assistant restarts. If it ever doesn't deliver sound, it falls back to the plain mic without echo
    cancelling, so the assistant always hears."""

    def __init__(self, level=0.65, echo=True):
        self.level = level
        self.echo = None
        if echo:
            try:
                from .echo import EchoCanceller
                self.echo = EchoCanceller()
            except Exception as e:
                log(f"echo cancelling is off — {e!r}")
        self.q: queue.Queue = queue.Queue(maxsize=200)
        self.proc = None
        self.stopping = False
        self.tee = None                     # tests: called with (mic, playing, cleaned) for every frame
        self.hold = None                    # () -> True while Room is speaking: echo cancelling rests then (below)
        self.linked = set()
        self._pw_pid, self._pw_deaths = None, []

    @staticmethod
    def raw_source():
        nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if p.get("media.class") == "Audio/Source" and p.get("node.name", "").startswith("alsa_input"):
                return p["node.name"], n["id"]
        return None, None

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    @staticmethod
    def _link(out_port, in_port, passive=False):
        cmd = ["pw-link"] + (["--passive"] if passive else []) + [out_port, in_port]   # (--passive is a flag here)
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return r.returncode == 0 or "exist" in (r.stderr or "").lower()

    def _wire(self, mic):
        """(Re)link the mic and every output's monitor into the ears. True if the mic is in."""
        ok = self._link(f"{mic}:capture_FL", f"{EARS}:input_FL")
        from .echo import outputs
        for o in outputs():
            if not o.startswith("alsa_output"):
                continue                    # the Surface's own speakers only (see the class note)
            for ch in ("FL", "FR"):
                if self._link(f"{o}:monitor_{ch}", f"{EARS}:input_FR", passive=True) and o not in self.linked:
                    self.linked.add(o)
                    log(f"echo: listening to what's playing on {o}")
        return ok

    def _run(self):
        while not self.stopping:
            name, nid = self.raw_source()
            if not name:
                log("no mic found — trying again in 5 s"); time.sleep(5); continue
            subprocess.run(["wpctl", "set-volume", str(nid), f"{self.level:.2f}"], timeout=3)
            if self.echo and self._sound_system_keeps_dying():
                log("echo: the sound system restarted twice in 3 min with echo cancelling on — turned it off until "
                    "the assistant restarts")
                self.echo = None
            if self.echo and self._ears(name):
                continue
            self._plain(name)

    def _sound_system_keeps_dying(self) -> bool:
        """True once PipeWire has been restarted twice within 3 minutes while echo cancelling was on. Its stream
        (mic + speaker in one) once got PipeWire killed every 8 s, which dropped the Bluetooth speaker and all
        sound each time; this guard makes sure that can never run for more than a couple of restarts."""
        try:
            pid = subprocess.run(["systemctl", "--user", "show", "-p", "MainPID", "--value", "pipewire"],
                                 capture_output=True, text=True, timeout=3).stdout.strip()
        except Exception:
            return False
        if pid == "0":                      # mid-restart: not running yet — wait for its new PID
            pid = ""
        now = time.time()
        if self._pw_pid and pid and pid != self._pw_pid:
            self._pw_deaths = [t for t in self._pw_deaths if now - t < 180] + [now]
        if pid:
            self._pw_pid = pid
        return len(self._pw_deaths) >= 2

    def _ears(self, name) -> bool:
        """The two-channel stream, mic + what's playing. False if it couldn't get going (then: the plain mic)."""
        self.linked = set()
        self.proc = subprocess.Popen(["pw-record", "--raw", "--target", "0", "--rate", str(RATE), "--channels", "2",
                                      "--format", "f32", "--latency", "40ms", "-P",
                                      f'{{ node.name = "{EARS}" application.name = "Room assistant" }}', "-"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        wired = False
        for _ in range(30):                 # its ports appear a moment after it starts
            time.sleep(0.1)
            if self._wire(name):
                wired = True; break
        got = threading.Event()
        self.last = time.time()
        proc = self.proc

        def watchdog():
            # No sound within 3 s at the start: this way doesn't work here (then: the plain mic). And later, any 3 s
            # with no sound at all — the mic or a link went away (after a restart the mic's node can be made again
            # once the session settles, leaving this stream linked to nothing, waiting forever: "no sound from the
            # mic") — start it again, linked afresh.
            if not got.wait(3):
                if proc.poll() is None:
                    proc.terminate()
                return
            while proc.poll() is None and not self.stopping:
                time.sleep(1)
                if time.time() - self.last > 3:
                    log("the mic went quiet (its link went away) — linking it again")
                    proc.terminate(); return
        threading.Thread(target=watchdog, daemon=True).start()
        if not wired:
            log("echo: couldn't link the mic into the echo canceller — using the plain mic")
            self.proc.terminate(); self.echo = None; return False
        log(f"listening on {name} at {round(self.level * 100)} %, with echo cancelling")
        next_wire = time.time() + 10
        while not self.stopping:
            b = self.proc.stdout.read(FRAME * 8)
            if len(b) < FRAME * 8:
                break
            got.set(); self.last = time.time()
            x = np.frombuffer(b, dtype="<f4").reshape(-1, 2)
            mic, ref = x[:, 0].copy(), x[:, 1].copy()
            try:
                # while Room speaks, nothing is listening for you yet, and the canceller's Python work competed with
                # the voice for the interpreter (its sound callback runs in Python too) — the voice broke up
                if self.hold and self.hold():
                    f = (np.clip(mic, -1, 1) * 32767).astype(np.int16)
                else:
                    f = self.echo.process(mic, ref)
            except Exception as e:
                log(f"echo cancelling failed — {e!r}"); f = (np.clip(mic, -1, 1) * 32767).astype(np.int16)
            if self.tee:
                self.tee(mic, ref, f)
            self._put(f)
            if time.time() > next_wire:
                next_wire = time.time() + 10
                threading.Thread(target=self._wire, args=(name,), daemon=True).start()
        if self.proc.poll() is None:
            self.proc.terminate()
        if not got.is_set():
            log("echo: no sound came through the echo canceller — using the plain mic")
            self.echo = None; return False
        if not self.stopping:
            log("the mic stopped — starting it again"); time.sleep(1)
        return True

    def _plain(self, name):
        self.proc = subprocess.Popen(["pw-record", "--raw", "--target", name, "--rate", str(RATE), "--channels", "1",
                                      "--format", "s16", "--latency", "40ms", "-P",
                                      '{ application.name = "Room assistant" }', "-"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        log(f"listening on {name} at {round(self.level * 100)} %")
        while not self.stopping:
            b = self.proc.stdout.read(FRAME * 2)
            if len(b) < FRAME * 2:
                break
            self._put(np.frombuffer(b, dtype="<i2"))
        if self.proc.poll() is None:
            self.proc.terminate()
        if not self.stopping:
            log("the mic stopped — starting it again"); time.sleep(1)

    def _put(self, f):
        try:
            self.q.put_nowait(f)
        except queue.Full:                  # fallen behind: drop the oldest, stay live
            try: self.q.get_nowait()
            except queue.Empty: pass

    def stop(self):
        self.stopping = True
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()


# ---------------------------------------------------------------- the wake word
class Wake:
    """Room's own "Alexa" (assistant/models/alexa.onnx, LiveKit WakeWord, trained for Room: 10/10 in a quiet room and
    18/20 over music on this Surface's raw mic, no false alarms — the stock model caught 7/10 and 3/20). It ships with
    the repo, so every install and update has it. If it's missing or won't load, the stock openWakeWord "alexa"
    (also in assistant/models) takes over, so the assistant always has a wake word."""
    OWN = os.path.join(MODELS, "alexa.onnx")

    def __init__(self, threshold=None):
        self.threshold = float(threshold or 0.5)
        self.m = None
        if os.path.exists(self.OWN):
            try:
                from livekit.wakeword import WakeWordModel
                import onnxruntime as ort
                # One thread, no spinning: it runs every 80 ms, and onnxruntime's default (a worker per core, kept
                # spinning between runs) held three cores at ~60 % nonstop and made the Surface hot. Same scores.
                o = ort.SessionOptions(); o.inter_op_num_threads = o.intra_op_num_threads = 1
                o.add_session_config_entry("session.intra_op.allow_spinning", "0")
                self.m = WakeWordModel(models=[self.OWN], sess_options=o)
                self.name = "Room's own alexa.onnx (LiveKit)"
            except Exception as e:
                log(f"couldn't load Room's own wake word ({e!r}) — using the stock one")
        if self.m is None:
            from openwakeword.model import Model
            self.m = Model(wakeword_models=[os.path.join(MODELS, "alexa_v0.1.onnx")], inference_framework="onnx",
                           melspec_model_path=os.path.join(MODELS, "melspectrogram.onnx"),
                           embedding_model_path=os.path.join(MODELS, "embedding_model.onnx"))
            self.name = "openWakeWord alexa (stock — Room's own model is missing)"
        log("wake word:", self.name, "· threshold", self.threshold)

    def score(self, frame) -> float:
        return float(max(self.m.predict(frame).values() or [0.0]))

    def reset(self):
        self.m.reset()


# ---------------------------------------------------------------- speech or not (Silero VAD, ONNX)
class VAD:
    def __init__(self):
        import onnxruntime as ort
        o = ort.SessionOptions(); o.inter_op_num_threads = o.intra_op_num_threads = 1
        self.s = ort.InferenceSession(os.path.join(MODELS, "silero_vad.onnx"), sess_options=o,
                                      providers=["CPUExecutionProvider"])
        self.reset()

    def reset(self):
        self.state = np.zeros((2, 1, 128), np.float32)
        self.ctx = np.zeros(64, np.float32)
        self.pending = np.zeros(0, np.float32)

    def prob(self, frame) -> float:
        """Highest speech probability in this 80 ms frame (Silero runs on 32 ms pieces, with 64 samples of context)."""
        self.pending = np.concatenate([self.pending, frame.astype(np.float32) / 32768])
        best = 0.0
        while len(self.pending) >= 512:
            x = np.concatenate([self.ctx, self.pending[:512]])[None, :]
            out, self.state = self.s.run(None, {"input": x, "state": self.state, "sr": np.array(RATE, np.int64)})
            self.ctx = self.pending[448:512].copy()
            self.pending = self.pending[512:]
            best = max(best, float(out[0][0]))
        return best


# ---------------------------------------------------------------- the words
_HTTP = None


def _http():
    global _HTTP
    if _HTTP is None:
        import requests
        _HTTP = requests.Session()
    return _HTTP


def warm():
    """Open (or refresh) the connection to Sarvam while you're still talking — a cold one added ~2 s to the words
    (2.4 and 2.5 s instead of 0.45 on the Surface)."""
    def go():
        try:
            _http().head("https://api.sarvam.ai/", timeout=5)
        except Exception:
            pass
    threading.Thread(target=go, daemon=True).start()


def sarvam(pcm: np.ndarray, key: str, model="saarika:v2.5") -> str:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(pcm.astype("<i2").tobytes())
    r = _http().post("https://api.sarvam.ai/speech-to-text", headers={"api-subscription-key": key},
                      files={"file": ("request.wav", buf.getvalue(), "audio/wav")},
                      data={"model": model, "language_code": "en-IN"}, timeout=15)
    if r.status_code != 200:
        raise RuntimeError(f"Sarvam {r.status_code}: {r.text[:160]}")
    return (r.json().get("transcript") or "").strip()


# ---------------------------------------------------------------- one request
class Listener:
    """wait_wake() blocks until "Alexa"; record() then returns your request's audio (or None if you said nothing).
    on_wake / on_done are called as it goes (music down / back up, the screen, a chime)."""
    ONSET = 5.0             # after "Alexa": how long it waits for you to start
    END_QUIET = 1.0         # once you've started: this much silence and you've finished
    MAX = 15.0
    PRE = 0.15              # audio kept from just before the request starts (not the "Alexa" before it)
    TAIL = 0.25             # the end of "Alexa" itself is still in the first moment: not the start of a request

    def __init__(self, mic: Mic, wake: Wake, vad: VAD):
        self.mic, self.wake, self.vad = mic, wake, vad
        self.last_wake = 0.0
        self.tap = threading.Event()        # a tap on the panel: listen now, no wake word needed
        self.abort = threading.Event()      # stop listening to this request (a tap to cancel)
        self.on_level = None                # called ~12 times a second with your voice's level (0…1) while recording
        self.floor = -50.0                  # the room's own hum (dB), followed as it goes: the level is your voice above it

    verbose = False         # print the mic level and the best "Alexa" score every 2 s (tests)

    def wait_wake(self) -> float:
        best, loud, since = 0.0, 0.0, time.time()
        while True:
            if self.tap.is_set():
                self.tap.clear()
                return -1.0
            try:
                f = self.mic.q.get(timeout=0.5)
            except queue.Empty:
                if time.time() - since > 3:
                    log("no sound from the mic"); since = time.time()
                continue
            s = self.wake.score(f)
            if self.verbose:
                best = max(best, s)
                loud = max(loud, float(np.sqrt(np.mean((f.astype(np.float32) / 32768) ** 2))))
                if time.time() - since > 2:
                    print(f"   mic {20 * np.log10(max(loud, 1e-6)):6.1f} dB · best \"Alexa\" score {best:.2f}", flush=True)
                    best, loud, since = 0.0, 0.0, time.time()
            if s >= self.wake.threshold and time.time() - self.last_wake > 2.0:
                self.last_wake = time.time()
                self.wake.reset()
                return s

    def voice_level(self, f, p) -> float:
        """How loud *your voice* is, 0…1, for the screen. Only speech counts (Silero's probability gates it), and only
        what's above the room's own hum: a silent room used to read as a fair level — the raw mic at 65 % hears the
        fan and the room at about −50 dB — so the light on the listening screen kept swelling with nobody talking."""
        rms = float(np.sqrt(np.mean((f.astype(np.float32) / 32768) ** 2)))
        db = 20 * np.log10(max(rms, 1e-5))
        self.floor += (db - self.floor) * (0.3 if db < self.floor else 0.01)
        loud = max(0.0, min(1.0, (db - self.floor - 4) / 22))
        return loud * max(0.0, min(1.0, (p - 0.15) / 0.35))

    def record(self, onset=None, fresh=False):
        """fresh: drop what the mic queued before now (after Room has spoken: that's its own voice). Not after
        "Alexa" — whatever you started saying straight after it is already queued, and is wanted."""
        onset = onset or self.ONSET
        self.abort.clear()
        while fresh and not self.mic.q.empty():
            try: self.mic.q.get_nowait()
            except queue.Empty: break
        self.vad.reset()
        if self.on_level:
            self.on_level(0.0)
        frames, started, quiet, t0 = [], None, 0.0, time.time()
        while True:
            if self.abort.is_set():
                return None, {"onset": None, "took": time.time() - t0, "aborted": True}
            try:
                f = self.mic.q.get(timeout=0.5)
            except queue.Empty:
                continue
            frames.append(f)
            t = len(frames) * FRAME / RATE
            p = self.vad.prob(f)
            if self.on_level:
                self.on_level(self.voice_level(f, p))
            if p >= 0.5 and t > self.TAIL:
                if started is None:
                    started = max(0.0, t - FRAME / RATE - self.PRE)
                quiet = 0.0
            elif started is not None:
                quiet += FRAME / RATE
            if started is None and t > onset:
                if self.on_level:
                    self.on_level(0.0)
                return None, {"onset": None, "took": time.time() - t0}
            if started is not None and (quiet >= self.END_QUIET or t > self.MAX):
                if self.on_level:
                    self.on_level(0.0)
                a = np.concatenate(frames)[int(started * RATE):]
                return a, {"onset": round(started, 2), "spoke": round(t - quiet - started, 2), "took": round(time.time() - t0, 2)}
