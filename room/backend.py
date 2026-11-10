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
from .mic import RoomMic
from .voice import VoiceLink
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
    settingsChanged = Signal()
    asleepChanged = Signal()
    voiceChanged = Signal()
    volumeShown = Signal(int, str)       # the volume buttons were pressed: show the level (0–100) and of what

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
        self.voicelink = VoiceLink(self)
        self.voicelink.changed.connect(self.voiceChanged)
        self.voicelink.changed.connect(lambda: self.voice.get("state") in ("listening", "thinking", "speaking")
                                       and self.sleep.wake("the assistant"))
        self.mic = RoomMic(self) if cfg.get("roomMic") is not False else None
        if self.mic:
            self.mic.level.connect(self._sound_level)
            self.mic.heard.connect(self.sleep.hear)

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
        from .output import Output
        self.output = Output(self.cfg); self.output.start()
        self.airplay.changed.connect(self.output.poke)
        # One thing plays at a time, as on any speaker: AirPlay starting pauses the Surface's own Spotify, and the
        # Surface's Spotify starting pauses AirPlay (the phone pauses too). Both used to play over each other, with
        # the screen showing only the newer one.
        self._spot_here = False
        self._ap_playing = False
        def spot_here():
            p = self.spotify.player or {}
            return bool(p.get("is_playing")) and (p.get("device") or {}).get("name", "").lower() == self.spotify.home
        def spot():
            here = spot_here()
            if here and not self._spot_here:
                self.output.poke()          # route it now, not at the next 20 s look
                if self.airplay.playing:
                    print("[room] Spotify started here — pausing AirPlay", flush=True)
                    self.airplay.pause()
            self._spot_here = here
        def airplay():
            if self.airplay.playing and not self._ap_playing and spot_here():
                print("[room] AirPlay started — pausing the Surface's Spotify", flush=True)
                self.spotify.pause()
                self._spot_here = False
            self._ap_playing = self.airplay.playing
        self.spotify.changed.connect(spot)
        self.airplay.changed.connect(airplay)
        self.bt.connectedChanged.connect(self.output.poke)
        self._read_out_volume()
        self._vol_timer = QTimer(self); self._vol_timer.timeout.connect(self._read_out_volume); self._vol_timer.start(10000)
        if self.mic:
            self.mic.start()
        self.voicelink.start()

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
        return {"homePlayingSec": int(c.get("homePlayingSec", 30)), "homeIdleSec": int(c.get("homeIdleSec", 300)),
                "musicSec": int(c.get("musicSec", 300)),
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

    @Property(bool, constant=True)
    def micOn(self):
        """Whether the room's loudness is measured (it drives the standby ripple and the music beat)."""
        return self.mic is not None and not self.demo

    def _sound_level(self, rms: float):
        import math
        db = 20 * math.log10(max(rms, 1e-5))
        v = max(0.0, min(1.0, (db + 60) / 45))         # quiet room ≈ 0, talking ≈ 0.5, music ≈ 0.8
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
        """'' when nothing needs the screen, else why (it's logged)."""
        if self.music.get("playing"):
            return "music playing"
        if self.alert and self.alert.get("kind"):
            return "an alarm or timer is showing"
        if self.voice.get("state") in ("listening", "thinking", "speaking"):
            return "the assistant is busy"
        return ""

    # ---------------------------------------------------------------- the voice assistant (its own program)
    @Property("QVariantMap", notify=voiceChanged)
    def voice(self):
        """For the screen: state (off · idle · listening · thinking · speaking), stage, heard, reply, line, card."""
        if self.demo and os.environ.get("ROOM_DEMO_VOICE"):          # screens to check: listen · think · speak · miss
            st = os.environ["ROOM_DEMO_VOICE"]
            q = "What's the weather going to be in Bali tomorrow?"
            return {"listen": {"state": "listening", "stage": "wake", "heard": ""},
                    "think": {"state": "thinking", "stage": "think", "heard": q},
                    "speak": {"state": "speaking", "stage": "done", "heard": q,
                              "reply": "Bali's looking warm tomorrow, around thirty one degrees, with a good chance of a "
                                       "thunderstorm in the afternoon.", "line": "31° · storms after 2"},
                    "miss": {"state": "idle", "stage": "miss", "heard": ""}}.get(st, {})
        return dict(self.voicelink.st)

    @Slot()
    def listen(self):
        self.voicelink.listen()

    @Slot()
    def cancelVoice(self):
        self.voicelink.cancel()

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
        import subprocess, time as _t
        m = self.music
        recent = _t.monotonic() - getattr(self, "_vol_at", 0) < 2.5     # pressed again quickly: carry on from there
        self._vol_at = _t.monotonic()
        if m.get("exists") and m.get("playing"):
            base = self._vol_last if recent and getattr(self, "_vol_what", "") == "music" else int(m.get("volume") or 50)
            v = max(0, min(100, base + delta))
            self.setVolume(v)
            what = "music"
        else:
            if recent and getattr(self, "_vol_what", "") == "speaker":
                base = self._vol_last
            else:
                try:
                    out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True, timeout=2).stdout
                    base = round(float(out.split()[1]) * 100)
                except Exception:
                    base = 50
            v = max(0, min(100, base + delta))
            subprocess.Popen(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v / 100:.2f}"])
            what = "speaker"
        self._vol_last, self._vol_what = v, what
        self.volumeShown.emit(v, what)

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
