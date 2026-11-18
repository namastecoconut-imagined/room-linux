"""Standby scenes, drawn once ahead of time (HANDOFF: "render once, then play") — never on the Surface.

  python3 tools/scenes/bake.py                 all four scenes, all three skies → assets/scenes/
  python3 tools/scenes/bake.py room night      just one
  python3 tools/scenes/bake.py --preview DIR   also a picture of each, finished and half drawn, for checking
  python3 tools/scenes/bake.py --data          only qml/scenesdata.js again (from what's baked)

The drawings are scenes.js (the approved prototype's, unchanged): every pen stroke with its place in the build. Each
scene and sky is drawn by Chromium exactly as the prototype draws it, and split into:

  base.png       everything that stays still, finished, at the panel's resolution (2736 × 1824)
  base.map.png   when each part of it appears (1368 × 912, one per stage pixel; read without smoothing), opaque
                 (pictures are loaded with their colours multiplied by their alpha, which would wipe the numbers):
                   red · green  a line's time in the top 12 bits, 0…TMAX build units — how far along its stroke the
                                pen is, through the prototype's own easing, so the line grows exactly as it did there —
                                and in the low 4, how much of the pixel is line rather than fill
                   blue         a fill's time (it fades in over 0.9 s, as in the prototype), 8 bits
  s<n>.png/.map  each moving piece (curtains, plants, the fish, stars, clouds, lit windows…) on its own, at rest,
                 with how it moves: SceneArt.qml turns, slides or fades it, stepped with the cats
  f<n>.png/.map  pieces drawn again over the cats, so one can be inside or behind them (props.json)
  scene.json     all of that, and the build's length (the draw takes drawSeconds whatever the length)
and qml/scenesdata.js: all of the scene.json files and the layout (scenes.json), for the QML to read.

The hand-drawn wobble (#hand, a displacement) is in the pictures; the times are moved by the same wobble, so they
line up with the lines.
"""
import json, math, os, shutil, sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "scenes"))
W, H, PX = 1368, 912, 2
TMAX = 12.0                       # build units the times are spread over (the longest build is ~8.2)
SKIES = ["day", "eve", "night"]
DRAW = {"day": 6, "eve": 6, "night": 10}       # (scenes.json drawSeconds — for the check pictures only)
MOTION = ["sway", "sway2", "curt", "tw", "blink", "lit", "cloud", "swim", "breathe", "spin"]

# the prototype's look of a line and a fill (index.html), without the animation
PEN = """.d{fill:none;stroke:#f4eee6;stroke-opacity:.9;stroke-width:2.5;stroke-linecap:round;stroke-linejoin:round}
.thin{stroke-width:1.8;stroke-opacity:.55}.f{opacity:var(--o,1)}
.sway,.sway2,.curt,.lit,.tw,.blink,.cloud,.swim,.breathe,.spin{transform-box:view-box}
.hid{visibility:hidden!important}"""
# the scenery's own movements (index.html) — read for each piece, then switched off while drawing it at rest
MOVES = """.sway{animation:sway 3.4s ease-in-out infinite alternate}.sway2{animation:sway2 4.6s ease-in-out infinite alternate}
.curt{animation:curt 6s ease-in-out infinite alternate}.tw{animation:tw 3.2s ease-in-out infinite alternate}
.blink{animation:blink 2.4s steps(1) infinite}.lit{animation:lit 30s steps(1) infinite}
.cloud{animation:cloud 70s linear infinite alternate}.swim{animation:swim 7s ease-in-out infinite alternate}
.breathe{animation:breathe 5s ease-in-out infinite alternate}.spin{animation:spin 90s linear infinite}
@keyframes sway{from{transform:rotate(-5deg)}to{transform:rotate(5deg)}}"""

PAGE = """<!doctype html><html><head><style>html,body{margin:0;background:transparent;overflow:hidden}
svg{position:absolute;left:0;top:0}%s</style><style id="moves">%s</style></head><body>
<svg id="env" xmlns="http://www.w3.org/2000/svg" width="1368" height="912" viewBox="0 0 1368 912"></svg>
<script>%s</script><script>%s</script></body></html>"""

