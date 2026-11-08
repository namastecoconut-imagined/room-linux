"""Spotify Web API — the same login as the iPhone panel (config "spotify": clientId + refreshToken).
Spotify can't push changes, so we ask: every 1.5 s while playing, less when idle or on standby.
A rotated refresh token is saved in ~/.local/state/room/spotify.json so the login survives restarts."""
import json
import time

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtGui import QColor, QImage

from . import net
from .config import State

API = "https://api.spotify.com/v1"


class Spotify(QObject):
    changed = Signal()

    def __init__(self, cfg: dict | None):
        super().__init__()
        cfg = cfg or {}
        self.client_id = cfg.get("clientId", "")
        self.store = State("spotify")
        saved = self.store.read()
        # a newer token we were handed beats the one in config.json, as long as config hasn't changed since
        self.refresh_token = saved.get("refreshToken") if saved.get("from") == cfg.get("refreshToken") else cfg.get("refreshToken", "")
        self.cfg_token = cfg.get("refreshToken", "")
        self.token, self.expiry = None, 0.0
        self.player: dict | None = None
        self.fetched_at = 0.0
        self.devices: list[dict] = []
        self.art = {"id": "", "url": "", "rgb": [40, 36, 32], "rgb2": [20, 18, 16]}
        self.relaxed = False
        self.ticks = 0
        self.error = ""
        self._waiting, self._refreshing, self._retry_at, self._fails = [], False, 0.0, 0

    @property
    def enabled(self):
        return bool(self.client_id and self.refresh_token)

    def start(self):
        if not self.enabled:
            return
        self.poll()
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(1500)

    def _tick(self):
        self.ticks += 1
        playing = bool(self.player and self.player.get("is_playing"))
        every = (4 if playing else 8) if self.relaxed else (1 if playing else 2)
        if self.ticks % every == 0:
            self.poll()

    # ---- auth
    def _with_token(self, use):
        if self.token and time.time() < self.expiry:
            return use(self.token)
        if time.time() < self._retry_at:
            return use(None)
        self._waiting.append(use)
        if self._refreshing:
            return
        self._refreshing = True

        def done(status, data):
            self._refreshing = False
            tok = None
            try:
                obj = json.loads(data) if data else {}
            except Exception:
                obj = {}
            if obj.get("access_token"):
                tok = self.token = obj["access_token"]
                self.expiry = time.time() + float(obj.get("expires_in", 3600)) - 60
                self.error, self._fails = "", 0
            else:
                self.error = "Spotify login expired — run tools/spotify_token.py again" if obj else "Couldn't reach Spotify"
            if obj.get("refresh_token"):
                self.refresh_token = obj["refresh_token"]
                self.store.write({"refreshToken": self.refresh_token, "from": self.cfg_token})
            if not tok:
                self._fails += 1
                self._retry_at = time.time() + min(1800, 15 * 2 ** min(self._fails, 7))
            w, self._waiting = self._waiting, []
            for f in w:
                f(tok)

        net.request("POST", "https://accounts.spotify.com/api/token", done,
                    {"Content-Type": "application/x-www-form-urlencoded"},
                    net.form({"grant_type": "refresh_token", "refresh_token": self.refresh_token, "client_id": self.client_id}))

    def _api(self, method, path, done=None, body=None):
        def go(tok):
            if not tok:
                if done: done(0, b"")
                return
            h = {"Authorization": f"Bearer {tok}"}
            if body is not None:
                h["Content-Type"] = "application/json"
            net.request(method, API + path, done, h, json.dumps(body).encode() if body is not None else None)
        self._with_token(go)

    # ---- state
    def poll(self):
        def got(status, data):
            if status == 204:
                self.player = None
            elif status == 200:
                try:
                    self.player = json.loads(data)
                    self.fetched_at = time.time()
                    self._update_art()
                except Exception:
                    pass
            self.changed.emit()
        self._api("GET", "/me/player?additional_types=episode", got)

    def _update_art(self):
        item = (self.player or {}).get("item") or {}
        tid = item.get("id") or item.get("uri") or item.get("name", "")
        if not tid or tid == self.art["id"]:
            return
        imgs = (item.get("album") or {}).get("images") or (item.get("images") or [])
        url = min(imgs, key=lambda i: abs((i.get("width") or 640) - 640))["url"] if imgs else ""
        self.art = {"id": tid, "url": url, "rgb": self.art["rgb"], "rgb2": self.art["rgb2"]}
        small = min(imgs, key=lambda i: abs((i.get("width") or 64) - 64))["url"] if imgs else ""
        if small:
            def got(status, data, tid=tid):
                if status != 200 or self.art["id"] != tid:
                    return
                img = QImage.fromData(data)
                if img.isNull():
                    return
                self.art["rgb"], self.art["rgb2"] = colours(img)
                self.changed.emit()
            net.request("GET", small, got)

    def snapshot(self) -> dict:
        p = self.player or {}
        item = p.get("item") or {}
        artists = ", ".join(a.get("name", "") for a in item.get("artists", [])) or (item.get("show") or {}).get("name", "")
        dur = (item.get("duration_ms") or 0) / 1000
        pos = (p.get("progress_ms") or 0) / 1000
        dev = p.get("device") or {}
        return {
            "enabled": self.enabled,
            "exists": bool(item),
            "playing": bool(p.get("is_playing")),
            "title": item.get("name", ""),
            "artist": artists,
            "album": (item.get("album") or {}).get("name", ""),
            "duration": dur,
            "position": pos,
            "at": self.fetched_at,
            "device": dev.get("name", ""),
            "volume": dev.get("volume_percent", 0) if dev.get("volume_percent") is not None else 0,
            "art": self.art["url"],
            "rgb": self.art["rgb"],
            "rgb2": self.art["rgb2"],
            "error": self.error,
        }

    # ---- commands
    def _soon(self, *_):
        QTimer.singleShot(350, self.poll)

    def play_pause(self):
        playing = bool(self.player and self.player.get("is_playing"))
        if self.player:
            self.player["is_playing"] = not playing
            self.changed.emit()
        self._api("PUT", "/me/player/pause" if playing else "/me/player/play", self._soon)

    def next(self):
        self._api("POST", "/me/player/next", self._soon)

    def previous(self):
        self._api("POST", "/me/player/previous", self._soon)

    def seek(self, seconds: float):
        self._api("PUT", f"/me/player/seek?position_ms={int(seconds * 1000)}", self._soon)

    def set_volume(self, pct: int):
        pct = max(0, min(100, int(pct)))
        if self.player and self.player.get("device"):
            self.player["device"]["volume_percent"] = pct
        self._api("PUT", f"/me/player/volume?volume_percent={pct}")


def colours(img: QImage):
    """Two colours from the cover: the strongest well-lit colour, and a deep one for the background."""
    img = img.scaled(24, 24).convertToFormat(QImage.Format.Format_RGB32)
    best, best_score, total, n = (60, 54, 48), -1.0, [0, 0, 0], 0
    for y in range(img.height()):
        for x in range(img.width()):
            c = QColor(img.pixel(x, y))
            r, g, b = c.red(), c.green(), c.blue()
            total[0] += r; total[1] += g; total[2] += b; n += 1
            h, s, v, _ = c.getHsvF()
            score = s * 0.7 + (1 - abs(v - 0.65)) * 0.3
            if v > 0.25 and score > best_score:
                best, best_score = (r, g, b), score
    avg = [int(t / max(n, 1)) for t in total]
    deep = [int(c * 0.35) for c in avg]
    return list(best), deep
