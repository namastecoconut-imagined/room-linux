"""Knows when an iPhone has started sending a video to "Room Screen" (UxPlay, scripts/airplay-video.sh), so the panel
can say "Getting the video ready…" for the ~10 s YouTube takes before the picture comes up (the video then opens
in its own window over the panel).

Reads UxPlay's own log as it's written (journalctl -f); nothing runs if AirPlay video isn't set up.
  connection request from <phone> (…)   → who's sending
  on_video_play                          → a video is coming: show "getting ready"
  Seeking is ENABLED …                   → it's about to play: the window takes over within moments
  on_video_stop / connection lost         → stopped: nothing to show
"""
import re
import subprocess
import threading
import time
from pathlib import Path

from PySide6.QtCore import QObject, QTimer, Signal

UNIT = Path.home() / ".config" / "systemd" / "user" / "room-airplay-video.service"


class AirPlayVideo(QObject):
    changed = Signal()
    _line = Signal(str)

    def __init__(self):
        super().__init__()
        self.waiting = False          # showing "getting the video ready"
        self.sender = ""              # "Aviral's iPhone"
        self.since = 0.0
        self._line.connect(self._on_line)
        self._give_up = QTimer(self); self._give_up.setSingleShot(True)
        self._give_up.timeout.connect(lambda: self._set(False))

    def start(self):
        if UNIT.exists():
            threading.Thread(target=self._follow, daemon=True).start()

    def snapshot(self) -> dict:
        return {"waiting": self.waiting, "from": self.sender, "since": self.since}

    def _follow(self):
        while True:
            try:
                p = subprocess.Popen(["journalctl", "--user", "-u", "room-airplay-video", "-f", "-n", "0", "-o", "cat"],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
                for line in p.stdout:
                    if "on_video" in line or "connection request" in line or "Seeking is ENABLED" in line \
                            or "lost connection" in line or "Connection closed" in line or "GStreamer error" in line:
                        self._line.emit(line.strip())
            except Exception as e:
                print(f"[room] airplay video: {e!r}", flush=True)
            time.sleep(10)

    def _on_line(self, line: str):
        m = re.search(r"connection request from (.+?) \(", line)
        if m:
            self.sender = m.group(1).replace("’", "'")
        elif "on_video_play" in line:
            self._set(True)
            self._give_up.start(40000)            # never stuck on it: it goes after 40 s whatever happens
        elif "Seeking is ENABLED" in line and self.waiting:
            self._give_up.start(6000)             # playing now: the video window covers this in a moment
        elif "on_video_stop" in line or "lost connection" in line or "GStreamer error" in line:
            self._set(False)

    def _set(self, on: bool):
        if on != self.waiting:
            self.waiting = on
            self.since = time.time() if on else 0.0
            print(f"[room] airplay video: {'getting ready' if on else 'done'}", flush=True)
            self.changed.emit()