JS = r"""
const MOT = %s;
let roots = [];
function build(i, sky, front) {
  D = .25; const inner = SCENES[i].draw(sky); const total = D;
  const env = document.getElementById('env');
  env.innerHTML = DEFS + `<g id="sc" filter="url(#hand)">${inner}</g>`;
  env.pauseAnimations(); env.setCurrentTime(0);
  document.getElementById('moves').disabled = true;            // drawn at rest
  // the moving pieces: the outermost group with one of the movements, or holding a path animation
  roots = [];
  const sc = document.getElementById('sc');
  for (const g of sc.querySelectorAll('g')) {
    const moving = MOT.some(c => g.classList.contains(c)) || [...g.children].some(c => c.tagName === 'animateMotion');
    if (!moving) continue;
    let r = g, smil = [...g.children].some(c => c.tagName === 'animateMotion');
    // a path animation's wrapper (the fly(): <g class="f"> fading in, <g> moving) and the falling leaf's own group
    if (smil && r.parentNode !== sc && r.parentNode.parentNode === sc) r = r.parentNode;
    let up = r.parentNode, inner = false;
    while (up && up !== sc) { if (roots.includes(up)) inner = true; up = up.parentNode; }
    if (!inner && !roots.includes(r)) roots.push(r);
  }
  leaves().forEach(e => { let a = e, k = -1; while (a && a !== sc) { const j = roots.indexOf(a); if (j >= 0) k = j; a = a.parentNode; } e.dataset.layer = k;
    (front || []).forEach((m, n) => { if (k < 0 && m.some(p => (e.getAttribute('d') || '').startsWith(p))) e.dataset.layer = 1000 + n; }); });
  // when it's all there: each line's end, each fill's start
  let lineEnd = 0, fillLast = 0;
  for (const e of leaves()) { if (isLine(e)) lineEnd = Math.max(lineEnd, +e.dataset.t0 + +e.dataset.dur); else fillLast = Math.max(fillLast, fillTime(e, total)); }
  return { total, n: roots.length, lineEnd, fillLast };
}
function leaves() { return [...document.querySelectorAll('#sc path, #sc circle, #sc ellipse, #sc rect, #sc line, #sc polyline, #sc polygon')]; }
function isLine(e) { return e.classList.contains('d'); }
// show only `which` (a layer number, or the front pieces' matches), as lines, fills, or the fills' times as colours
function show(which, mode, match) {
  const sc = document.getElementById('sc');
  for (const e of leaves()) {
    let on = +e.dataset.layer === which;
    if (mode === 'lines' && !isLine(e)) on = false;
    if (mode === 'fillcode' && isLine(e)) on = false;
    e.classList.toggle('hid', !on);
    if (mode === 'fillcode' && on) {
      const c = Math.max(1, Math.round(fillTime(e) / %f * 255));
      e.setAttribute('style', (e.getAttribute('style') || '') + `;fill:rgb(${c},255,0);stroke:rgb(${c},255,0);stroke-width:3;opacity:1;fill-opacity:1;stroke-opacity:1;shape-rendering:crispEdges`);
    }
  }
  if (mode === 'fillcode') { sc.removeAttribute('filter'); sc.querySelectorAll('[mask]').forEach(g => g.removeAttribute('mask')); }
}
// a fill's time: its own fade's start (--d), or its group's (fly), or the end of the build (the falling leaf)
function fillTime(e, total) {
  for (let a = e; a && a.id !== 'sc'; a = a.parentNode) {
    const s = a.getAttribute && a.getAttribute('style') || '', m = s.match(/--d:\s*([0-9.]+)/);
    if (m && a.classList && a.classList.contains('f')) return +m[1];
  }
  return total || window.TOTAL || 8;
}
// points along every line of the layer: where, how far along its stroke (0…1), its time and width
function samples(which, match) {
  const out = [];
  for (const e of leaves()) {
    const on = +e.dataset.layer === which;
    if (!on || !isLine(e)) continue;
    const t0 = +e.dataset.t0, dur = +e.dataset.dur, pl = e.getAttribute('pathLength');
    e.removeAttribute('pathLength');
    const L = e.getTotalLength(), m = e.getCTM(), w = parseFloat(getComputedStyle(e).strokeWidth) * Math.hypot(m.a, m.b);
    const n = Math.max(2, Math.ceil(L / .4));
    for (let i = 0; i <= n; i++) {
      const p = e.getPointAtLength(L * i / n);
      out.push(m.a * p.x + m.c * p.y + m.e, m.b * p.x + m.d * p.y + m.f, i / n, t0, dur, w);
    }
    if (pl !== null) e.setAttribute('pathLength', pl);
  }
  return out;
}
// the box a layer covers (stage units), the stroke and the wobble included
function box(which) {
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (const e of leaves()) {
    if (+e.dataset.layer !== which) continue;
    const r = e.getBoundingClientRect(); if (!r.width && !r.height) continue;
    x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top); x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom);
  }
  return [x0, y0, x1, y1];
}
// how a piece moves (read from the prototype's own rules for it)
function motion(k) {
  document.getElementById('moves').disabled = false;
  const r = roots[k], cs = getComputedStyle(r), cls = MOT.find(c => r.classList.contains(c)) || '';
  const st = r.getAttribute('style') || '', o = st.match(/transform-origin:\s*([-0-9.]+)px\s+([-0-9.]+)px/);
  const m = { kind: cls, dur: parseFloat(cs.animationDuration) || 0, delay: parseFloat(cs.animationDelay) || 0,
              origin: o ? [+o[1], +o[2]] : null };
  const mo = r.querySelector('animateMotion');
  if (mo) {
    m.kind = 'path'; m.path = mo.getAttribute('path'); m.dur = parseFloat(mo.getAttribute('dur')); m.delay = parseFloat(mo.getAttribute('begin') || '0');
    m.rotate = mo.getAttribute('rotate') === 'auto';
    const fl = r.querySelector('animateTransform'); if (fl) m.flap = { dur: parseFloat(fl.getAttribute('dur')), values: fl.getAttribute('values') };
    const op = [...r.querySelectorAll('animate')].find(a => a.getAttribute('attributeName') === 'opacity');
    if (op) m.fade = { values: op.getAttribute('values').split(';').map(Number), times: op.getAttribute('keyTimes').split(';').map(Number) };
    const st2 = r.getAttribute('style') || '', d = st2.match(/--d:\s*([0-9.]+)/); m.appear = d ? +d[1] : null;
  }
  document.getElementById('moves').disabled = true;
  return m;
}
// a path-animated piece, drawn on its own at (60, 60) without its animations
function soloPath(k) {
  const r = roots[k], mo = r.querySelector('animateMotion'), g = mo.parentNode;
  r.querySelectorAll('animate, animateMotion, animateTransform').forEach(a => a.remove());
  g.setAttribute('transform', 'translate(60,60)'); r.removeAttribute('opacity');
  document.getElementById('sc').removeAttribute('filter');
}
"""


