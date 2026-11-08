"""Spotify Web API — the same login as the iPhone panel (config "spotify": clientId + refreshToken).
Spotify can't push changes, so we ask: every 1.5 s while playing, less when idle or on standby.
A rotated refresh token is saved in ~/.local/state/room/spotify.json so the login survives restarts."""
import json
import time

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtGui import QColor, QImage

from . import net
from .config import State
from .art import wash

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
        self.art = {"id": "", "url": "", "rgb": [40, 36, 32], "rgb2": [20, 18, 16], "wash": ""}
        self.relaxed = False
        self.ticks = 0
        self.error = ""
        self._waiting, self._refreshing, self._retry_at, self._fails = [], False, 0.0, 0
        self.next_up: list[dict] = []      # the next few songs (cover flow, right side)
        self.recent: list[dict] = []       # the last couple played (cover flow, left side)
        self.playlists: list[dict] = []
        self.context_name = ""
        self._context_uri = ""
        self._queue_for = ""
        self._devices_at = 0.0
        self._playlists_at = 0.0
        self.liked = None                  # is the current song in Liked Songs (None: unknown / not allowed)

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
        if time.time() - self._devices_at > 20:
            self.refresh_devices()
        if time.time() - self._playlists_at > 600:
            self.refresh_playlists()

    # ---- what's around the current song, and what you can play
    @staticmethod
    def _track(t: dict) -> dict:
        imgs = (t.get("album") or {}).get("images") or t.get("images") or []
        art = min(imgs, key=lambda i: abs((i.get("width") or 300) - 300))["url"] if imgs else ""
        artists = ", ".join(a.get("name", "") for a in t.get("artists", [])) or (t.get("show") or {}).get("name", "")
        return {"title": t.get("name", ""), "artist": artists, "art": art, "uri": t.get("uri", "")}

    def _refresh_around(self):
        def q(status, data):
            if status != 200: return
            try:
                obj = json.loads(data)
                self.next_up = [self._track(t) for t in (obj.get("queue") or [])[:4] if t]
                self.changed.emit()
            except Exception:
                pass
        self._api("GET", "/me/player/queue", q)

        def r(status, data):
            if status != 200: return
            try:
                cur = ((self.player or {}).get("item") or {}).get("uri")
                items = [self._track(i["track"]) for i in json.loads(data).get("items", []) if i.get("track")]
                self.recent = [t for t in items if t["uri"] != cur][:2]
                self.changed.emit()
            except Exception:
                pass
        self._api("GET", "/me/player/recently-played?limit=4", r)

        ctx = (self.player or {}).get("context") or {}
        uri = ctx.get("uri", "")
        if uri != self._context_uri:
            self._context_uri, self.context_name = uri, ""
            kind = uri.split(":")[1] if uri.count(":") >= 2 else ""
            if kind in ("playlist", "album", "artist", "show"):
                def n(status, data, uri=uri):
                    if status == 200 and uri == self._context_uri:
                        try:
                            self.context_name = json.loads(data).get("name", ""); self.changed.emit()
                        except Exception:
                            pass
                self._api("GET", f"/{kind}s/{uri.split(':')[-1]}?fields=name", n)
            elif kind == "collection":
                self.context_name = "Liked Songs"

    def _refresh_liked(self, tid):
        self.liked = None
        if not tid:
            return
        def got(status, data, tid=tid):
            if status == 200 and ((self.player or {}).get("item") or {}).get("id") == tid:
                try:
                    self.liked = bool(json.loads(data)[0]); self.changed.emit()
                except Exception:
                    pass
        self._api("GET", f"/me/tracks/contains?ids={tid}", got)

    def toggle_liked(self):
        tid = ((self.player or {}).get("item") or {}).get("id")
        if not tid or self.liked is None:
            return
        self.liked = not self.liked
        self.changed.emit()
        self._api("PUT" if self.liked else "DELETE", f"/me/tracks?ids={tid}")

    def refresh_devices(self):
        self._devices_at = time.time()
        def got(status, data):
            if status != 200: return
            try:
                self.devices = [{"id": d.get("id"), "name": d.get("name", ""), "type": d.get("type", ""),
                                 "active": bool(d.get("is_active"))} for d in json.loads(data).get("devices", []) if d.get("id")]
                self.changed.emit()
            except Exception:
                pass
        self._api("GET", "/me/player/devices", got)

    def refresh_playlists(self):
        self._playlists_at = time.time()
        def got(status, data):
            if status != 200: return
            try:
                out = []
                for p in json.loads(data).get("items", []):
                    if not p: continue
                    imgs = p.get("images") or []
                    out.append({"name": p.get("name", ""), "uri": p.get("uri", ""),
                                "art": (min(imgs, key=lambda i: abs((i.get("width") or 300) - 300))["url"] if imgs else "")})
                self.playlists = out[:12]
                self.changed.emit()
            except Exception:
                pass
        self._api("GET", "/me/playlists?limit=20", got)

    def _update_art(self):
        item = (self.player or {}).get("item") or {}
        tid = item.get("id") or item.get("uri") or item.get("name", "")
        if not tid or tid == self.art["id"]:
            return
        imgs = (item.get("album") or {}).get("images") or (item.get("images") or [])
        url = min(imgs, key=lambda i: abs((i.get("width") or 640) - 640))["url"] if imgs else ""
        self.art = {"id": tid, "url": url, "rgb": self.art["rgb"], "rgb2": self.art["rgb2"], "wash": self.art.get("wash", "")}
        self._refresh_around()
        self._refresh_liked(item.get("id"))
        small = min(imgs, key=lambda i: abs((i.get("width") or 64) - 64))["url"] if imgs else ""
        if small:
            def got(status, data, tid=tid):
                if status != 200 or self.art["id"] != tid:
                    return
                img = QImage.fromData(data)
                if img.isNull():
                    return
                self.art["rgb"], self.art["rgb2"] = colours(img)
                self.art["wash"], self.art["rgb"] = wash(img)
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
            "wash": self.art.get("wash", ""),
            "error": self.error,
            "source": "spotify",
            "liked": self.liked,
            "context": self.context_name,
            "nextUp": self.next_up,
            "recent": self.recent,
            "playlists": self.playlists,
            "devices": self.devices,
            "canVolume": bool(dev.get("supports_volume", True)) and dev.get("volume_percent") is not None,
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

    def transfer(self, device_id: str):
        self._api("PUT", "/me/player", lambda *_: (self.refresh_devices(), self._soon()), {"device_ids": [device_id], "play": True})

    def play_uri(self, uri: str, speaker: str | None = None):
        body = {"context_uri": uri} if ":track:" not in uri else {"uris": [uri]}
        dev = self.device_named(speaker) if speaker else None
        def done(status, data):
            if status == 404:   # nothing active to play on — wake the last speaker we saw
                if self.devices:
                    self._api("PUT", f"/me/player/play?device_id={self.devices[0]['id']}", self._soon, body)
            else:
                self._soon()
        self._api("PUT", "/me/player/play" + (f"?device_id={dev['id']}" if dev else ""), done, body)

    def device_named(self, name: str):
        """The closest speaker to a spoken name ('desk speaker' → 'Desk Speaker (Echo)')."""
        n = (name or "").lower()
        best, score = None, 0
        for d in self.devices:
            dn = d["name"].lower()
            sc = 3 if dn == n else 2 if n in dn or dn in n else len(set(n.split()) & set(dn.split())) / 4
            if sc > score:
                best, score = d, sc
        return best

    def play_search(self, query: str, kind: str | None, speaker: str | None, done):
        """Search Spotify and play the best match: a track plays with its album after it, an artist plays their top
        songs, a playlist or album plays from the start. done(name or None, why)."""
        from urllib.parse import quote
        kind = kind if kind in ("track", "artist", "album", "playlist") else "track"
        def got(status, data):
            if status != 200:
                done(None, "spotify search failed"); return
            try:
                items = (json.loads(data).get(kind + "s") or {}).get("items") or []
                it = next((i for i in items if i), None)
            except Exception:
                it = None
            if not it:
                done(None, "nothing found"); return
            uri, name = it.get("uri", ""), it.get("name", "")
            self.play_uri(uri, speaker=speaker)
            done(name, None)
        self._api("GET", f"/search?q={quote(query)}&type={kind}&limit=3&market=from_token", got)

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
