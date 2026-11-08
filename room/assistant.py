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
from .brain import Brain, Computer

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
    _main = Signal(object)          # work handed back from Claude's threads to the main thread

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
        # the phone's stages for the screen: wake · follow · heard · think · done · miss · idle
        self.stage = "idle"
        self.line = ""             # the on-screen caption under the answer
        self.card = ""             # weather · forecast · air · timer · music · schedule · alarm
        self.following = False     # this turn came from the open mic after an answer (no wake word)
        self._follow_next = False
        self._follow_turns = 0
        self._turn = 0
        self._talking = False
        self._main.connect(lambda f: f())
        key = (room.cfg.get("anthropicKey") or "").strip()
        self.brain = Brain(key, room.cfg.get("anthropicModel"), room="living room") if key else None
        self.computer = Computer(room.cfg.get("computer"))

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
        if cmd.get("cmd") == "say" and cmd.get("text"):
            self._talking = True
            if not getattr(self, "_t_say", 0):
                import time as _t
                self._t_say = _t.time()
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
        if ev not in ("level",):
            print(f"[room] voice {ev}{(' ' + repr(e.get('text'))) if e.get('text') else ''} · stage {self.stage}", flush=True)
        if ev == "level":
            self.level = float(e.get("v", 0)); self.levelChanged.emit(); return      # raw RMS 0…1
        if ev == "ready":
            self._fails = 0; self.error = ""; self.state = "idle"
            self._send(cmd="words", words=self._words())
            self._send(cmd="prepare", lines=self._everyday_lines())
        elif ev == "error":
            self.error = e.get("msg", "")
        elif ev in ("wake", "listening"):
            if ev == "wake" or not self.following:
                self.following = bool(e.get("follow"))
            if ev == "wake":
                self.following = False; self._follow_turns = 0
            self.state = "listening"; self.heard = ""; self.reply = ""; self.error = ""; self.line = ""; self.card = ""
            self._quick = False
            self.stage = "follow" if self.following else "wake"
            self._duck(True)
            if self.brain:
                self.brain.warm()
        elif ev == "partial":
            self.heard = (e.get("text") or "").strip()        # words as they're recognised
            if self.heard:
                self.stage = "heard"
                # already a whole, plain command ("turn off the lights")? Then Room needn't wait for a long silence
                try:
                    q = self._fast(self.heard, self._parse(self.heard))
                    if q != getattr(self, "_quick", False):
                        self._quick = q
                        self._send(cmd="quick", on=q)       # and back off if it grows into something more
                except Exception:
                    pass
        elif ev == "thinking":
            self.state = "thinking"; self.stage = "think"
        elif ev == "heard":
            import time as _t
            self._t_heard, self._t_say = _t.time(), 0
            self.heard = (e.get("text") or "").strip()
            self._alt = (e.get("alt") or "").strip()
            if not self.heard and e.get("quiet"):
                self.following = True             # a "maybe Alexa" with nothing after it: close without the miss chime
            self._act(self.heard)
        elif ev == "speaking":
            self.state = "speaking"
            import time as _t
            if getattr(self, "_t_heard", 0):
                n = _t.time()
                say = getattr(self, "_t_say", 0)
                print(f"[room] timing after your words came through: "
                      f"{(say - self._t_heard) if say else 0:.1f} s to the answer, "
                      f"{(n - say) if say else 0:.1f} s to its voice · {n - self._t_heard:.1f} s in all", flush=True)
                self._t_heard = 0
        elif ev == "spoken":
            self._talking = False
            if self.state == "speaking":
                self.state = "idle"
                if self._follow_next:
                    # it asked something: keep the mic open a few seconds, no wake word needed (like the phone)
                    self._follow_next = False
                    self.following = True
                    self._send(cmd="listen", follow=True)
                else:
                    self._duck(False)
        self.changed.emit()

    def listen(self):
        """Tap to talk."""
        if self.state == "off":
            return
        self._send(cmd="listen")

    def cancel(self):
        self._send(cmd="cancel")
        if self.brain and self.state == "speaking":
            self.brain.mark_interrupted()
        self._turn += 1                      # anything still on its way is dropped
        self._follow_next = False
        if self.state != "off":
            self.state = "idle"
        self.stage = "idle"
        self._duck(False)
        self.changed.emit()

    def chime(self, name):
        self._send(cmd="chime", name=name)

    def _words(self):
        """Names to listen out for (rooms, playlists) — recognition gets them as key terms."""
        r = self.room
        w = [x["name"] for x in r.lights.snapshot()]
        w += [p.get("name", "") for p in (r.spotify.snapshot().get("playlists") or [])]
        return [x for x in w if x][:40]

    # ---------------------------------------------------------------- music down while talking
    def _music_streams(self):
        """Apps playing sound — AirPlay, a browser… — never Room's own voice and tones, and never a filter's output
        (the Dolby speaker tuning shows up as a playback stream too: ducking it turned everything played through
        the Surface's speakers, Room's voice included, down to 3 % — the long-running "the voice is so quiet")."""
        out = []
        try:
            nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
            for n in nodes:
                props = ((n.get("info") or {}).get("props") or {})
                if props.get("media.class") != "Stream/Output/Audio":
                    continue
                app = (props.get("application.name") or props.get("node.name") or "").lower()
                node = (props.get("node.name") or "").lower()
                if "pw-play" in app or "pw-cat" in app or "room voice" in app:
                    continue
                if node.startswith(("effect_", "output.", "input.")) or props.get("node.virtual") or \
                        props.get("factory.name") == "filter-chain" or "filter" in node or "loopback" in node:
                    continue
                out.append(n["id"])
        except Exception:
            pass
        return out

    def _duck(self, on: bool):
        """Music down to 30 % while you talk to Room — just the music streams, never the speaker as a whole (turning
        the whole speaker down also made Room's own answer quiet). The PipeWire calls run on a worker thread, in
        order: done on the main thread they held up the screen and the words by about a second after "Alexa"."""
        if on == getattr(self, "_duck_want", False):
            return
        self._duck_want = on
        if not hasattr(self, "_duckq"):
            import queue, threading
            self._duckq = queue.Queue()
            threading.Thread(target=self._duck_worker, daemon=True).start()
        sp = self.room.spotify.snapshot()
        if on:
            spv = sp.get("volume") if sp.get("playing") and sp.get("canVolume") and not self.room.airplay.showing else None
            self._spv = spv
            if spv:
                self.room.spotify.set_volume(max(5, int(spv * 0.3)))
        else:
            spv, self._spv = getattr(self, "_spv", None), None
            if spv:
                self.room.spotify.set_volume(int(spv))
        self._duckq.put(on)

    def _duck_worker(self):
        saved = None
        while True:
            on = self._duckq.get()
            try:
                if on and saved is None:
                    saved = {}
                    for sid in self._music_streams():
                        out = subprocess.run(["wpctl", "get-volume", str(sid)], capture_output=True, text=True, timeout=2).stdout
                        try:
                            v = float(out.split()[1])
                        except Exception:
                            continue
                        saved[sid] = v
                        subprocess.run(["wpctl", "set-volume", str(sid), f"{v * 0.4:.2f}"], timeout=2)    # ≈ −24 dB: clear of your words
                elif not on and saved is not None:
                    for sid, v in saved.items():
                        subprocess.run(["wpctl", "set-volume", str(sid), f"{v:.2f}"], timeout=2)
                    saved = None
            except Exception as e:
                print(f"[room] duck: {e!r}")
                saved = None

    # ---------------------------------------------------------------- doing it
    def say(self, text: str, listen=False):
        self.reply = text
        if text:
            self._send(cmd="say", text=text, listen=listen)
        else:
            self.state = "idle"
            self._duck(False)
        self.changed.emit()

    def _finish(self, stage, line="", spoken="", card="", follow=False):
        """Show the outcome; speak it unless it was already spoken early."""
        self.stage, self.line, self.card = stage, line, card
        self.reply = spoken or line
        self._follow_next = follow
        if follow and not self._talking and self.state != "speaking":
            # the question was already spoken (it streamed out early) — open the mic now
            self._follow_next = False
            self.following = True
            self._send(cmd="listen", follow=True)
        self.changed.emit()

    def _act(self, text: str):
        self._turn += 1
        turn = self._turn
        if not text:
            # nothing heard: the phone's "miss" chime, unless it was just the open mic after an answer
            if self.following:
                self.following = False; self.stage = "idle"; self.state = "idle"; self._duck(False)
            else:
                self.chime("miss"); self.state = "idle"; self._finish("miss", "")
                QTimer.singleShot(1500, lambda: self._duck(False))
            return
        if self._pending:
            lead = {"timer_length": "set a timer for ", "alarm_time": "set an alarm for ", "reminder_text": "remind me to "}[self._pending]
            self._pending = None
            if not re.search(r"\b(timer|alarm|remind)\b", text.lower()):
                text = lead + text
        it = self._parse(text)
        # plain commands run on the Surface at once — a chime, or a short line it already has (no Claude, no waiting)
        if self._fast(text, it):
            try:
                line, _ = self._do(it)
            except Exception as e:
                line = ""
                print(f"[room] fast path: {e!r}")
            print(f"[room] on the Surface: {it.get('do')} → {line!r}", flush=True)
            if self.brain:
                self.brain.remember(text, line, did=line)
            self.following = False
            if it.get("do") in self.SPOKEN and line:
                self._finish("done", line.rstrip(".").lower(), line)
                self.say(line)
            else:
                if it.get("do") != "dismiss":
                    self.chime("done")
                self.state = "idle"
                self._finish("done" if it.get("do") != "dismiss" else "idle", (line or "done").rstrip(".").lower())
                QTimer.singleShot(1200, lambda: self._duck(False))
            return
        if self.brain:
            self.state = "thinking"; self.stage = "think"; self.changed.emit()
            spoken_early = {"t": ""}

            def on_say(sentence):
                def go():
                    if turn != self._turn or not sentence:
                        return
                    spoken_early["t"] = sentence
                    self.reply = sentence
                    self._send(cmd="say", text=sentence, listen=False)
                self._main.emit(go)

            def on_done(out):
                self._main.emit(lambda: turn == self._turn and self._deliver(text, out, spoken_early["t"], it, turn))
            self.brain.interpret(text, self.snapshot(), self.following, self.computer.ok, on_say, on_done,
                                 alt=getattr(self, "_alt", ""))
            return
        self._local(text, it)

    def _local(self, text, it):
        try:
            reply, listen = self._do(it)
        except Exception as e:
            print(f"[room] assistant: {e!r} for {it}")
            reply, listen = "Sorry, something went wrong there.", False
        self.stage, self.line, self.card = ("miss" if it.get("do") == "unknown" else "done"), reply.rstrip(".").lower(), ""
        self.say(reply, listen)

    def _parse(self, text):
        r = self.room
        rooms = [x["name"] for x in r.lights.snapshot()]
        pls = [p.get("name", "") for p in (r.spotify.snapshot().get("playlists") or [])]
        return intents.parse(text, rooms, pls)

    # what the Surface does by itself, at once (the phone's fast path, and how Alexa does it): plain commands and the
    # clock. Everything else — questions, chat, anything unusual — goes to Claude.
    QUIET = ("lights", "scene", "pause", "resume", "next", "previous", "volume")          # a chime, no words
    SPOKEN = ("timer_start", "timer_cancel", "timer_pause", "timer_resume", "timer_add", "alarm_set", "time", "date",
              "play", "dismiss")

    @staticmethod
    def _fast(text, it) -> bool:
        d = it.get("do")
        low = " " + intents.clean(text) + " "
        if len(low.split()) > 10:
            return False
        if d in ("time", "date"):
            return True
        if d == "dismiss":
            return True
        if d == "play" and not (it.get("playlist") or it.get("mood")):
            return False                    # a song or an artist by name: Claude picks the right kind of search
        if d == "alarm_set" and "h" not in it and "in" not in it:
            return False
        if re.match(r"\s*(is|are|what|how|did|does|do|can|could|will|would|why|when|which|who|should)\b", low):
            return False
        if any(w in low for w in (" not ", " don't ", " no ", " never ", " except ", " but ", " and ", " then ",
                                  " after ", " before ", " if ", " unless ")):
            return False
        if re.search(r"\bin (\d|a |an |half|the next|ten|five|twenty|thirty)", low) and d not in ("timer_start", "alarm_set"):
            return False                    # "…in 20 minutes" — something for later: Claude
        return d in Assistant.QUIET + Assistant.SPOKEN

    def _everyday_lines(self):
        lines = ["Lights off.", "Lights on.", "Okay.", "Timer cancelled.", "Timers cancelled.", "Paused.", "Resumed.",
                 "There's no timer running.", "Saved.", "Putting on something chill.", "Putting on something relaxing.",
                 "I couldn't find that on Spotify."]
        lines += [f"Timer for {dur_text(n)}, starting now." for n in (30, 60, 120, 180, 240, 300, 360, 420, 480, 600, 900,
                                                                       1200, 1500, 1800, 2700, 3600, 5400, 7200)]
        lines += [f"Added {dur_text(n)}." for n in (60, 120, 300, 600)]
        try:
            lines += [f"{x['name']} off." for x in self.room.lights.snapshot()] + [f"{x['name']} on." for x in self.room.lights.snapshot()]
        except Exception:
            pass
        return lines

    # ---------------------------------------------------------------- Claude's answer → the home
    def _deliver(self, text, out, spoken_early, it, turn):
        if out is None:
            print(f"[room] claude failed ({self.brain.last_error}) — using the built-in rules")
            self._local(text, it)
            return
        if self.following and out.get("for_me") is False:
            # the open mic heard something that wasn't for the panel — close quietly
            self.following = False; self.state = "idle"; self.stage = "idle"; self._duck(False); self.changed.emit()
            return
        actions = out.get("actions") or []

        def finished(summary):
            if turn != self._turn:
                return
            failed = "couldn't" in summary
            looked = any(a.get("kind") == "look_up" for a in actions)
            line = summary if looked else ((out.get("reply") or "") if out.get("reply") and not failed else summary).lower()
            spoken = summary if looked else ((out.get("say") or "") if out.get("say") and not failed else line)
            if self.brain:
                self.brain.remember(text, spoken, did=summary)
            asked = spoken.strip().endswith("?")
            follow = bool(out.get("follow_up", True)) and asked and self.room.cfg.get("followUp") is not False \
                and self._follow_turns < 3
            if self.following:
                self._follow_turns += 1
            card = out.get("card") if out.get("card") not in (None, "none") else ""
            stage = "miss" if not actions and not out.get("say") else "done"
            # speak now unless the same sentence already went out early
            if spoken and (looked or spoken.strip() != (spoken_early or "").strip()):
                self._send(cmd="say", text=spoken, listen=False)
            elif not spoken:
                self.state = "idle"
                if actions:
                    self.chime("done")
            self._finish(stage, line, spoken, card, follow)
            if not spoken and not follow:
                QTimer.singleShot(1500, lambda: self._duck(False))
        self.run(actions, lambda summary: self._main.emit(lambda: finished(summary)))

    def snapshot(self) -> dict:
        r, th = self.room, self.room._things
        now = dt.datetime.now()
        w = r.weather or {}
        wx = {k: w.get(k) for k in ("t", "feels", "hum", "d", "hi", "lo", "aqi", "sunrise", "sunset") if w.get(k) is not None}
        wx["next_hours"] = [f"{h['h']}:00 {h['t']}° {h['d']}{' rain ' + str(h['p']) + '%' if h.get('p', 0) >= 30 else ''}" for h in (w.get("hours") or [])[:12]]
        wx["next_days"] = [f"{d['name']} {d['hi']}°/{d['lo']}° {d['d']}{' rain ' + str(d['p']) + '%' if d.get('p', 0) >= 30 else ''}" for d in (w.get("days") or [])[:3]]
        snap = {"now": now.strftime("%A %-d %b, %-I:%M %p"), "here": r.lights.here or "", "place": "Bangalore",
                "lights": r.lights.lamps_now(), "weather": wx,
                "timers": [{"label": t["label"], "left_seconds": int(t["left"]), "paused": t["paused"]} for t in th.snapshot()["timers"]],
                "computer": self.computer.name if self.computer.ok else "not set up"}
        days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        snap["alarms"] = [{"alarm_id": a["id"], "time": f"{a['h']:02d}:{a['m']:02d}", "on": a.get("on"),
                           "repeat": ",".join(days[d] for d in a.get("days") or []) or "once"} for a in th.alarms]
        snap["reminders"] = [{"reminder_id": x["id"], "text": x["text"], "at": x["when"] or "no time"}
                             for x in th.snapshot()["reminders"] if not x["done"]][:12]
        if th.alert.get("kind") == "reminder":
            snap["reminder_showing"] = {"reminder_id": th.alert.get("id"), "text": th.alert.get("title")}
        m = r.music
        sp = r.spotify.snapshot()
        snap["music"] = {"state": "playing" if m.get("playing") else ("paused" if m.get("exists") else "idle"),
                         "track": m.get("title", ""), "artist": m.get("artist", ""), "speaker": m.get("device", ""),
                         "volume": m.get("volume"), "speakers": [d["name"] for d in sp.get("devices") or []]}
        if r.airplay.showing:
            snap["music"]["note"] = "playing from their phone over AirPlay to this panel: music and volume actions control it; to play something new, use play (Spotify)"
        snap["my_playlists"] = [{"name": p["name"], "uri": p["uri"]} for p in (sp.get("playlists") or [])][:40]
        snap["calendar"] = [f"{e['title']} — {e['when']}{(' ' + e['extra']) if e.get('extra') else ''}" for e in r.events[:5]]
        return snap

    def run(self, actions, done):
        """Carry out Claude's actions (the phone's run(steps)); done(summary) once — some steps finish later."""
        r, th = self.room, self.room._things
        parts, waiting = [], [0]
        finished = [False]

        def fin():
            if waiting[0] == 0 and not finished[0]:
                finished[0] = True
                done(" · ".join(parts))
        for a in actions:
            k = a.get("kind")
            try:
                if k == "lights":
                    ids = a.get("light_ids") or []
                    plain = a.get("brightness") is None and a.get("kelvin") is None and a.get("rgb") is None
                    if a.get("on") is False:
                        n = r.lights.set_lamps(ids, on=False)
                    else:
                        n = r.lights.set_lamps(ids, on=True, level=None if plain else a.get("brightness"),
                                               kelvin=a.get("kelvin"), rgb=a.get("rgb"))
                    if n:
                        parts.append(f"{n} light{'s' if n != 1 else ''}")
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
                    self._duck(False)
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
                            self._main.emit(fin)
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
                    h, m = (int(x) for x in a["time"].split(":")[:2])
                    dmap = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
                    th.add_alarm(h, m, [dmap[d] for d in a.get("days") or [] if d in dmap])
                    parts.append(f"alarm {h}:{m:02d}")
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
                    th.add_reminder(a["label"][0].upper() + a["label"][1:], due)
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
                elif k == "remember" and a.get("label") and self.brain:
                    self.brain.memory.add(a["label"]); parts.append("noted")
                elif k == "forget" and a.get("label") and self.brain:
                    n = self.brain.memory.forget(a["label"]); parts.append("forgotten" if n else "nothing to forget")
                elif k == "look_up" and a.get("question") and self.brain:
                    waiting[0] += 1

                    def ans(x):
                        parts.append(x or "Sorry, I couldn't look that up just now.")
                        waiting[0] -= 1
                        self._main.emit(fin)
                    self.brain.look_up(a["question"], ans)
                elif k == "computer":
                    if not self.computer.ok:
                        parts.append("couldn't — the computer isn't set up")
                    else:
                        waiting[0] += 1
                        cmd = a.get("command", "")

                        def pc(why, cmd=cmd):
                            parts.append(f"couldn't reach the computer — {why}" if why else
                                         {"sleep": "computer asleep", "lock": "computer locked", "screen_off": "computer screen off",
                                          "shutdown": "computer shutting down", "restart": "computer restarting"}.get(cmd, cmd))
                            waiting[0] -= 1
                            self._main.emit(fin)
                        self.computer.send(cmd, pc)
            except Exception as e:
                print(f"[room] action {k}: {e!r}")
        fin()

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
            if it.get("mood"):
                mood = it["mood"]

                def rep(name, why):
                    if not name:
                        self._main.emit(lambda: self.say("I couldn't find that on Spotify."))
                    else:
                        print(f"[room] playing {name!r} for {mood!r}", flush=True)
                r.spotify.play_search(mood, "playlist", None, rep)
                return f"Putting on {it.get('phrase') or 'something ' + mood}.", False
            return f"I couldn't find {it.get('query')} in your playlists.", False

        if d == "ask":
            q = {"timer_length": "For how long?", "alarm_time": "For what time?", "reminder_text": "What should I remind you about?"}
            self._pending = it["what"]
            return q.get(it["what"], "Sorry?"), True
        return "Sorry, I didn't get that.", False
