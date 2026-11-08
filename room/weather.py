"""Weather + air quality from Open-Meteo (no key), as on the iPhone panel. The last forecast is kept on disk
so a restart shows weather straight away while a fresh one loads."""
import datetime as dt
import time

from PySide6.QtCore import QObject, QTimer, Signal

from . import net
from .config import State


def text(c: int) -> str:
    if c == 0: return "Clear"
    if c <= 2: return "Partly cloudy"
    if c == 3: return "Overcast"
    if c in (45, 48): return "Fog"
    if 51 <= c <= 57: return "Drizzle"
    if 61 <= c <= 67 or 80 <= c <= 82: return "Rain"
    if 71 <= c <= 86: return "Snow"
    if c >= 95: return "Storms"
    return ""


class Weather(QObject):
    changed = Signal()

    def __init__(self, lat: float, lon: float):
        super().__init__()
        self.lat, self.lon = lat, lon
        self.store = State("weather")
        self.data: dict = {}
        self.aqi: int | None = None
        self.failures = 0
        saved = self.store.read()
        if saved.get("at", 0) > time.time() - 12 * 3600:
            self._apply(saved.get("w", {}), save=False)
            self.aqi = saved.get("aqi")

    def start(self):
        self.poll()
        self.timer = QTimer(self); self.timer.timeout.connect(self.poll); self.timer.start(15 * 60 * 1000)

    def poll(self):
        q = f"?latitude={self.lat}&longitude={self.lon}&timezone=auto"
        u = ("https://api.open-meteo.com/v1/forecast" + q +
             "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code"
             "&hourly=temperature_2m,precipitation_probability,weather_code"
             "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset&forecast_days=3")
        net.get_json(u, self._got)
        net.get_json("https://air-quality-api.open-meteo.com/v1/air-quality" + q + "&current=us_aqi", self._got_aqi)

    def _got(self, w):
        if not w or "current" not in w:
            self.failures += 1
            QTimer.singleShot(int(min(600, 30 * 2 ** min(self.failures - 1, 5)) * 1000), self.poll)
            return
        self.failures = 0
        self._apply(w, save=True)

    def _got_aqi(self, a):
        try:
            self.aqi = int(round(a["current"]["us_aqi"]))
        except Exception:
            return
        self.changed.emit()

    def _apply(self, w: dict, save: bool):
        cur = w.get("current")
        if not cur:
            return
        if save:
            self.store.write({"at": time.time(), "w": w, "aqi": self.aqi})
        H = w.get("hourly", {})
        times, temps = H.get("time", []), H.get("temperature_2m", [])
        pp, codes = H.get("precipitation_probability", []), H.get("weather_code", [])
        now = dt.datetime.now().replace(minute=0, second=0, microsecond=0)
        hours = []
        for i, t in enumerate(times):
            try:
                at = dt.datetime.fromisoformat(t)
            except ValueError:
                continue
            if at <= now or temps[i] is None:
                continue
            hours.append({"h": at.hour, "t": round(temps[i]), "p": pp[i] if i < len(pp) and pp[i] is not None else 0,
                          "d": text(codes[i] if i < len(codes) else 0)})
            if len(hours) >= 24:
                break
        D = w.get("daily", {})
        hi, lo = D.get("temperature_2m_max", [None]), D.get("temperature_2m_min", [None])
        self.data = {
            "ok": True,
            "t": round(cur.get("temperature_2m", 0)),
            "feels": round(cur.get("apparent_temperature", 0)),
            "hum": cur.get("relative_humidity_2m", 0),
            "d": text(cur.get("weather_code", 0)),
            "hi": round(hi[0]) if hi and hi[0] is not None else None,
            "lo": round(lo[0]) if lo and lo[0] is not None else None,
            "hours": hours,
        }
        self.changed.emit()

    def snapshot(self) -> dict:
        d = dict(self.data) if self.data else {"ok": False, "hours": []}
        d["aqi"] = self.aqi
        return d
