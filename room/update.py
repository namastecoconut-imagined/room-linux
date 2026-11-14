"""Settings → More settings → Updates: check GitHub for a newer Room and, if there is one, update to it.

The update itself is scripts/ota.sh, started on its own (systemd-run), so it carries on while Room restarts: it runs
room-update (pull, packages, restart), then checks Room came back up; if it didn't, it goes back to the version
before and restarts that. What happened is left in ~/.local/state/room/update.json for Room to show.
"""
import json
import subprocess
import threading
import time
from pathlib import Path

from PySide6.QtCore import QObject, Qt, Signal

from .config import STATE_DIR

REPO = Path(__file__).resolve().parents[1]
RESULT = STATE_DIR / "update.json"


def git(*args, timeout=30) -> str:
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, timeout=timeout,
                          check=True).stdout.strip()


class Updater(QObject):
    changed = Signal()
    _done = Signal(dict)

    def __init__(self, demo=False, parent=None):
        super().__init__(parent)
        self.demo = demo
        self.state = {"state": "idle", "note": "", "changes": []}
        self._done.connect(self._finish, Qt.ConnectionType.QueuedConnection)
        try:
            self.version = git("log", "-1", "--format=%h · %cd", "--date=format:%-d %b")
        except Exception:
            self.version = ""
        # what the last update did (shown for a while after it)
        try:
            r = json.loads(RESULT.read_text())
            if time.time() - r.get("at", 0) < 3600:
                self.state = {"state": "done" if r.get("ok") else "back", "note": r.get("note", ""), "changes": []}
        except Exception:
            pass

    def check(self):
        if self.state["state"] in ("checking", "updating"):
            return
        self.state = {"state": "checking", "note": "Checking…", "changes": []}
        self.changed.emit()
        if self.demo:
            self._done.emit({"state": "current", "note": "Up to date", "changes": []})
            return
        threading.Thread(target=self._check, daemon=True).start()

    def _check(self):
        try:
            git("fetch", "-q", "origin", timeout=60)
            new = git("log", "--format=%s", "HEAD..@{u}").splitlines()
        except Exception:
            self._done.emit({"state": "error", "note": "Couldn't reach GitHub · try again in a bit", "changes": []})
            return
        if not new:
            self._done.emit({"state": "current", "note": "Up to date", "changes": []})
            return
        try:
            subprocess.run(["systemd-run", "--user", "--collect", "--quiet", f"--unit=room-ota-{int(time.time())}",
                            "bash", str(REPO / "scripts" / "ota.sh")], check=True, timeout=15)
        except Exception:
            self._done.emit({"state": "error", "note": "Couldn't start the update", "changes": new})
            return
        n = len(new)
        self._done.emit({"state": "updating", "note": f"Updating · {n} change{'s' if n != 1 else ''} · Room restarts in a moment",
                         "changes": new[:5]})

    def _finish(self, st):
        self.state = st
        self.changed.emit()