def ease_inv_table():
    """The prototype's pen easing, cubic-bezier(.22, 1, .36, 1): for a share s of the stroke drawn, the share of its
    time that has gone (the inverse), as a table."""
    u = np.linspace(0, 1, 20001)
    x1, y1, x2, y2 = .22, 1, .36, 1
    bx = 3 * x1 * u * (1 - u) ** 2 + 3 * x2 * u ** 2 * (1 - u) + u ** 3       # time
    by = 3 * y1 * u * (1 - u) ** 2 + 3 * y2 * u ** 2 * (1 - u) + u ** 3       # progress
    return by, bx                                                               # progress → time


EASE_P, EASE_T = ease_inv_table()


def rgba(png):
    return np.asarray(Image.open(png).convert("RGBA"), dtype=np.uint8)


class Baker:
    def __init__(self, page, tmp):
        self.page, self.tmp, self.noise = page, tmp, None

    def shot(self, clip, name):
        p = os.path.join(self.tmp, name + ".png")
        self.page.screenshot(path=p, clip={"x": clip[0], "y": clip[1], "width": clip[2], "height": clip[3]}, omit_background=True)
        return rgba(p)

    def wobble(self):
        """The #hand displacement, per screen pixel, in stage units: a point p is drawn at q where q + d(q) = p."""
        if self.noise is not None:
            return self.noise
        self.page.evaluate("""() => { document.getElementById('env').innerHTML = `<defs><filter id="nz" filterUnits="userSpaceOnUse" x="0" y="0" width="1368" height="912">
          <feTurbulence type="fractalNoise" baseFrequency=".011" numOctaves="1" seed="7"/></filter></defs><rect width="1368" height="912" filter="url(#nz)"/>` }""")
        a = self.shot((0, 0, W, H), "noise").astype(np.float64) / 255
        # the noise is made in linear light (the filter's default) and shown in sRGB: back to linear, as the map reads it
        lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
        self.noise = (4 * (lin[..., 0] - 0.5), 4 * (lin[..., 1] - 0.5))        # scale 4: ±2 stage units
        return self.noise

    def displace(self, x, y):
        dx, dy = self.wobble()
        qx, qy = x.copy(), y.copy()
        for _ in range(3):
            ix = np.clip((qx * PX).astype(int), 0, W * PX - 1); iy = np.clip((qy * PX).astype(int), 0, H * PX - 1)
            qx, qy = x - dx[iy, ix], y - dy[iy, ix]
        return qx, qy

    def layer(self, which, clip, name, out, match=None, smil=False, total=8.0):
        """One layer: its picture (2×) and its map (1×), cropped to clip (x, y, w, h in whole stage units)."""
        x, y, w, h = clip
        self.page.evaluate("(a) => { show(a[0], 'all', a[1]) }", [which, match])
        art = self.shot(clip, name)
        self.page.evaluate("(a) => { show(a[0], 'lines', a[1]) }", [which, match])
        lines = self.shot(clip, name + "-lines")
        s = np.array(self.page.evaluate("(a) => samples(a[0], a[1])", [which, match]), dtype=np.float64).reshape(-1, 6)
        self.page.evaluate("(a) => { show(a[0], 'fillcode', a[1]) }", [which, match])
        code = self.shot(clip, name + "-fills")

        # 1× grids (one per stage unit) of the picture's cover, the lines' cover, and the fills' times
        def down(a):
            return a.reshape(h, PX, w, PX).mean(axis=(1, 3))
        aa, al = down(art[..., 3] / 255.0), down(lines[..., 3] / 255.0)
        has_fill = code[..., 1] > 200
        fill_t = np.where(has_fill, code[..., 0], 0).astype(np.float64)
        fill_t = fill_t.reshape(h, PX, w, PX).max(axis=(1, 3))
        fill_on = has_fill.reshape(h, PX, w, PX).any(axis=(1, 3))

        # the lines' times: each sample's place in its stroke → the moment the pen reaches it; stamped where the
        # wobble draws it, then every line pixel takes the nearest stamp
        tl = np.zeros((h, w)); on = np.zeros((h, w), bool)
        if len(s):
            px, py, frac, t0, dur, wd = s.T
            if not smil:
                px, py = self.displace(px, py)
            when = t0 + dur * np.interp(frac, EASE_P, EASE_T)
            ix = np.floor(px - x).astype(int); iy = np.floor(py - y).astype(int)
            ok = (ix >= 0) & (ix < w) & (iy >= 0) & (iy < h)
            # earliest wins where strokes cross (a pixel shows as soon as any pen reaches it)
            order = np.argsort(-when[ok])
            tl[iy[ok][order], ix[ok][order]] = when[ok][order]
            on[iy[ok][order], ix[ok][order]] = True
        cover = (aa > 0.002)
        line_px = al > 0.002
        if on.any():
            _, (ny, nx) = ndimage.distance_transform_edt(~on, return_indices=True)
            tl = np.where(line_px, tl[ny, nx], 0)
        if fill_on.any():
            _, (ny, nx) = ndimage.distance_transform_edt(~fill_on, return_indices=True)
            fill_t = np.where(cover & ~line_px | (cover & (al < aa - 0.01)), fill_t[ny, nx], 0)
        else:
            fill_t = np.zeros((h, w))
        # nothing to say when the line's there (a line with no time: shows at once)
        weight = np.where(aa > 0.002, np.clip(al / np.maximum(aa, 1e-6), 0, 1), 0)
        code = (np.round(np.clip(tl / TMAX, 0, 1) * 4095).astype(np.uint32) << 4) | np.round(weight * 15).astype(np.uint32)
        m = np.zeros((h, w, 4), np.uint8)
        m[..., 0] = code >> 8; m[..., 1] = code & 255
        m[..., 2] = np.clip(fill_t, 0, 255).astype(np.uint8)
        m[..., 3] = 255
        Image.fromarray(art, "RGBA").save(os.path.join(out, name + ".png"), optimize=True)
        Image.fromarray(m, "RGBA").save(os.path.join(out, name + ".map.png"), optimize=True)
        missing = int((line_px & ~(on | ndimage.binary_dilation(on, iterations=2))).sum())
        return {"x": x, "y": y, "w": w, "h": h, "art": name + ".png", "map": name + ".map.png", "unstamped": missing}

    def scene(self, i, sid, sky, props, out):
        fronts = [fp["match"] for fp in props.get(sid, [])]
        info = self.page.evaluate("(a) => build(a[0], a[1], a[2])", [i, sky, fronts])
        total = info["total"]
        self.page.evaluate(f"() => {{ window.TOTAL = {total} }}")
        man = {"scene": sid, "sky": sky, "total": round(total, 3), "lineEnd": round(info["lineEnd"], 3), "fillLast": round(info["fillLast"], 3),
               "tmax": TMAX, "px": PX, "sprites": [], "front": []}
        man["base"] = self.layer(-1, (0, 0, W, H), "base", out, total=total)
        for k in range(info["n"]):
            self.page.evaluate("(a) => build(a[0], a[1], a[2])", [i, sky, fronts])
            mo = self.page.evaluate(f"() => motion({k})")
            if mo["kind"] == "path":
                self.page.evaluate(f"() => soloPath({k})")
                lay = self.layer(k, (0, 0, 120, 120), f"s{k}", out, smil=True, total=total)
                lay["anchor"] = [60, 60]
            else:
                x0, y0, x1, y1 = self.page.evaluate(f"() => box({k})")
                m = 8
                x0, y0 = max(0, math.floor(x0 - m)), max(0, math.floor(y0 - m))
                x1, y1 = min(W, math.ceil(x1 + m)), min(H, math.ceil(y1 + m))
                lay = self.layer(k, (x0, y0, x1 - x0, y1 - y0), f"s{k}", out, total=total)
            lay.update({k2: v for k2, v in mo.items() if v is not None})
            man["sprites"].append(lay)
        for n, fp in enumerate(props.get(sid, [])):
            self.page.evaluate("(a) => build(a[0], a[1], a[2])", [i, sky, fronts])
            x0, y0, x1, y1 = fp["box"]
            lay = self.layer(1000 + n, (x0, y0, x1 - x0, y1 - y0), f"f{n}", out, total=total)
            lay["name"] = fp["name"]
            man["front"].append(lay)
        with open(os.path.join(out, "scene.json"), "w") as f:
            json.dump(man, f, indent=1)
        return man


