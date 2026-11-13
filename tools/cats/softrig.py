"""The round, curvy pen-line cats as a puppet. A key pose is a set of points (the body's outline, legs, tail) and a
head (centre, size, tilt, ears, eyes, mouth); any two blend point by point, so every in-between frame can be drawn
and one action flows into the next. 200-unit box, ground at y 180, facing right."""
import math, random, re
from brush import stroke

INK, G, PINK, BEAN, EYEG, PUP, BELL, MOUTHC = "#f4eee6", "#f0a565", "#f3a9b6", "#d99aa3", "#dcdc92", "#24160f", "#ffcf6e", "#b86f7c"
GROUND = 180

def P(*xy): return [tuple(p) for p in xy]

# body outline order: chest-bottom, chest-front, neck, back1, back2, rump-top, rump-back, rump-bottom
STAND = dict(
    body=P((128, 150), (138, 128), (128, 108), (104, 103), (78, 105), (60, 112), (51, 130), (62, 150)),
    haunch=0.0,
    head=dict(x=141, y=97, r=24, tilt=0, earL=0, earR=0, eye=1.0, mouth=0.0),
    legs=[P((125, 146), (127, 163), (128, 180)), P((134, 144), (138, 162), (139, 180)),
          P((70, 146), (64, 162), (70, 180)), P((79, 146), (75, 163), (80, 180))],
    legv=[1, 1, 1, 1],
    tail=P((53, 118), (43, 104), (41, 86), (46, 72), (53, 67)),
    breath=0.0, squash=1.0,
)
SIT = dict(
    body=P((118, 177), (125, 142), (117, 113), (99, 112), (84, 126), (73, 146), (70, 166), (82, 180)),
    haunch=1.0,
    head=dict(x=115, y=90, r=25, tilt=0, earL=0, earR=0, eye=1.0, mouth=0.0),
    legs=[P((109, 136), (108, 158), (109, 180)), P((119, 136), (120, 158), (120, 180)),
          P((90, 166), (96, 172), (100, 180)), P((94, 166), (99, 172), (103, 180))],
    legv=[1, 1, 0.6, 0.0],
    tail=P((72, 172), (58, 180), (45, 178), (39, 168), (45, 161)),
    breath=0.0, squash=1.0,
)
LOAF = dict(
    body=P((132, 178), (140, 160), (128, 140), (104, 133), (80, 135), (62, 141), (52, 158), (62, 178)),
    haunch=0.3,
    head=dict(x=143, y=139, r=24, tilt=4, earL=0, earR=0, eye=1.0, mouth=0.0),
    legs=[P((134, 172), (138, 177), (140, 180)), P((140, 172), (144, 177), (148, 180)),
          P((70, 172), (72, 176), (74, 180)), P((78, 172), (80, 176), (82, 180))],
    legv=[1, 1, 0, 0],
    tail=P((53, 168), (40, 178), (27, 178), (17, 174), (13, 167)),
    breath=0.0, squash=1.0,
)
CURL = dict(
    body=P((118, 178), (136, 168), (132, 142), (110, 125), (84, 125), (64, 134), (55, 154), (68, 176)),
    haunch=0.4,
    head=dict(x=124, y=158, r=22, tilt=18, earL=-6, earR=-6, eye=0.0, mouth=0.0),
    legs=[P((120, 174), (124, 178), (128, 180)), P((126, 174), (130, 178), (134, 180)),
          P((70, 172), (72, 176), (74, 180)), P((78, 172), (80, 176), (82, 180))],
    legv=[0.8, 0, 0, 0],
    tail=P((60, 168), (76, 182), (100, 185), (124, 183), (142, 176)),
    breath=0.0, squash=1.0,
)

def lerp(a, b, t):
    if isinstance(a, dict): return {k: lerp(a[k], b[k], t) for k in a}
    if isinstance(a, list): return [lerp(x, y, t) for x, y in zip(a, b)]
    if isinstance(a, tuple): return tuple(x + (y - x) * t for x, y in zip(a, b))
    return a + (b - a) * t
