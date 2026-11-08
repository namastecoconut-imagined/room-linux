"""Screen brightness and the little status line on standby — the iPhone panel's rules, on the Surface.

Brightness (as on the phone, PanelViewController.applyBrightness):
  awake     day level (config dayBrightness, 0.55); at most 0.55 in the evening (21–6), 0.4 in night hours
  standby   0.5 in daylight hours (7–18, config standbyDayBrightness), 0.45 otherwise (config standbyBrightness);
            0.3 once nobody has been around for 15 minutes; night level (config nightBrightness, 0.3) in night hours
  never above 0.7, and multiplied by config brightnessScale (1.0 on the Surface — the phone used 0.55)
It's set with brightnessctl (works without root through logind) and re-applied every 20 s.

Status: ⚡ while on the charger, then how warm the Surface is (Cool / Normal / Warm / Hot from its CPU sensor).
"""
import datetime as dt
import glob
import shutil
import subprocess
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
        self.tool = shutil.which("brightnessctl")

    def start(self):
        self.apply()
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(20000)
        self._status()

    def _tick(self):
        self.apply()
        self._status()

    def night_hour(self, h: int) -> bool:
        a, b = int(self.cfg.get("nightStart", 23)), int(self.cfg.get("nightEnd", 7))
        return (h >= a or h < b) if a > b else (a <= h < b)

    def set_state(self, standby: bool, dim: bool):
        if not standby:
            self.last_presence = time.time()
        if (standby, dim) != (self.standby, self.dim):
            self.standby, self.dim = standby, dim
            self.apply()

    def apply(self):
        if self.alarm_ringing:
            return
        h = dt.datetime.now().hour
        day = float(self.cfg.get("dayBrightness", 0.55))
        cap = 0.7
        late = self.night_hour(h)
        evening = h >= 21 or h < 6
        awake = min(cap, min(day, 0.4) if late else min(day, 0.55) if evening else day)
        stand = min(cap, float(self.cfg.get("standbyDayBrightness", 0.5)) if 7 <= h < 18 else float(self.cfg.get("standbyBrightness", 0.45)))
        if time.time() - self.last_presence > 15 * 60:
            stand = min(stand, 0.3)
        level = awake if not self.standby else float(self.cfg.get("nightBrightness", 0.3)) if self.dim else stand
        level *= max(0.3, min(1.0, float(self.cfg.get("brightnessScale", 1.0))))
        pct = max(3, int(round(level * 100)))
        if pct == self._last_pct or not self.tool:
            return
        self._last_pct = pct
        try:
            subprocess.Popen([self.tool, "-q", "set", f"{pct}%"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

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
