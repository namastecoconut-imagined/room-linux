"""The bridge between the services and the QML screens: one object, exposed to QML as `room`."""
import os
import time

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from .airplay import AirPlay
from .calendar import Calendar
from .lights import Lights
from .spotify import Spotify
from .weather import Weather
from . import demo


class Room(QObject):
    weatherChanged = Signal()
    eventsChanged = Signal()
    roomsChanged = Signal()
    musicChanged = Signal()
    levelChanged = Signal()

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
        self.wx.changed.connect(self.weatherChanged)
        self.calendar.changed.connect(self.eventsChanged)
        self.lights.changed.connect(self.roomsChanged)
        self.spotify.changed.connect(self.musicChanged)
        self._level = 0.0
        self._mic = None

    def start(self):
        if self.demo:
            return
        self.wx.start()
        self.calendar.start()
        self.lights.start()
        self.spotify.start()
        self.airplay.start()
        # the room-sound ripple on standby: off until it's proven on this machine (opening the mic crashed in testing)
        if os.environ.get("ROOM_MIC") == "1" or self.cfg.get("standbyMic") is True:
            self._start_mic()

    # ---------------------------------------------------------------- what the screens read
    @Property("QVariantMap", notify=weatherChanged)
    def weather(self):
        return demo.WEATHER if self.demo else self.wx.snapshot()

    @Property("QVariantList", notify=eventsChanged)
    def events(self):
        return demo.EVENTS if self.demo else self.calendar.upcoming(3, self.clock24)

    @Property("QVariantList", notify=roomsChanged)
    def rooms(self):
        return demo.ROOMS if self.demo else self.lights.snapshot()

    @Property("QVariantMap", notify=musicChanged)
    def music(self):
        if self.demo:
            m = dict(demo.MUSIC); m["at"] = time.time() - 4
            m["playing"] = os.environ.get("ROOM_SCREEN") != "standby"; m["exists"] = m["playing"]
            return m
        # whatever's actually playing: AirPlay while a phone or Mac is sending to Room, otherwise Spotify
        return self.airplay.snapshot() if self.airplay.showing else self.spotify.snapshot()

    @Property(bool, constant=True)
    def clock24(self):
        return bool(self.cfg.get("clock24"))

    @Property(int, constant=True)
    def standbySec(self):
        return int(self.cfg.get("standbySec", 15))

    @Property(str, constant=True)
    def here(self):
        return self.cfg.get("here", "")

    @Property(float, notify=levelChanged)
    def level(self):
        """Room loudness, 0…1 — the standby dots ripple with it."""
        return self._level

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
        self.spotify.set_volume(v)

    @Slot(str)
    def transfer(self, device_id):
        self.spotify.transfer(device_id)

    @Slot(str)
    def playUri(self, uri):
        self.spotify.play_uri(uri)

    @Slot()
    def refreshDevices(self):
        self.spotify.refresh_devices()

    @Slot(float)
    def seek(self, s):
        self.spotify.seek(s)

    @Slot(bool)
    def setStandby(self, on):
        self.spotify.relaxed = on

    @Slot()
    def listen(self):
        print("[room] voice: coming in the voice stage (wake word + Whisper)")

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
