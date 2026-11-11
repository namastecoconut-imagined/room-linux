"""The assistant's speaker: one audio stream, opened once and kept open, fed from a buffer.

Why it's built this way: the last attempt piped speech into `pw-play` as it arrived from the network. Whenever the
pipe was empty at the moment the speaker needed sound — speech arriving no faster than it plays — that moment was a
gap mid-word (pw-top's ERR count climbed through every long answer). Here the speaker never waits on the network:

  • feed() puts samples into a ring buffer (resampled once to the stream's rate);
  • the audio callback only copies out what's there, and plays silence if there's nothing — it never blocks;
  • it starts speaking once PREBUFFER seconds are in hand (or the answer is complete), and if it ever runs out
    mid-answer it goes quiet and waits until more is in hand — a short pause, never a stutter — holding more each
    time it happens in the same answer;
  • every played block is handed to on_played (the echo canceller's reference, later — exactly what was played).

stats() reports how often it ran out (starved) and how often the sound system missed a block (xruns).

When an answer ends is PREDICTED, not waited for: Room made every sample, so it knows how long they take to play.
Each feed() moves `until` on by its length (from now, if the speaker had already played everything before it), plus
the stream's latency. `speaking` is true until then (+ a little slack) — or until it has really all played, if
that's sooner. So a speaker that stalls (the sound system restarted under it) can never hold the assistant on
"speaking": at `until` it moves on, the rest is dropped, and if the stream itself has died (its callback, which runs
every 50 ms even in silence, stopped) it's reopened in the background, so the next answer is heard.
"""
import threading
import time

import numpy as np


