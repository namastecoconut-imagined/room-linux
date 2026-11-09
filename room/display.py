"""The screen's brightness: automatic from the Surface's light sensor, or set by hand from Settings.

Automatic: the room's light (lux) is read every 2 s and the screen eases towards a level for it (dim room → dim
screen), at most a few percent a second so it never jumps. Moving the slider switches automatic off until it's
turned back on. The level is set through logind (no root needed), the same way GNOME's slider does it. Kept in
~/.local/state/room/display.json.
"""
import glob
import math
import os
import subprocess

from PySide6.QtCore import QObject, QTimer, Signal

from .config import State


def _read(p, kind=float):
    try:
        with open(p) as f:
            return kind(f.read().strip())
    except Exception:
        return None


class Display(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.store = State("display")
        s = self.store.read()
        self.auto = bool(s.get("auto", True))
        self.manual = float(s.get("level", 0.6))
        self.dim = False                     # night standby: a little lower still
        bl = sorted(glob.glob("/sys/class/backlight/*"), key=lambda p: "intel" not in p)
        self.bl = bl[0] if bl else ""
        self.max = _read(self.bl + "/max_brightness", int) if self.bl else None
        self.level = self._current() or self.manual
        self.lux = None
        self._lux_avg = None
        self.als = self._find_sensor()

    # ---------------------------------------------------------------- what Settings shows
    def snapshot(self):
        return {"auto": self.auto and bool(self.als), "level": round(self.level, 3), "sensor": bool(self.als),
                "canSet": bool(self.bl and self.max), "lux": round(self.lux) if self.lux is not None else -1}

    def start(self):
        if self.auto and self.als:
            self._tick()
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(2000)

    # ---------------------------------------------------------------- the sensor
    @staticmethod
    def _find_sensor():
        for d in glob.glob("/sys/bus/iio/devices/iio:device*"):
            for raw in ("in_illuminance_input", "in_illuminance_raw", "in_intensity_both_raw", "in_intensity_clear_raw"):
                if os.path.exists(os.path.join(d, raw)):
                    base = raw.rsplit("_", 1)[0]
                    return {"raw": os.path.join(d, raw), "scale": _read(os.path.join(d, base + "_scale")) or 1.0,
                            "offset": _read(os.path.join(d, base + "_offset")) or 0.0}
        return None

    def _read_lux(self):
        v = _read(self.als["raw"])
        if v is None:
            return None
        return max(0.0, (v + self.als["offset"]) * self.als["scale"])

    @staticmethod
    def level_for(lux):
        # dark room ~8 %, a lamp-lit room (~50 lux) ~45 %, daylight indoors (~500) ~70 %, bright sun 100 %
        return max(0.06, min(1.0, 0.08 + 0.22 * math.log10(lux + 1)))

    def _tick(self):
        if not (self.auto and self.als and self.bl and self.max):
            return
        lux = self._read_lux()
        if lux is None:
            return
        self._lux_avg = lux if self._lux_avg is None else self._lux_avg + (lux - self._lux_avg) * 0.35
        self.lux = self._lux_avg
        target = self.level_for(self._lux_avg) * (0.7 if self.dim else 1.0)
        diff = target - self.level
        if abs(diff) < 0.02:
            return
        step = max(-0.06, min(0.06, diff))    # eases: at most 6 % every 2 s
        self._apply(self.level + step)
        self.changed.emit()

    # ---------------------------------------------------------------- setting it
    def _current(self):
        if not (self.bl and self.max):
            return None
        v = _read(self.bl + "/brightness", int)
        return v / self.max if v is not None else None

    def _apply(self, v):
        v = max(0.03, min(1.0, v))
        self.level = v
        if not (self.bl and self.max):
            return
        raw = max(1, round(v * self.max))
        name = os.path.basename(self.bl)
        try:
            r = subprocess.run(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                                "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", name, str(raw)],
                               capture_output=True, text=True, timeout=3)
            if r.returncode != 0:
                with open(self.bl + "/brightness", "w") as f:        # (works where the file is writable)
                    f.write(str(raw))
        except Exception as e:
            print(f"[room] brightness: {e!r}")

    def set_level(self, v):
        self.auto = False
        self.manual = max(0.03, min(1.0, float(v)))
        self._apply(self.manual)
        self._save()

    def set_auto(self, on):
        self.auto = bool(on)
        if not self.auto:
            self._apply(self.manual)
        else:
            self._lux_avg = None
            self._tick()
        self._save()

    def set_dim(self, dim):
        self.dim = bool(dim)

    def _save(self):
        self.store.write({"auto": self.auto, "level": self.manual})
        self.changed.emit()
