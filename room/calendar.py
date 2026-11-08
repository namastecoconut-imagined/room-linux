"""Google Calendar through its secret iCal address (config "icalURL"), refreshed every 10 minutes.
Recurring events and their exceptions are expanded the same way the iPhone panel does."""
import datetime as dt

from PySide6.QtCore import QObject, QTimer, Signal

from . import net


class Calendar(QObject):
    changed = Signal()

    def __init__(self, url: str | None):
        super().__init__()
        self.url = (url or "").replace("webcal://", "https://")
        self.events: list[dict] = []

    def start(self):
        if not self.url:
            return
        self.fetch()
        self.timer = QTimer(self); self.timer.timeout.connect(self.fetch); self.timer.start(10 * 60 * 1000)
        # the list rolls over at midnight and as events end, even without a new download
        self.tick = QTimer(self); self.tick.timeout.connect(self.changed.emit); self.tick.start(60 * 1000)

    def fetch(self):
        net.request("GET", self.url, self._got, timeout_ms=20000)

    def _got(self, status, data):
        if status != 200:
            return
        try:
            import icalendar
            import recurring_ical_events
            cal = icalendar.Calendar.from_ical(data)
            now = dt.datetime.now().astimezone()
            items = recurring_ical_events.of(cal).between(now - dt.timedelta(hours=12), now + dt.timedelta(days=7))
        except Exception as e:
            print(f"[room] calendar couldn't be read: {e}")
            return
        out = []
        for ev in items:
            s, e = ev.get("DTSTART").dt, (ev.get("DTEND") or ev.get("DTSTART")).dt
            all_day = not isinstance(s, dt.datetime)
            if all_day:
                s = dt.datetime.combine(s, dt.time(), tzinfo=now.tzinfo)
                e = dt.datetime.combine(e, dt.time(), tzinfo=now.tzinfo)
            else:
                s, e = s.astimezone(), e.astimezone()
            out.append({"title": str(ev.get("SUMMARY", "")).strip() or "Busy", "start": s, "end": e, "allDay": all_day})
        out.sort(key=lambda x: x["start"])
        self.events = out
        self.changed.emit()

    def upcoming(self, n=3, clock24=False) -> list[dict]:
        """The next few events as the screen shows them: '22:00 Dinner', 'Tue Team standup · 10:30'."""
        now = dt.datetime.now().astimezone()
        today = now.date()
        res = []
        for ev in self.events:
            if ev["end"] <= now:
                continue
            s = ev["start"]
            hm = s.strftime("%H:%M") if clock24 else s.strftime("%-I:%M %p").lower().replace(":00", "")
            if s.date() == today:
                when, extra = ("All day" if ev["allDay"] else ("Now" if s <= now else hm)), ""
            elif s.date() == today + dt.timedelta(days=1):
                when, extra = "Tmrw", ("" if ev["allDay"] else hm)
            else:
                when, extra = s.strftime("%a"), ("" if ev["allDay"] else hm)
            res.append({"when": when, "title": ev["title"], "extra": extra, "today": s.date() <= today})
            if len(res) >= n:
                break
        return res