def main():
    from playwright.sync_api import sync_playwright
    if "--data" in sys.argv:
        write_data(); return
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    if preview:
        args = [a for a in args if a != preview]
    layout = json.load(open(os.path.join(HERE, "scenes.json")))
    props = json.load(open(os.path.join(HERE, "props.json")))
    src = open(os.path.join(HERE, "scenes.js"), encoding="utf-8").read()
    ids = [s["id"] for s in layout["scenes"]]
    want = [(s, k) for s in ids for k in SKIES if (not args or s == args[0]) and (len(args) < 2 or k == args[1])]
    tmp = os.path.join(OUT, ".tmp"); os.makedirs(tmp, exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={"width": W, "height": H}, device_scale_factor=PX)
        page.set_content(PAGE % (PEN, MOVES, src, JS % (json.dumps(MOTION), TMAX)))
        bk = Baker(page, tmp)
        bk.wobble()
        page.set_content(PAGE % (PEN, MOVES, src, JS % (json.dumps(MOTION), TMAX)))
        for sid, sky in want:
            out = os.path.join(OUT, f"{sid}-{sky}")
            shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
            man = bk.scene(ids.index(sid), sid, sky, props, out)
            un = man["base"]["unstamped"] + sum(s["unstamped"] for s in man["sprites"])
            print(f"{sid}-{sky}: build {man['total']} units, {len(man['sprites'])} moving pieces, "
                  f"{len(man['front'])} front · {un} line pixels without a stamp nearby")
            if preview:
                os.makedirs(preview, exist_ok=True)
                for f in (0.5, 1.0):
                    play(out, man, f, DRAW[sky]).save(os.path.join(preview, f"{sid}-{sky}-{int(f * 100)}.png"))
        b.close()
    shutil.rmtree(tmp, ignore_errors=True)
    write_data()


