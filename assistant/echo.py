"""Taking what Room is playing back out of the mic — a gentle, linear echo canceller.

WebRTC's AEC3 (tried first, via LiveKit) removed 30 dB of music on this Surface but ate your voice along with it:
its suppressor treats speech over loud music as echo, so "Alexa" scores fell from 0.6–0.96 to under 0.1. This one
only subtracts its estimate of the music (an adaptive filter: what was played, delayed and coloured the way the
room and speakers colour it) and never touches what's left — so your voice comes through exactly as it was, with
less music under it. It learns while only music is playing and holds still while you talk.

Partitioned-block frequency-domain NLMS (overlap-save): 8 ms blocks, a 200 ms echo tail; a bulk delay (Bluetooth
plays ~300 ms late) is taken off the reference first.

It rests while nothing plays: once a second and a bit of silence has gone through it, its estimate is zero and the
mic would come out exactly as it went in, so it hands the mic straight on — it was half the assistant's load in a
quiet room (measured with scripts/assistant-profile.sh). It picks up again the moment anything plays.
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


# ---------------------------------------------------------------- live: the mic and what's playing, in step
import json        # noqa: E402
import subprocess  # noqa: E402

RATE = 16000


def outputs() -> list:
    """The real outputs (node names): the Surface's speakers and any Bluetooth speaker."""
    try:
        nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
    except Exception:
        return []
    out = []
    for n in nodes:
        p = (n.get("info") or {}).get("props") or {}
        name = p.get("node.name", "")
        if n.get("type") == "PipeWire:Interface:Node" and p.get("media.class") == "Audio/Sink" and (
                name.startswith("bluez_output") or (name.startswith("alsa_output") and "hdmi" not in name)):
            out.append(name)
    return out


class EchoCanceller:
    """The mic, minus what Room is playing. The mic and what every output is sent (its monitor) arrive together, in one
    two-channel PipeWire stream (listen.Mic links them), so they're in step sample for sample — reading them as two
    separate streams lined them up by the wall clock, which wandered by tens of ms and left nothing to cancel.
    What's playing is delayed by how late the mic hears it (GCC-PHAT, measure()), then LinearAEC takes it out.

    Measured on this Surface (bench/aec_eval, 10 lines over music): "Alexa" caught 4/10 → 10/10 on the Surface's
    speakers and 9/10 → 10/10 on the Xiaomi; Sarvam got 2/10 lines right → 8/10 on the Surface's speakers."""

    def __init__(self):
        self.aec = LinearAEC()
        self.shift = 0
        self.hist = np.zeros(RATE, np.float32)            # the last second of what's playing (the delay line)
        self.win_m = np.zeros(4 * RATE, np.float32)        # the last 4 s of mic and of what's playing (for the delay)
        self.win_r = np.zeros(4 * RATE, np.float32)
        self.looks = []
        self.clock = 0.0                                   # seconds of mic heard
        self.next_delay = 5.0
        self.said = 0.0
        self.removed = []
        self.silent = 0                                    # samples since anything played
        self.rested = False

    QUIET = 1e-4                                           # what's playing is silence below this (−80 dB)

    def process(self, mic: np.ndarray, ref: np.ndarray) -> np.ndarray:
        """One frame of mic and of what's playing (float, in step) → the mic with it taken out (int16)."""
        m = len(mic)
        self.clock += m / RATE
        # Nothing played for longer than the delay line (1 s) plus the filter's tail (200 ms): what it would take out
        # is zero, so the mic is handed straight on. Its learning (the echo path) is kept for when music comes back.
        if float(np.max(np.abs(ref))) < self.QUIET:
            self.silent += m
            if self.silent > len(self.hist) + self.aec.B * self.aec.P:
                if not self.rested:
                    self.rested = True
                    print("[assistant] echo: resting while nothing plays (it picks up the moment anything does)", flush=True)
                return (np.clip(mic, -1, 1) * 32767).astype(np.int16)
        else:
            self.silent = 0
        self.hist = np.concatenate([self.hist[m:], ref])
        d = self.hist[len(self.hist) - m - self.shift:len(self.hist) - self.shift]
        B = self.aec.B
        out = np.empty(m, np.float32)
        for i in range(0, m, B):
            out[i:i + B] = self.aec.process(mic[i:i + B], d[i:i + B])
        self._watch(mic, ref, out, self.clock)
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

