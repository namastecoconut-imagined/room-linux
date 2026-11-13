"""The cats' pen: a centreline (an SVG path) + a width and a pressure profile → a filled outline that swells and tapers
like ink from a pen."""
import math, random
from svgpathtools import parse_path

def profile(kind, s):
    if kind == "swell":  return math.sin(math.pi * s) ** 0.75
    if kind == "press":  return min(1, s * 7) * (1 - s) ** 0.55          # lands heavy, lifts off
    if kind == "flick":  return min(1, s * 9) * (1 - s) ** 1.4           # a quick flick to a point
    if kind == "lift":   return (s ** 0.55) * min(1, (1 - s) * 7)        # starts fine, ends heavy
    return min(1, s * 12) * min(1, (1 - s) * 12)                          # even

def stroke(d, w, kind="swell", seed=0, wobble=0.14, gaps=None):
    p = parse_path(d); L = p.length()
    n = max(24, int(L / 1.2)); rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]
    left, right, out = [], [], []
    def flush():
        if len(left) > 2:
            pts = left + right[::-1]
            out.append("M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + "Z")
        left.clear(); right.clear()
    for i in range(n + 1):
        s = i / n
        if gaps and any(a < s < b for a, b in gaps):
            flush(); continue
        t = p.ilength(s * L, s_tol=1e-4) if 0 < s < 1 else s
        pt = p.point(t); tg = p.unit_tangent(t) if 0 < t < 1 else p.unit_tangent(min(max(t, 1e-3), 1 - 1e-3))
        nx, ny = -tg.imag, tg.real
        k = profile(kind, s) * (1 + wobble * (math.sin(9 * s + ph[0]) * 0.6 + math.sin(23 * s + ph[1]) * 0.4))
        hw = max(0.18, w * k / 2)
        left.append((pt.real + nx * hw, pt.imag + ny * hw)); right.append((pt.real - nx * hw, pt.imag - ny * hw))
    flush()
    return " ".join(out)
