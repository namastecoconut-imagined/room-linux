"""The little status line on standby: ⚡ while on the charger, then how warm the Surface is (Cool / Normal / Warm /
Hot from its CPU sensor). (Screen brightness is left to the Surface itself.)
"""
import datetime as dt
import glob
import time

from PySide6.QtCore import QObject, QTimer, Signal


class Screen(QObject):
    statusChanged = Signal()

    def __init__(self, cfg: dict):
        super().__init__()
        self.cfg = cfg
        self.standby = False
        self.dim = False
        self.last_presence = time.time()
        self.alarm_ringing = False
        self.status = ""
        self._last_pct = None

    def start(self):
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(20000)
        self._status()

    def _tick(self):
        self._status()

    def night_hour(self, h: int) -> bool:
        a, b = int(self.cfg.get("nightStart", 23)), int(self.cfg.get("nightEnd", 7))
        return (h >= a or h < b) if a > b else (a <= h < b)

    def set_state(self, standby: bool, dim: bool):
        self.standby, self.dim = standby, dim

    # ---- ⚡ Cool
    def _status(self):
        parts = []
        try:
            for p in glob.glob("/sys/class/power_supply/*/online"):
                if open(p).read().strip() == "1":
                    parts.append("⚡"); break
        except Exception:
            pass
        temp = None
        try:
            for z in glob.glob("/sys/class/thermal/thermal_zone*"):
                kind = open(z + "/type").read().strip()
                if kind in ("x86_pkg_temp", "TCPU", "cpu-thermal", "acpitz"):
                    t = int(open(z + "/temp").read().strip()) / 1000
                    temp = t if temp is None else max(temp, t)
        except Exception:
            pass
        if temp is not None:
            parts.append("Cool" if temp < 50 else "Normal" if temp < 65 else "Warm" if temp < 80 else "Hot")
        s = " ".join(parts)
        if s != self.status:
            self.status = s
            self.statusChanged.emit()
