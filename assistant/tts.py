"""Room's voice: Sarvam's Bulbul (v4 Flash, "Ishita · customer" unless another is chosen), streamed — the answer is
sent the moment it's complete and played as it arrives, so Room starts talking with the first sound. Nothing is made
on the Surface any more: Kokoro, made here, only just kept up with playback, and once the screen got busier (the cats)
it fell behind and the voice stopped between sentences.

  • one kept connection (listen.py's, opened the moment "Alexa" is heard) — a cold one cost ~2 s;
  • every answer is brought to the same loudness (Leveller): voices and lines come out at different levels;
  • short lines ("Done.", "Lights off.", "Sorry, I can't reach the internet right now.") are made once and kept on
    disk (~/.local/state/room/voice/<voice>/): they play at once, cost nothing again, and the internet line is there
    when the internet isn't;
  • if Sarvam can't be reached mid-answer, Room says the kept internet line instead (the words are on the screen).

Sarvam is paid per character: ₹10 per 10,000 with v4 Flash — about 1.5 paise for a usual answer.
"""
import hashlib
import os
import threading
import time

import numpy as np

from .listen import _http, log
from .player import Player

URL = "https://api.sarvam.ai/text-to-speech/stream"
MODEL = "bulbul:v4-flash"
DEFAULT = "ishita_en_customer"
RATE = 24000
CACHE = os.path.expanduser("~/.local/state/room/voice")
OFFLINE = "Sorry, I can't reach the internet right now."
COMMON = ["Done.", "Okay.", "Sure.", "Sorry, I didn't catch that.", OFFLINE, "Let me check.", "On it.", "Lights off.",
          "Lights on.", "Goodnight.", "Sorry, I couldn't reach my brain just now — try again in a moment."]
KEEP = 60                       # lines up to this long are kept once made
TARGET = 10 ** (-17 / 20)       # the speech level every answer is brought to (RMS of its voiced parts, of full scale)


class Leveller:
    """Brings an answer to TARGET as it streams: the level of its voiced parts so far (it settles within the first
    few words, which the speaker holds back anyway) sets the gain, eased from one chunk to the next, and a soft
    ceiling keeps the loudest syllables from clipping."""
    def __init__(self):
        self.level, self.gain = None, None

    def whole(self, x: np.ndarray) -> np.ndarray:
        self.level = None
        self.__call__(x)                                     # (measures it all)
        self.gain = None
        return self.__call__(x)

    def __call__(self, x: np.ndarray) -> np.ndarray:
        n = 480                                              # 20 ms frames
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


def voice_ok(name) -> bool:
    return isinstance(name, str) and "_en_" in name


class Voice:
    def __init__(self, key: str, voice: str = DEFAULT):
        self.key = key
        self.voice = voice if voice_ok(voice) else DEFAULT
        self.player = Player()
        self.player.start()
        self.gen = 0
        self.making = False
        threading.Thread(target=self._prepare, args=(self.voice,), daemon=True).start()

    def set_voice(self, voice: str):
        """Another voice (Settings → More settings → Voice): from the next line on; its usual lines made meanwhile."""
        if voice_ok(voice) and voice != self.voice:
            self.voice = voice
            log(f"voice: {voice}")
            threading.Thread(target=self._prepare, args=(voice,), daemon=True).start()

    # ---------------------------------------------------------------- kept lines
    def _path(self, text, voice=None):
        h = hashlib.sha1(text.strip().encode()).hexdigest()[:16]
        return os.path.join(CACHE, voice or self.voice, h + ".pcm")

    def _kept(self, text, voice=None):
        try:
            with open(self._path(text, voice), "rb") as f:
                b = f.read()
            return np.frombuffer(b, dtype="<i2").astype(np.float32) / 32768 if b else None
        except OSError:
            return None

    def _keep(self, text, x, voice=None):
        x = Leveller().whole(x)                              # (all of it known: levelled as one)
        p = self._path(text, voice)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".part", "wb") as f:
            f.write((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
        os.replace(p + ".part", p)

    def _prepare(self, voice):
        """The usual short lines, made once (and the internet line, for when there isn't any)."""
        if not self.key:
            return
        for t in COMMON:
            if self._kept(t, voice) is None:
                try:
                    self._make(t, lambda x: None, lambda: True, voice)
                except Exception as e:
                    log("voice: couldn't make the usual lines yet —", repr(e)); return

    # ---------------------------------------------------------------- making a line
    def _make(self, text, out, live, voice=None):
        """Streams `text` from Sarvam, levelled, into out(samples) as it arrives, while live() says so. Lines up to
        KEEP characters are kept. Returns the samples made."""
        lev, got, left, head = Leveller(), [], b"", True
        r = _http().post(URL, stream=True, timeout=(6, 20),
                         headers={"api-subscription-key": self.key, "Content-Type": "application/json"},
                         json={"text": text, "language_code": "en-IN", "model": MODEL, "speaker": voice or self.voice,
                               "output_audio_codec": "linear16", "speech_sample_rate": RATE, "enable_preprocessing": True})
        try:
            if r.status_code != 200:
                raise RuntimeError(f"Sarvam {r.status_code}: {r.text[:160]}")
            for chunk in r.iter_content(chunk_size=4800):
                if not live():
                    return None
                if not chunk:
                    continue
                b = left + chunk
                if head:                                     # (a WAV header, if one comes)
                    head = False
                    if b[:4] == b"RIFF":
                        i = b.find(b"data")
                        b = b[i + 8:] if i >= 0 else b[44:]
                cut = len(b) - len(b) % 2
                left = b[cut:]
                if cut:
                    y = lev(np.frombuffer(b[:cut], dtype="<i2").astype(np.float32) / 32768)
                    got.append(y)
                    out(y)
        finally:
            r.close()
        x = np.concatenate(got) if got else np.zeros(0, np.float32)
        if len(text) <= KEEP and len(x):
            self._keep(text, x, voice)
        return x

    # ---------------------------------------------------------------- speaking
    def say(self, text: str, done=None, started=None, voice=None):
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
                self.player.feed(y, RATE)
                if first[0]:
                    first[0] = False
                    log(f"voice: first sound {time.time() - t0:.2f} s after the answer")
                    if started:
                        try:
                            started()
                        except Exception as e:
                            log("voice: started():", repr(e))
            try:
                kept = self._kept(text, voice)
                if kept is not None:
                    out(kept)
                elif not self.key:
                    raise RuntimeError("no sarvamKey in config.json")
                else:
                    self._make(text, out, lambda: g == self.gen, voice)
            except Exception as e:
                log("voice:", repr(e))
                if first[0] and g == self.gen and text != OFFLINE:      # nothing said yet: the internet line
                    k = self._kept(OFFLINE, voice)
                    if k is None:
                        k = self._kept(OFFLINE, DEFAULT)                    # (a voice just chosen: Ishita's)
                    if k is not None:
                        self.player.feed(k, RATE)
            finally:
                self.making = False
                if g == self.gen:
                    self.player.end()
                    self.player.wait_done()
                    s1 = self.player.stats()
                    if s1["starved"] or s1["xruns"]:
                        log(f"voice: broke up — ran dry {s1['starved']}× (arrived slower than it played), "
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
