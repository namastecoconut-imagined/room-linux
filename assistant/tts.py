"""Room's voice: Kokoro ("Heart", af_heart), made on the Surface itself — free, offline — and played by player.py.

Measured on this Surface: the half-precision build (fp16) makes speech about 2× faster than it plays (int8 and full
precision were slower here). So:
  • the first piece of an answer is kept short (up to ~7 words, or the first clause if that's shorter), so Room
    starts talking ~1 s after the answer arrives; the rest is made, sentence by sentence, while it speaks;
  • short lines ("Done.", "Timer set for ten minutes.") are kept once made — the common ones are made at start —
    so they play instantly.
"""
import os
import re
import threading
import time

import numpy as np

from .player import Player

KDIR = os.path.expanduser("~/.local/share/room/assistant/kokoro")
COMMON = ["Done.", "Okay.", "Sure.", "Sorry, I didn't catch that.", "Sorry, I can't reach the internet right now.",
          "Let me check.", "On it.", "Lights off.", "Lights on.", "Goodnight."]


SMALL = {"a", "an", "the", "in", "on", "at", "of", "to", "for", "with", "and", "or", "but", "from", "by", "is", "are",
         "was", "it's", "its", "my", "your", "this", "that", "some", "about", "around", "like", "into"}


def pieces(text: str) -> list[str]:
    """The answer as speakable pieces: a short first one, then whole sentences."""
    sents = [s.strip() for s in re.findall(r"[^.!?]+[.!?]*", text) if s.strip()]
    if not sents:
        return []
    first, rest = sents[0], sents[1:]
    w = first.split()
    if len(w) > 9:
        cut = next((i + 1 for i, x in enumerate(w[:9]) if x.endswith((",", ";", ":")) and i >= 2), None)
        if not cut:                     # no comma early on: about 7 words, never ending on "in", "the", "and"…
            cut = 7
            while cut > 4 and w[cut - 1].lower().strip(",") in SMALL:
                cut -= 1
        rest.insert(0, " ".join(w[cut:]))
        first = " ".join(w[:cut])
    return [first] + rest


class Voice:
    def __init__(self, voice="af_heart", speed=1.0, model="kokoro-v1.0.fp16.onnx"):
        from kokoro_onnx import Kokoro
        import onnxruntime as ort
        # Kokoro leaves a core free: with every core busy making the next sentence, the speaker's callback (Python,
        # every 50 ms) was served late — the voice broke up ("sound system missed 46 blocks" an answer) while there
        # was plenty made ("ran dry 0×")
        o = ort.SessionOptions()
        o.intra_op_num_threads = max(1, (os.cpu_count() or 4) // 2 - 1)
        o.inter_op_num_threads = 1
        sess = ort.InferenceSession(os.path.join(KDIR, model), sess_options=o, providers=["CPUExecutionProvider"])
        self.k = Kokoro.from_session(sess, os.path.join(KDIR, "voices-v1.0.bin"))
        self.voice, self.speed = voice, speed
        self.player = Player()
        self.player.start()
        self.cache: dict[str, tuple[np.ndarray, int]] = {}
        self.gen = 0
        self.lock = threading.Lock()          # one Kokoro call at a time
        self.making = False
        threading.Thread(target=self._prepare, daemon=True).start()

    def _make(self, text):
        if text in self.cache:
            return self.cache[text]
        with self.lock:
            a, sr = self.k.create(text, voice=self.voice, speed=self.speed, lang="en-us")
        a = np.asarray(a, dtype=np.float32)
        if len(text) <= 60:
            self.cache[text] = (a, sr)
            if len(self.cache) > 300:
                self.cache.pop(next(iter(self.cache)))
        return a, sr

    def _prepare(self):
        for t in COMMON:
            try:
                self._make(t)
            except Exception as e:
                print("[assistant] voice:", repr(e), flush=True); return

    def say(self, text: str, done=None):
        """Speak (replacing whatever was being said). done() once it's all been played (or it was stopped)."""
        self.gen += 1
        g = self.gen
        self.player.begin()

        def go():
            self.making = True
            t0 = time.time()
            try:
                for i, p in enumerate(pieces(text)):
                    if g != self.gen:
                        break
                    a, sr = self._make(p)
                    if g != self.gen:
                        break
                    if i == 0:
                        print(f"[assistant] voice: first sound {time.time() - t0:.2f} s after the answer", flush=True)
                    self.player.feed(a, sr)
            except Exception as e:
                print("[assistant] voice:", repr(e), flush=True)
            finally:
                self.making = False
                if g == self.gen:
                    self.player.end()
                    self.player.wait_done()
                    s1 = self.player.stats()
                    if s1["starved"] or s1["xruns"]:
                        print(f"[assistant] voice: broke up — ran dry {s1['starved']}× (made slower than it played), "
                              f"sound system missed {s1['xruns']} blocks (so far, all told)", flush=True)
                    if done and g == self.gen:
                        done()
        threading.Thread(target=go, daemon=True).start()

    def stop(self):
        self.gen += 1
        self.player.stop()

    @property
    def busy(self) -> bool:
        return self.making or self.player.busy
