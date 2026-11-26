"""The pixel display (a 32 × 32 dot display on Bluetooth): what it's showing, and telling it.

The Pixel screen (qml/PixelView.qml) draws the pictures — clock faces, art loops — dot by dot and hands the frames
over; this turns them into what the display takes (a PNG for a still, a GIF for a loop, corrected for LEDs), sends them
down the link (link.py), and remembers what's showing and every choice made (~/.local/state/room/pixel.json), so the
display comes back the same after a restart, an update or a power cut. Effects and one colour are
the display's own: a short command starts them and they keep running by themselves.

"pixel": false in config.json: no link at all (the screen says so).
"""
import os
import random
import threading
import re
import time

from PySide6.QtCore import Property, QByteArray, QObject, QSize, QTimer, QUrl, Qt, Signal, Slot
from PySide6.QtGui import QImage, QImageReader

from .. import config
from . import proto

CHOICES = {"face": "orbit", "clockCol": 0, "h24": True, "secs": False, "art": "lattice", "artCol": 0, "pace": 85,
           "effect": 0, "effCols": [1, 3, 5], "solidCol": 6,
           "item": "", "slides": [], "every": 60, "shuffle": False, "faces": [], "faceOrder": "order",
           "cdSet": 1500, "score": [0, 0], "timerStyle": "minimal",
           "text": "Hello", "textCol": 3, "textSpeed": 5, "textSize": 55, "textFont": "sans", "textLook": "crisp",
           "tune": dict(proto.TUNE), "flip": False, "eco": {"on": False, "start": 22 * 60, "end": 7 * 60, "light": 10}, "held": True}
GONE = ("classic", "rings", "jumbo", "outline", "solar")       # clock faces taken out (27 Nov)
PICTURES = (".gif", ".png", ".jpg", ".jpeg", ".webp", ".bmp")
MAX_FRAMES = 300


