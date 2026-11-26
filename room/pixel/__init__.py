"""The pixel display (a 32 × 32 dot display on Bluetooth): what it's showing, and telling it.

The Pixel screen (qml/PixelView.qml) draws the pictures — clock faces, art loops — dot by dot and hands the frames
over; this turns them into what the display takes (a PNG for a still, a GIF for a loop, corrected for LEDs), sends them
down the link (link.py), and remembers what's showing and every choice made (~/.local/state/room/pixel.json), so the
display comes back the same after a restart, an update or a power cut. Effects, one colour and the Classic clock are
the display's own: a short command starts them and they keep running by themselves.

"pixel": false in config.json: no link at all (the screen says so).
"""
import os
import time

from PySide6.QtCore import Property, QByteArray, QObject, QTimer, Signal, Slot

from .. import config
from . import proto

CHOICES = {"face": "orbit", "clockCol": 0, "h24": True, "secs": False, "date": True, "art": "ripple", "artCol": 0, "pace": 85,
           "effect": 0, "effCols": [1, 3, 5], "solidCol": 6}


class Pixel(QObject):
    changed = Signal()
    again = Signal()              # (to the screen) draw the clock face now and send it: the display has just come back

    def __init__(self, cfg=None, demo=False):
        super().__init__()
        self.demo = demo
        self.enabled = (cfg or {}).get("pixel", True) is not False
        self.store = config.State("pixel")
        saved = {} if demo else self.store.read()
        self.sel = dict(CHOICES, **(saved.get("sel") or {}))
        self.on = saved.get("on", True)
        self.bright = int(saved.get("bright", 50))
        self.mode = saved.get("mode", "")             # clockface · classic · art · effect · colour
        self.label = saved.get("label", "")
        self.address, self.name = saved.get("address", ""), saved.get("name", "")
        self.gif_path = config.STATE_DIR / "pixel-loop.gif"       # the art loop that's showing, as sent
        self.tuner = proto.Tuner()
        self.frames = []
        self.link = None
        self._save = QTimer(self); self._save.setSingleShot(True); self._save.setInterval(800); self._save.timeout.connect(self._write)
        if demo:                                       # (checks) sample state, no Bluetooth
            scr = os.environ.get("ROOM_SCREEN", "")
            self.name, self.mode, self.label = "IDM-A99C51", "clockface", "Orbit"
            if "art" in scr:
                self.mode, self.label, self.sel["art"], self.sel["artCol"] = "art", "Tunnel", "tunnel", 5
            if "light" in scr:
                self.mode, self.label = "effect", "Gradient sweep"

    def start(self):
        if self.demo or not self.enabled:
            return
        from .link import Link                        # (Qt's Bluetooth is only loaded when there's a display to talk to)
        self.link = Link(self.address, self.name)
        self.link.changed.connect(self._link_changed)
        self.link.ready.connect(self._ready)
        self.link.start()

    # ---------------------------------------------------------------- what the screen reads
    @Property("QVariantMap", notify=changed)
    def view(self):
        ln = self.link
        scr = os.environ.get("ROOM_SCREEN", "") if self.demo else ""
        return {
            "enabled": self.enabled,
            "link": ("searching" if "lost" in scr else "on") if self.demo else ln.state if ln else "off",
            "name": (ln.name if ln and ln.name else self.name) or "",
            "firmware": (ln.info.get("firmware", "") if ln else "") or ("4.15" if self.demo else ""),
            "on": self.on, "bright": self.bright, "mode": self.mode, "label": self.label,
            "sending": bool(ln and ln.total), "progress": (ln.sent / ln.total) if ln and ln.total else 0,
            "sel": dict(self.sel), "palette": proto.PALETTE,
        }

    def _link_changed(self):
        ln = self.link
        if ln.address and (ln.address != self.address or ln.name != self.name):
            self.address, self.name = ln.address, ln.name
            self._save.start()
        self.changed.emit()

    def _write(self):
        if not self.demo:
            self.store.write({"sel": self.sel, "on": self.on, "bright": self.bright, "mode": self.mode, "label": self.label,
                              "address": self.address, "name": self.name})

    def _showing(self, mode, label):
        self.mode, self.label = mode, label
        self._save.start()
        self.changed.emit()

    def _up(self):
        return self.link is not None and self.link.state == "on"

    def _tint(self, index):
        return self.tuner.one(*proto.rgb(proto.PALETTE[int(index) % len(proto.PALETTE)]))

    # ---------------------------------------------------------------- the display has just (re)connected
    def _ready(self):
        ln = self.link
        ln.command(proto.brightness(self.bright))
        if not self.on:
            ln.command(proto.power(False))
        elif self.mode == "clockface":
            self.again.emit()
        elif self.mode == "classic":
            self._classic()
        elif self.mode == "effect":
            self._effect()
        elif self.mode == "colour":
            ln.command(proto.colour(*self._tint(self.sel["solidCol"])))
        elif self.mode == "art":
            try:
                ln.picture("gif", self.gif_path.read_bytes())
            except OSError:
                pass

    # ---------------------------------------------------------------- what the screen asks for
    @Slot(str, "QVariant")
    def choose(self, key, value):
        """Keep a choice (a face, a colour, 24-hour…). It's shown when the screen asks for it to be."""
        if key in CHOICES:
            self.sel[key] = value.toVariant() if hasattr(value, "toVariant") else value
            self._save.start()
            self.changed.emit()

    @Slot(str, str, QByteArray)
    def still(self, mode, label, rgba):
        """One frame (32 × 32 × RGBA) — a clock face, drawn by the screen."""
        data = bytes(rgba.data())
        if len(data) != proto.N * proto.N * 4:
            return
        if self._up() and self.on:
            self.link.picture("png", proto.png(self.tuner.frame(data)))
        if (mode, label) != (self.mode, self.label):
            self._showing(mode, label)

    @Slot()
    def loopBegin(self):
        self.frames = []

    @Slot(QByteArray)
    def loopFrame(self, rgba):
        data = bytes(rgba.data())
        if len(data) == proto.N * proto.N * 4:
            self.frames.append(self.tuner.frame(data))

    @Slot(str, str, int)
    def loopEnd(self, mode, label, delay_ms):
        """The frames handed over since loopBegin, as one seamless loop: sent once, it keeps running on the display."""
        frames, self.frames = self.frames, []
        if not frames:
            return
        data = proto.gif(frames, delay_ms)
        if not self.demo:
            try:
                tmp = self.gif_path.with_suffix(".tmp")
                tmp.write_bytes(data)
                tmp.replace(self.gif_path)
            except OSError:
                pass
        if self._up() and self.on:
            self.link.picture("gif", data)
        self._showing(mode, label)

    def _effect(self):
        cols = [self._tint(i) for i in (self.sel["effCols"] or [1, 3])][:7]
        if len(cols) < 2:
            cols = cols + cols if cols else [(255, 77, 46), (46, 196, 255)]
        self.link.command(proto.effect(int(self.sel["effect"]), cols))

    @Slot(str)
    def effect(self, label):
        """The display's own effect (sel.effect: its style number) in sel.effCols."""
        if self._up() and self.on:
            self._effect()
        self._showing("effect", label)

    @Slot(str)
    def colour(self, label):
        if self._up() and self.on:
            self.link.command(proto.colour(*self._tint(self.sel["solidCol"])))
        self._showing("colour", label)

    def _classic(self):
        self.link.command(proto.set_time(time.localtime()))
        self.link.command(proto.clock(3, bool(self.sel["date"]), bool(self.sel["h24"]), *self._tint(self.sel["clockCol"])))

    @Slot()
    def classic(self):
        """The display's own clock: it keeps time by itself."""
        if self._up() and self.on:
            self._classic()
        self._showing("classic", "Classic")

    @Slot(bool)
    def power(self, on):
        self.on = bool(on)
        if self._up():
            self.link.command(proto.power(self.on))
            if self.on:
                self._ready()                          # (back on: what it was showing, sent again)
        self._save.start()
        self.changed.emit()

    @Slot(int)
    def brightness(self, pct):
        self.bright = max(5, min(100, int(pct)))
        if self._up():
            self.link.command(proto.brightness(self.bright))
        self._save.start()
        self.changed.emit()
