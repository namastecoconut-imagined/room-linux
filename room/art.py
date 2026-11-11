"""Two readings of a cover. field(): what the screen's background is made of (the redesign's "Field") — its four main
colours, where each sits and how much of the cover it fills, how vivid and contrasty it is, and which way its light
falls. wash(): the older player's background, made the iPhone panel's way (SpotifyClient.wash): the cover shrunk to 6 × 4 pixels, each
pixel a little more saturated and pulled dark enough for white text, then stretched smoothly over the whole screen —
the cover's own colours as soft light, not a blur of the picture. Also picks the accent: the most colourful pixel
that isn't nearly black or white (it colours the glow behind the cover)."""
import colorsys
import time

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QImage

from .config import STATE_DIR

_dir = STATE_DIR / "wash"
_n = 0
_written: list = []
for _old in (_dir.glob("wash-*.png") if _dir.exists() else []):      # last run's: start clean
    _old.unlink(missing_ok=True)


def wash(img: QImage) -> tuple[str, list[int]]:
    """→ (file:// URL of the 6×4 wash, accent rgb)."""
    small = img.scaled(6, 4, Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.SmoothTransformation) \
               .convertToFormat(QImage.Format.Format_RGB32)
    best, best_score = [180, 150, 120], -1.0
    for y in range(4):
        for x in range(6):
            c = QColor(small.pixel(x, y))
            r, g, b = c.redF(), c.greenF(), c.blueF()
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            score = s * (1 - abs(v - 0.65))
            if score > best_score:
                best, best_score = [c.red(), c.green(), c.blue()], score
            rr, gg, bb = colorsys.hsv_to_rgb(h, min(1.0, s * 1.25), min(v, 0.6) * 0.75)
            small.setPixel(x, y, QColor(int(rr * 255), int(gg * 255), int(bb * 255)).rgb())
    _dir.mkdir(parents=True, exist_ok=True)
    global _n
    _n += 1
    path = _dir / f"wash-{int(time.time() * 1000)}-{_n}.png"
    small.save(str(path), "PNG")
    # keep the few written most recently (by the order written, not the files' dates — a wrong clock at start-up
    # once made every new file look oldest, so it was deleted as soon as it was written)
    _written.append(path)
    while len(_written) > 4:
        _written.pop(0).unlink(missing_ok=True)
    return path.as_uri(), best


def base_fill(cols: list) -> list:
    """The colour under the lights: the cover's least common colour (as in the design, room-motion.html: BG.cols[3])
    — unless it's near black or near white, which a real cover's small dark corner or white lettering can be (the
    design's own covers never were): then the next least common that isn't, and failing that the least common one
    brought into range. Keeps the field from going black (rejected as too dark) or glaring white."""
    lo, hi = 0.18, 0.82
    lum = lambda c: (.2126 * c[0] + .7152 * c[1] + .0722 * c[2]) / 255
    for c in reversed(cols):
        if lo <= lum(c) <= hi:
            return list(c)
    c, l = cols[-1], lum(cols[-1])
    if l > hi:
        return [int(v * hi / l) for v in c]
    if l >= 0.02:                                    # brightened, keeping its hue
        return [min(255, int(v * lo / l)) for v in c]
    return [int(lo * 255)] * 3                       # black: a dark grey


def field(img: QImage) -> dict:
    """The cover read for the background (design: room-motion.html, analyse()). At 40 × 40: four colours by k-means
    (8 rounds, started from pixels at 0, ⅓, ⅔ and the end), each with where it sits (its pixels' centre, 0…1) and its
    share; sorted biggest share first. Also vividness (mean saturation), contrast (spread of brightness) and the light
    direction (from the dark parts' centre to the bright parts' centre) — they set how fast and far the colours drift."""
    n = 40
    small = img.scaled(n, n, Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.SmoothTransformation) \
               .convertToFormat(QImage.Format.Format_RGB32)
    px = []
    for i in range(n * n):
        c = QColor(small.pixel(i % n, i // n))
        px.append((c.red(), c.green(), c.blue(), (i % n) / n, (i // n) / n))
    N = len(px)
    C = [dict(r=px[int(q * (N - 1))][0], g=px[int(q * (N - 1))][1], b=px[int(q * (N - 1))][2]) for q in (0, .33, .66, .99)]
    for _ in range(8):
        acc = [[0, 0, 0, 0.0, 0.0, 0] for _ in C]
        for r, g, b, x, y in px:
            bi, bd = 0, 1e18
            for i, c in enumerate(C):
                d = (r - c["r"]) ** 2 + (g - c["g"]) ** 2 + (b - c["b"]) ** 2
                if d < bd:
                    bd, bi = d, i
            a = acc[bi]; a[0] += r; a[1] += g; a[2] += b; a[3] += x; a[4] += y; a[5] += 1
        C = [dict(r=a[0] / a[5], g=a[1] / a[5], b=a[2] / a[5], x=a[3] / a[5], y=a[4] / a[5], share=a[5] / N) if a[5]
             else C[i] for i, a in enumerate(acc)]
    C.sort(key=lambda c: -c.get("share", 0))
    lum = [.2126 * r + .7152 * g + .0722 * b for r, g, b, _, _ in px]
    sat = sum((max(r, g, b) - min(r, g, b)) / max(r, g, b) if max(r, g, b) else 0 for r, g, b, _, _ in px) / N
    mean = sum(lum) / N
    con = (sum((l - mean) ** 2 for l in lum) / N) ** 0.5 / 128
    bx = by = dx = dy = bw = dw = 0.0
    for (r, g, b, x, y), l in zip(px, lum):
        w = l / 255
        bx += x * w; by += y * w; bw += w; dx += x * (1 - w); dy += y * (1 - w); dw += 1 - w
    vx = (bx / bw - dx / dw) if bw and dw else 0
    vy = (by / bw - dy / dw) if bw and dw else 0
    vl = (vx * vx + vy * vy) ** 0.5 or 1
    energy = max(0.0, min(1.2, sat * .7 + con * .9))
    cols = [[int(c["r"]), int(c["g"]), int(c["b"])] for c in C]
    return {"cols": cols, "base": base_fill(cols),
            "pos": [[round(c.get("x", .5), 3), round(c.get("y", .5), 3)] for c in C],
            "share": [round(c.get("share", .2), 3) for c in C],
            "lum": round(mean / 255, 3), "sat": round(sat, 3), "con": round(con, 3),
            "dir": [round(vx / vl, 3), round(vy / vl, 3)],
            "period": round(max(14.0, min(46.0, 46 - 30 * energy)), 1), "amp": round(max(60.0, min(220.0, 60 + 180 * con)))}
