"""The bridge between the services and the QML screens: one object, exposed to QML as `room`."""
import os
import time

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from .airplay import AirPlay
from .bluetooth import Bluetooth
from .display import Display
from .calendar import Calendar
from .lights import Lights
from .screen import Screen
from .spotify import Spotify
from .things import Things
from .assistant import Assistant
from .weather import Weather
from . import demo


class Room(QObject):
    weatherChanged = Signal()
    eventsChanged = Signal()
    roomsChanged = Signal()
    musicChanged = Signal()
    levelChanged = Signal()
    statusChanged = Signal()
    thingsChanged = Signal()
    alertChanged = Signal()
    voiceChanged = Signal()
    settingsChanged = Signal()
    asleepChanged = Signal()

    def __init__(self, cfg: dict):
        super().__init__()
        self.cfg = cfg
        self.demo = os.environ.get("ROOM_DEMO") == "1"
        loc = cfg.get("location") or {}
        self.wx = Weather(loc.get("lat", 12.9716), loc.get("lon", 77.5946))
        self.calendar = Calendar(cfg.get("icalURL"))
        self.lights = Lights(cfg.get("rooms", []), cfg.get("here", ""))
        self.spotify = Spotify(cfg.get("spotify"))
        self.airplay = AirPlay()
        self.airplay.changed.connect(self.musicChanged)
        # what played before, whatever the source — the left side of the cover flow
        self._history: list[dict] = []
        self._settle = QTimer(self); self._settle.setSingleShot(True); self._settle.setInterval(1500)
        self._settle.timeout.connect(self._settled)
        self.musicChanged.connect(self._note_track)
        self._out_volume = None   # the Surface's own output volume (used for AirPlay)
        self.wx.changed.connect(self.weatherChanged)
        self.calendar.changed.connect(self.eventsChanged)
        self.lights.changed.connect(self.roomsChanged)
        self.spotify.changed.connect(self.musicChanged)
        self.screen = Screen(cfg)
        self.screen.statusChanged.connect(self.statusChanged)
        self._level = 0.0
        self._mic = None
        self._things = Things(cfg, self.lights)
        self._things.changed.connect(self.thingsChanged)
        self._things.alertChanged.connect(self.alertChanged)
        if self.demo:
            demo.fill_things(self._things)
        self._display = Display()
        self._display.changed.connect(self.settingsChanged)
        from .sleep import Sleep
        self.sleep = Sleep(self._display, self._needs_screen)
        self.sleep.changed.connect(self.asleepChanged)
        self.alertChanged.connect(lambda: self.alert and self.alert.get("kind") and self.sleep.wake("alert"))
        self.bt = Bluetooth()
        self.bt.changed.connect(self.settingsChanged)
        self._kiosk = False
        self._desktop_note = ""
        self.assistant = Assistant(self)
        self.assistant.changed.connect(self.voiceChanged)
        self.assistant.levelChanged.connect(self._voice_level)

    def start(self):
        self._things.start()
        if self.demo:
            self.bt.devices = demo.BLUETOOTH; self.settingsChanged.emit()
            return
        self._display.start()
        self.bt.refresh()
        self._kiosk = self._session() == "room-panel"
        self.wx.start()
        self.screen.start()
        self.calendar.start()
        self.lights.start()
        self.spotify.start()
        self.airplay.start()
        self.assistant.start()
        from .output import Output
        self.output = Output(self.cfg); self.output.start()
        self.airplay.changed.connect(self.output.poke)
        # the Surface's own Spotify speaker starting to play: route it now, not at the next 20 s look
        self._spot_here = False
        def spot():
            p = self.spotify.player or {}
            here = bool(p.get("is_playing")) and (p.get("device") or {}).get("name", "").lower() == self.spotify.home
            if here and not self._spot_here:
                self.output.poke()
            self._spot_here = here
        self.spotify.changed.connect(spot)
        self.bt.connectedChanged.connect(self.output.poke)
        self._read_out_volume()
        self._vol_timer = QTimer(self); self._vol_timer.timeout.connect(self._read_out_volume); self._vol_timer.start(10000)
        # the room-sound ripple on standby comes from the voice process's mic when voice is on; the Qt mic is only a
        # fallback, off unless asked for (opening it crashed in testing)
        if not self.assistant.available() and (os.environ.get("ROOM_MIC") == "1" or self.cfg.get("standbyMic") is True):
            self._start_mic()

    # ---------------------------------------------------------------- what the screens read
    @Property("QVariantMap", notify=weatherChanged)
    def weather(self):
        if self.demo:
            return {"ok": False} if os.environ.get("ROOM_DEMO_EMPTY") == "1" else demo.WEATHER
        return self.wx.snapshot()

    @Property("QVariantList", notify=eventsChanged)
    def events(self):
        return demo.EVENTS if self.demo else self.calendar.upcoming(3, self.clock24)

    @Property("QVariantList", notify=roomsChanged)
    def rooms(self):
        if self.demo:
            return [dict(r, on=0, level=0) for r in demo.ROOMS] if os.environ.get("ROOM_DEMO_EMPTY") == "1" else demo.ROOMS
        return self.lights.snapshot()

    @Property("QVariantMap", notify=musicChanged)
    def music(self):
        if self.demo:
            m = dict(demo.MUSIC); m["at"] = time.time() - 4; m["canSeek"] = True
            m["playing"] = os.environ.get("ROOM_SCREEN") != "standby"; m["exists"] = m["playing"]
            if os.environ.get("ROOM_DEMO_ART"):          # a cover to check layouts with
                if not getattr(self, "_demo_art", None):
                    from PySide6.QtGui import QImage
                    from . import art
                    img = QImage(os.environ["ROOM_DEMO_ART"])
                    w, rgb = art.wash(img)
                    self._demo_art = ("file://" + os.path.abspath(os.environ["ROOM_DEMO_ART"]), w, rgb)
                m["art"], m["wash"], m["rgb"] = self._demo_art
            if os.environ.get("ROOM_DEMO_EMPTY") == "1":
                m["nextUp"] = []
            if os.environ.get("ROOM_DEMO_IDLE") == "1":       # nothing playing (the home card's shortcuts)
                m["exists"] = m["playing"] = False
                m["last"] = {"name": "Late Night Drives", "art": "", "uri": "spotify:playlist:x", "kind": "playlist"}
            return m
        # whatever's actually playing: AirPlay while a phone or Mac is sending to Room, otherwise Spotify
        m = self.airplay.snapshot() if self.airplay.showing else self.spotify.snapshot()
        if m.get("source") == "airplay":
            # AirPlay never says what's next. But if it's Spotify on the phone being AirPlayed here, Spotify's own
            # account still knows the queue — borrow it whenever the two agree on the song.
            sp = self.spotify.snapshot()
            same = self._same_song(m, sp)
            if same:
                m["nextUp"] = sp.get("nextUp", [])
                m["recent"] = sp.get("recent", [])
                m["context"] = sp.get("context", "")
                m["canSeek"] = True          # AirPlay can't seek, but Spotify on the phone can — seek through it
                # AirPlay 2 often sends no progress at all; Spotify always knows where the song is
                if sp.get("duration"):
                    m["duration"], m["position"], m["at"], m["playing"] = sp["duration"], sp["position"], sp["at"], sp["playing"]
            key = (m.get("title"), sp.get("title"), same)
            if key != getattr(self, "_match_said", None):
                self._match_said = key
                print(f"[room] airplay {m.get('title')!r} · spotify {sp.get('title')!r} ({sp.get('device') or 'no device'})"
                      f" → {'same song: queue, progress and seek from Spotify' if same else 'not the same song'}", flush=True)
        m.setdefault("nextUp", [])
        m.setdefault("canSeek", m.get("source") != "airplay")
        if m.get("source") == "airplay":
            # AirPlay plays through the Surface itself, so the slider is the Surface's volume
            # the phone's own AirPlay volume (it reports every change); the panel's slider sets the Surface's output
            m["canVolume"] = True
            m["volume"] = self.airplay.volume
            m["playlists"] = self.spotify.playlists
        return m

    @staticmethod
    def _same_song(a: dict, sp: dict) -> bool:
        """Is AirPlay playing the song Spotify's account is on? Titles differ in small ways between the two ("Song -
        Remastered", "(feat. X)", censored words, punctuation), so compare the cleaned-up words, and the artist."""
        import re
        if not sp.get("exists") or not a.get("title"):
            return False
        def words(t):
            t = re.sub(r"\s*[\(\[].*?[\)\]]", "", (t or "").lower())        # (feat …), [Remastered]
            t = re.split(r"\s+-\s+", t)[0]                                   # "Song - Remastered 2011"
            return re.sub(r"[^a-z0-9]+", " ", t).split()
        x, y = words(a["title"]), words(sp.get("title"))
        if not x or not y:
            return False
        n = min(len(x), len(y))
        title_ok = x == y or x[:n] == y[:n] or (n >= 2 and sum(w in y for w in x) >= len(x) - 1)
        if not title_ok:
            return False
        aa, sa = set(words(a.get("artist"))), set(words(sp.get("artist")))
        return not aa or not sa or bool(aa & sa)

    # ---- the Surface's own output volume (PipeWire), for AirPlay
    def _read_out_volume(self):
        import subprocess
        try:
            out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True, timeout=2).stdout
            v = int(round(float(out.split()[1]) * 100))   # "Volume: 0.45"
            if v != self._out_volume:
                self._out_volume = v
                self.musicChanged.emit()
        except Exception:
            pass

    def _note_track(self):
        # metadata arrives a field at a time (title, then artist, then cover), so wait for it to settle
        # (Spotify reports every 1.5 s, so only a change of song restarts the wait)
        if self.demo:
            return
        m = self.airplay.snapshot() if self.airplay.showing else self.spotify.snapshot()
        key = f"{m.get('title')}|{m.get('artist')}|{m.get('art')}"
        if key != getattr(self, "_seen_key", None):
            self._seen_key = key
            self._settle.start()

    def _settled(self):
        m = self.airplay.snapshot() if self.airplay.showing else self.spotify.snapshot()
        if not m.get("exists"):
            return
        now = {"title": m["title"], "artist": m["artist"], "art": m["art"], "uri": ""}
        cur = getattr(self, "_now", None)
        if cur and cur["title"] != now["title"]:
            self._history = ([cur] + [h for h in self._history if h["title"] != cur["title"]])[:3]
            self.musicChanged.emit()
        self._now = now

    @Property(bool, constant=True)
    def clock24(self):
        return bool(self.cfg.get("clock24"))

    @Property(int, constant=True)
    def standbySec(self):
        return int(self.cfg.get("standbySec", 15))

    @Property(str, constant=True)
    def here(self):
        return self.cfg.get("here", "")

    @Property(str, notify=statusChanged)
    def status(self):
        return "⚡ Cool" if self.demo else self.screen.status

    @Property("QVariantMap", constant=True)
    def timing(self):
        """The standby rules' settings (seconds and hours), straight from config.json."""
        c = self.cfg
        day = int(c.get("standbySec", 15))
        return {"standbySec": day, "nightStandbySec": int(c.get("nightStandbySec", day)),
                "idleReturnSec": int(c.get("idleReturnSec", 60)),
                "menuStandbySec": int(c.get("menuStandbySec", 180)),
                "refreshAt": c.get("refreshAt", "04:00") or "",
                "nightStart": int(c.get("nightStart", 23)), "nightEnd": int(c.get("nightEnd", 7))}

    input_at = 0.0           # the last touch, click, scroll, mouse move or key (set by the app's event filter)

    @Slot(result=float)
    def lastInput(self):
        return self.input_at

    @Slot(bool, bool)
    def setScreenState(self, standby, dim):
        """Standby on/off and night-dim → screen brightness, and Spotify polls less while nobody's looking."""
        self.screen.set_state(standby, dim)
        self.sleep.set_standby(standby)
        self._display.set_dim(standby and dim)
        self.spotify.relaxed = standby

    @Property(bool, notify=voiceChanged)
    def micOn(self):
        """Whether the room's sound is being listened to (it drives the standby ripple and the music beat)."""
        return self.assistant.state != "off" or os.environ.get("ROOM_MIC") == "1"

    @Property("QVariantMap", notify=voiceChanged)
    def voice(self):
        """For the Alexa screen: state (off · idle · listening · thinking · speaking), what was heard, the answer."""
        a = self.assistant
        if self.demo and os.environ.get("ROOM_DEMO_VOICE"):
            # stages to check the screen with: wake · heard · think · done · weather · timer · music · miss · off
            st = os.environ["ROOM_DEMO_VOICE"]
            q = {"weather": "What's the weather like this evening", "timer": "Set a timer for ten minutes",
                 "music": "Play something mellow", "miss": ""}.get(st, "Turn the living room to forty percent")
            d = {"state": "listening", "stage": st, "heard": q, "reply": "", "line": "", "card": "", "error": "",
                 "on": st != "off", "following": False}
            if st == "wake":
                d["heard"] = ""
            elif st == "heard":
                d["heard"] = "Turn the living room"
            elif st == "think":
                d["state"] = "thinking"
            elif st == "done":
                d.update(state="idle", line="living room · 40%")
            elif st == "weather":
                d.update(state="speaking", stage="done", card="weather",
                         reply="It's 24 and clear now, cooling to about 19 by ten. No rain tonight.",
                         line="24° and clear · 19° by ten")
            elif st == "timer":
                d.update(state="speaking", stage="done", card="timer", reply="Ten minutes, starting now.", line="timer · 10 min")
            elif st == "music":
                d.update(state="speaking", stage="done", card="music", reply="Here's something mellow.", line="playing late night jazz")
            elif st == "miss":
                d.update(state="idle", stage="miss")
            elif st == "off":
                d.update(state="off", stage="idle", heard="", error="Voice isn't set up yet")
            return d
        return {"state": a.state, "stage": a.stage, "heard": a.heard, "reply": a.reply, "line": a.line, "card": a.card,
                "error": a.error, "on": a.state != "off", "following": a.following}

    def _voice_level(self):
        import math
        self.sleep.hear(self.assistant.level)
        if self.assistant.state in ("listening", "thinking", "speaking"):
            self.sleep.wake("Alexa")
        db = 20 * math.log10(max(self.assistant.level, 1e-5))
        v = max(0.0, min(1.0, (db + 60) / 45))
        self._level += (v - self._level) * (0.5 if v > self._level else 0.12)
        self.levelChanged.emit()

    @Property(float, notify=levelChanged)
    def level(self):
        """Room loudness, 0…1 — the standby dots ripple with it."""
        return self._level


    # ---------------------------------------------------------------- alarms, timers, reminders
    @Property("QVariantMap", notify=thingsChanged)
    def things(self):
        return self._things.snapshot()

    @Property("QVariantMap", notify=alertChanged)
    def alert(self):
        return self._things.alert

    @Slot(int, int, "QVariantList")
    def addAlarm(self, h, m, days): self._things.add_alarm(h, m, [int(d) for d in days])

    @Slot(str, int, int, "QVariantList")
    def setAlarm(self, aid, h, m, days): self._things.set_alarm(aid, h, m, [int(d) for d in days])

    @Slot(str)
    def toggleAlarm(self, aid): self._things.toggle_alarm(aid)

    @Slot(str)
    def deleteAlarm(self, aid): self._things.delete_alarm(aid)

    @Slot(int, str)
    def startTimer(self, sec, label): self._things.start_timer(sec, label)

    @Slot(str, int)
    def addTime(self, tid, sec): self._things.add_time(tid, sec)

    @Slot(str)
    def pauseTimer(self, tid): self._things.pause_timer(tid)

    @Slot(str)
    def cancelTimer(self, tid): self._things.cancel_timer(tid)

    @Slot(str, float)
    def addReminder(self, text, due): self._things.add_reminder(text, due)

    @Slot(str)
    def toggleReminder(self, rid): self._things.toggle_reminder(rid)

    @Slot(str)
    def deleteReminder(self, rid): self._things.delete_reminder(rid)

    @Slot()
    def stopAlert(self): self._things.stop_alert()

    @Slot()
    def snoozeAlert(self): self._things.snooze_alert()

    # ---------------------------------------------------------------- lamps and scenes
    @Slot(str)
    def toggleLamp(self, mac): self.lights.toggle_lamp(mac)

    ROOM_SCENES = {"Relax": (40, 2400), "Read": (90, 4000), "Movie": (15, 2200), "Night": (8, 2200)}

    @Slot(str, str)
    def roomScene(self, name, scene):
        lv, k = self.ROOM_SCENES.get(scene, (60, 2700))
        self.lights.set_room(name, on=True, level=lv, kelvin=k)

    @Slot(str)
    def houseScene(self, scene):
        """Evening: every room warm at half. Movie: the panel's room very low, the rest off. Night / All off."""
        if scene == "Evening":
            self.lights.set_room(None, on=True, level=50, kelvin=2500)
        elif scene == "Movie":
            for r in self.lights.rooms:
                if r.get("name") == self.lights.here:
                    self.lights.set_room(r["name"], on=True, level=12, kelvin=2200)
                else:
                    self.lights.set_room(r["name"], on=False)
        elif scene == "Night":
            self.night()
        else:
            self.allOff()

    # ---------------------------------------------------------------- what the screens do
    @Slot(str)
    def toggleRoom(self, name):
        self.lights.toggle_room(name)

    @Slot(str, int)
    def setRoomLevel(self, name, level):
        self.lights.set_room(name, level=level)

    @Slot(str, int)
    def setRoomKelvin(self, name, k):
        self.lights.set_room(name, kelvin=k)

    @Slot(str, int, int, int)
    def setRoomColour(self, name, r, g, b):
        self.lights.set_room(name, rgb=[r, g, b])

    @Slot()
    def allOff(self):
        self.lights.set_room(None, on=False)

    @Slot()
    def dimAll(self):
        self.lights.dim_all()

    @Slot()
    def night(self):
        """Everything off except a low candle glow in the room the panel is in."""
        for r in self.lights.rooms:
            if r.get("name") == self.lights.here:
                self.lights.set_room(r["name"], level=10, kelvin=2200)
            else:
                self.lights.set_room(r["name"], on=False)

    @Slot()
    def playLiked(self):
        self.spotify.play_liked()

    @Slot()
    def playLast(self):
        self.spotify.play_last()

    @Slot()
    def playPause(self):
        (self.airplay if self.airplay.showing else self.spotify).play_pause()

    @Slot()
    def next(self):
        (self.airplay if self.airplay.showing else self.spotify).next()

    @Slot()
    def previous(self):
        (self.airplay if self.airplay.showing else self.spotify).previous()

    @Slot(int)
    def setVolume(self, v):
        if self.airplay.showing:
            import subprocess
            v = max(0, min(100, int(v)))
            self._out_volume = v
            self.airplay.volume = v
            subprocess.Popen(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v / 100:.2f}"])
            self.musicChanged.emit()
        else:
            self.spotify.set_volume(v)

    # ---------------------------------------------------------------- screen off / on, the Surface's buttons
    def _needs_screen(self):
        m = self.music
        return bool(m.get("playing")) or bool(self.alert and self.alert.get("kind")) or \
            self.assistant.state in ("listening", "thinking", "speaking")

    @Property(bool, notify=asleepChanged)
    def asleep(self):
        return self.sleep.asleep

    @Slot()
    def wakeScreen(self):
        self.sleep.touched()

    def power_button(self):
        self.sleep.power_button()

    def volume_step(self, delta: int):
        """The Surface's volume buttons: the music's volume while something's playing, else the speaker's."""
        m = self.music
        if m.get("exists") and m.get("playing"):
            self.setVolume(max(0, min(100, int(m.get("volume") or 50) + delta)))
        else:
            import subprocess
            subprocess.Popen(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@",
                              f"{abs(delta)}%{'+' if delta > 0 else '-'}"])

    @Slot()
    def shutDown(self):
        import subprocess
        print("[room] shutting down (Settings)", flush=True)
        subprocess.Popen(["systemctl", "poweroff"])

    @Slot()
    def toggleLiked(self):
        self.spotify.toggle_liked()

    @Slot(str)
    def transfer(self, device_id):
        self.spotify.transfer(device_id)

    @Slot(str)
    def playUri(self, uri):
        if uri == "liked":
            self.spotify.play_liked()
        else:
            self.spotify.play_uri(uri)


    @Slot()
    def refreshDevices(self):
        self.spotify.refresh_devices()

    @Slot(float)
    def seek(self, s):
        """Spotify seeks (also when it's Spotify on the phone being AirPlayed here); AirPlay itself has no seek."""
        if self.music.get("canSeek"):
            self.spotify.seek(s)
            if self.airplay.showing:          # show the new place straight away; the phone confirms it shortly
                self.airplay.position, self.airplay.at = float(s), time.time()
                self.musicChanged.emit()

    @Slot()
    def listen(self):
        self.assistant.listen()

    # ---------------------------------------------------------------- Settings: screen, Bluetooth, the desktop
    @Property("QVariantMap", notify=settingsChanged)
    def display(self):
        if self.demo:
            return {"auto": True, "level": 0.38, "sensor": True, "canSet": True, "lux": 40}
        return self._display.snapshot()

    @Slot(bool)
    def setAutoBrightness(self, on): self._display.set_auto(on)

    @Slot(float)
    def setBrightness(self, v): self._display.set_level(v)

    @Property("QVariantMap", notify=settingsChanged)
    def bluetooth(self):
        return self.bt.snapshot()

    @Slot()
    def btSearch(self):
        if not self.demo:
            self.bt.search()

    @Slot()
    def btStop(self):
        if not self.demo:
            self.bt.stop_search()

    @Slot(str)
    def btPair(self, mac): self.bt.pair(mac)

    @Slot(str)
    def btConnect(self, mac): self.bt.connect(mac)

    @Slot(str)
    def btDisconnect(self, mac): self.bt.disconnect(mac)

    @Slot(str)
    def btForget(self, mac): self.bt.forget(mac)

    @Property("QVariantMap", notify=statusChanged)
    def battery(self):
        """{pct, charging} — shown small in Settings."""
        if self.demo:
            return {"pct": 82, "charging": True}
        return self.screen.battery

    @Property(bool, notify=settingsChanged)
    def kiosk(self):
        """Started as just the panel (room-kiosk on), not inside GNOME."""
        return self._kiosk or self.demo

    @Property(str, notify=settingsChanged)
    def desktopNote(self):
        return self._desktop_note

    @staticmethod
    def _session():
        import subprocess
        try:
            out = subprocess.run(["busctl", "get-property", "org.freedesktop.Accounts",
                                  f"/org/freedesktop/Accounts/User{os.getuid()}", "org.freedesktop.Accounts.User",
                                  "Session"], capture_output=True, text=True, timeout=3).stdout
            return out.split('"')[1] if '"' in out else ""
        except Exception:
            return ""

    @Slot()
    def switchToDesktop(self):
        """Next start into GNOME, and restart now."""
        import subprocess
        r = subprocess.run(["busctl", "call", "org.freedesktop.Accounts", f"/org/freedesktop/Accounts/User{os.getuid()}",
                            "org.freedesktop.Accounts.User", "SetSession", "s", "gnome"], capture_output=True, text=True, timeout=10)
        if r.returncode != 0 or self._session() != "gnome":
            self._desktop_note = "Couldn't switch here — use Ctrl+Alt+F3 and run room-kiosk off"
            print(f"[room] switch to desktop: {r.stderr.strip()}")
            self.settingsChanged.emit()
            return
        subprocess.Popen(["systemctl", "reboot"])

    @Slot()
    def cancelVoice(self):
        self.assistant.cancel()

    # ---------------------------------------------------------------- room sound for the standby ripple
    def _start_mic(self):
        try:
            from PySide6.QtMultimedia import QAudioFormat, QAudioSource, QMediaDevices
        except Exception:
            return
        dev = QMediaDevices.defaultAudioInput()
        if dev.isNull():
            return
        fmt = QAudioFormat()
        fmt.setSampleRate(16000); fmt.setChannelCount(1); fmt.setSampleFormat(QAudioFormat.SampleFormat.Int16)
        self._mic = QAudioSource(dev, fmt, self)
        self._mic_io = self._mic.start()
        if not self._mic_io:
            return
        self._mic_io.readyRead.connect(self._read_mic)

    def _read_mic(self):
        import array, math
        raw = bytes(self._mic_io.readAll().data())
        if len(raw) < 64:
            return
        a = array.array("h", raw[: len(raw) // 2 * 2])
        rms = math.sqrt(sum(x * x for x in a[::4]) / max(1, len(a) // 4)) / 32768
        db = 20 * math.log10(max(rms, 1e-5))          # −100 … 0
        v = max(0.0, min(1.0, (db + 60) / 45))         # quiet room ≈ 0, talking ≈ 0.5, music ≈ 0.8
        self._level += (v - self._level) * (0.5 if v > self._level else 0.12)
        self.levelChanged.emit()
