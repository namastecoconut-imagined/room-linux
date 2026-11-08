"""Alexa on the panel: runs the voice process, acts on what was said, and answers.

The voice process (voice/roomvoice.py, in its own Python at voice/.venv) does the hearing and speaking; this side keeps
the screen's state ({state, heard, reply, level, ready, error}) and does the work through the same calls the touch
screens use. While someone's talking to it, music playing from the Surface (and Spotify, wherever it's playing) is
turned down, and back up when it's done.
"""
import datetime as dt
import json
import os
import re
import subprocess
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, QTimer, Signal

from . import intents

ROOT = Path(__file__).resolve().parent.parent
NUM = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}


def dur_text(sec: float) -> str:
    sec = int(round(sec))
    h, m, s = sec // 3600, sec % 3600 // 60, sec % 60
    parts = []
    if h:
        parts.append(f"{h} hour" + ("s" if h != 1 else ""))
    if m:
        parts.append(f"{m} minute" + ("s" if m != 1 else ""))
    if s and not h and (not m or m < 5):
        parts.append(f"{s} second" + ("s" if s != 1 else ""))
    return " and ".join(parts) or "no time"


def time_text(h: int, m: int, h24=False) -> str:
    if h24:
        return f"{h:02d}:{m:02d}"
    ap = "am" if h < 12 else "pm"
    hh = h % 12 or 12
    return f"{hh} {ap}" if m == 0 else f"{hh}:{m:02d} {ap}"


