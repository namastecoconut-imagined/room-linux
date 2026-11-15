"""Room's voice: its own Piper voice (en_US-room-medium), made on the Surface itself — offline, free, about ten times
faster than it's spoken. Trained on 16 minutes of speech, fine-tuned from Piper's Lessac voice.

The voice files are not in the repo: they live in ~/.local/share/room/voices/ (en_US-room-medium.onnx and its
.onnx.json), copied there once. Without them Room still answers, on the screen only.

  • the answer is made sentence by sentence and played as each is ready — Room starts with the first sentence;
  • every answer is brought to the same loudness (Leveller);
  • short lines ("Done.", "Lights off.") are made once and kept on disk (~/.local/state/room/voice/<voice>/) — they
    play at once. A retrained voice (a different file) gets its own lines; the old ones are cleared.
"""
import hashlib
import os
import shutil
import threading
import time

import numpy as np

from .listen import log
from .player import Player

NAME = "en_US-room-medium"
VOICES = os.path.expanduser("~/.local/share/room/voices")
CACHE = os.path.expanduser("~/.local/state/room/voice")
THREADS = 2                     # leaves the other cores to the panel, the cats and the speaker
COMMON = ["Done.", "Okay.", "Sure.", "Sorry, I didn't catch that.", "Sorry, I can't reach the internet right now.",
          "Let me check.", "On it.", "Lights off.", "Lights on.", "Goodnight.",
          "Sorry, I couldn't reach my brain just now — try again in a moment."]
KEEP = 60                       # lines up to this long are kept once made
TARGET = 10 ** (-17 / 20)       # the speech level every answer is brought to (RMS of its voiced parts, of full scale)


