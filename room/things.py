"""Alarms, timers and reminders — all kept on this panel only (in ~/.local/state/room/things.json), as on the
iPhone panel. Checked once a second. When one goes off, `alert` is set (the screen shows it full-size and wakes
from standby) and a chime plays until it's stopped:
  • an alarm rings until Stop (or Snooze, 9 min), for at most 10 minutes; 10 minutes before it, the lights in the
    panel's room fade up from a candle glow (cfg "alarmLights": false turns that off)
  • a timer chimes until Stop, for at most 2 minutes
  • a reminder chimes once; it stays due (amber, and on standby) until it's ticked off
"""
import datetime as dt
import math
import shutil
import struct
import subprocess
import time
import uuid
import wave

from PySide6.QtCore import QObject, QTimer, Signal

from .config import STATE_DIR, State

DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def days_text(days: list[int]) -> str:
    d = sorted(set(days or []))
    if not d:
        return "Once"
    if d == list(range(7)):
        return "Every day"
    if d == [0, 1, 2, 3, 4]:
        return "Weekdays"
    if d == [5, 6]:
        return "Weekends"
    return " ".join(DAYS[i] for i in d)


def _chime_file() -> str:
    """A soft two-note chime (written once as a .wav)."""
    p = STATE_DIR / "chime.wav"
    if p.exists():
        return str(p)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    rate, frames = 44100, []
    n = int(rate * 1.4)
    for i in range(n):
        t = i / rate
        v = 0.0
        for f, s in ((880.0, 0.0), (1318.5, 0.28)):
            if t >= s:
                tt = t - s
                v += math.sin(2 * math.pi * f * tt) * math.exp(-tt * 3.2) * 0.32
                v += math.sin(2 * math.pi * f * 2 * tt) * math.exp(-tt * 6) * 0.06
        frames.append(struct.pack("<h", int(max(-1, min(1, v)) * 32000)))
    with wave.open(str(p), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b"".join(frames))
    return str(p)


def play_chime():
    try:
        f = _chime_file()
        for cmd in (["pw-play", f], ["paplay", f], ["aplay", "-q", f]):
            if shutil.which(cmd[0]):
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
    except Exception as e:
        print(f"[room] chime failed: {e}")