def ease(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def copy(p): return lerp(p, p, 0)

# ---------------------------------------------------------------- smooth paths
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def pt(p): return f"{p[0]:.2f} {p[1]:.2f}"
def smooth(points, closed=False):
    pts = points + points[:3] if closed else points
    if len(pts) < 2: return ""
    d = f"M{pt(pts[0])}"
    n = len(pts) - (3 if closed else 1)
    for i in range(n):
        p0 = pts[i - 1] if (i > 0 or closed) else pts[i]; p1 = pts[i]; p2 = pts[i + 1]
        p3 = pts[i + 2] if i + 2 < len(pts) else p2
        c1 = add(p1, mul(sub(p2, p0), 1 / 6)); c2 = sub(p2, mul(sub(p3, p1), 1 / 6))
        d += f" C{pt(c1)} {pt(c2)} {pt(p2)}"
    return d
def rot(p, c, deg):
    r = math.radians(deg); s, co = math.sin(r), math.cos(r)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * co - y * s, c[1] + x * s + y * co)
def tf(d, f):
    """apply a point function to every x y pair of a path made of absolute M/C/L commands"""
    nums = [float(v) for v in re.findall(r"-?\d+\.?\d*", d)]
    cmds = re.findall(r"[MCLQ]", d)
    pts = [f((nums[i], nums[i + 1])) for i in range(0, len(nums), 2)]
    out, k = "", 0
    for seg in re.findall(r"[MCLQ][^MCLQ]*", d):
        c = seg[0]; n = len(re.findall(r"-?\d+\.?\d*", seg)) // 2
        out += c + " ".join(pt(pts[k + j]) for j in range(n)) + " "; k += n
    return out.strip()

