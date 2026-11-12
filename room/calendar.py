"""Google Calendar through secret iCal addresses (config "icalURLs", a list — say work and personal — and the older
single "icalURL"), each refreshed every 10 minutes and shown together. Recurring events and their exceptions are
expanded the same way the iPhone panel does. The addresses are secrets: they're never printed (scripts/calendar.sh
adds them to config.json)."""
import datetime as dt

from PySide6.QtCore import QObject, QTimer, Signal

from . import net


class Calendar(QObject):
    changed = Signal()

    def __init__(self, urls):
        super().__init__()
        if isinstance(urls, str):
            urls = [urls]
        self.urls = list(dict.fromkeys(u.strip().replace("webcal://", "https://") for u in (urls or []) if u and u.strip()))
        self.got: dict = {}               # address → its events (the last good download)
        self.events: list[dict] = []

    def start(self):
        if not self.urls:
            return
        self.fetch()
        self.timer = QTimer(self); self.timer.timeout.connect(self.fetch); self.timer.start(10 * 60 * 1000)
        # the list rolls over at midnight and as events end, even without a new download
        self.tick = QTimer(self); self.tick.timeout.connect(self.changed.emit); self.tick.start(60 * 1000)

    def fetch(self):
        for i, u in enumerate(self.urls):
            net.request("GET", u, lambda status, data, u=u, i=i: self._got(u, i, status, data), timeout_ms=20000)

    def _got(self, url, i, status, data):
        if status != 200:
            print(f"[room] calendar {i + 1} of {len(self.urls)}: couldn't be fetched ({status})", flush=True)
            return
        try:
            import icalendar
            import recurring_ical_events
            cal = icalendar.Calendar.from_ical(data)
            now = dt.datetime.now().astimezone()
            items = recurring_ical_events.of(cal).between(now - dt.timedelta(hours=12), now + dt.timedelta(days=7))
        except Exception as e:
            print(f"[room] calendar {i + 1} of {len(self.urls)} couldn't be read: {e}")
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
        self.got[url] = out
        # all the calendars together; a meeting that's on both (an invite to both) once
        seen, merged = set(), []
        for ev in sorted((e for evs in self.got.values() for e in evs), key=lambda x: x["start"]):
            k = (ev["title"].lower(), ev["start"])
            if k not in seen:
                seen.add(k); merged.append(ev)
        self.events = merged
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
