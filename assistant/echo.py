"""Taking what Room is playing back out of the mic — a gentle, linear echo canceller.

WebRTC's AEC3 (tried first, via LiveKit) removed 30 dB of music on this Surface but ate your voice along with it:
its suppressor treats speech over loud music as echo, so "Alexa" scores fell from 0.6–0.96 to under 0.1. This one
only subtracts its estimate of the music (an adaptive filter: what was played, delayed and coloured the way the
room and speakers colour it) and never touches what's left — so your voice comes through exactly as it was, with
less music under it. It learns while only music is playing and holds still while you talk.

Partitioned-block frequency-domain NLMS (overlap-save): 8 ms blocks, a 200 ms echo tail; a bulk delay (Bluetooth
plays ~300 ms late) is taken off the reference first.
"""
import numpy as np


class LinearAEC:
    def __init__(self, rate=16000, block=128, tail_ms=200, mu=0.5):
        self.B = block
        self.P = max(1, int(rate * tail_ms / 1000) // block)
        self.mu = mu
        self.W = np.zeros((self.P, block + 1), np.complex64)        # the echo path, per partition
        self.X = np.zeros((self.P, block + 1), np.complex64)        # the last P blocks of what was played
        self.prev = np.zeros(block, np.float32)
        self.Px = np.full(block + 1, 1e-6, np.float32)              # smoothed power of what's played, per bin
        self.pyy = self.pee = self.pmm = 1e-9
        self.bad = 0
        self.resets = 0

    def process(self, mic: np.ndarray, ref: np.ndarray) -> np.ndarray:
        """One block (B samples each, float): the mic with the echo of `ref` taken out."""
        B = self.B
        Xk = np.fft.rfft(np.concatenate([self.prev, ref]))
        self.prev = ref.astype(np.float32).copy()
        self.X = np.roll(self.X, 1, axis=0); self.X[0] = Xk
        Y = np.sum(self.W * self.X, axis=0)
        y = np.fft.irfft(Y)[B:]
        e = mic - y
        # learn only when it's mostly music: while you talk, the error is much bigger than the echo estimate
        self.pyy = 0.9 * self.pyy + 0.1 * float(np.mean(y * y))
        self.pee = 0.9 * self.pee + 0.1 * float(np.mean(e * e))
        self.pmm = 0.9 * self.pmm + 0.1 * float(np.mean(mic * mic))
        # never make it worse: if what's left is louder than the mic itself for a quarter of a second, the filter has
        # gone wrong (it used to run away — a wrong guess made a bigger step, which made a worse guess) — start again
        self.bad = self.bad + 1 if self.pee > 1.3 * self.pmm + 1e-9 else 0
        if self.bad > 30:
            self.W[:] = 0; self.bad = 0; self.resets += 1
        ratio = self.pyy / (self.pee + 1e-9)
        step = self.mu * min(1.0, max(0.03, ratio)) * (0.2 if self.pee > self.pmm else 1.0)
        self.Px = 0.9 * self.Px + 0.1 * np.abs(Xk) ** 2
        E = np.fft.rfft(np.concatenate([np.zeros(B, np.float32), e]))
        G = np.conj(self.X) * E / (self.P * self.Px + 1e-6)
        g = np.fft.irfft(G, axis=1); g[:, B:] = 0                     # keep the filter causal (overlap-save)
        self.W += step * np.fft.rfft(g, axis=1)
        return e if float(np.mean(e * e)) <= float(np.mean(mic * mic)) * 1.05 else mic.astype(np.float32)


# ---------------------------------------------------------------- what Room is playing, live
import json        # noqa: E402
import subprocess  # noqa: E402
import threading   # noqa: E402

RATE = 16000


class _Tap:
    """One output's monitor (what that speaker is being sent), read live into a ring. Passive: it never wakes a
    sleeping speaker or keeps one running — with nothing playing it just goes quiet (and reads as silence)."""
    LAG = int(0.10 * RATE)          # the reader stays this far behind the writer (both streams arrive in bursts)
    SLACK = int(0.25 * RATE)        # how far that may wander before it steps back in line

    def __init__(self, sink: str):
        self.sink = sink
        self.buf = np.zeros(RATE * 2, np.float32)
        self.w = 0                   # samples written so far
        self.r = None                # samples read so far (None: not in step yet)
        self.lock = threading.Lock()
        self.proc = subprocess.Popen(
            ["pw-record", "--raw", "--target", sink, "--rate", str(RATE), "--channels", "1", "--format", "s16",
             "--latency", "40ms", "-P",
             '{ stream.capture.sink = true node.passive = true application.name = "Room assistant echo reference" }',
             "-"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        n = len(self.buf)
        while True:
            b = self.proc.stdout.read(640)
            if not b:
                return
            x = np.frombuffer(b, dtype="<i2").astype(np.float32) / 32768
            with self.lock:
                i = self.w % n
                k = min(len(x), n - i)
                self.buf[i:i + k] = x[:k]; self.buf[:len(x) - k] = x[k:]
                self.w += len(x)

    def take(self, m: int) -> np.ndarray:
        """The next m samples, kept a steady LAG behind what's arrived (silence if nothing is playing)."""
        with self.lock:
            ahead = self.w - (self.r if self.r is not None else -10**9)
            if self.r is None or ahead > self.LAG + m + self.SLACK or ahead < m:
                if self.w < self.LAG + m:
                    return np.zeros(m, np.float32)
                self.r = self.w - self.LAG - m           # (re)join in step: just started, or caught up/fell behind
            n = len(self.buf); i = self.r % n
            out = np.concatenate([self.buf[i:], self.buf[:i]])[:m] if i + m > n else self.buf[i:i + m].copy()
            self.r += m
            return out

    def alive(self) -> bool:
        return self.proc.poll() is None

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()


class EchoCanceller:
    """The mic, minus what Room is playing: every real output's monitor (the Surface's speakers, a Bluetooth speaker —
    whatever's connected, checked every 10 s), summed, delayed by how late the mic hears it (measured from the
    music itself every few seconds: ~20 ms on the Surface's speakers, ~310 ms on the Xiaomi), then LinearAEC. The delay is measured with GCC-PHAT (see measure()).

    Measured on this Surface (bench/aec_eval, 10 lines over music): "Alexa" caught 4/10 → 10/10 on the Surface's
    speakers and 9/10 → 10/10 on the Xiaomi; Sarvam got 2/10 lines right → 8/10 on the Surface's speakers."""

    def __init__(self):
        self.taps: dict = {}
        self.aec = LinearAEC()
        self.shift = int(0.0 * RATE)
        self.hist = np.zeros(RATE, np.float32)            # the last second of reference (for the delay line)
        self.win_m = np.zeros(4 * RATE, np.float32)        # the last 4 s of mic and of what's playing (for the delay)
        self.win_r = np.zeros(4 * RATE, np.float32)
        self.looks = []
        self.clock = 0.0                                   # seconds of mic heard (its own clock, not the wall's)
        self.next_look = 0.0
        self.next_delay = 5.0
        self.said = 0.0
        self.removed = []

    def _outputs(self):
        try:
            nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
        except Exception:
            return None
        out = []
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            name = p.get("node.name", "")
            if n.get("type") == "PipeWire:Interface:Node" and p.get("media.class") == "Audio/Sink" and (
                    name.startswith("bluez_output") or (name.startswith("alsa_output") and "hdmi" not in name)):
                out.append(name)
        return out

    def _refresh(self):
        outs = self._outputs()
        if outs is None:
            return
        for s in list(self.taps):
            if s not in outs or not self.taps[s].alive():
                self.taps.pop(s).close()
        for s in outs:
            if s not in self.taps:
                self.taps[s] = _Tap(s)
                print(f"[assistant] echo: listening to what's playing on {s}", flush=True)

    def process(self, frame: np.ndarray) -> np.ndarray:
        """One mic frame (int16) → the same with Room's own sound taken out (int16)."""
        self.clock += len(frame) / RATE
        now = self.clock
        if now >= self.next_look:
            self.next_look = now + 10
            threading.Thread(target=self._refresh, daemon=True).start()
        m = len(frame)
        mic = frame.astype(np.float32) / 32768
        ref = np.zeros(m, np.float32)
        for t in list(self.taps.values()):
            ref += t.take(m)
        self.hist = np.concatenate([self.hist[m:], ref])
        d = self.hist[len(self.hist) - m - self.shift:len(self.hist) - self.shift]
        B = self.aec.B
        out = np.empty(m, np.float32)
        for i in range(0, m, B):
            out[i:i + B] = self.aec.process(mic[i:i + B], d[i:i + B])
        self._watch(mic, ref, out, now)
        return (np.clip(out, -1, 1) * 32767).astype(np.int16)

    def _watch(self, mic, ref, out, now):
        self.win_m = np.concatenate([self.win_m[len(mic):], mic])
        self.win_r = np.concatenate([self.win_r[len(ref):], ref])
        playing = float(np.mean(ref ** 2)) > 1e-5
        if playing:
            self.removed.append((float(np.mean(mic ** 2)), float(np.mean(out ** 2))))
        if now >= self.next_delay and float(np.mean(self.win_r ** 2)) > 1e-5:
            self.next_delay = now + 3
            ms, sure = self.measure()
            if sure:
                # three looks in a row within 15 ms of each other before acting on it (one stray look used to reset
                # the canceller every few seconds, and it never settled)
                self.looks = [x for x in self.looks[-2:] if abs(x - ms) <= 15] + [ms]
                if len(self.looks) >= 3:
                    ms = int(np.median(self.looks))
                    want = max(0, int((ms - 30) / 1000 * RATE))
                    if abs(want - self.shift) > int(0.03 * RATE):
                        print(f"[assistant] echo: the mic hears it {ms} ms late — following that", flush=True)
                        self.shift = want
                        self.aec = LinearAEC()
        if now - self.said > 120 and len(self.removed) > 300:
            mi = np.mean([x for x, _ in self.removed]); oi = np.mean([y for _, y in self.removed])
            print(f"[assistant] echo: taking out {10 * np.log10((mi + 1e-12) / (oi + 1e-12)):.1f} dB of what's playing", flush=True)
            self.said, self.removed = now, []

    def measure(self):
        """How late the mic hears what's playing (ms), and whether that's clear. GCC-PHAT over the last 4 s: it lines
        up the fine detail of the sound, not its loudness — loudness alone matched music with a beat to itself a
        beat later (it swung between 0 and 360 ms)."""
        n = len(self.win_m)
        X = np.fft.rfft(self.win_r, 2 * n); Y = np.fft.rfft(self.win_m, 2 * n)
        G = Y * np.conj(X); G /= np.abs(G) + 1e-9
        cc = np.fft.irfft(G)[:int(0.6 * RATE)]
        i = int(np.argmax(cc)); peak = cc[i]
        rest = np.abs(np.concatenate([cc[:max(0, i - 80)], cc[i + 80:]]))
        sure = rest.size > 0 and peak > 5 * float(np.percentile(rest, 99))
        return i * 1000 // RATE, bool(sure)

    def close(self):
        for t in self.taps.values():
            t.close()
