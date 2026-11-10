"""The assistant's ears: the raw Surface mic → the wake word → (music down) → your request, recorded until you've
finished → Sarvam's words.

Built on step 3 and 4's measurements on this Surface:
  • the RAW mic, held at 65 % (100 % clipped — 47,000 clipped samples in 3 minutes of music; the noise-suppressed
    "Surface Mic" was no better for the wake word, and worse for every speech-to-text option);
  • Sarvam, sent the whole request once you've finished (7.1 % word errors, all the Hinglish right, 0.4 s) — not
    streamed: its live guesses were the garbage on screen last time;
  • you've finished when, after you've started talking, there's END_QUIET of silence (Silero VAD); before you
    start, it waits up to ONSET for you (a pause after "Alexa" is fine).

Wake-word engines: LiveKit WakeWord (a trained alexa*.onnx in the models folder — preferred) or openWakeWord's stock
"alexa" (until one's trained).
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

MODELS = os.path.expanduser("~/.local/share/room/assistant/models")
RATE, FRAME = 16000, 1280                          # 80 ms frames


def log(*a):
    print("[assistant]", *a, flush=True)


# ---------------------------------------------------------------- the mic
class Mic:
    """The raw Surface mic at a fixed level, 80 ms frames (int16) on a queue."""

    def __init__(self, level=0.65):
        self.level = level
        self.q: queue.Queue = queue.Queue(maxsize=200)
        self.proc = None
        self.stopping = False

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

    def _run(self):
        while not self.stopping:
            name, nid = self.raw_source()
            if not name:
                log("no mic found — trying again in 5 s"); time.sleep(5); continue
            subprocess.run(["wpctl", "set-volume", str(nid), f"{self.level:.2f}"], timeout=3)
            self.proc = subprocess.Popen(["pw-record", "--raw", "--target", name, "--rate", str(RATE), "--channels", "1",
                                          "--format", "s16", "--latency", "40ms", "-P",
                                          '{ application.name = "Room assistant" }', "-"],
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            log(f"listening on {name} at {round(self.level * 100)} %")
            while not self.stopping:
                b = self.proc.stdout.read(FRAME * 2)
                if len(b) < FRAME * 2:
                    break
                try:
                    self.q.put_nowait(np.frombuffer(b, dtype="<i2"))
                except queue.Full:                  # fallen behind: drop the oldest, stay live
                    try: self.q.get_nowait()
                    except queue.Empty: pass
            if self.proc.poll() is None:
                self.proc.terminate()
            if not self.stopping:
                log("the mic stopped — starting it again"); time.sleep(1)

    def stop(self):
        self.stopping = True
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()


# ---------------------------------------------------------------- the wake word
class Wake:
    def __init__(self, threshold=None):
        lk = sorted(f for f in os.listdir(MODELS) if f.lower().startswith("alexa") and f.endswith(".onnx")
                    and f != "alexa_v0.1.onnx") if os.path.isdir(MODELS) else []
        if lk:
            from livekit.wakeword import WakeWordModel
            self.m = WakeWordModel(models=[os.path.join(MODELS, lk[0])])
            self.name, self.threshold = f"LiveKit {lk[0]}", threshold or 0.5
        else:
            from openwakeword.model import Model
            self.m = Model(wakeword_models=[os.path.join(MODELS, "alexa_v0.1.onnx")], inference_framework="onnx",
                           melspec_model_path=os.path.join(MODELS, "melspectrogram.onnx"),
                           embedding_model_path=os.path.join(MODELS, "embedding_model.onnx"))
            self.name, self.threshold = "openWakeWord alexa (stock)", threshold or 0.5
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

    verbose = False         # print the mic level and the best "Alexa" score every 2 s (tests)

    def wait_wake(self) -> float:
        best, loud, since = 0.0, 0.0, time.time()
        while True:
            try:
                f = self.mic.q.get(timeout=3)
            except queue.Empty:
                log("no sound from the mic for 3 s"); continue
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

    def record(self):
        self.vad.reset()
        frames, started, quiet, t0 = [], None, 0.0, time.time()
        while True:
            f = self.mic.q.get()
            frames.append(f)
            t = len(frames) * FRAME / RATE
            p = self.vad.prob(f)
            if p >= 0.5 and t > self.TAIL:
                if started is None:
                    started = max(0.0, t - FRAME / RATE - self.PRE)
                quiet = 0.0
            elif started is not None:
                quiet += FRAME / RATE
            if started is None and t > self.ONSET:
                return None, {"onset": None, "took": time.time() - t0}
            if started is not None and (quiet >= self.END_QUIET or t > self.MAX):
                a = np.concatenate(frames)[int(started * RATE):]
                return a, {"onset": round(started, 2), "spoke": round(t - quiet - started, 2), "took": round(time.time() - t0, 2)}
