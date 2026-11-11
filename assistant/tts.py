"""Room's voice: Kokoro ("Heart", af_heart), made on the Surface itself — free, offline — and played by player.py.

The half-precision build (fp16) is the fastest here — but on the cool power profile it only just keeps up with
playback (2.06 s to make 2.03 s of speech; 1.43 s with the CPU boosted, see boost.py). So:
  • the first piece of an answer is very short (3–4 words, or up to the first comma), so Room starts talking well
    under a second after the answer arrives; the rest is made, sentence by sentence, while it speaks;
  • the CPU is boosted only while speech is being made (boost.py);
  • short lines ("Done.", "Timer set for ten minutes.") are kept once made — the common ones are made at start —
    so they play instantly.
"""
import os
import re
import threading
import time

import numpy as np

from .boost import Boost
from .player import Player

KDIR = os.path.expanduser("~/.local/share/room/assistant/kokoro")
COMMON = ["Done.", "Okay.", "Sure.", "Sorry, I didn't catch that.", "Sorry, I can't reach the internet right now.",
          "Let me check.", "On it.", "Lights off.", "Lights on.", "Goodnight."]


SMALL = {"a", "an", "the", "in", "on", "at", "of", "to", "for", "with", "and", "or", "but", "from", "by", "is", "are",
         "was", "it's", "its", "my", "your", "this", "that", "some", "about", "around", "like", "into",
         # nor on a word that leaves the sentence hanging ("what would you / like…")
         "you", "i", "we", "they", "he", "she", "would", "could", "should", "will", "can", "be", "have", "has", "do",
         "does", "did", "not", "so", "as", "than", "if", "when", "what", "which", "who", "how", "there", "here"}


def pieces(text: str) -> list[str]:
    """The answer as speakable pieces, growing: ~3 words, then ~5, ~7, ~10, ~14… — never past a sentence's end.

    Making a piece takes about as long as saying it (0.7× with the CPU boosted), so the first is tiny (Room starts
    talking almost at once) and each next one is only a little longer than what's already queued to play — it's made
    while that plays, so there's no gap. One tiny first piece followed by the whole rest of the sentence "ran dry":
    a pause after the opening words. Breaks fall on a sentence end, else a comma near the budget, never on "the",
    "and", "you"…"""
    words = text.split()
    out, i, budget = [], 0, 3.0
    while i < len(words):
        # this sentence's end, from here
        end = next((j + 1 for j in range(i, len(words)) if words[j].endswith((".", "!", "?"))), len(words))
        n = max(2, int(round(budget)))
        if end - i <= n + max(2, n // 3):            # the rest of the sentence fits (or nearly): take it whole
            cut = end
        else:
            cut = None
            for j in range(min(i + n + 1, end - 1), i, -1):         # a comma at or just past the budget, or before it
                if words[j - 1].endswith((",", ";", ":")):
                    cut = j
                    break
            if not cut:                 # nearest to the budget, either way, that doesn't end on "you", "the", "and"…
                near = sorted(range(i + 2, end), key=lambda c: (abs(c - (i + n)), c > i + n))
                cut = next((c for c in near if words[c - 1].lower().strip(",;:") not in SMALL), i + n)
            if end - cut <= 2:          # never leave a stub ("…like me / to do?"): the sentence's end goes with it
                cut = end
        out.append(" ".join(words[i:cut]))
        i = cut
        budget = min(budget * 1.45, 40)
    return out


class Voice:
    def __init__(self, voice="af_heart", speed=1.0, model="kokoro-v1.0.fp16.onnx", boost=True):
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
        self.boost = Boost(boost)
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

    def say(self, text: str, done=None, started=None):
        """Speak (replacing whatever was being said). started() as the first sound goes out (the screen shows the
        words then, not before); done() once it's all been played (or it was stopped)."""
        self.gen += 1
        g = self.gen
        self.player.begin()

        def go():
            self.making = True
            self.boost.on()
            t0 = time.time()
            try:
                for i, p in enumerate(pieces(text)):
                    if g != self.gen:
                        break
                    a, sr = self._make(p)
                    if g != self.gen:
                        break
                    self.player.feed(a, sr)
                    if i == 0:
                        print(f"[assistant] voice: first sound {time.time() - t0:.2f} s after the answer", flush=True)
                        if started:
                            try:
                                started()
                            except Exception as e:
                                print("[assistant] voice: started():", repr(e), flush=True)
            except Exception as e:
                print("[assistant] voice:", repr(e), flush=True)
            finally:
                self.making = False
                self.boost.off()
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
        """Making or speaking. Speaking ends at the answer's predicted end (player.py), never on a stalled speaker."""
        return self.making or self.player.speaking
