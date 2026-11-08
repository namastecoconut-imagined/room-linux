"""Two mics into one, steered at whoever's talking (delay-and-sum).

The Surface's two front mics are a hand-span apart, so someone off to one side reaches one mic up to ~0.7 ms before the
other. Simply mixing them (what a mono recording does) then blurs the voice — whole bands of it cancel. Here the delay
between the mics is measured while someone's speaking (GCC-PHAT), the later mic is shifted to line up, and only then
are they added: the voice adds up, the room's noise (different at each mic) doesn't.
"""
import numpy as np

MAXLAG = 24                      # ±1.5 ms at 16 kHz — more than the mics' spacing can produce


class Beam:
    def __init__(self):
        self.lag = 0
        self.votes: list[int] = []
        self.hist = np.zeros((MAXLAG * 2, 2), np.float32)
        self.noise = 1e-4

    @staticmethod
    def delay(a: np.ndarray, b: np.ndarray) -> int:
        """How many samples b is behind a (GCC-PHAT)."""
        n = 1 << int(np.ceil(np.log2(len(a) + len(b))))
        A, B = np.fft.rfft(a, n), np.fft.rfft(b, n)
        R = B * np.conj(A)
        R /= np.abs(R) + 1e-9
        cc = np.fft.irfft(R, n)
        cc = np.concatenate((cc[-MAXLAG:], cc[:MAXLAG + 1]))
        return int(np.argmax(cc)) - MAXLAG

    def mix(self, st: np.ndarray) -> np.ndarray:
        """st: (n, 2) int16 → (n,) int16, steered. Output runs MAXLAG samples (1.5 ms) behind the input."""
        x = st.astype(np.float32)
        e = float(np.mean(x ** 2))
        self.noise = min(e, self.noise * 1.01 + 1e-3) if e > 0 else self.noise
        if e > self.noise * 6:                      # someone's talking: measure where from
            self.votes = (self.votes + [self.delay(x[:, 0], x[:, 1])])[-9:]
            self.lag = int(np.median(self.votes))
        h = np.concatenate([self.hist, x])          # MAXLAG*2 of history, then this chunk
        L, n = MAXLAG * 2, len(x)
        t = np.arange(n) + L - MAXLAG               # output sample t ↔ input t − MAXLAG
        y = (h[t, 0] + h[t + self.lag, 1]) / 2      # b is `lag` behind a: take b that much later
        self.hist = h[-L:]
        return np.clip(y, -32768, 32767).astype(np.int16)