# ---------------------------------------------------------------- drawing one frame
def head_marks(h, who):
    """the round head in its own frame (centre 0,0, radius 24), then placed, tilted and sized"""
    k = h["r"] / 24.0; c = (h["x"], h["y"])
    fx, fy = 5.0 * h.get("lx", 0.0), 3.5 * h.get("ly", 0.0)
    def place(d, pivot=None, ang=0, off=None):
        def f(p):
            if off: p = (p[0] + off[0], p[1] + off[1])
            if pivot is not None and ang: p = rot(p, pivot, ang)
            p = (p[0] * k, p[1] * k)
            p = rot(p, (0, 0), h["tilt"])
            return (p[0] + c[0], p[1] + c[1])
        return tf(d, f)
    L, out = [], []
    earL = place("M-22 -7 C-24 -17 -25 -25 -24 -33 C-17 -29 -11 -24 -7 -19", (-15, -13), h["earL"])
    earR = place("M7 -19 C12 -25 18 -30 25 -33 C26 -25 25 -16 22 -7", (15, -13), -h["earR"])
    L += [("line", earL, 1.9), ("line", place("M-7 -19 C-3 -20.5 3 -20.5 7 -19"), 1.4), ("line", earR, 1.9)]
    L += [("thin", place("M-21 -26 L-18 -20")), ("thin", place("M20 -26 L17 -20"))]
    L += [("line", place("M-22 -5 C-26 5 -24 15 -16 22"), 2.2), ("line", place("M22 -5 C26 5 24 15 16 22"), 2.2)]
    L += [("thin", place("M-16 23 C-8 27 8 27 16 23"))]
    if who == "bebo": L += [("thin", place("M-24 4 L-28 6 M-23 10 L-27 13"))]
    eo, mo = h["eye"], h["mouth"]
    for ex in (-10, 10):
        if who == "evan" and eo > (0.62 if h.get("lx") is not None else 0.35):
            cx, cy = place(f"M{ex} -2", off=(fx, fy))[1:].split()
            cx, cy = float(cx), float(cy); r = 4.3 * k * (min(1.2, eo) if h.get("lx") is None else min(1.2, 0.55 + 0.45 * eo)); pr = r * (0.5 + 0.6 * max(0.0, eo - 1.0))
            out.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{EYEG}"/><circle cx="{cx + .4:.2f}" cy="{cy + .6:.2f}" r="{pr:.2f}" fill="{PUP}"/><circle cx="{cx - 1.3:.2f}" cy="{cy - 1.4:.2f}" r="{.8 * k:.2f}" fill="#fff"/>')
        else:
            lift = 3.2 * (1 - eo) - (1.5 * eo if who == "bebo" else 0)
            L.append(("line", place(f"M{ex - 5} -2 C{ex - 2} {-2 + lift + 1.2} {ex + 2} {-2 + lift + 1.2} {ex + 5} -2", off=(fx, fy)), 1.8))
            if who == "bebo" and eo > 0.4:
                out.append(f'<path d="{place(f"M{ex - 3.5} -1.2 C{ex - 1} {0.6 * eo + .4} {ex + 1} {0.6 * eo + .4} {ex + 3.5} -1.2 Z", off=(fx, fy))}" fill="#f0b44c" fill-opacity="{min(1, (eo - .4) * 2):.2f}"/>')
    nose = place("M-2.7 5 C-1.5 4 1.5 4 2.7 5 C1.7 7 .7 7.8 0 7.8 C-.7 7.8 -1.7 7 -2.7 5 Z", off=(fx, fy))
    out.append(f'<path d="{nose}" fill="{PINK}"/>')
    if mo > 0.06:
        w_, h_ = 4 + 5 * mo, 3 + 13 * mo
        mouth = place(f"M{-w_ / 2} 9 C{-w_ / 2} {9 + h_} {w_ / 2} {9 + h_} {w_ / 2} 9 Z", off=(fx, fy))
        out.append(f'<path d="{mouth}" fill="{MOUTHC}"/>'); L.append(("thin", mouth))
    else:
        L.append(("thin", place("M0 8.4 C-1 10.8 -3 11.4 -5 10.4 M0 8.4 C1 10.8 3 11.4 5 10.4", off=(fx, fy))))
    L.append(("thin", place("M-21 6 C-29 4 -35 4 -41 6 M-20 10 C-27 11 -33 13 -38 16 M21 6 C29 4 35 4 41 6 M20 10 C27 11 33 13 38 16", off=(fx * .6, fy * .6))))
    gin = []
    if who == "evan":
        gin = [place("M-22 -7 C-24 -17 -25 -25 -24 -32 C-17 -28 -11 -24 -7 -19 C-6 -11 -10 -5 -16 -3 Z", (-15, -13), h["earL"]),
               place("M22 -7 C24 -17 25 -25 24 -32 C17 -28 11 -24 7 -19 C6 -11 10 -5 16 -3 Z", (15, -13), -h["earR"])]
    return L, out, gin

