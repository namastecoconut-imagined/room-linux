"""Have you finished, or just paused? Smart Turn v3.2 (Daily / Pipecat, BSD-2-Clause, assistant/models/smart-turn-v3.2-cpu.onnx)
listens to *how* the request ended — a sentence that lands, or one that trails off — from the sound alone (no words
needed, so it works before Sarvam has heard anything).

Room used to wait for 1.4 s of silence after every request: 1.4 s of nothing before it even started thinking, and
still long enough to cut off "set a timer for… ten minutes". Now (listen.Listener): after a short pause it asks this;
a finished sentence ends the request at once, an unfinished one gets more time. If the model can't be loaded, Room
goes back to the 1.4 s rule; "assistant": {"smartTurn": false} in config.json does the same.
"""
import os
import time

import numpy as np

from .whisper_features import compute_whisper_log_mel_features

MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "smart-turn-v3.2-cpu.onnx")
RATE = 16000
SECONDS = 8                 # the model hears the last 8 s (earlier: dropped; shorter: silence before it)


class Turn:
    def __init__(self, path=MODEL):
        import onnxruntime as ort
        o = ort.SessionOptions()
        o.intra_op_num_threads = 1; o.inter_op_num_threads = 1         # one core, no spinning: it runs only at a pause
        o.add_session_config_entry("session.intra_op.allow_spinning", "0")
        o.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        self.s = ort.InferenceSession(path, sess_options=o, providers=["CPUExecutionProvider"])
        self.done(np.zeros(RATE, np.int16))                            # (warm: the first run is the slow one)

    def done(self, pcm: np.ndarray) -> tuple[float, float]:
        """pcm: the request so far (int16, 16 kHz, its pause included). → (how sure it's finished 0…1, seconds taken)."""
        t0 = time.perf_counter()
        x = pcm.astype(np.float32) / 32768
        n = RATE * SECONDS
        x = x[-n:] if len(x) > n else np.pad(x, (n - len(x), 0))
        f = compute_whisper_log_mel_features(x, do_normalize=True)[None]
        p = float(np.asarray(self.s.run(None, {"input_features": f})[0]).reshape(-1)[0])
        return p, time.perf_counter() - t0
