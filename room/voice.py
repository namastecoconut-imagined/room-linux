"""Room's side of the voice assistant. The assistant is its own program (assistant/, its own service); this is the
panel's end of the line to it — a local socket ($XDG_RUNTIME_DIR/room-assistant.sock), one JSON object per line.

The assistant tells Room what it's doing (for the screen) and asks it two things:
  {"t": "state", "state": "listening|thinking|speaking|idle", "stage": …, "heard": …, "reply": …, "line": …, "card": …}
  {"t": "snapshot", "id": n}              → {"t": "reply", "id": n, "data": {the home right now}}
  {"t": "run", "id": n, "actions": [...]} → {"t": "reply", "id": n, "data": "what was done"}
Room tells it:  {"t": "listen"} (a tap), {"t": "cancel"} (tap to stop), {"t": "voice", "voice": id} (the voice chosen in
Settings), {"t": "preview", "voice": id, "name": …} (play its sample; voice "" stops it) → {"t": "preview", "playing": id or ""}.

If the assistant isn't running, Room carries on exactly the same; the screen just never shows it.
"""
import datetime as dt
import json
import os
import time

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtNetwork import QLocalServer, QLocalSocket

from .wiz import norm_mac

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "room-assistant.sock")


class VoiceLink(QObject):
    changed = Signal()

    def __init__(self, room):
        super().__init__()
        self.room = room
        self.peer: QLocalSocket | None = None
        self.buf = b""
        self.level = 0.0
        # Room's own notes, for the screen: lit — the rooms whose lights the last answer changed (the lights card);
        # reminded — the reminder it just made (the reminder card); about — what Room asked it to listen for
        # ("reminder": the Reminders screen's + Add a reminder)
        self.st = {"state": "off", "stage": "idle", "heard": "", "reply": "", "line": "", "card": "", "follow": False,
                   "lit": [], "reminded": "", "about": ""}
        self.about_at = 0.0
        self.previewing = ""                # the voice whose sample is playing (Settings → More settings → Voice)
        self.server = QLocalServer(self)
        self.server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
        self.server.newConnection.connect(self._accept)

    def start(self):
        QLocalServer.removeServer(SOCK)
        if not self.server.listen(SOCK):
            print(f"[room] voice link: couldn't listen on {SOCK}: {self.server.errorString()}", flush=True)

    @property
    def connected(self) -> bool:
        return self.peer is not None and self.peer.state() == QLocalSocket.LocalSocketState.ConnectedState

    def _accept(self):
        s = self.server.nextPendingConnection()
        if self.peer:
            self.peer.disconnectFromServer()
        self.peer, self.buf = s, b""
        s.readyRead.connect(self._read)
        s.disconnected.connect(self._gone)
        self.st.update(state="idle", stage="idle")
        print("[room] voice link: the assistant is connected", flush=True)
        self.changed.emit()

    def _gone(self):
        if self.sender() is self.peer:
            self.peer = None
            self.st.update(state="off", stage="idle")
            print("[room] voice link: the assistant went away", flush=True)
            self.changed.emit()

    def send(self, msg: dict):
        if self.connected:
            self.peer.write((json.dumps(msg) + "\n").encode())
            self.peer.flush()

    def _read(self):
        self.buf += bytes(self.peer.readAll())
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            try:
                m = json.loads(line)
            except ValueError:
                continue
            try:
                self._handle(m)
            except Exception as e:
                print(f"[room] voice link: {m.get('t')}: {e!r}", flush=True)

    def _handle(self, m: dict):
        t = m.get("t")
        if t == "level":
            self.level = float(m.get("v", 0))
            self.changed.emit()
            return
        if t == "preview":                                     # a voice's sample playing (Settings), or done
            self.previewing = m.get("playing") or ""
            self.changed.emit()
            return
        if t == "state":
            if m.get("state") == "listening":
                self.st["lit"], self.st["reminded"] = [], ""     # a new question
                if time.monotonic() - self.about_at > 10:
                    self.st["about"] = ""                         # (not the one Room just asked for)
            elif m.get("state") == "idle":
                self.st["about"] = ""
            for k in self.st:
                if k in m:
                    self.st[k] = m[k]
            self.changed.emit()
        elif t == "snapshot":
            self.send({"t": "reply", "id": m.get("id"), "data": self.snapshot()})
        elif t == "run":
            self.run(m.get("actions") or [], lambda summary, i=m.get("id"): self.send({"t": "reply", "id": i, "data": summary}))

    # ---------------------------------------------------------------- what Room tells the assistant
    def listen(self, about: str = ""):
        """Start listening (a tap). about: what it's for — "reminder": what you say is something to be reminded of."""
        self.st["about"], self.about_at = about, time.monotonic()
        self.send({"t": "listen", "about": about} if about else {"t": "listen"})
        self.changed.emit()

    def cancel(self):
        self.send({"t": "cancel"})

    def preview(self, voice: str, name: str = ""):
        """Play a voice's sample (Settings → More settings → Voice); voice "" stops it."""
        self.send({"t": "preview", "voice": voice, "name": name})
        if not voice and self.previewing:
            self.previewing = ""; self.changed.emit()

    def use_voice(self, voice: str):
        self.send({"t": "voice", "voice": voice})

    # ---------------------------------------------------------------- the home right now (for Claude)
    def snapshot(self) -> dict:
        r, th = self.room, self.room._things
        now = dt.datetime.now()
        w = r.weather or {}
        wx = {k: w.get(k) for k in ("t", "feels", "hum", "d", "hi", "lo", "aqi", "sunrise", "sunset") if w.get(k) is not None}
        wx["next_hours"] = [f"{h['h']}:00 {h['t']}° {h['d']}{' rain ' + str(h['p']) + '%' if h.get('p', 0) >= 30 else ''}"
                            for h in (w.get("hours") or [])[:12]]
        wx["next_days"] = [f"{d['name']} {d['hi']}°/{d['lo']}° {d['d']}{' rain ' + str(d['p']) + '%' if d.get('p', 0) >= 30 else ''}"
                           for d in (w.get("days") or [])[:3]]
        ts = th.snapshot()
        snap = {"now": now.strftime("%A %-d %b %Y, %-I:%M %p"), "here": r.lights.here or "", "place": "Bangalore",
                "rooms": [x.get("name") for x in r.lights.rooms],
                "lights": r.lights.lamps_now(), "weather": wx,
                "timers": [{"label": t["label"], "left_seconds": int(t["left"]), "paused": t["paused"]} for t in ts["timers"]]}
        days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        snap["alarms"] = [{"alarm_id": a["id"], "time": f"{a['h']:02d}:{a['m']:02d}", "on": a.get("on"),
                           "repeat": ",".join(days[d] for d in a.get("days") or []) or "once"} for a in th.alarms]
        snap["reminders"] = [{"reminder_id": x["id"], "text": x["text"], "at": x["when"] or "no time"}
                             for x in ts["reminders"] if not x["done"]][:12]
        if th.alert.get("kind") == "reminder":
            snap["reminder_showing"] = {"reminder_id": th.alert.get("id"), "text": th.alert.get("title")}
        m = r.music
        sp = r.spotify.snapshot()
        snap["music"] = {"state": "playing" if m.get("playing") else ("paused" if m.get("exists") else "idle"),
                         "track": m.get("title", ""), "artist": m.get("artist", ""), "speaker": m.get("device", ""),
                         "volume": m.get("volume"), "speakers": [d["name"] for d in sp.get("devices") or []]}
        if r.airplay.showing:
            snap["music"]["note"] = ("playing from their phone over AirPlay to this panel: music and volume actions control "
                                     "it; to play something new, use play (Spotify)")
        snap["my_playlists"] = [{"name": p["name"], "uri": p["uri"]} for p in (sp.get("playlists") or [])][:40]
        snap["calendar"] = [f"{e['title']} — {e['when']}{(' ' + e['extra']) if e.get('extra') else ''}" for e in r.events[:5]]
        return snap

    # ---------------------------------------------------------------- doing what Claude decided
    def run(self, actions, done):
        """Carry out the actions; done(summary) once (playing a search finishes later)."""
        r, th = self.room, self.room._things
        parts, waiting, finished = [], [0], [False]

        def fin():
            if waiting[0] == 0 and not finished[0]:
                finished[0] = True
                done(" · ".join(p for p in parts if p))
        for a in actions:
            k = a.get("kind")
            try:
                if k == "lights":
                    ids = a.get("light_ids") or []
                    want = {norm_mac(i) for i in ids}
                    for room in r.lights.rooms:
                        if room.get("name") not in self.st["lit"] and \
                                any(norm_mac(d.get("mac", "")) in want for d in room.get("devices", [])):
                            self.st["lit"].append(room.get("name"))
                    plain = a.get("brightness") is None and a.get("kelvin") is None and a.get("rgb") is None
                    if a.get("on") is False:
                        n = r.lights.set_lamps(ids, on=False)
                    else:
                        n = r.lights.set_lamps(ids, on=True, level=None if plain else a.get("brightness"),
                                               kelvin=a.get("kelvin"), rgb=a.get("rgb"))
                    parts.append(f"{n} light{'s' if n != 1 else ''}" if n else "couldn't reach those lights")
                elif k == "music":
                    c = a.get("command")
                    src = r.airplay if r.airplay.showing else r.spotify
                    m = r.music
                    if c == "pause" and m.get("playing") or c == "play" and not m.get("playing"):
                        src.play_pause()
                    elif c == "next":
                        r.next()
                    elif c == "previous":
                        r.previous()
                    parts.append(c or "")
                elif k == "volume":
                    v = a.get("level")
                    if v is None:
                        v = (r.music.get("volume") or 50) + int(a.get("change") or 0)
                    v = max(0, min(100, int(v)))
                    r.setVolume(v); parts.append(f"volume {v}")
                elif k == "speaker":
                    d = r.spotify.device_named(a.get("speaker", ""))
                    if d:
                        r.spotify.transfer(d["id"]); parts.append(f"on {d['name'].lower()}")
                elif k == "play":
                    uri = a.get("uri") or ""
                    if uri.startswith("spotify:"):
                        r.spotify.play_uri(uri, speaker=a.get("speaker"))
                        name = next((p["name"] for p in r.spotify.playlists if p.get("uri") == uri), a.get("query") or "that")
                        parts.append(f"playing {name.lower()}")
                    elif a.get("query"):
                        waiting[0] += 1

                        def rep(name, why):
                            parts.append(f"playing {name.lower()}" if name else f"couldn't play — {why}")
                            waiting[0] -= 1
                            fin()
                        r.spotify.play_search(a["query"], a.get("search_type"), a.get("speaker"), rep)
                elif k == "timer" and a.get("seconds"):
                    th.start_timer(int(a["seconds"]), (a.get("label") or "").capitalize())
                    sec = int(a["seconds"]); parts.append(f"timer {sec // 60} min" if sec >= 60 else f"timer {sec} s")
                elif k == "cancel_timer":
                    lab = (a.get("label") or "").lower()
                    for t in list(th.timers):
                        if not lab or lab in (t.get("label") or "").lower():
                            th.cancel_timer(t["id"])
                    parts.append("timer cancelled")
                elif k == "sleep_timer" and a.get("seconds"):
                    sec = int(a["seconds"])
                    QTimer.singleShot(sec * 1000, lambda: r.music.get("playing") and r.playPause())
                    parts.append(f"music stops in {sec // 60} min")
                elif k == "set_alarm" and a.get("time"):
                    h, mi = (int(x) for x in a["time"].split(":")[:2])
                    dmap = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
                    th.add_alarm(h, mi, [dmap[d] for d in a.get("days") or [] if d in dmap])
                    parts.append(f"alarm {h}:{mi:02d}")
                elif k == "alarm_off" and a.get("alarm_id"):
                    for al in th.alarms:
                        if al["id"] == a["alarm_id"] and al.get("on"):
                            th.toggle_alarm(al["id"])
                    parts.append("alarm off")
                elif k == "delete_alarm" and a.get("alarm_id"):
                    th.delete_alarm(a["alarm_id"]); parts.append("alarm deleted")
                elif k == "set_reminder" and a.get("label"):
                    due = 0.0
                    if a.get("at"):
                        try:
                            due = dt.datetime.strptime(a["at"].strip(), "%Y-%m-%d %H:%M").timestamp()
                        except ValueError:
                            pass
                    self.st["reminded"] = th.add_reminder(a["label"][0].upper() + a["label"][1:], due) or ""
                    parts.append("reminder" + (" · " + dt.datetime.fromtimestamp(due).strftime("%-I:%M %p").lower() if due else ""))
                elif k == "cancel_reminder" and a.get("reminder_id"):
                    th.delete_reminder(a["reminder_id"]); parts.append("reminder cancelled")
                elif k == "reminder_done":
                    rid = a.get("reminder_id") or th.alert.get("id")
                    if rid:
                        th.toggle_reminder(rid)
                        if th.alert.get("kind") == "reminder":
                            th.stop_alert()
                        parts.append("done")
            except Exception as e:
                print(f"[room] voice action {k}: {e!r}", flush=True)
        fin()
