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

ROOT = Path(__file__).resolve().parent.parent

# Wayland first (Fedora's default), with the GPU scene graph; fall back to X11 if Wayland isn't there.
os.environ.setdefault("QT_QPA_PLATFORM", "wayland;xcb")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import QTimer, QUrl, Qt  # noqa: E402
from PySide6.QtGui import QFontDatabase, QGuiApplication, QCursor  # noqa: E402
from PySide6.QtQml import QQmlApplicationEngine  # noqa: E402

from .backend import Room  # noqa: E402
from . import config  # noqa: E402


def main():
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Room")
    app.setOrganizationName("Imagined")
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    # let Python see Ctrl-C while Qt is running
    t = QTimer(); t.start(500); t.timeout.connect(lambda: None)

    for f in (ROOT / "assets" / "fonts").glob("*.ttf"):
        QFontDatabase.addApplicationFont(str(f))

    cfg = config.load()
    room = Room(cfg)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("room", room)
    engine.rootContext().setContextProperty("shaderDir", QUrl.fromLocalFile(str(ROOT / "shaders") + "/").toString())
    engine.rootContext().setContextProperty("startScreen", os.environ.get("ROOM_SCREEN", "home"))
    engine.rootContext().setContextProperty("shotPath", os.environ.get("ROOM_SHOT", ""))
    engine.rootContext().setContextProperty("shotMs", int(os.environ.get("ROOM_SHOT_MS", "2500")))
    engine.rootContext().setContextProperty("windowed", os.environ.get("ROOM_WINDOWED") == "1")
    engine.load(QUrl.fromLocalFile(str(ROOT / "qml" / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    win = engine.rootObjects()[0]
    if os.environ.get("ROOM_WINDOWED") != "1":
        app.setOverrideCursor(QCursor(Qt.CursorShape.BlankCursor))   # a touch panel: no mouse pointer

    room.start()
    code = app.exec()
    del engine          # tear the screens down before the object they read from
    sys.exit(code)


if __name__ == "__main__":
    main()