class Leveller:
    """Brings an answer to TARGET as it's made: the level of its voiced parts so far sets the gain, eased from one
    sentence to the next, and a soft ceiling keeps the loudest syllables from clipping."""
    def __init__(self):
        self.level, self.gain = None, None

    def whole(self, x: np.ndarray) -> np.ndarray:
        self.level = None
        self.__call__(x)                                     # (measures it all)
        self.gain = None
        return self.__call__(x)

    def __call__(self, x: np.ndarray) -> np.ndarray:
        n = 480                                              # ~20 ms frames
        if len(x) >= n:
            f = x[:len(x) // n * n].reshape(-1, n)
            rms = np.sqrt((f ** 2).mean(axis=1))
            v = rms[rms > 0.008]
            if len(v):
                r = float(np.sqrt((v ** 2).mean()))
                self.level = r if self.level is None else 0.7 * self.level + 0.3 * r
        want = 1.0 if self.level is None else float(np.clip(TARGET / self.level, 0.5, 4.0))
        g0 = want if self.gain is None else self.gain
        self.gain = want
        y = x * np.linspace(g0, want, len(x), dtype=np.float32)
        a = np.abs(y)
        over = a > 0.85
        if over.any():                                      # soft ceiling at full scale
            y[over] = np.sign(y[over]) * (0.85 + 0.15 * np.tanh((a[over] - 0.85) / 0.15))
        return y


def load(path: str):
    """The Piper voice, run the way the assistant can afford: two threads, no spinning while idle."""
    import onnxruntime
    from piper import PiperVoice
    v = PiperVoice.load(path)
    o = onnxruntime.SessionOptions()
    o.intra_op_num_threads = THREADS
    o.inter_op_num_threads = 1
    o.add_session_config_entry("session.intra_op.allow_spinning", "0")
    v.session = onnxruntime.InferenceSession(path, sess_options=o, providers=["CPUExecutionProvider"])
    return v


class Voice:
    def __init__(self, name: str = NAME):
        self.player = Player()
        self.player.start()
        self.gen = 0
        self.making = False
        self.lock = threading.Lock()                         # one sentence made at a time
        self.v, self.rate, self.tag = None, 22050, name
        path = os.path.join(VOICES, name + ".onnx")
        try:
            self.v = load(path)
            self.rate = self.v.config.sample_rate
            st = os.stat(path)
            self.tag = f"{name}-{st.st_size}-{int(st.st_mtime)}"     # (a retrained voice: new kept lines)
            log(f"voice: {name}")
        except Exception as e:
            log(f"voice: can't load {path} ({e!r}) — answers will be on the screen only. "
                f"Copy {name}.onnx and {name}.onnx.json into {VOICES}/")
        if self.v:
            threading.Thread(target=self._prepare, daemon=True).start()

    # ---------------------------------------------------------------- kept lines
    def _path(self, text):
        h = hashlib.sha1(text.strip().encode()).hexdigest()[:16]
        return os.path.join(CACHE, self.tag, h + ".pcm")

    def _kept(self, text):
        try:
            with open(self._path(text), "rb") as f:
                b = f.read()
            return np.frombuffer(b, dtype="<i2").astype(np.float32) / 32768 if b else None
        except OSError:
            return None

    def _keep(self, text, x):
        x = Leveller().whole(x)                              # (all of it known: levelled as one)
        p = self._path(text)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".part", "wb") as f:
            f.write((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
        os.replace(p + ".part", p)

    def _prepare(self):
        """Lines kept for another voice (an earlier one) cleared; the usual short lines made once."""
        try:
            for d in os.listdir(CACHE):
                if d != self.tag and os.path.isdir(os.path.join(CACHE, d)):
                    shutil.rmtree(os.path.join(CACHE, d), ignore_errors=True)
        except OSError:
            pass
        for t in COMMON:
            if self._kept(t) is None:
                try:
                    self._make(t, lambda x: None, lambda: True)
                except Exception as e:
                    log("voice: couldn't make the usual lines —", repr(e)); return

    # ---------------------------------------------------------------- making a line
    def _make(self, text, out, live):
        """Makes `text`, sentence by sentence, levelled, into out(samples) as each is ready, while live() says so.
        Lines up to KEEP characters are kept."""
        lev, got = Leveller(), []
        with self.lock:
            for chunk in self.v.synthesize(text):
                if not live():
                    return None
                y = lev(np.asarray(chunk.audio_float_array, dtype=np.float32))
                got.append(y)
                out(y)
        x = np.concatenate(got) if got else np.zeros(0, np.float32)
        if len(text) <= KEEP and len(x):
            self._keep(text, x)
        return x

    # ---------------------------------------------------------------- speaking
    def say(self, text: str, done=None, started=None):
        """Speak (replacing whatever was being said). started() as the first sound goes out (the screen shows the
        words then, not before); done() once it's all been played (or it was stopped)."""
        self.gen += 1
        g = self.gen
        self.player.begin()

        def go():
            self.making = True
            t0 = time.time()
            first = [True]

            def out(y):
                if g != self.gen:
                    return
                self.player.feed(y, self.rate)
                if first[0]:
                    first[0] = False
                    log(f"voice: first sound {time.time() - t0:.2f} s after the answer")
                    if started:
                        try:
                            started()
                        except Exception as e:
                            log("voice: started():", repr(e))
            try:
                kept = self._kept(text) if self.v else None
                if kept is not None:
                    out(kept)
                elif not self.v:
                    raise RuntimeError(f"no voice ({NAME}.onnx isn't in {VOICES})")
                else:
                    self._make(text, out, lambda: g == self.gen)
            except Exception as e:
                log("voice:", repr(e))
            finally:
                self.making = False
                if g == self.gen:
                    self.player.end()
                    self.player.wait_done()
                    s1 = self.player.stats()
                    if s1["starved"] or s1["xruns"]:
                        log(f"voice: broke up — ran dry {s1['starved']}× (made slower than it played), "
                            f"sound system missed {s1['xruns']} blocks (so far, all told)")
                    if done:
                        done()
        threading.Thread(target=go, daemon=True).start()

    def stop(self):
        self.gen += 1
        self.player.stop()

    @property
    def busy(self) -> bool:
        """Making or speaking. Speaking ends at the answer's predicted end (player.py), never on a stalled speaker."""
        return self.making or self.player.speaking
