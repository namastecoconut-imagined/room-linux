"""Spotify Web API — the same login as the iPhone panel (config "spotify": clientId + refreshToken).
Spotify can't push changes, so we ask: every 1.5 s while playing, less when idle or on standby.
A rotated refresh token is saved in ~/.local/state/room/spotify.json so the login survives restarts."""
import json
import time

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtGui import QColor, QImage

from . import net
from .config import State
from .art import field, wash

API = "https://api.spotify.com/v1"


class Spotify(QObject):
    changed = Signal()

    def __init__(self, cfg: dict | None):
        super().__init__()
        cfg = cfg or {}
        self.client_id = cfg.get("clientId", "")
        # the Surface's own Spotify speaker (scripts/spotify-connect.sh): where "play …" goes when nothing else is playing
        self.home = (cfg.get("homeDevice") or "Room").lower()
        self.store = State("spotify")
        saved = self.store.read()
        # a newer token we were handed beats the one in config.json, as long as config hasn't changed since
        self.refresh_token = saved.get("refreshToken") if saved.get("from") == cfg.get("refreshToken") else cfg.get("refreshToken", "")
        self.cfg_token = cfg.get("refreshToken", "")
        # (timing by time.monotonic(): the wall clock can jump hours at start-up on this Surface, which once left an
        # expired login looking valid — and the queue, playlists and speakers all quietly stopped)
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
        # the home card's shortcuts when nothing's playing: Liked Songs, and what you last played (kept across restarts)
        self.user_id = ""
        self.idle_after = 60.0             # paused this long: the home card goes back to its shortcuts
        self._paused_at = 0.0
        self.last_store = State("spotify-last")
        self.last: dict = self.last_store.read()        # {name, art, uri, kind}

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
        # (1.5 s ticks) awake and playing: every 1.5 s (so a new song and its cover show quickly); on standby every 9 s;
        # nothing playing: 6 s / 30 s — each poll is a request to Spotify, and the radio costs battery
        every = (6 if playing else 20) if self.relaxed else (1 if playing else 4)
        if self.ticks % every == 0:
            self.poll()

    # ---- auth
    def _with_token(self, use):
        if self.token and time.monotonic() < self.expiry:
            return use(self.token)
        if time.monotonic() < self._retry_at:
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
                self.expiry = time.monotonic() + float(obj.get("expires_in", 3600)) - 60
                self.error, self._fails = "", 0
            else:
                self.error = "Spotify login expired — sign in to Spotify again (refreshToken in config.json)" if obj else "Couldn't reach Spotify"
            if obj.get("refresh_token"):
                self.refresh_token = obj["refresh_token"]
                self.store.write({"refreshToken": self.refresh_token, "from": self.cfg_token})
            if not tok:
                self._fails += 1
                self._retry_at = time.monotonic() + min(1800, 15 * 2 ** min(self._fails, 7))
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

            def back(status, data):
                if status == 401 and self.token == tok:
                    self.token, self.expiry = None, 0.0      # turned down: log in again on the next call
                if method != "GET" and (status == 0 or status >= 300):     # a command Spotify didn't carry out: say why
                    why = ""
                    try:
                        why = (json.loads(data or b"{}").get("error") or {}).get("message", "")
                    except Exception:
                        pass
                    print(f"[room] spotify: {method} {path.split('?')[0]} didn't work — {status or 'no answer'}"
                          + (f" · {why}" if why else ""), flush=True)
                if done:
                    done(status, data)
            net.request(method, API + path, back, h, json.dumps(body).encode() if body is not None else None)
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
                    if self.player.get("is_playing"):
                        self._paused_at = 0.0
                    elif not self._paused_at:
                        self._paused_at = time.monotonic()
                    self._update_art()
                except Exception:
                    pass
            self.changed.emit()
        self._api("GET", "/me/player?additional_types=episode", got)
        if time.monotonic() - self._devices_at > 20:
            self.refresh_devices()
        if time.monotonic() - self._playlists_at > (600 if self.playlists else 30):
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
                def n(status, data, uri=uri, kind=kind):
                    if status == 200 and uri == self._context_uri:
                        try:
                            obj = json.loads(data)
                            self.context_name = obj.get("name", "")
                            imgs = obj.get("images") or []
                            art = min(imgs, key=lambda i: abs((i.get("width") or 300) - 300))["url"] if imgs else ""
                            self._remember_last({"name": self.context_name, "art": art, "uri": uri, "kind": kind})
                            self.changed.emit()
                        except Exception:
                            pass
                self._api("GET", f"/{kind}s/{uri.split(':')[-1]}" + ("?fields=name,images" if kind == "playlist" else ""), n)
            elif kind == "collection":
                self.context_name = "Liked Songs"
            elif not uri:
                # a song on its own (no playlist or album around it): that's what you last played
                item = (self.player or {}).get("item") or {}
                if item.get("uri"):
                    t = self._track(item)
                    self._remember_last({"name": t["title"], "art": t["art"], "uri": t["uri"], "kind": "song"})

    def _remember_last(self, last: dict):
        if last.get("uri") and last != self.last:
            self.last = last
            try:
                self.last_store.write(last)
            except Exception:
                pass

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

    def refresh_devices(self, then=None):
        self._devices_at = time.monotonic()
        def got(status, data):
            if status == 200:
                try:
                    self.devices = [{"id": d.get("id"), "name": d.get("name", ""), "type": d.get("type", ""),
                                     "active": bool(d.get("is_active"))} for d in json.loads(data).get("devices", []) if d.get("id")]
                    self.changed.emit()
                except Exception:
                    pass
            if then:
                then()
        self._api("GET", "/me/player/devices", got)

    def refresh_playlists(self):
        self._playlists_at = time.monotonic()
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
        self.art = {"id": tid, "url": url, "rgb": self.art["rgb"], "rgb2": self.art["rgb2"], "wash": self.art.get("wash", ""),
                    "field": self.art.get("field", {})}
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
                self.art["field"] = field(img)
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
            "field": self.art.get("field", {}),
            "error": self.error,
            "source": "spotify",
            "liked": self.liked,
            "context": self.context_name,
            "nextUp": self.next_up,
            "recent": self.recent,
            "playlists": self.playlists,
            "last": self.last,
            "idle": bool(item) and not p.get("is_playing") and bool(self._paused_at)
                    and time.monotonic() - self._paused_at > self.idle_after,
            "devices": self.devices,
            "canVolume": bool(dev.get("supports_volume", True)) and dev.get("volume_percent") is not None,
        }

    # ---- commands
    def _soon(self, *_):
        for ms in (350, 1200, 2500):
            QTimer.singleShot(ms, self.poll)

    def play_pause(self):
        playing = bool(self.player and self.player.get("is_playing"))
        if self.player:
            self.player["is_playing"] = not playing
            self.changed.emit()
        self._api("PUT", "/me/player/pause" if playing else "/me/player/play", self._soon)

    def pause(self):
        if self.player:
            self.player["is_playing"] = False
            self.changed.emit()
        self._api("PUT", "/me/player/pause", self._soon)

    def next(self):
        self._api("POST", "/me/player/next", self._soon)

    def previous(self):
        self._api("POST", "/me/player/previous", self._soon)

    def seek(self, seconds: float):
        self._api("PUT", f"/me/player/seek?position_ms={int(seconds * 1000)}", self._soon)

    def transfer(self, device_id: str):
        self._api("PUT", "/me/player", lambda *_: (self.refresh_devices(), self._soon()), {"device_ids": [device_id], "play": True})

    def home_device(self):
        """The Surface itself as a Spotify speaker, if it's running and logged in."""
        return next((d for d in self.devices if d["name"].lower() == self.home), None)

    def play_uri(self, uri: str, speaker: str | None = None, then=None, uris: list | None = None, fallback=None):
        """Play a playlist / album / artist (context) or a song — or a list of songs (uris). Where: the speaker named,
        else whatever's playing, else the Surface itself (its Spotify speaker), else the last speaker seen.
        Every failure is logged; fallback() runs if Spotify won't play it at all."""
        body = {"uris": uris} if uris else ({"context_uri": uri} if ":track:" not in uri else {"uris": [uri]})
        dev = self.device_named(speaker) if speaker else None
        if not dev and not (self.player or {}).get("is_playing"):
            dev = self.home_device()    # nothing playing anywhere: play here, on the Surface
        what = uri or f"{len(uris or [])} songs"

        def finish():
            then() if then else self._soon()

        def failed(status, data, where):
            print(f"[room] spotify: couldn't play {what} {where}: {status} {(data or b'')[:200]!r}", flush=True)
            if fallback:
                fallback()

        def retry(status, data):
            if 200 <= status < 300:
                finish()
            else:
                failed(status, data, "(second try)")

        def done(status, data):
            if 200 <= status < 300:
                finish()
            elif status == 404:
                # nothing active to play on: look again for speakers (the Surface's may have just come up), then try
                def got_devices(*_):
                    d = self.home_device() or (self.devices[0] if self.devices else None)
                    if d:
                        self._api("PUT", f"/me/player/play?device_id={d['id']}", retry, body)
                    else:
                        failed(status, data, "(no speaker: is Spotify running on the Surface or your phone?)")
                self.refresh_devices(got_devices)
            else:
                failed(status, data, f"on {dev['name'] if dev else 'the active speaker'}")
        self._api("PUT", "/me/player/play" + (f"?device_id={dev['id']}" if dev else ""), done, body)

    def play_liked(self):
        """Liked Songs, shuffled. Spotify's own "Liked Songs" collection if it'll take it; if not, the 50 most recently
        liked, shuffled here."""
        print("[room] spotify: Liked Songs", flush=True)
        import random
        shuffle = lambda: self._api("PUT", "/me/player/shuffle?state=true", self._soon)

        def from_tracks():
            def got(status, data):
                try:
                    uris = [i["track"]["uri"] for i in json.loads(data).get("items", []) if i.get("track")] if status == 200 else []
                except Exception:
                    uris = []
                if not uris:
                    print(f"[room] spotify: couldn't read Liked Songs: {status}", flush=True)
                    return
                random.shuffle(uris)
                self.play_uri("", uris=uris)
            self._api("GET", "/me/tracks?limit=50", got)

        def go(uid):
            if not uid:
                from_tracks()
                return
            self.play_uri(f"spotify:user:{uid}:collection", then=shuffle, fallback=from_tracks)
        if self.user_id:
            go(self.user_id)
        else:
            def me(status, data):
                try:
                    self.user_id = json.loads(data).get("id", "") if status == 200 else ""
                except Exception:
                    self.user_id = ""
                if not self.user_id:
                    print(f"[room] spotify: couldn't read your account: {status}", flush=True)
                go(self.user_id)
            self._api("GET", "/me", me)

    def play_last(self):
        """Whatever you last played — picks up where it was if Spotify still remembers."""
        if self.last.get("uri"):
            self.play_uri(self.last["uri"])

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
        tries = [f"/search?q={quote(query)}&type={kind}&limit=5&market=from_token", f"/search?q={quote(query)}&type={kind}&limit=5"]

        def got(status, data):
            if status != 200:
                print(f"[room] spotify search {status}: {bytes(data or b'')[:200]!r}", flush=True)
                if tries:                     # (once more without the market — some apps' searches refuse it)
                    self._api("GET", tries.pop(), got); return
                done(None, f"spotify search failed ({status})"); return
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
        self._api("GET", tries.pop(0), got)

    def set_volume(self, pct: int):
        pct = max(0, min(100, int(pct)))
        if self.player and self.player.get("device"):
            self.player["device"]["volume_percent"] = pct
        def done(status, data):
            if status not in (200, 202, 204):
                print(f"[room] spotify volume {pct}: {status} {bytes(data or b'')[:160]!r}", flush=True)
        self._api("PUT", f"/me/player/volume?volume_percent={pct}", done)


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