class Player:
    def __init__(self, rate=48000, block=2400, prebuffer=0.30, reprime=0.15, seconds=30, device=None,
                 on_played=None, name="Room assistant"):
        self.rate, self.block, self.device = rate, block, device
        self.prebuffer, self.reprime = int(prebuffer * rate), int(reprime * rate)
        self.buf = np.zeros(int(seconds * rate), dtype=np.float32)
        self.r = self.w = 0                  # read / write positions (ever-growing; index modulo len)
        self.lock = threading.Lock()
        self.playing = False                 # sound is going out (else waiting to have enough in hand)
        self.ended = True                    # the current answer has all arrived
        self.need = self.prebuffer
        self.on_played = on_played
        self.name = name
        self.starved = self.xruns = 0
        self.dry = 0                         # times it ran out in this answer
        self.played = 0                      # samples sent to the speaker (the clock answer text follows)
        self.stream = None
        self._rs = {}                        # one streaming resampler per input rate
        self.until = 0.0                     # when the current answer will have finished playing (predicted)
        self.last_cb = time.monotonic()      # the stream's last callback (every 50 ms while it's alive)
        self._healing = False

    LATENCY = 0.25                           # what the sound system holds (the stream's latency, below)
    SLACK = 0.5                              # allowance on top of the prediction
    DEAD = 2.0                               # no callback for this long: the stream has died

    # ---------------------------------------------------------------- the stream
    def start(self):
        import os
        os.environ.setdefault("PIPEWIRE_PROPS", '{ application.name = "Room assistant" media.role = "Assistant" }')
        import sounddevice as sd
        self.stream = sd.OutputStream(samplerate=self.rate, blocksize=self.block, channels=1, dtype="float32",
                                      latency=0.25, device=self.device, callback=self._callback)
        # 50 ms blocks and a quarter of a second queued in the sound system: the callback runs in Python, so it can be
        # a little late when the Surface is busy — with 20 ms blocks and "high" (~0.1 s) it missed blocks and the
        # voice broke up. Adds nothing you'd hear at the start of an answer.
        self.stream.start()

    def close(self):
        if self.stream:
            self.stream.stop(); self.stream.close(); self.stream = None

    def _callback(self, out, frames, _time, status):
        self.last_cb = time.monotonic()
        if status.output_underflow:
            self.xruns += 1
        with self.lock:
            have = self.w - self.r
            if not self.playing and (have >= self.need or (self.ended and have > 0)):
                self.playing = True
            n = min(have, frames) if self.playing else 0
            if n:
                i = self.r % len(self.buf)
                first = min(n, len(self.buf) - i)
                out[:first, 0] = self.buf[i:i + first]
                if n > first:
                    out[first:n, 0] = self.buf[:n - first]
                self.r += n
            out[n:, 0] = 0.0
            if self.playing and n < frames:
                if not self.ended:
                    # ran out mid-answer: pause, and hold more in hand before carrying on — more each time it
                    # happens in the same answer (0.15 → 0.3 → 0.6 s, never longer: a 1.5 s silence mid-sentence sounded broken), so a slow connection costs a few
                    # pauses, not dozens
                    self.starved += 1
                    self.dry += 1
                    self.need = min(int(0.6 * self.rate), self.reprime * 2 ** (self.dry - 1))
                self.playing = False
            self.played += n
        if self.on_played and n:
            self.on_played(out[:, 0].copy())

    # ---------------------------------------------------------------- what's said
    def begin(self):
        """A new answer is starting (whatever was playing stops)."""
        if self.dead:
            self.heal()
        with self.lock:
            self.r = self.w
            self.playing, self.ended, self.need, self.dry = False, False, self.prebuffer, 0
            self.until = 0.0
        self._rs.clear()

    def feed(self, samples, rate=None):
        """Add audio: int16 bytes or a float array, at `rate` (resampled once, as it streams)."""
        if isinstance(samples, (bytes, bytearray, memoryview)):
            x = np.frombuffer(samples, dtype="<i2").astype(np.float32) / 32768
        else:
            x = np.asarray(samples, dtype=np.float32)
        rate = rate or self.rate
        if rate != self.rate:
            import soxr
            rs = self._rs.get(rate) or self._rs.setdefault(rate, soxr.ResampleStream(rate, self.rate, 1, dtype="float32"))
            x = rs.resample_chunk(x)
        with self.lock:
            room = len(self.buf) - (self.w - self.r)
            x = x[:room]                     # (a 30 s buffer never fills with spoken answers)
            now = time.monotonic()
            self.until = max(self.until, now + self.LATENCY) + len(x) / self.rate
            i = self.w % len(self.buf)
            first = min(len(x), len(self.buf) - i)
            self.buf[i:i + first] = x[:first]
            if len(x) > first:
                self.buf[:len(x) - first] = x[first:]
            self.w += len(x)

    def end(self):
        """The whole answer has arrived: play out what's left even if it's less than the prebuffer."""
        for rate, rs in list(self._rs.items()):
            tail = rs.resample_chunk(np.zeros(0, dtype=np.float32), last=True)
            if len(tail):
                self._rs.pop(rate)
                self.feed(tail)
        with self.lock:
            self.ended = True

    def stop(self):
        """Stop talking now (barge-in, a tap): what's buffered is dropped."""
        with self.lock:
            self.r = self.w
            self.playing, self.ended = False, True
            self.until = 0.0

    @property
    def busy(self) -> bool:
        """Sound still waiting to be played (as the stream reports it)."""
        with self.lock:
            return self.w > self.r

    @property
    def speaking(self) -> bool:
        """Still speaking: there's sound left AND its predicted end hasn't passed. Never stuck on a stalled speaker."""
        return self.busy and time.monotonic() < self.until + self.SLACK

    @property
    def dead(self) -> bool:
        return self.stream is None or time.monotonic() - self.last_cb > self.DEAD

    def heal(self):
        """Reopen the stream (in the background — never blocks the assistant). Called when its callback stopped."""
        if self._healing:
            return
        self._healing = True

        def go():
            print("[assistant] voice: the speaker stopped responding — reconnecting it", flush=True)
            old, self.stream = self.stream, None

            def shut():
                try:
                    if old:
                        old.abort(); old.close()
                except Exception:
                    pass
            t = threading.Thread(target=shut, daemon=True); t.start(); t.join(2.0)
            if not t.is_alive():             # (a stream that won't even close is left behind, not waited on)
                try:
                    import sounddevice as sd
                    sd._terminate(); sd._initialize()     # PortAudio forgets the old sound system
                except Exception:
                    pass
            try:
                self.start()
                self.last_cb = time.monotonic()
                print("[assistant] voice: speaker reconnected", flush=True)
            except Exception as e:
                print(f"[assistant] voice: couldn't reconnect the speaker — {e!r} (trying again next answer)", flush=True)
            finally:
                self._healing = False
        threading.Thread(target=go, daemon=True).start()

    def stats(self) -> dict:
        return {"starved": self.starved, "xruns": self.xruns, "buffered_s": round((self.w - self.r) / self.rate, 2)}

    def wait_done(self):
        """Until the answer has played — or its predicted end has passed. Then anything left is dropped, and a dead
        stream is reopened."""
        while self.speaking:
            time.sleep(0.05)
        if self.busy:
            left = (self.w - self.r) / self.rate
            print(f"[assistant] voice: the speaker fell {left:.1f} s behind its predicted end — moved on", flush=True)
            self.stop()
            if self.dead:
                self.heal()
