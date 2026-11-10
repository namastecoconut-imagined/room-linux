"""Reads config.json — the same file the iPhone panel uses, so rooms, Spotify and the calendar carry over as-is.

Looked for in this order: $ROOM_CONFIG, ~/.config/room/config.json, ./config.json.
Things the panel learns while running (a rotated Spotify token, the last forecast) go in ~/.local/state/room/.
"""
import json
import os
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "room"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "room"

DEFAULTS = {
    "here": "",
    "rooms": [],
    "location": {"lat": 12.9716, "lon": 77.5946},
    "clock24": False,
    "nightStart": 23,
    "nightEnd": 7,
    "dayBrightness": 0.55,
    "nightBrightness": 0.3,
    "idleReturnSec": 60,
}


def find_config() -> Path | None:
    for p in (os.environ.get("ROOM_CONFIG"), CONFIG_DIR / "config.json", Path.cwd() / "config.json"):
        if p and Path(p).is_file():
            return Path(p)
    return None


def load() -> dict:
    cfg = dict(DEFAULTS)
    p = find_config()
    if p:
        try:
            cfg.update(json.loads(p.read_text()))
        except Exception as e:  # a typo in config.json shouldn't stop the panel from starting
            print(f"[room] config.json couldn't be read ({e}) — starting with defaults")
    else:
        print("[room] no config.json found — copy yours to ~/.config/room/config.json")
    return cfg


class State:
    """A small JSON file for things the panel keeps between restarts."""

    def __init__(self, name: str):
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.path = STATE_DIR / f"{name}.json"

    def read(self) -> dict:
        try:
            return json.loads(self.path.read_text())
        except Exception:
            return {}

    def write(self, data: dict) -> None:
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data))
        tmp.replace(self.path)
