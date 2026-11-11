"""The bridge between the services and the QML screens: one object, exposed to QML as `room`."""
import os
import time

from PySide6.QtCore import Property, QObject, Qt, QTimer, Signal, Slot

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


# (checks) a question and Room's answer for each card the assistant's answers can show
DEMO_ASK = {
    "weather": ("What's it like outside?", "It's twenty seven and partly cloudy right now, with rain likely around four."),
    "forecast": ("What's the weather tomorrow?", "Tomorrow's overcast, twenty nine at its warmest, and rain is likely in the afternoon."),
    "air": ("How's the air today?", "It's moderate today, about eighty five. Fine for a walk, maybe not a run."),
    "timer": ("Set a twelve minute timer for pasta", "Pasta timer, twelve minutes. Starting now."),
    "music": ("Play something calm", "Here's Fidelio, by ansh."),
    "schedule": ("What's on today?", "Dinner at ten tonight. Then the team standup on Tuesday at ten thirty."),
    "alarm": ("Wake me up at seven", "Done. Your alarm's set for seven tomorrow morning."),
    "lights": ("Dim the living room to thirty", "Living room's at thirty now."),
    "reminder": ("Remind me to water the plants at six", "Okay. I'll remind you to water the plants at six this evening."),
    "none": ("Who made Fidelio?", "Fidelio is by ansh. It's from Late Night, the playlist that's on right now. "
                                  "Want me to play more like it?"),
}


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
    browserChanged = Signal()
    _sinkFound = Signal()                # (from the speaker lookup's thread)
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
        self._out_volume = None   # the volume of the speaker the music plays on (the slider, while it plays on Room)
        self._sink = "@DEFAULT_AUDIO_SINK@"   # that speaker: a Bluetooth one (its PipeWire id) or the Surface (the default)
        # volume changes reach the speaker at most ~8 a second (the latest one wins): sliding the phone's volume sends
        # a burst of steps — 8 in 4 s, the pattern that once tipped PipeWire over — and each was its own wpctl
        self._vol_want, self._vol_applied = None, 0.0
        # the phone's AirPlay volume, relative to where the speaker was when the session started: (phone, speaker).
        # The phone remembers its own AirPlay level for Room and announces it when a session starts — applied as is,
        # Spotify on the Xiaomi at 15 jumped to 68 the moment AirPlay took over. Now the speaker stays put and the
        # phone's slider moves it proportionally from there (down to 0, up to 100). Room's own slider/buttons re-set it.
        self._pv_anchor, self._pv_last = None, None
        # how far each step of the phone's volume moves the speaker: the iPhone's buttons step ~6 of 100, which at
        # a low volume was a big jump (12 → 19 on one click); half by default ("airplayVolumeStep" in config.json)
        self._pv_step = max(0.1, min(1.0, float(self.cfg.get("airplayVolumeStep", 0.5))))
        self._vol_apply = QTimer(self); self._vol_apply.setSingleShot(True); self._vol_apply.timeout.connect(self._apply_sink)
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
        self._desktop = False
        self._desktop_note = ""
        self._browser = None                 # the Firefox Room opened (Settings → Web browser), while it's open
        self._browser_check = QTimer(self); self._browser_check.timeout.connect(self._browser_closed)
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
        # the panel session says so itself (kiosk.sh); the login manager's note is the fallback
        self._kiosk = os.environ.get("XDG_CURRENT_DESKTOP") == "Room" or self._session() == "room-panel"
        import shutil
        self._desktop = shutil.which("gnome-session") is not None     # GNOME still installed (scripts/slim.py removes it)
        self.wx.start()
        self.screen.start()
        self.calendar.start()
        self.lights.start()
        self.spotify.start()
        self.airplay.start()
        from .output import Output
        self.output = Output(self.cfg)
        self.output.on_airplay_audio = lambda: setattr(self.airplay, "audio_at", time.time())
        self.output.start()
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
                self._spotify_full()
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
        # the phone's AirPlay volume moves the speaker (and the slider) too, as before; the slider still sets the
        # speaker directly (AirPlay can't move the phone's volume back)
        self.airplay.volumeSet.connect(self._phone_volume)
        self.airplay.changed.connect(self._airplay_session)
        self.bt.connectedChanged.connect(self.output.poke)
        # the volume slider works on the speaker the music is on: a Bluetooth speaker when one's connected, otherwise
        # the Surface's own. Looked up off the screen's thread (pw-dump is slow), at start, when a
        # speaker connects or goes (its sink appears a moment after), and every minute in case.
        self._sinkFound.connect(self._sink_changed, Qt.ConnectionType.QueuedConnection)
        self._find_sink()
        # (a Bluetooth speaker's sound output shows up a few seconds after it connects — sometimes many — so look a few
        # times; and whenever AirPlay starts or changes, and every 15 s in case: it took up to a minute before, and
        # the phone's volume went to the Surface meanwhile)
        self.bt.connectedChanged.connect(lambda *_: [QTimer.singleShot(ms, self._find_sink) for ms in (1500, 5000, 10000, 20000)])
        self.airplay.changed.connect(self._find_sink_soon)
        self._sink_timer = QTimer(self); self._sink_timer.timeout.connect(self._find_sink); self._sink_timer.start(15000)
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
                    self._demo_art = ("file://" + os.path.abspath(os.environ["ROOM_DEMO_ART"]), w, rgb, art.field(img))
                m["art"], m["wash"], m["rgb"], m["field"] = self._demo_art
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
        m["hereDevice"] = (self.spotify.home or "").lower()      # this panel's own Spotify Connect name (Play on)
        if m.get("source") == "airplay":
            m["playlists"] = self.spotify.playlists
        if self._plays_here():
            # playing on Room (AirPlay, or Room's own Spotify): the slider is the speaker it's coming out of
            m["canVolume"] = self._out_volume is not None
            m["volume"] = self._out_volume if self._out_volume is not None else 0
        else:
            # Spotify on another device: its volume is that device's, set from the Spotify app
            m["canVolume"] = False
        return m

    def _plays_here(self) -> bool:
        if self.airplay.showing:
            return True
        p = self.spotify.player or {}
        return (p.get("device") or {}).get("name", "").lower() == self.spotify.home

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

    # ---- the volume of the speaker the music comes out of (PipeWire)
    def _find_sink(self):
        import json, subprocess, threading
        def go():
            sink = "@DEFAULT_AUDIO_SINK@"
            try:
                for n in json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]"):
                    p = (n.get("info") or {}).get("props") or {}
                    if n.get("type") == "PipeWire:Interface:Node" and p.get("media.class") == "Audio/Sink" \
                            and p.get("node.name", "").startswith("bluez_output"):
                        sink = str(n["id"]); break
            except Exception:
                return
            if sink != self._sink:
                print(f"[room] volume: the slider is now {'the Bluetooth speaker (' + sink + ')' if sink[0] != '@' else 'the Surface'}", flush=True)
                self._sink = sink
                self._sinkFound.emit()
        threading.Thread(target=go, daemon=True).start()

    def _find_sink_soon(self):
        if time.time() - getattr(self, "_sink_looked", 0) > 3:
            self._sink_looked = time.time()
            self._find_sink()

    def _sink_changed(self):
        # the speaker changed: if the phone set a volume just before (it went to the old speaker), apply it here
        pv = getattr(self, "_phone_vol", None)
        if pv and time.time() - pv[1] < 20 and self.airplay.showing:
            self._set_sink(pv[0])
        else:
            self._read_out_volume()

    def _read_out_volume(self):
        import subprocess
        try:
            out = subprocess.run(["wpctl", "get-volume", self._sink], capture_output=True, text=True, timeout=2).stdout
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
        return self.cfg.get("here", "") or ("Living room" if self.demo else "")

    @Property(str, notify=statusChanged)
    def status(self):
        return "⚡ Cool" if self.demo else self.screen.status

    @Property("QVariantMap", constant=True)
    def timing(self):
        """The standby rules' settings (seconds and hours), straight from config.json."""
        c = self.cfg
        return {"homePlayingSec": int(c.get("homePlayingSec", 300)), "homeIdleSec": int(c.get("homeIdleSec", 300)),
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
        # from just above the room's own background (the raw mic hums; room/sleep.py learns it), else from −60 dB:
        # quiet room ≈ 0, talking ≈ 0.5, music ≈ 0.8
        base = max(-60.0, self.sleep.floor + 3) if self.sleep.floor is not None else -60.0
        v = max(0.0, min(1.0, (db - base) / 45))
        self._level += (v - self._level) * (0.5 if v > self._level else 0.12)
        self.levelChanged.emit()

    @Property(float, notify=voiceChanged)
    def voiceLevel(self):
        """Your voice as the assistant hears it (0…1), while it's listening — the assistant screen moves with it."""
        return self.voicelink.level

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

    # the Room screen's scenes (the redesign: Relax 45 % candle, Read 90 % neutral, Movie 15 % candle, Night 5 % candle —
    # the bulbs go no lower than 10 %)
    ROOM_SCENES = {"Relax": (45, 2200), "Read": (90, 4000), "Movie": (15, 2200), "Night": (5, 2200)}

    @Slot(str, int)
    def setLampLevel(self, mac, level):
        """One lamp's brightness (the Room screen's lamp lines); 0 switches it off."""
        if level <= 0:
            self.lights.set_lamps([mac], on=False)
        else:
            self.lights.set_lamps([mac], on=True, level=level)

    @Slot(str)
    def roomOff(self, name):
        """A room's lights off (its brightness line dragged right down)."""
        self.lights.set_room(name, on=False)

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
    def setVolumeLive(self, v):
        """While the slider is being dragged: the speaker's level, straight away (a local change, no servers)."""
        if self._plays_here():
            self._set_sink(v)
            self._reanchor(int(v))

    @Slot(int)
    def setVolume(self, v):
        """Music playing on Room (AirPlay or Room's own Spotify): the speaker it's coming out of — the Bluetooth
        speaker or the Surface's. Room's Spotify itself stays at full. Spotify on another device: that device's volume
        (the voice assistant's "turn it down"; the slider is hidden then)."""
        v = max(0, min(100, int(v)))
        if self._plays_here():
            self._set_sink(v)
            self._reanchor(v)
        else:
            self.spotify.set_volume(v)

    GAP = 0.12                     # seconds between volume changes sent to the speaker (≤ ~8 a second)

    def _set_sink(self, v):
        v = max(0, min(100, int(v)))
        self._vol_want = v
        if v != self._out_volume:
            self._out_volume = v
            self.musicChanged.emit()
        if self._vol_apply.isActive():
            return                     # a change is already queued: it'll send this latest value
        wait = self.GAP - (time.monotonic() - self._vol_applied)
        if wait <= 0:
            self._apply_sink()         # the first change goes straight out — it feels instant
        else:
            self._vol_apply.start(max(1, int(wait * 1000)))

    def _apply_sink(self):
        import subprocess
        v = self._vol_want
        if v is None:
            return
        self._vol_applied = time.monotonic()
        subprocess.Popen(["wpctl", "set-volume", self._sink, f"{v / 100:.2f}"], stderr=subprocess.DEVNULL)
        if time.time() - getattr(self, "_vol_said", 0) > 3:
            self._vol_said = time.time()
            print(f"[room] volume: {v} on {'the Bluetooth speaker' if self._sink[0] != '@' else 'the Surface'}", flush=True)

    def _phone_volume(self, v):
        print(f"[room] AirPlay: the phone's volume is {v}", flush=True)
        self._pv_last = v
        if self._pv_anchor is None or not self.airplay.showing:
            # a session starting (AirPlay wasn't the music here — e.g. Room's Spotify was playing): the phone's level
            # only becomes the starting point and the speaker stays where it is. (It once asked "is AirPlay playing?",
            # and a wrong "paused" made every click of the phone's volume do nothing.)
            here = self._out_volume if self._out_volume is not None else v
            if self._pv_anchor != (v, here):
                print(f"[room] AirPlay: the speaker stays at {here} — the phone's {v} is the starting point", flush=True)
            self._pv_anchor = (v, here)
            return
        target = self._phone_mapped(v)
        self._phone_vol = (target, time.time())
        self._find_sink_soon()
        self._vol_said = 0
        self._set_sink(target)

    def _phone_mapped(self, v):
        """The phone's volume → the speaker's: from the session's starting point, each step of the phone moves the
        speaker by a fraction of it (airplayVolumeStep). The phone at zero is always silence. Reaching 0 or 100 moves
        the starting point, so coming back the other way responds from the first click."""
        if v <= 0:
            self._pv_anchor = (0, 0.0)           # silence — and turning it back up starts from silence
            return 0
        pa, sa = self._pv_anchor
        t = sa + self._pv_step * (v - pa)
        if t > 100 or t < 0:
            t = max(0.0, min(100.0, t))
            self._pv_anchor = (v, t)
        return round(t)

    def _airplay_session(self):
        if self._pv_anchor is not None and not self.airplay.active:
            self._pv_anchor = None             # the session ended: the next one starts from the speaker again

    def _reanchor(self, v):
        """Room's own slider or buttons set the speaker: the phone's current level now means this."""
        if self._pv_anchor is not None and self._pv_last is not None:
            self._pv_anchor = (self._pv_last, v)

    def _spotify_full(self):
        """Room's own Spotify plays at full — the speaker's volume is the one that changes. Once, when it starts
        playing here (turned down from the phone afterwards, it's left alone). Its sound stream too: the old slider
        turned that down, and Soloist keeps it."""
        import subprocess
        dev = (self.spotify.player or {}).get("device") or {}
        if (dev.get("volume_percent") or 0) < 100:
            print(f"[room] Spotify here was at {dev.get('volume_percent')} % — to full", flush=True)
            self.spotify.set_volume(100)
        sid = self._soloist_stream()
        if sid:
            subprocess.Popen(["wpctl", "set-volume", str(sid), "1.0"], stderr=subprocess.DEVNULL)

    def _soloist_stream(self):
        import json, subprocess
        try:
            for n in json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]"):
                p = (n.get("info") or {}).get("props") or {}
                who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name", "application.process.binary")).lower()
                if n.get("type") == "PipeWire:Interface:Node" and p.get("media.class") == "Stream/Output/Audio" \
                        and ("soloist" in who or "spotify" in who):
                    return n["id"]
        except Exception:
            pass
        return None

    # ---------------------------------------------------------------- screen off / on, the Surface's buttons
    def _needs_screen(self):
        """'' when nothing needs the screen, else why (it's logged)."""
        if self.browserOpen:
            return "the web browser is open"
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
        if self.demo and os.environ.get("ROOM_DEMO_VOICE"):          # screens to check: listen · follow · think · speak
            st = os.environ["ROOM_DEMO_VOICE"]                          # · error · miss · ready; ROOM_DEMO_CARD: the answer
            card = os.environ.get("ROOM_DEMO_CARD", "forecast")
            q, a = DEMO_ASK.get(card, DEMO_ASK["forecast"])
            return {"listen": {"state": "listening", "stage": "wake", "heard": ""},
                    "remlisten": {"state": "listening", "stage": "wake", "heard": "", "about": "reminder"},
                    "follow": {"state": "listening", "stage": "follow", "heard": ""},
                    "think": {"state": "thinking", "stage": "think", "heard": q},
                    "speak": {"state": "speaking", "stage": "done", "heard": q, "reply": a, "line": a.lower(),
                              "card": "" if card in ("lights", "reminder", "none") else card,
                              "lit": ["Living room"] if card == "lights" else [],
                              "reminded": "r1" if card == "reminder" else ""},
                    "error": {"state": "speaking", "stage": "error", "heard": q,
                              "reply": "Sorry, I couldn't reach my brain just now — try again in a moment."},
                    "miss": {"state": "idle", "stage": "miss", "heard": ""},
                    "ready": {"state": "idle", "stage": "idle"}}.get(st, {})
        return dict(self.voicelink.st)

    @Slot()
    def listen(self):
        self.voicelink.listen()

    @Slot(str)
    def listenFor(self, about):
        """Listen for something in particular ("reminder": the Reminders screen's + Add a reminder)."""
        self.voicelink.listen(about)

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
                    out = subprocess.run(["wpctl", "get-volume", self._sink], capture_output=True, text=True, timeout=2).stdout
                    base = round(float(out.split()[1]) * 100)
                except Exception:
                    base = 50
            v = max(0, min(100, base + delta))
            self._set_sink(v)
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

    @Property(bool, notify=settingsChanged)
    def desktop(self):
        """GNOME is installed — there's a desktop to switch to."""
        return self._desktop or self.demo

    # ---------------------------------------------------------------- the web browser (Settings → Web browser)
    @Property(bool, notify=settingsChanged)
    def browser(self):
        """Firefox is there to open (in the panel session)."""
        import shutil
        return (self._kiosk and shutil.which("firefox") is not None) or self.demo

    @Property(bool, notify=browserChanged)
    def browserOpen(self):
        return self._browser is not None and self._browser.poll() is None

    @Slot()
    def openBrowser(self):
        """Firefox, full screen over Room (cage shows the newest window). Closing its last tab closes it — Room is
        underneath, where it was. While it's open Room keeps the screen on (its touches don't reach Room)."""
        if self.browserOpen:
            return
        import subprocess
        self._browser_size()
        env = dict(os.environ, MOZ_ENABLE_WAYLAND="1")
        for k in ("QT_QPA_PLATFORM", "QT_SCALE_FACTOR", "QSG_RHI_BACKEND"):
            env.pop(k, None)
        try:
            self._browser = subprocess.Popen(["firefox"], env=env, cwd=os.path.expanduser("~"), stdin=subprocess.DEVNULL,
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            print(f"[room] web browser: couldn't open Firefox ({e})", flush=True)
            return
        print("[room] web browser: opened", flush=True)
        self._browser_check.start(2000)
        self.browserChanged.emit()

    def _browser_size(self):
        """Firefox at the panel's size. cage draws everything at the screen's own pixels (2736 × 1824, no scaling),
        so Firefox came up at 100 % — tiny. Room itself is drawn at 200 % (its 1368 × 912 stage); Firefox gets the
        same through its own setting (layout.css.devPixelsPerPx) in user.js — read at every start of Firefox — in
        each of its profiles. ("browserScale" in config.json: 2 by default.) A profile Firefox makes on its very
        first start gets it once it closes."""
        import configparser
        scale = float(self.cfg.get("browserScale", 2.0))
        line = f'user_pref("layout.css.devPixelsPerPx", "{scale}");  // Room: the panel\'s size (room/backend.py)'
        for base in (os.path.expanduser("~/.mozilla/firefox"), os.path.expanduser("~/.config/mozilla/firefox")):
            ini = configparser.RawConfigParser()
            if not ini.read(os.path.join(base, "profiles.ini")):
                continue
            for sec in ini.sections():
                if not ini.has_option(sec, "Path"):
                    continue
                path = ini.get(sec, "Path")
                prof = os.path.join(base, path) if ini.get(sec, "IsRelative", fallback="1") == "1" else path
                if not os.path.isdir(prof):
                    continue
                js = os.path.join(prof, "user.js")
                try:
                    old = open(js).read().splitlines() if os.path.exists(js) else []
                    keep = [l for l in old if "layout.css.devPixelsPerPx" not in l]
                    if line not in old or len(keep) != len(old) - 1:
                        open(js, "w").write("\n".join(keep + [line]) + "\n")
                        print(f"[room] web browser: {scale:g}× in {os.path.basename(prof)}", flush=True)
                except OSError as e:
                    print(f"[room] web browser: couldn't set its size in {prof} ({e})", flush=True)

    def _browser_closed(self):
        if self._browser is not None and self._browser.poll() is not None:
            self._browser_size()                     # (a profile made on Firefox's very first start)
            print("[room] web browser: closed", flush=True)
            self._browser = None
            self._browser_check.stop()
            self.browserChanged.emit()

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
        import shutil, subprocess
        if shutil.which("gnome-session") is None:
            self._desktop_note = "GNOME isn't installed any more — there's no desktop to switch to"
            self.settingsChanged.emit()
            return
        r = subprocess.run(["busctl", "call", "org.freedesktop.Accounts", f"/org/freedesktop/Accounts/User{os.getuid()}",
                            "org.freedesktop.Accounts.User", "SetSession", "s", "gnome"], capture_output=True, text=True, timeout=10)
        if r.returncode != 0 or self._session() != "gnome":
            self._desktop_note = "Couldn't switch here — use Ctrl+Alt+F3 and run room-kiosk off"
            print(f"[room] switch to desktop: {r.stderr.strip()}")
            self.settingsChanged.emit()
            return
        subprocess.Popen(["systemctl", "reboot"])