class Things(QObject):
    changed = Signal()
    alertChanged = Signal()

    def __init__(self, cfg: dict, lights=None):
        super().__init__()
        self.cfg = cfg
        self.lights = lights
        self.store = State("things")
        s = self.store.read()
        self.alarms: list[dict] = s.get("alarms", [])
        self.reminders: list[dict] = s.get("reminders", [])
        self.timers: list[dict] = []          # timers don't survive a restart
        self.alert: dict = {}
        self._ring_until = 0.0
        self._next_chime = 0.0
        self._fading = None
        self._last_min = None

    def start(self):
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(1000)

    def _save(self):
        self.store.write({"alarms": self.alarms, "reminders": self.reminders})
        self.changed.emit()

    # ---------------------------------------------------------------- what the screens read
    def next_alarm(self, now: dt.datetime | None = None):
        """(alarm, when) of the next alarm that's on, or (None, None)."""
        now = now or dt.datetime.now()
        best = (None, None)
        for a in self.alarms:
            if not a.get("on"):
                continue
            for add in range(8):
                day = (now + dt.timedelta(days=add)).date()
                when = dt.datetime.combine(day, dt.time(a["h"], a["m"]))
                if when <= now:
                    continue
                if a.get("days") and day.weekday() not in a["days"]:
                    continue
                if best[1] is None or when < best[1]:
                    best = (a, when)
                break
        return best

    def snapshot(self) -> dict:
        now = time.time()
        a, when = self.next_alarm()
        nxt = ""
        if when:
            mins = int((when - dt.datetime.now()).total_seconds() // 60) + 1
            nxt = (f"{mins // 60} h {mins % 60} m" if mins >= 60 else f"{mins} min")
        timers = []
        for t in self.timers:
            left = t["left"] if t.get("paused") else max(0.0, t["ends"] - now)
            timers.append({"id": t["id"], "label": t.get("label", ""), "total": t["total"], "left": left,
                           "paused": bool(t.get("paused")), "done": left <= 0})
        today = dt.date.today()
        rem = []
        for r in sorted(self.reminders, key=lambda r: (r.get("done", False), r.get("due") or 9e12)):
            due = r.get("due") or 0
            d = dt.datetime.fromtimestamp(due) if due else None
            rem.append({"id": r["id"], "text": r["text"], "done": bool(r.get("done")), "due": due,
                        "dueNow": bool(due and due <= now and not r.get("done")),
                        "today": bool(d and d.date() == today), "when": self._when_text(d)})
        return {
            "alarms": [dict(x, daysText=days_text(x.get("days"))) for x in sorted(self.alarms, key=lambda x: (x["h"], x["m"]))],
            "nextAlarm": {"h": a["h"], "m": a["m"], "in": nxt} if a else {},
            "timers": timers,
            "reminders": rem,
        }

    @staticmethod
    def _when_text(d):
        if not d:
            return ""
        today = dt.date.today()
        t = d.strftime("%-I:%M %p").lower().replace(":00", "") if d.minute else d.strftime("%-I %p").lower()
        if d.date() == today:
            return "Today · " + t
        if d.date() == today + dt.timedelta(days=1):
            return "Tomorrow · " + t
        if (d.date() - today).days < 7:
            return d.strftime("%a") + " · " + t
        return d.strftime("%-d %b") + " · " + t

    # ---------------------------------------------------------------- alarms
    def add_alarm(self, h, m, days):
        self.alarms.append({"id": uuid.uuid4().hex[:8], "h": int(h), "m": int(m), "days": list(days or []), "on": True})
        self._save()

    def set_alarm(self, aid, h, m, days):
        for a in self.alarms:
            if a["id"] == aid:
                a.update(h=int(h), m=int(m), days=list(days or []), on=True)
        self._save()

    def toggle_alarm(self, aid):
        for a in self.alarms:
            if a["id"] == aid:
                a["on"] = not a.get("on")
        self._save()

    def delete_alarm(self, aid):
        self.alarms = [a for a in self.alarms if a["id"] != aid]
        self._save()

    # ---------------------------------------------------------------- timers
    def start_timer(self, sec, label=""):
        self.timers.append({"id": uuid.uuid4().hex[:8], "label": label, "total": float(sec), "ends": time.time() + sec})
        self.changed.emit()

    def add_time(self, tid, sec):
        for t in self.timers:
            if t["id"] == tid:
                if t.get("paused"):
                    t["left"] += sec
                else:
                    t["ends"] = max(t["ends"], time.time()) + sec
                t["total"] += sec
        self.changed.emit()

    def pause_timer(self, tid):
        for t in self.timers:
            if t["id"] == tid:
                if t.get("paused"):
                    t["ends"] = time.time() + t["left"]; t["paused"] = False
                else:
                    t["left"] = max(0.0, t["ends"] - time.time()); t["paused"] = True
        self.changed.emit()

    def cancel_timer(self, tid):
        self.timers = [t for t in self.timers if t["id"] != tid]
        if self.alert.get("kind") == "timer" and self.alert.get("id") == tid:
            self.stop_alert()
        self.changed.emit()

    # ---------------------------------------------------------------- reminders
    def add_reminder(self, text, due):
        text = (text or "").strip()
        if not text:
            return
        self.reminders.append({"id": uuid.uuid4().hex[:8], "text": text, "due": float(due or 0), "done": False, "fired": False})
        self._save()

    def toggle_reminder(self, rid):
        for r in self.reminders:
            if r["id"] == rid:
                r["done"] = not r.get("done")
                r["doneAt"] = time.time() if r["done"] else 0
        self._save()

    def delete_reminder(self, rid):
        self.reminders = [r for r in self.reminders if r["id"] != rid]
        self._save()

    # ---------------------------------------------------------------- going off
    def _raise(self, kind, iid, title, sub, ring_for):
        self.alert = {"kind": kind, "id": iid, "title": title, "sub": sub, "at": time.time()}
        self._ring_until = time.time() + ring_for
        self._next_chime = 0.0
        self.alertChanged.emit()

    def stop_alert(self):
        if self.alert.get("kind") == "timer":
            self.timers = [t for t in self.timers if t["id"] != self.alert.get("id")]
            self.changed.emit()
        self.alert = {}
        self._ring_until = 0
        self.alertChanged.emit()

    def snooze_alert(self):
        if self.alert.get("kind") == "alarm":
            sid = "snooze-" + self.alert["id"]
            self.timers.append({"id": sid, "label": "Snooze", "total": 540.0, "ends": time.time() + 540, "snooze": True})
            self.changed.emit()
        self.alert = {}
        self._ring_until = 0
        self.alertChanged.emit()

    def _tick(self):
        now = time.time()
        n = dt.datetime.now()
        # alarms: once a minute, on the minute
        key = (n.year, n.month, n.day, n.hour, n.minute)
        if key != self._last_min:
            self._last_min = key
            for a in self.alarms:
                if a.get("on") and a["h"] == n.hour and a["m"] == n.minute and (not a.get("days") or n.weekday() in a["days"]):
                    t = dt.time(a["h"], a["m"]).strftime("%-I:%M %p").lower()
                    self._raise("alarm", a["id"], t, "Alarm", 600)
                    if not a.get("days"):
                        a["on"] = False
                        self._save()
            self._lights_before_alarm(n)
        # timers
        for t in list(self.timers):
            if not t.get("paused") and t["ends"] <= now and not t.get("rang"):
                t["rang"] = True
                if t.get("snooze"):
                    self.timers.remove(t)
                    self._raise("alarm", t["id"], n.strftime("%-I:%M %p").lower(), "Alarm · snoozed", 600)
                else:
                    self._raise("timer", t["id"], "Time's up", t.get("label") or "Timer", 120)
                self.changed.emit()
        # reminders: chime once when due
        for r in self.reminders:
            if r.get("due") and r["due"] <= now and not r.get("fired") and not r.get("done"):
                r["fired"] = True
                self._save()
                if not self.alert:
                    self._raise("reminder", r["id"], r["text"], "Reminder", 0)
                    play_chime()
        # the chime, every 3 s while ringing
        if self.alert and self._ring_until > now and now >= self._next_chime:
            self._next_chime = now + 3
            play_chime()
        elif self.alert and self.alert.get("kind") != "reminder" and self._ring_until and now > self._ring_until:
            self.stop_alert()
        if self.timers:
            self.changed.emit()        # the countdowns move

    def _lights_before_alarm(self, n: dt.datetime):
        """10 minutes before an alarm, the panel's own room fades up from a candle glow to a warm 70%."""
        if not self.lights or self.cfg.get("alarmLights") is False or not self.lights.here:
            return
        a, when = self.next_alarm(n - dt.timedelta(seconds=1))
        if not when:
            return
        mins = (when - n).total_seconds() / 60
        if not (0 < mins <= 10):
            return
        fade_id = a["id"] + when.isoformat()
        if self._fading != fade_id:
            # only if the room is dark — lights someone already turned on are left alone
            here = [r for r in self.lights.snapshot() if r["name"] == self.lights.here]
            if here and here[0]["on"] > 0:
                return
            self._fading = fade_id
        step = 10 - int(math.ceil(mins))           # 0 … 9
        self.lights.set_room(self.lights.here, on=True, level=8 + step * 7, kelvin=2200 + step * 60)