def write_data():
    """qml/scenesdata.js: the layout and timings (scenes.json) and every baked scene's pieces, for Scene.qml and
    SceneArt.qml (QML can't read a file by itself)."""
    layout = json.load(open(os.path.join(HERE, "scenes.json")))
    props = json.load(open(os.path.join(HERE, "props.json")))
    for sc in layout["scenes"]:                         # the toys, and the platforms added for them
        sc["toys"] = props.get("toys", {}).get(sc["id"], [])
        sc["spots"] = sc["spots"] + props.get("spots", {}).get(sc["id"], [])
    baked = {}
    for d in sorted(os.listdir(OUT)):
        f = os.path.join(OUT, d, "scene.json")
        if os.path.exists(f):
            m = json.load(open(f))
            for lay in [m["base"]] + m["sprites"] + m["front"]:
                lay.pop("unstamped", None)
            for t in props.get("toys", {}).get(m["scene"], []):        # the toys' pieces, by name
                mt = t.get("match")
                for sp in m["sprites"] if mt else []:
                    o = sp.get("origin")
                    if ("origin" in mt and o and abs(o[0] - mt["origin"][0]) < 1 and abs(o[1] - mt["origin"][1]) < 1) \
                            or ("path" in mt and (sp.get("path") or "").startswith(mt["path"])) \
                            or ("kind" in mt and sp.get("kind") == mt["kind"]):
                        sp["name"] = t["name"]
            baked[d] = m
    with open(os.path.join(HERE, "..", "..", "qml", "scenesdata.js"), "w") as f:
        f.write("// The standby scenes (made by tools/scenes/bake.py from tools/scenes/scenes.json and the baked pictures in\n"
                "// assets/scenes; don't edit by hand).\n.pragma library\n")
        f.write("var layout = " + json.dumps(layout, separators=(",", ":")) + ";\n")
        f.write("var baked = " + json.dumps(baked, separators=(",", ":")) + ";\n")


