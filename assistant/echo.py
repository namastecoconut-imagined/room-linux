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
        self.pyy = self.pee = 1e-9

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
        ratio = self.pyy / (self.pee + 1e-9)
        step = self.mu * min(1.0, max(0.03, ratio))
        self.Px = 0.9 * self.Px + 0.1 * np.abs(Xk) ** 2
        E = np.fft.rfft(np.concatenate([np.zeros(B, np.float32), e]))
        G = np.conj(self.X) * E / (self.P * self.Px + 1e-6)
        g = np.fft.irfft(G, axis=1); g[:, B:] = 0                     # keep the filter causal (overlap-save)
        self.W += step * np.fft.rfft(g, axis=1)
        return e
