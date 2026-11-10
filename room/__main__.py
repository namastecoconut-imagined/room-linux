"""python -m room  — starts the panel full screen.

  ROOM_DEMO=1        sample data (no bulbs / Spotify / calendar needed)
  ROOM_WINDOWED=1    a 1368×912 window instead of full screen (for working on it)
  ROOM_SHOT=path.png save a screenshot after ROOM_SHOT_MS (default 2500) and quit — used to check builds
  ROOM_SCREEN=home|standby|musicstandby   which screen to open on
"""
import os
import signal
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(line_buffering=True)   # every log line reaches the journal when it happens
except Exception:
    pass

ROOT = Path(__file__).resolve().parent.parent

# Wayland first (Fedora's default), with the GPU scene graph; fall back to X11 if Wayland isn't there.
os.environ.setdefault("QT_QPA_PLATFORM", "wayland;xcb")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
# a harmless Wayland text-input warning GNOME triggers on every tap — hide it so real errors stand out
os.environ.setdefault("QT_LOGGING_RULES", "qt.qpa.wayland.textinput=false")

from PySide6.QtCore import QEvent, QObject, QTimer, QUrl, Qt  # noqa: E402
from PySide6.QtGui import QFontDatabase, QGuiApplication, QCursor, QInputDevice  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402

from .backend import Room  # noqa: E402
from . import config  # noqa: E402


class Pointer(QObject):
    """The mouse pointer shows whenever a real mouse or trackpad moves, and hides 3 s after it stops —
    so it's there when you use one, and never sits on the panel when you only use touch."""

    def __init__(self, app):
        super().__init__()
        self.app, self.hidden = app, False
        self.timer = QTimer(self); self.timer.setSingleShot(True); self.timer.timeout.connect(self.hide)
        app.installEventFilter(self)
        self.hide()

    def hide(self):
        if not self.hidden:
            self.app.setOverrideCursor(QCursor(Qt.CursorShape.BlankCursor)); self.hidden = True

    def show(self):
        if self.hidden:
            self.app.restoreOverrideCursor(); self.hidden = False
        self.timer.start(3000)

    room = None          # set once Room exists: every input is noted on it (standby waits for real idleness)

    # This Surface's touch sensor has two faulty lines (6–7 of 44 from the top) that fire phantom touches right across
    # the screen. A touch that starts there is dropped, whole, before anything sees it — so it can't wake standby,
    # close a sheet or press anything. Nothing on the screens is meant to be touched there anyway.
    GHOST = (6 / 44, 8 / 44)
    eating = False

    def eventFilter(self, obj, ev):
        t = ev.type()
        if t in (QEvent.Type.TouchBegin, QEvent.Type.TouchUpdate, QEvent.Type.TouchEnd, QEvent.Type.TouchCancel) \
                and hasattr(obj, "height") and callable(obj.height) and obj.isWindowType():
            if t == QEvent.Type.TouchBegin:
                try:
                    h = obj.height() or 1
                    pts = ev.points()
                    self.eating = bool(pts) and all(self.GHOST[0] <= p.scenePosition().y() / h <= self.GHOST[1] for p in pts)
                except Exception:
                    self.eating = False
            if self.eating:
                if t in (QEvent.Type.TouchEnd, QEvent.Type.TouchCancel):
                    self.eating = False
                return True
        # the Surface's buttons (in the panel-only session nothing else hears them): power → screen off / on,
        # volume up / down → the music (or the speaker) ±6 %
        if self.room is not None and t == QEvent.Type.KeyPress and not ev.isAutoRepeat():
            k = ev.key()
            if k in (Qt.Key.Key_PowerOff, Qt.Key.Key_PowerDown, Qt.Key.Key_Sleep, Qt.Key.Key_Suspend, Qt.Key.Key_Standby):
                self.room.power_button()
                return True
            if k in (Qt.Key.Key_VolumeUp, Qt.Key.Key_VolumeDown):
                self.room.volume_step(6 if k == Qt.Key.Key_VolumeUp else -6)
                return True
        elif self.room is not None and t == QEvent.Type.KeyPress and ev.key() in (Qt.Key.Key_VolumeUp, Qt.Key.Key_VolumeDown):
            self.room.volume_step(6 if ev.key() == Qt.Key.Key_VolumeUp else -6)      # held: keeps going
            return True
        if self.room is not None and t in (QEvent.Type.MouseMove, QEvent.Type.MouseButtonPress, QEvent.Type.Wheel,
                                           QEvent.Type.TouchBegin, QEvent.Type.TouchUpdate, QEvent.Type.KeyPress):
            import time
            self.room.input_at = time.time()
        if t in (QEvent.Type.MouseMove, QEvent.Type.MouseButtonPress, QEvent.Type.Wheel):
            dev = ev.device() if hasattr(ev, "device") else None
            if dev is None or dev.type() in (QInputDevice.DeviceType.Mouse, QInputDevice.DeviceType.TouchPad):
                self.show()
        return False


def main():
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Room")
    app.setOrganizationName("Imagined")
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    # let Python see Ctrl-C while Qt is running
    t = QTimer(); t.start(2000); t.timeout.connect(lambda: None)

    for f in (ROOT / "assets" / "fonts").glob("*.ttf"):
        QFontDatabase.addApplicationFont(str(f))

    cfg = config.load()
    room = Room(cfg)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("room", room)
    engine.rootContext().setContextProperty("shaderDir", QUrl.fromLocalFile(str(ROOT / "shaders") + "/").toString())
    engine.rootContext().setContextProperty("startScreen", os.environ.get("ROOM_SCREEN", "home"))
    engine.rootContext().setContextProperty("showDead", os.environ.get("ROOM_SHOW_DEAD") == "1")   # (checks) the dead strips, in red
    engine.rootContext().setContextProperty("shotPath", os.environ.get("ROOM_SHOT", ""))
    engine.rootContext().setContextProperty("shotMs", int(os.environ.get("ROOM_SHOT_MS", "2500")))
    engine.rootContext().setContextProperty("windowed", os.environ.get("ROOM_WINDOWED") == "1")
    engine.load(QUrl.fromLocalFile(str(ROOT / "qml" / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    win = engine.rootObjects()[0]
    pointer = Pointer(app)  # noqa: F841
    pointer.room = room

    room.start()
    code = app.exec()
    if room.mic:
        room.mic.stop()   # the sound-level reader goes with Room
    del engine          # tear the screens down before the object they read from
    sys.exit(code)


if __name__ == "__main__":
    main()
