"""The player's background, made the iPhone panel's way (SpotifyClient.wash): the cover shrunk to 6 × 4 pixels, each
pixel a little more saturated and pulled dark enough for white text, then stretched smoothly over the whole screen —
the cover's own colours as soft light, not a blur of the picture. Also picks the accent: the most colourful pixel
that isn't nearly black or white (it colours the glow behind the cover)."""
import colorsys
import time

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QImage

from .config import STATE_DIR

_dir = STATE_DIR / "wash"


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
    path = _dir / f"wash-{int(time.time() * 1000)}.png"
    small.save(str(path), "PNG")
    for old in sorted(_dir.glob("wash-*.png"), key=lambda f: f.stat().st_mtime)[:-4]:
        old.unlink(missing_ok=True)
    return path.as_uri(), best