def ends(man, draw):
    """How far the build runs (units), and how fast (k: seconds a unit): to the last line's end, or the last fill's
    0.9 s fade."""
    k = draw / man["total"]
    return max(man["lineEnd"], man["fillLast"] + 0.9 / k), k


def play(out, man, f, draw, bg=(90, 42, 22)):
    """What SceneArt.qml shows at a share f of the draw (the shader's sums), over a plain background — for checking."""
    end, k = ends(man, draw)
    now = f * end
    canvas = Image.new("RGBA", (W * PX, H * PX), bg + (255,))
    for lay in [man["base"]] + man["sprites"] + man["front"]:
        art = rgba(os.path.join(out, lay["art"])).astype(np.float64) / 255
        mp = rgba(os.path.join(out, lay["map"])).astype(np.float64)
        mp = mp.repeat(PX, 0).repeat(PX, 1)[:art.shape[0], :art.shape[1]]
        v = mp[..., 0] * 256 + mp[..., 1]
        tl = np.floor(v / 16) / 4095 * TMAX
        tf = mp[..., 2] / 255 * TMAX
        lv = (now >= tl).astype(float)
        fv = np.clip((now - tf) * k / 0.9, 0, 1)
        vis = fv + (lv - fv) * (v % 16) / 15
        a = art.copy(); a[..., 3] *= vis
        im = Image.fromarray(np.round(a * 255).astype(np.uint8), "RGBA")
        ox, oy = (lay.get("x", 0)) * PX, (lay.get("y", 0)) * PX
        if lay.get("kind") == "path":
            pass                                            # (moves along its path: left out of the still)
        else:
            canvas.alpha_composite(im, (int(ox), int(oy)))
    return canvas.convert("RGB")


if __name__ == "__main__":
    main()