class Assistant(QObject):
    changed = Signal()
    levelChanged = Signal()

    def __init__(self, room):
        super().__init__()
        self.room = room
        self.state = "off"         # off · idle · listening · thinking · speaking
        self.heard = ""
        self.reply = ""
        self.error = ""
        self.level = 0.0
        self.proc: QProcess | None = None
        self._buf = b""
        self._ducked = None
        self._restart = QTimer(self); self._restart.setSingleShot(True); self._restart.timeout.connect(self.start)
        self._fails = 0
        self._pending = None

    # ---------------------------------------------------------------- the voice process
    def available(self) -> bool:
        return (ROOT / "voice" / ".venv" / "bin" / "python").exists() and self.room.cfg.get("voice") is not False

    def start(self):
        if not self.available():
            self.state = "off"; self.error = "Voice isn't installed yet — run scripts/voice.sh"
            self.changed.emit()
            return
        self.proc = QProcess(self)
        env = QProcessEnvironment.systemEnvironment()
        cfg = dict(self.room.cfg.get("voiceSettings") or {})
        for k in ("deepgramKey", "picovoiceKey"):          # the two service keys live at the top of config.json
            if self.room.cfg.get(k):
                cfg[k] = self.room.cfg[k]
        env.insert("ROOM_VOICE_CFG", json.dumps(cfg))
        self.proc.setProcessEnvironment(env)
        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.ForwardedErrorChannel)
        self.proc.readyReadStandardOutput.connect(self._read)
        self.proc.finished.connect(self._ended)
        self.proc.start(str(ROOT / "voice" / ".venv" / "bin" / "python"), [str(ROOT / "voice" / "roomvoice.py")])
        self.state = "idle"; self.changed.emit()

    def stop(self):
        if self.proc:
            self.proc.finished.disconnect(self._ended)
            self.proc.kill(); self.proc.waitForFinished(1000)
            self.proc = None

    def _ended(self, *_):
        # the voice process dying never takes Room with it; try again a little later
        self._fails += 1
        self.state = "off"
        if not self.error:
            self.error = "Voice stopped — restarting"
        self.changed.emit()
        self._restart.start(min(60000, 3000 * self._fails))

    def _send(self, **cmd):
        if self.proc and self.proc.state() == QProcess.ProcessState.Running:
            self.proc.write((json.dumps(cmd) + "\n").encode())

    def _read(self):
        self._buf += bytes(self.proc.readAllStandardOutput())
        while b"\n" in self._buf:
            line, self._buf = self._buf.split(b"\n", 1)
            try:
                self._event(json.loads(line))
            except Exception:
                pass

    # ---------------------------------------------------------------- what it hears
    def _event(self, e: dict):
        ev = e.get("ev")
        if ev == "level":
            self.level = float(e.get("v", 0)); self.levelChanged.emit(); return      # raw RMS 0…1
        if ev == "ready":
            self._fails = 0; self.error = ""; self.state = "idle"
            self._send(cmd="words", words=self._words())
        elif ev == "error":
            self.error = e.get("msg", "")
        elif ev in ("wake", "listening"):
            self.state = "listening"; self.heard = ""; self.reply = ""; self.error = ""
            self._duck(True)
        elif ev == "partial":
            self.heard = (e.get("text") or "").strip()        # words as they're recognised
        elif ev == "thinking":
            self.state = "thinking"
        elif ev == "heard":
            self.heard = (e.get("text") or "").strip()
            self._act(self.heard)
        elif ev == "speaking":
            self.state = "speaking"
        elif ev == "spoken":
            if self.state == "speaking":
                self.state = "idle"
                self._duck(False)
        self.changed.emit()

    def listen(self):
        """Tap to talk."""
        if self.state == "off":
            return
        self._send(cmd="listen")

    def cancel(self):
        self._send(cmd="cancel")
        if self.state != "off":
            self.state = "idle"
        self._duck(False)
        self.changed.emit()

    def _words(self):
        r = self.room
        w = [x["name"] for x in r.lights.snapshot()]
        w += [p.get("name", "") for p in (r.spotify.snapshot().get("playlists") or [])]
        return [x for x in w if x]

    # ---------------------------------------------------------------- music down while talking
    def _music_streams(self):
        """PipeWire playback streams other than Room's own voice and tones (pw-play) — AirPlay, a browser…"""
        out = []
        try:
            nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
            for n in nodes:
                props = ((n.get("info") or {}).get("props") or {})
                if props.get("media.class") != "Stream/Output/Audio":
                    continue
                app = (props.get("application.name") or props.get("node.name") or "").lower()
                if "pw-play" in app or "pw-cat" in app:
                    continue
                out.append(n["id"])
        except Exception:
            pass
        return out

    def _duck(self, on: bool):
        """Music down to 30 % while you talk to Room — just the music streams, never the speaker as a whole (turning
        the whole speaker down also made Room's own answer quiet)."""
        try:
            if on and self._ducked is None:
                saved = {}
                for sid in self._music_streams():
                    out = subprocess.run(["wpctl", "get-volume", str(sid)], capture_output=True, text=True, timeout=2).stdout
                    try:
                        v = float(out.split()[1])
                    except Exception:
                        continue
                    saved[sid] = v
                    subprocess.run(["wpctl", "set-volume", str(sid), f"{v * 0.3:.2f}"], timeout=2)
                sp = self.room.spotify.snapshot()
                spv = sp.get("volume") if sp.get("playing") and sp.get("canVolume") and not self.room.airplay.showing else None
                if spv:
                    self.room.spotify.set_volume(max(5, int(spv * 0.3)))
                self._ducked = (saved, spv)
            elif not on and self._ducked is not None:
                saved, spv = self._ducked
                self._ducked = None
                for sid, v in saved.items():
                    subprocess.run(["wpctl", "set-volume", str(sid), f"{v:.2f}"], timeout=2)
                if spv:
                    self.room.spotify.set_volume(int(spv))
        except Exception as e:
            print(f"[room] duck: {e!r}")
            self._ducked = None

    # ---------------------------------------------------------------- doing it
    def say(self, text: str, listen=False):
        self.reply = text
        if text:
            self._send(cmd="say", text=text, listen=listen)
        else:
            self.state = "idle"
            self._duck(False)
        self.changed.emit()

    def _act(self, text: str):
        if not text:
            self.state = "idle"; self.reply = ""; self._duck(False); return
        if self._pending:
            lead = {"timer_length": "set a timer for ", "alarm_time": "set an alarm for ", "reminder_text": "remind me to "}[self._pending]
            self._pending = None
            if not re.search(r"\b(timer|alarm|remind)\b", text.lower()):
                text = lead + text
        r = self.room
        rooms = [x["name"] for x in r.lights.snapshot()]
        pls = [p.get("name", "") for p in (r.spotify.snapshot().get("playlists") or [])]
        it = intents.parse(text, rooms, pls)
        try:
            reply, listen = self._do(it)
        except Exception as e:
            print(f"[room] assistant: {e!r} for {it}")
            reply, listen = "Sorry, something went wrong there.", False
        self.say(reply, listen)

    def _here(self):
        return self.room.lights.here or (self.room.lights.rooms[0]["name"] if self.room.lights.rooms else None)

    def _do(self, it: dict):
        r, d = self.room, it["do"]
        h24 = r.cfg.get("clock24", False)
        now = dt.datetime.now()
        if d == "nothing":
            return "", False
        if d == "dismiss":
            return ("You're welcome." if it.get("thanks") else ""), False
        if d == "greet":
            part = "morning" if now.hour < 12 else "afternoon" if now.hour < 17 else "evening"
            return f"Good {part}.", False

        # ---------------- lights
        if d == "scene":
            sc = it["scene"]
            if sc in ("Relax", "Read") or (it.get("room") and sc in ("Movie", "Night")):
                rm = it.get("room") or self._here()
                r.roomScene(rm, sc)
                return f"{sc} lights in the {rm.lower()}.", False
            r.houseScene(sc)
            return {"Movie": "Movie time.", "Evening": "Evening lights.", "Night": "Good night."}.get(sc, "Okay."), False
        if d == "lights":
            target = None if it.get("all") else (it.get("room") or self._here())
            name = "everything" if target is None else target
            lights = r.lights
            if it.get("on") is False:
                lights.set_room(target, on=False)
                return ("Lights off." if target is None else f"{target} off."), False
            if it.get("on") is True:
                lights.set_room(target, on=True)
                return ("Lights on." if target is None else f"{target} on."), False
            if "level" in it:
                lights.set_room(target, on=True, level=it["level"])
                return f"{name.capitalize() if target is None else target}, {it['level']} percent.", False
            if "rgb" in it:
                lights.set_room(target, on=True, rgb=it["rgb"])
                return "Okay.", False
            if "kelvin" in it:
                lights.set_room(target, on=True, kelvin=it["kelvin"])
                return "Okay.", False
            snap = {x["name"]: x for x in lights.snapshot()}
            cur = snap.get(target) if target else None
            if it.get("warmer") or it.get("cooler"):
                k = (cur or {}).get("kelvin", 2700)
                k = max(2200, k - 800) if it.get("warmer") else min(6500, k + 800)
                lights.set_room(target, on=True, kelvin=k)
                return ("Warmer." if it.get("warmer") else "Cooler."), False
            if "step" in it:
                lv = (cur or {}).get("level", 50) if (cur or {}).get("on") else (0 if it["step"] > 0 else 50)
                lv = max(5, min(100, lv + it["step"]))
                lights.set_room(target, on=True, level=lv)
                return f"{lv} percent.", False
        if d == "lights_query":
            lit = [x for x in r.lights.snapshot() if x["on"]]
            if not lit:
                return "All the lights are off.", False
            return "On: " + ", ".join(f"{x['name']} at {x['level']} percent" for x in lit) + ".", False

        # ---------------- timers
        th = r._things
        if d == "timer_start":
            th.start_timer(it["sec"], it.get("label", ""))
            lab = it["label"].capitalize() + " timer" if it.get("label") else "Timer"
            return f"{lab} for {dur_text(it['sec'])}, starting now.", False
        if d in ("timer_left", "timer_cancel", "timer_pause", "timer_resume", "timer_add"):
            ts = th.snapshot()["timers"]
            if not ts:
                return "There's no timer running.", False
            t = ts[0]
            if d == "timer_left":
                if len(ts) == 1:
                    return f"{dur_text(t['left']).capitalize()} left.", False
                return " ".join(f"{(x['label'] or 'Timer')}: {dur_text(x['left'])}." for x in ts), False
            if d == "timer_cancel":
                for x in ts:
                    th.cancel_timer(x["id"])
                return ("Timer cancelled." if len(ts) == 1 else "Timers cancelled."), False
            if d == "timer_pause":
                if not t["paused"]:
                    th.pause_timer(t["id"])
                return "Paused.", False
            if d == "timer_resume":
                if t["paused"]:
                    th.pause_timer(t["id"])
                return "Resumed.", False
            th.add_time(t["id"], it["sec"])
            return f"Added {dur_text(it['sec'])}.", False

        # ---------------- alarms
        if d == "alarm_set":
            if "in" in it:
                at = now + dt.timedelta(seconds=it["in"])
                h, m, days = at.hour, at.minute, []
            else:
                h, m, days = it["h"], it["m"], it["days"]
            th.add_alarm(h, m, days)
            when = time_text(h, m, h24)
            if days:
                from .things import days_text
                dt_ = days_text(days).replace("Weekdays", "Weekday").replace("Weekends", "Weekend").replace("Every day", "Daily")
                return f"{dt_} alarm set for {when}.", False
            a, nxt = th.next_alarm()
            day = "tomorrow" if nxt and nxt.date() != now.date() else "today"
            return f"Alarm set for {when} {day}.", False
        if d == "alarm_off":
            al = [a for a in th.alarms if a.get("on")]
            if it.get("at"):
                al = [a for a in al if (a["h"], a["m"]) == tuple(it["at"])]
            elif not it.get("all"):
                a, _ = th.next_alarm()
                al = [a] if a else []
            if not al:
                return "I couldn't find that alarm.", False
            for a in al:
                th.toggle_alarm(a["id"])
            return ("Alarm off." if len(al) == 1 else f"{len(al)} alarms off."), False
        if d == "alarm_query":
            a, when = th.next_alarm()
            if not a:
                return "You've no alarms set.", False
            day = "today" if when.date() == now.date() else "tomorrow" if when.date() == now.date() + dt.timedelta(days=1) else when.strftime("%A")
            return f"Your next alarm is at {time_text(a['h'], a['m'], h24)} {day}.", False

        # ---------------- reminders
        if d == "reminder_add":
            due = 0.0
            if it.get("in"):
                due = (now + dt.timedelta(seconds=it["in"])).timestamp()
            elif it.get("at"):
                h, m = it["at"]
                target = now.replace(hour=h, minute=m, second=0, microsecond=0) + dt.timedelta(days=it.get("day", 0))
                if target <= now and not it.get("day"):
                    if h < 12 and h + 12 < 24 and now.replace(hour=h + 12, minute=m) > now:
                        target = target.replace(hour=h + 12)        # "at 6" in the afternoon means 6 pm
                    else:
                        target += dt.timedelta(days=1)
                due = target.timestamp()
            th.add_reminder(it["text"], due)
            what = it["text"][0].lower() + it["text"][1:]
            if not due:
                return f"Okay, I'll keep that: {what}.", False
            dd = dt.datetime.fromtimestamp(due)
            day = "" if dd.date() == now.date() else " tomorrow" if dd.date() == now.date() + dt.timedelta(days=1) else dd.strftime(" on %A")
            if it.get("in"):
                return f"I'll remind you to {what} in {dur_text(it['in'])}.", False
            return f"I'll remind you to {what} at {time_text(dd.hour, dd.minute, h24)}{day}.", False
        if d == "reminder_list":
            rs = [x for x in th.snapshot()["reminders"] if not x["done"]]
            if not rs:
                return "Nothing to remember.", False
            head = f"You've got {len(rs)}." if len(rs) > 1 else "Just one."
            return head + " " + ". ".join(x["text"] + (", " + x["when"].replace("Today · ", "today at ").replace("Tomorrow · ", "tomorrow at ") if x["when"] else "") for x in rs[:4]) + ".", False

        # ---------------- weather, time, calendar
        wx = r.wx.snapshot() if not r.demo else __import__("room.demo", fromlist=["WEATHER"]).WEATHER
        if d in ("weather", "weather_rain"):
            if not wx.get("ok"):
                return "I don't have the weather right now.", False
            if it["when"] == "tomorrow":
                days = wx.get("days") or []
                if len(days) < 2:
                    return "I don't have tomorrow's forecast yet.", False
                t = days[1]
                if d == "weather_rain":
                    return (f"Tomorrow looks wet — {t['p']} percent chance of rain." if t["p"] >= 50 else f"Probably not — {t['p']} percent chance tomorrow."), False
                return f"Tomorrow: {t['d'].lower()}, {t['hi']} and {t['lo']}.", False
            ra = next((x for x in (wx.get("hours") or [])[:12] if (x.get("p") or 0) >= 50), None)
            if d == "weather_rain":
                return (f"Yes, around {time_text(ra['h'], 0, h24)}." if ra else "No rain expected in the next few hours."), False
            s = f"It's {wx['t']} degrees and {wx['d'].lower()}."
            if wx.get("hi") is not None:
                s += f" Up to {wx['hi']} today."
            if ra:
                s += f" Rain's likely around {time_text(ra['h'], 0, h24)}."
            return s, False
        if d == "time":
            return f"It's {time_text(now.hour, now.minute, h24)}.", False
        if d == "date":
            return f"It's {now.strftime('%A, %-d %B')}.", False
        if d == "calendar":
            evs = r.events
            if not evs:
                return "Nothing on your calendar.", False
            e = evs[0]
            when = e["when"]
            if re.match(r"\d", when):
                s = f"Next up: {e['title']} at {when}."
            elif when in ("All day", "Now"):
                s = f"{e['title']}, " + ("all day today." if when == "All day" else "happening now.")
            else:
                day = {"Tmrw": "tomorrow"}.get(when, "on " + {"Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"}.get(when, when))
                s = f"Next up: {e['title']} {day}" + (f" at {e['extra']}" if e.get("extra") else "") + "."
            return s, False

        # ---------------- music
        playing_src = r.airplay if r.airplay.showing else r.spotify
        m = r.music
        if d == "pause":
            if m.get("playing"):
                playing_src.play_pause()
            return "", False
        if d == "resume":
            if not m.get("playing") and m.get("exists"):
                playing_src.play_pause()
            return "", False
        if d == "next":
            r.next(); return "", False
        if d == "previous":
            r.previous(); return "", False
        if d == "like":
            r.toggleLiked(); return "Saved.", False
        if d == "now_playing":
            if not m.get("exists") or not m.get("title"):
                return "Nothing's playing.", False
            artist = m.get("artist") or "an artist I can't name"
            return f"This is {m['title']} by {artist}.", False
        if d == "volume":
            v = m.get("volume") if m.get("volume") is not None else 50
            v = it["to"] if "to" in it else max(0, min(100, v + it["by"]))
            self._duck(False)                     # back to normal first, so the new level is the one that stays
            r.setVolume(int(v))
            return "", False
        if d == "play":
            pl = it.get("playlist")
            if pl:
                uri = next((p.get("uri") for p in (r.spotify.snapshot().get("playlists") or []) if p.get("name") == pl), None)
                if uri:
                    r.playUri(uri)
                    return f"Playing {pl}.", False
            return f"I couldn't find {it.get('query')} in your playlists.", False

        if d == "ask":
            q = {"timer_length": "For how long?", "alarm_time": "For what time?", "reminder_text": "What should I remind you about?"}
            self._pending = it["what"]
            return q.get(it["what"], "Sorry?"), True
        return "Sorry, I didn't get that.", False