class Pixel(QObject):
    changed = Signal()
    again = Signal()              # (to the screen) draw the clock face now and send it: the display has just come back
    redraw = Signal()             # (to the screen) draw what's showing again and send it: the picture tuning changed

    def __init__(self, cfg=None, demo=False):
        super().__init__()
        self.demo = demo
        self.enabled = (cfg or {}).get("pixel", True) is not False
        self.store = config.State("pixel")
        saved = {} if demo else self.store.read()
        self.sel = dict(CHOICES, **(saved.get("sel") or {}))
        self.on = saved.get("on", True)
        self.bright = int(saved.get("bright", 50))
        self.mode = saved.get("mode", "")             # clockface · art · text · effect · colour · library · slideshow
        if self.mode == "classic" or (self.mode == "clockface" and self.sel["face"] in GONE):
            self.mode, self.label, self.sel["face"] = "clockface", "Orbit", "orbit"      # (a face that's been taken out)
        self._stills = False                          # the display is in its picture mode (the last thing sent was a still)
        self.over = None                              # something up for now, over that: a timer, the assistant's face
        self.lib_dir = config.STATE_DIR / "pixel-library"     # saved GIFs and pictures (copied in from the Mac)
        self.items = []
        self._made = {}                               # a library picture as the display takes it: id → (mtime, kind, bytes)
        self._face_i, self._face_last, self._slide_i = 0, "", 0
        self._slide = QTimer(self); self._slide.timeout.connect(self._slide_next)
        self.label = saved.get("label", "")
        self.address, self.name = saved.get("address", ""), saved.get("name", "")
        self.gif_path = config.STATE_DIR / "pixel-loop.gif"       # the loop that's showing (art, text), as sent
        self.tuner = proto.Tuner(self.sel["tune"] if isinstance(self.sel["tune"], dict) else None)
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
            if "library" in scr or "setup" in scr:
                self.items = [{"id": n + ".gif", "name": n.capitalize(), "url": "", "sample": i} for i, n in enumerate(["ripple", "heart", "tunnel", "comet", "snow"])]
                self.sel.update(slides=["ripple.gif", "tunnel.gif"], faces=["heart.gif"], item="heart.gif")
                if "library" in scr:
                    self.mode, self.label = "library", "Heart"
        else:
            self._scan()

    def start(self):
        if self.demo or not self.enabled:
            return
        from .link import Link                        # (Qt's Bluetooth is only loaded when there's a display to talk to)
        self.link = Link(self.address, self.name)
        self.link.changed.connect(self._link_changed)
        self.link.ready.connect(self._ready)
        if self.sel["held"]:                          # (released: left alone until it's taken back)
            self.link.start()
        self._warm()

    def _warm(self):
        """The assistant's faces made ready ahead of time (off the screen's thread), so the first one is as quick
        as the rest."""
        ids = list(self.sel["faces"])
        if ids and not self.demo:
            threading.Thread(target=lambda: [self._make(i) for i in ids], daemon=True).start()

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
            "over": (self.over or {}).get("kind", ""), "overLabel": (self.over or {}).get("label", ""), "overItem": (self.over or {}).get("item", ""),
            "held": bool(self.sel["held"]), "packet": ln.packet if ln and ln.state == "on" else 0, "answer": ln.answer if ln else "",
            "tunes": proto.TUNES,
            "items": self.items, "libraryPath": str(self.lib_dir).replace(os.path.expanduser("~"), "~"),
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
        """A new thing to stay on the display (it replaces a timer or the face, and ends a slideshow)."""
        self.mode, self.label, self.over = mode, label, None
        if mode != "slideshow":
            self._slide.stop()
        self._save.start()
        self.changed.emit()

    def _up(self):
        return self.link is not None and self.link.state == "on"

    def _still(self, png):
        """A still, sent. The display is told to go into its picture mode only when it isn't in it already: told each
        time, it went black for a moment before every frame (a clock's seconds, a countdown)."""
        self.link.picture("png", png, not self._stills)
        self._stills = True

    def _loop(self, kind, data):
        self._stills = kind == "png"
        self.link.picture(kind, data, True)

    def _cmd(self, data):
        """A command that puts something else on the display (an effect, a colour, its own timers, off)."""
        self._stills = False
        self.link.command(data)

    def _tint(self, index):
        return self.tuner.one(*proto.rgb(proto.PALETTE[int(index) % len(proto.PALETTE)]))

    # ---------------------------------------------------------------- the display has just (re)connected
    def _ready(self):
        self._stills = False
        self.link.command(proto.brightness(self.bright))
        self.link.command(proto.flip(bool(self.sel["flip"])))
        self._eco()
        self.over = None
        if not self.on:
            self.link.command(proto.power(False))
        else:
            self._rest()

    def _rest(self):
        """What stays on the display, sent (again)."""
        ln = self.link
        if self.mode == "clockface":
            self.again.emit()
        elif self.mode == "effect":
            self._effect()
        elif self.mode == "colour":
            self._cmd(proto.colour(*self._tint(self.sel["solidCol"])))
        elif self.mode in ("art", "text"):
            try:
                self._loop("gif", self.gif_path.read_bytes())
            except OSError:
                pass
        elif self.mode in ("library", "slideshow"):
            self._send_item(self.sel["item"])
            if self.mode == "slideshow":
                self._slide.start(max(10, int(self.sel["every"])) * 1000)

    @Slot()
    def restore(self):
        """The timer's done, the assistant has finished: back to what was on."""
        if self.over is None:
            return
        self.over = None
        if self._up() and self.on:
            self._rest()
        self.changed.emit()

    # ---------------------------------------------------------------- what the screen asks for
    @Slot(str, "QVariant")
    def choose(self, key, value):
        """Keep a choice (a face, a colour, 24-hour…). It's shown when the screen asks for it to be."""
        if key not in CHOICES or key == "held":
            return
        self.sel[key] = value.toVariant() if hasattr(value, "toVariant") else value
        self._save.start()
        self.changed.emit()
        if key == "faces":
            self._warm()
        elif key == "flip" and self._up():
            self.link.command(proto.flip(bool(self.sel["flip"])))
        elif key == "eco" and self._up():
            self._eco()
        elif key == "tune":                            # every picture is corrected again, and what's showing sent again
            self.tuner = proto.Tuner(self.sel["tune"] if isinstance(self.sel["tune"], dict) else None)
            self._made.clear()
            self._warm()
            if self._up() and self.on and not self.over:
                if self.mode in ("clockface", "art", "text"):
                    self.redraw.emit()
                else:
                    self._rest()

    def _eco(self):
        e = dict(CHOICES["eco"], **(self.sel["eco"] if isinstance(self.sel["eco"], dict) else {}))
        self.link.command(proto.eco(bool(e["on"]), int(e["start"]), int(e["end"]), int(e["light"])))

    @Slot(bool)
    def hold(self, on):
        """Let go of the display (so the web app or the phone app can connect to it), or take it back."""
        self.sel["held"] = bool(on)
        self._save.start()
        if self.link is not None:
            if on:
                self.link.start()
            else:
                self.link.stop()
        self.changed.emit()

    @Slot()
    def check(self):
        if self._up():
            self.link.check()
            self.link.command(proto.brightness(self.bright))

    @Slot(str, str, QByteArray)
    def still(self, mode, label, rgba):
        """One frame (32 × 32 × RGBA) — a clock face, drawn by the screen."""
        data = bytes(rgba.data())
        if len(data) != proto.N * proto.N * 4:
            return
        if self.over and (mode, label) == (self.mode, self.label):
            return                                     # (the clock keeping time: not over a timer or the face)
        if self._up() and self.on:
            self._still(proto.png(self.tuner.frame(data)))
        if self.over or (mode, label) != (self.mode, self.label):
            self._showing(mode, label)

    @Slot(str, str, QByteArray)
    def temp(self, kind, label, rgba):
        """One frame that's up for now (a countdown's second, the scoreboard): what was showing stays remembered."""
        data = bytes(rgba.data())
        if len(data) != proto.N * proto.N * 4:
            return
        if self._up() and self.on:
            self._still(proto.png(self.tuner.frame(data)))
        if not self.over or self.over.get("kind") != kind or self.over.get("label") != label:
            self.over = {"kind": kind, "label": label}
            self.changed.emit()

    @Slot(str, int, int)
    def native(self, what, a, b):
        """The display's own countdown, stopwatch and scoreboard."""
        cmd = {"cd_start": lambda: proto.countdown(1, a, b), "cd_pause": lambda: proto.countdown(2, a, b),
               "cd_resume": lambda: proto.countdown(3, a, b), "cd_stop": lambda: proto.countdown(0, 0, 0),
               "sw_start": lambda: proto.chrono(1), "sw_pause": lambda: proto.chrono(2), "sw_resume": lambda: proto.chrono(3),
               "sw_reset": lambda: proto.chrono(0), "score": lambda: proto.score(a, b)}.get(what)
        if not cmd:
            return
        if self._up() and self.on:
            self._cmd(cmd())
        if what in ("cd_start", "sw_start", "score") and not (self.over and self.over.get("kind") == "native"):
            self.over = {"kind": "native", "label": what}
            self.changed.emit()

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
            self._loop("gif", data)
        self._showing(mode, label)

    def _effect(self):
        cols = [self._tint(i) for i in (self.sel["effCols"] or [1, 3])][:7]
        if len(cols) < 2:
            cols = cols + cols if cols else [(255, 77, 46), (46, 196, 255)]
        self._cmd(proto.effect(int(self.sel["effect"]), cols))

    @Slot(str)
    def effect(self, label):
        """The display's own effect (sel.effect: its style number) in sel.effCols."""
        if self._up() and self.on:
            self._effect()
        self._showing("effect", label)

    @Slot(str)
    def colour(self, label):
        if self._up() and self.on:
            self._cmd(proto.colour(*self._tint(self.sel["solidCol"])))
        self._showing("colour", label)

    # ---------------------------------------------------------------- the library: saved GIFs and pictures
    def _scan(self):
        try:
            self.lib_dir.mkdir(parents=True, exist_ok=True)
            files = sorted((p for p in self.lib_dir.iterdir() if p.suffix.lower() in PICTURES), key=lambda p: p.name.lower())
        except OSError:
            files = []
        self.items = [{"id": p.name, "name": re.sub(r"[-_]+", " ", re.sub(r"(-smooth|-still)?(-32)?$", "", p.stem)).strip().capitalize() or p.stem,
                       "url": QUrl.fromLocalFile(str(p)).toString(), "sample": -1} for p in files]
        ids = {i["id"] for i in self.items}
        for key in ("slides", "faces"):
            self.sel[key] = [i for i in self.sel[key] if i in ids]

    def _name(self, item):
        return next((i["name"] for i in self.items if i["id"] == item), "")

    def _make(self, item):
        """A library picture as the display takes it: every frame fitted to 32 × 32 (cropped to fill), corrected for
        LEDs; a PNG for a still, one GIF for an animation. Made once and kept until the file changes."""
        path = self.lib_dir / os.path.basename(item)
        try:
            mtime = path.stat().st_mtime
        except OSError:
            return None
        if item in self._made and self._made[item][0] == mtime:
            return self._made[item][1:]
        rd = QImageReader(str(path))
        rd.setDecideFormatFromContent(True)
        frames, delays, n = [], [], proto.N
        while len(frames) < MAX_FRAMES:
            img = rd.read()
            if img.isNull():
                break
            small = max(img.width(), img.height()) <= 64
            img = img.convertToFormat(QImage.Format.Format_RGBA8888).scaled(
                QSize(n, n), Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                Qt.TransformationMode.FastTransformation if small else Qt.TransformationMode.SmoothTransformation)
            img = img.copy((img.width() - n) // 2, (img.height() - n) // 2, n, n)
            rows = b"".join(bytes(img.constScanLine(y))[:n * 4] for y in range(n))
            flat = bytearray(rows)                    # (see-through parts: black)
            for i in range(3, len(flat), 4):
                if flat[i] < 128:
                    flat[i - 3:i] = b"\0\0\0"
            frames.append(self.tuner.frame(bytes(flat)))
            delays.append(max(20, rd.nextImageDelay() or 100))
            if not rd.supportsAnimation():
                break
        if not frames:
            return None
        made = ("png", proto.png(frames[0])) if len(frames) == 1 else ("gif", proto.gif(frames, delays))
        self._made[item] = (mtime, *made)
        return made

    def _send_item(self, item):
        made = self._make(item) if item else None
        if made and self._up() and self.on:
            self._loop(*made)
        return made is not None

    @Slot()
    def rescan(self):
        """Look in the library folder again (the screen asks when its Library is opened)."""
        if not self.demo:
            before = [i["id"] for i in self.items]
            self._scan()
            if before != [i["id"] for i in self.items]:
                self.changed.emit()

    @Slot(str)
    def show(self, item):
        """A saved picture, on the display."""
        if self.demo or self._make(item):
            self.sel["item"] = item
            self._send_item(item)
            self._showing("library", self._name(item))

    @Slot(str)
    def remove(self, item):
        try:
            (self.lib_dir / os.path.basename(item)).unlink()
        except OSError:
            pass
        self._made.pop(item, None)
        self._scan()
        self._save.start()
        self.changed.emit()

    @Slot(bool)
    def slideshow(self, on):
        """The ticked pictures, one after another (sel.every seconds each, shuffled or in order) — for as long as
        nothing else is put on the display; it picks up again after a restart."""
        if not on:
            self._slide.stop()
            if self.mode == "slideshow":
                self._showing("library", self._name(self.sel["item"]))
            return
        if not self.sel["slides"]:
            return
        self._slide_i = 0
        self._showing("slideshow", "Slideshow")
        self._slide_next()
        self._slide.start(max(10, int(self.sel["every"])) * 1000)

    def _slide_next(self):
        ids = [i for i in self.sel["slides"] if any(x["id"] == i for x in self.items)]
        if not ids or self.mode != "slideshow":
            self._slide.stop()
            return
        if self.over:
            return                                     # (a timer or the face is up: carry on after it)
        if self.sel["shuffle"] and len(ids) > 1:
            item = random.choice([i for i in ids if i != self.sel["item"]])
        else:
            item = ids[self._slide_i % len(ids)]
            self._slide_i += 1
        self.sel["item"] = item
        self._send_item(item)
        self._save.start()
        self.changed.emit()

    # ---------------------------------------------------------------- the assistant's face
    @Slot()
    def faceOn(self):
        """The assistant is answering: one of the chosen pictures (sel.faces — the next, or any other when shuffled)
        goes up until faceOff."""
        ids = [i for i in self.sel["faces"] if any(x["id"] == i for x in self.items)]
        if not ids or not self.on or (self.over and self.over.get("kind") != "face"):
            return                                     # (none chosen; or a timer is up, and stays)
        if self.sel["faceOrder"] == "shuffle" and len(ids) > 1:
            item = random.choice([i for i in ids if i != self._face_last])
        else:
            item = ids[self._face_i % len(ids)]
            self._face_i += 1
        self._face_last = item
        if self.demo or self._send_item(item):
            self.over = {"kind": "face", "label": self._name(item), "item": item}
            self.changed.emit()

    @Slot()
    def faceOff(self):
        if self.over and self.over.get("kind") == "face":
            self.restore()

    @Slot(bool)
    def power(self, on):
        self.on = bool(on)
        self.over = None
        if self._up():
            self._cmd(proto.power(self.on))
            if self.on:
                self._rest()                           # (back on: what it was showing, sent again)
        self._save.start()
        self.changed.emit()

    @Slot(int)
    def brightness(self, pct):
        self.bright = max(5, min(100, int(pct)))
        if self._up():
            self.link.command(proto.brightness(self.bright))
        self._save.start()
        self.changed.emit()
