"""Can the Surface change a voice fast enough? RVC's own models (its v2, 40 kHz voice model, the HuBERT that hears
the words, the RMVPE that hears the pitch), run on this machine exactly as they would with a trained voice — the
weights are blank, which doesn't change how much work they are — on speech of 2 and 5 seconds, and in the 1-second
pieces Room would stream. "Speed" is how long it takes over how long the speech is: under 0.5 is the bar (twice as
fast as it plays, with Room, the cats and the assistant running).

Set up and run by scripts/rvc-speed.sh (everything in ~/rvc-test: its own Python, PyTorch, RVC's model code; nothing
in Room changes). scripts/experiments.sh clean takes it all off.
"""
import os
import sys
import time
import types

sys.path.insert(0, os.environ.get("RVC_REPO") or os.path.expanduser("~/rvc-test/repo"))
cg = types.ModuleType("tools.cuda_graph")                 # (RVC's GPU helper: on a CPU it just runs the model)
cg.run_cuda_graph = lambda model, name, fn, *a, **k: fn(*a, **k)
cg.cuda_graph_enabled = lambda *a, **k: False
sys.modules["tools"] = types.ModuleType("tools"); sys.modules["tools.cuda_graph"] = cg

import numpy as np
import torch
import torch.nn.functional as F

THREADS = int(os.environ.get("THREADS", "3"))              # (the assistant's voice used 3 of the 8: Room needs the rest)
torch.set_num_threads(THREADS)
torch.manual_seed(0)

from transformers import HubertConfig, HubertModel
from infer.module.models import SynthesizerTrnMs768NSFsid
from infer.rmvpe import E2E, MelSpectrogram

print(f"PyTorch {torch.__version__} · {THREADS} threads · building the models (blank weights)…", flush=True)
hubert = HubertModel(HubertConfig()).eval()                                  # ContentVec / HuBERT base: 12 layers, 768
pitch_net = E2E(4, 1, (2, 2)).eval()                                         # RMVPE
mel = MelSpectrogram(False, 128, 16000, 1024, 160, None, 30, 8000)
def voice_model(sr):                                     # RVC v2's two usual sizes: 40 kHz, and the lighter 32 kHz
    up, k, spec = ([10, 10, 2, 2], [16, 16, 4, 4], 1025) if sr == 40000 else ([10, 8, 2, 2], [20, 16, 4, 4], 513)
    m = SynthesizerTrnMs768NSFsid(spec, 32, 192, 192, 768, 2, 6, 3, 0, "1", [3, 7, 11], [[1, 3, 5]] * 3,
                                  up, 512, k, 109, 256, sr, is_half=False).eval()
    try:
        m.remove_weight_norm()
    except Exception:
        pass
    return m
SR = 40000
synth = voice_model(SR)
n = lambda m: sum(p.numel() for p in m.parameters()) / 1e6
print(f"  HuBERT {n(hubert):.0f} M weights · RMVPE {n(pitch_net):.0f} M · voice model {n(synth):.0f} M", flush=True)


@torch.no_grad()
def convert(seconds):
    """One piece of speech, 16 kHz in → the voice model's rate out. Returns the time each part took."""
    x = torch.randn(1, int(16000 * seconds)) * 0.1
    t = {}
    t0 = time.perf_counter()
    feats = hubert(x).last_hidden_state                                     # 50 a second
    feats = F.interpolate(feats.transpose(1, 2), scale_factor=2).transpose(1, 2)   # → 100 a second
    t["words"] = time.perf_counter() - t0
    t0 = time.perf_counter()
    m = mel(x, center=True)
    frames = m.shape[-1]
    pad = 32 * ((frames - 1) // 32 + 1) - frames
    hidden = pitch_net(F.pad(m, (0, pad)))[:, :frames]
    t["pitch"] = time.perf_counter() - t0
    L = min(feats.shape[1], hidden.shape[1])
    pitch = torch.randint(1, 255, (1, L)); pitchf = torch.rand(1, L) * 200 + 80
    t0 = time.perf_counter()
    out = synth.infer(feats[:, :L], torch.tensor([L]), pitch, pitchf, torch.tensor([0]))[0]
    t["voice"] = time.perf_counter() - t0
    return t, out.shape[-1] / SR


def report(label, seconds, runs=3):
    convert(seconds)                                                        # (warm up)
    best = None
    for _ in range(runs):
        t, dur = convert(seconds)
        tot = sum(t.values())
        if best is None or tot < sum(best[0].values()):
            best = (t, dur)
    t, dur = best
    tot = sum(t.values())
    parts = " · ".join(f"{k} {v:.2f} s" for k, v in t.items())
    verdict = "fast enough" if tot / seconds <= 0.5 else "borderline" if tot / seconds <= 0.8 else "too slow"
    print(f"{label}: {tot:.2f} s for {seconds:.1f} s of speech → speed {tot / seconds:.2f} ({verdict}) — {parts}", flush=True)
    return tot / seconds


res = {}
for sr in (40000, 32000):
    SR, synth = sr, voice_model(sr)
    print(f"\n— the {sr // 1000} kHz voice model —", flush=True)
    r = [report("a 2-second line", 2.0), report("a 5-second answer", 5.0)]
    s = report("a 1-second piece while streaming (+0.5 s before it)", 1.5)     # (0.5 s of what came before: smooth joins)
    res[sr] = (max(r), s * 1.5)
print()
for sr, (w, s) in res.items():
    v = "GO" if w <= 0.5 else "NO-GO" if w > 0.8 else "BORDERLINE"
    print(f"Verdict, {sr // 1000} kHz: {v} — whole lines take {w:.2f} of their length; a streamed 1-second piece {s:.2f} s", flush=True)