def frame(F, who="bebo", seed=0):
    rnd = random.Random(seed * 977 + (5 if who == "evan" else 0))
    br = F["breath"]; b = F["body"]
    # breathing: the back and chest rise a little
    cen = (sum(p[0] for p in b) / len(b), sum(p[1] for p in b) / len(b))
    b = [(p[0] + (p[0] - cen[0]) * 0.03 * br, p[1] + (p[1] - cen[1]) * 0.05 * br - (1.2 * br if i in (2, 3, 4) else 0)) for i, p in enumerate(b)]
    L, extra, gin = [], [], []
    L.append(("line", smooth([b[2], b[3], b[4], b[5], b[6], b[7]]), 2.4))
    L.append(("line", smooth([b[0], b[1], (b[1][0] - 4, b[1][1] - 14)]), 2.0))
    sag = F.get("sag", 1.5)            # the belly line hangs a little (on its back, it bulges up: negative)
    bl = max(b[7][1], b[0][1]) + sag if sag >= 0 else min(b[7][1], b[0][1]) + sag
    L.append(("line", smooth([b[7], ((b[7][0] + b[0][0]) / 2, bl), b[0]]), 1.3, [[0.4, 0.52]]))
    if F["haunch"] > 0.15:
        h0 = b[5]; h1 = b[6]
        arc = [add(h0, (10, 4)), add(h0, (24, 10)), add(h1, (28, 4)), add(h1, (26, 14))]
        L.append(("line", smooth(arc), 2.2 * min(1, F["haunch"])))
    for leg, v in zip(F["legs"], F["legv"]):
        if v < 0.08: continue
        a, k_, p = leg
        L.append(("line", smooth([a, k_, p]), 1.9 * v + 0.2))
        L.append(("thin", f"M{pt(add(p, (-4, 0)))} C{pt(add(p, (-3, -4)))} {pt(add(p, (3, -4)))} {pt(add(p, (4, 0)))}"))
    t = F["tail"]
    # the tail as a soft tube: two lines a little apart, joined in a round tip
    left, right = [], []
    for i, p in enumerate(t):
        q = t[min(i + 1, len(t) - 1)]; o = t[max(i - 1, 0)]
        dx, dy = q[0] - o[0], q[1] - o[1]; l = math.hypot(dx, dy) or 1
        w = 4.2 * (1 - 0.25 * i / len(t)) * F.get("puff", 1.0)
        left.append((p[0] - dy / l * w / 2, p[1] + dx / l * w / 2)); right.append((p[0] + dy / l * w / 2, p[1] - dx / l * w / 2))
    tip = t[-1]; tipdir = sub(t[-1], t[-2]); tl = math.hypot(*tipdir) or 1
    cap = add(tip, mul(tipdir, 2.6 / tl))
    L.append(("line", smooth(left + [cap] + right[::-1]), 1.8))
    upside = (b[3][1] + b[4][1]) / 2 > (b[0][1] + b[7][1]) / 2 + 8      # on its back: the patch is underneath
    if who == "evan":
        for i in (1, 2, 3):
            p = t[i]; extra.append(f'<circle cx="{p[0]:.1f}" cy="{p[1]:.1f}" r="2.4" fill="{G}" fill-opacity=".8"/>')
        mid = mul(add(b[3], b[4]), 0.5)
        if not upside: gin.append(f"M{pt(add(mid, (-14, 2)))} C{pt(add(mid, (-8, -4)))} {pt(add(mid, (10, -4)))} {pt(add(mid, (18, 3)))} C{pt(add(mid, (10, 10)))} {pt(add(mid, (-6, 10)))} {pt(add(mid, (-14, 2)))} Z")
    hl, hx, hg = head_marks(F["head"], who)
    L += hl; extra += hx; gin += hg
    if who == "bebo":
        h = F["head"]; nb = rot((h["x"] + 2, h["y"] + h["r"] * 1.05), (h["x"], h["y"]), h["tilt"])
        extra.append(f'<circle cx="{nb[0]:.1f}" cy="{nb[1]:.1f}" r="3.2" fill="{BELL}"/>')
    # to SVG: the pen line (pressure) plus a faint second pass
    out = [f'<path d="{g}" fill="{G}" fill-opacity=".72" filter="url(#soft)"/>' for g in gin]
    for i, m in enumerate(L):
        if m[0] == "line":
            d, w = m[1], m[2]; gaps = m[3] if len(m) > 3 else None
            ghost = re.sub(r"-?\d+\.?\d*", lambda mm: f"{float(mm.group()) + rnd.uniform(-0.9, 0.9):.2f}", d)
            out.append(f'<path d="{ghost}" fill="none" stroke="{INK}" stroke-width=".8" stroke-opacity=".38" stroke-linecap="round"/>')
            out.append(f'<path d="{stroke(d, w * 1.15, "swell", seed=i + seed * 13, wobble=.16, gaps=gaps)}" fill="{INK}"/>')
        else:
            out.append(f'<path d="{m[1]}" fill="none" stroke="{INK}" stroke-width=".95" stroke-opacity=".85" stroke-linecap="round"/>')
    out += extra
    sq = F["squash"]
    body = "".join(out)
    return f'<g transform="translate(0 {GROUND * (1 - sq):.2f}) scale(1 {sq:.4f})">{body}</g>'

DEFS = '<defs><filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="1.0"/></filter></defs>'
def svg(F, who="bebo", seed=0, size=400):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="{size}" height="{size}">{DEFS}{frame(F, who, seed)}</svg>'
