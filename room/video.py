"""Music videos on the panel: "Alexa, play the Kesariya video" finds it on YouTube (yt-dlp) and the panel plays it
full screen (qml/VideoScreen.qml, Qt's own player — hardware decoding through FFmpeg/VA-API).

yt-dlp lives in Room's own Python packages (requirements.txt), with Deno beside it for the JavaScript YouTube now
needs. A search keeps the top few results, so "next" moves to the next one without searching again. Nothing here
runs until a video is asked for.
"""
import os
import subprocess
import sys
import threading

from PySide6.QtCore import Property, QObject, Signal, Slot


class Video(QObject):
    changed = Signal()
    _ready = Signal(object)                  # from the search thread back to Qt's

    def __init__(self, cfg: dict | None = None):
        super().__init__()
        cfg = cfg or {}
        self.max_height = int(cfg.get("videoMaxHeight", 1080))
        self._active = False
        self._loading = False
        self._paused = False
        self._info = {"title": "", "channel": "", "url": "", "error": ""}
        self.results: list[dict] = []        # the search's top hits (id, title, channel)
        self.at = 0
        self._gen = 0
        self._ready.connect(self._got)

    # ------------------------------------------------------------------ for the screen
    @Property(bool, notify=changed)
    def active(self): return self._active

    @Property(bool, notify=changed)
    def loading(self): return self._loading

    @Property(bool, notify=changed)
    def paused(self): return self._paused

    @Property(str, notify=changed)
    def title(self): return self._info["title"]

    @Property(str, notify=changed)
    def channel(self): return self._info["channel"]

    @Property(str, notify=changed)
    def url(self): return self._info["url"]

    @Property(str, notify=changed)
    def error(self): return self._info["error"]

    @Slot()
    def togglePause(self):
        self._paused = not self._paused
        self.changed.emit()

    def set_paused(self, p: bool):
        if self._active and self._paused != p:
            self._paused = p
            self.changed.emit()

    @Slot()
    def close(self):
        self._gen += 1
        self._active = self._loading = self._paused = False
        self._info = {"title": "", "channel": "", "url": "", "error": ""}
        self.results, self.at = [], 0
        self.changed.emit()

    @Slot()
    def next(self):
        if self.at + 1 < len(self.results):
            self._open(self.at + 1)

    @Slot()
    def ended(self):
        """The video finished: the next result, or close."""
        if self.at + 1 < len(self.results):
            self._open(self.at + 1)
        else:
            self.close()

    def show_file(self, path: str):
        """(checks) play a local file as if it had been found."""
        from pathlib import Path
        self._gen += 1
        self._active, self._loading, self._paused = True, False, False
        self.results, self.at = [{"id": "", "title": "Kesariya", "channel": "Arijit Singh"}], 0
        self._info = {"title": "Kesariya", "channel": "Arijit Singh", "url": Path(path).resolve().as_uri(), "error": ""}
        self.changed.emit()

    # ------------------------------------------------------------------ finding it
    def play(self, query: str, done=None):
        """Search YouTube and play the best match. done(title or None, why) once it's found (or not)."""
        self._gen += 1
        gen = self._gen
        self._active, self._loading, self._paused = True, True, False
        self._info = {"title": query, "channel": "", "url": "", "error": ""}
        self.changed.emit()

        def go():
            try:
                hits = self._search(query)
                if not hits:
                    self._ready.emit((gen, None, "nothing found", done))
                    return
                self.results = hits
                self._ready.emit((gen, (0, self._resolve(hits[0]["id"])), None, done))
            except Exception as e:
                print(f"[room] video: {e!r}", flush=True)
                self._ready.emit((gen, None, "couldn't reach YouTube", done))
        threading.Thread(target=go, daemon=True).start()

    def _open(self, i):
        self._gen += 1
        gen = self._gen
        hit = self.results[i]
        self._loading, self._paused = True, False
        self._info = {"title": hit["title"], "channel": hit["channel"], "url": "", "error": ""}
        self.changed.emit()

        def go():
            try:
                self._ready.emit((gen, (i, self._resolve(hit["id"])), None, None))
            except Exception as e:
                print(f"[room] video: {e!r}", flush=True)
                self._ready.emit((gen, None, "couldn't play that one", None))
        threading.Thread(target=go, daemon=True).start()

    def _got(self, msg):
        gen, found, why, done = msg
        if gen != self._gen:
            return                               # closed or replaced meanwhile
        self._loading = False
        if found:
            i, url = found
            self.at = i
            hit = self.results[i]
            self._info = {"title": hit["title"], "channel": hit["channel"], "url": url, "error": ""}
            print(f"[room] video: {hit['title']!r} · {hit['channel']}", flush=True)
        else:
            self._info["error"] = why or "couldn't play that"
        self.changed.emit()
        if done:
            done(self._info["title"] if found else None, why)

    def _run(self, *args) -> str:
        here = os.path.dirname(sys.executable)   # Room's venv: yt-dlp and deno live here
        env = dict(os.environ, PATH=here + os.pathsep + os.environ.get("PATH", ""))
        r = subprocess.run([os.path.join(here, "yt-dlp"), "--no-warnings", "--ignore-config", *args],
                           capture_output=True, text=True, timeout=40, env=env)
        if r.returncode != 0:
            raise RuntimeError((r.stderr or "").strip().splitlines()[-1:] or "yt-dlp failed")
        return r.stdout

    def _search(self, query: str) -> list[dict]:
        out = self._run("--flat-playlist", "--print", "%(id)s\t%(title)s\t%(channel,uploader)s",
                        f"ytsearch5:{query}")
        hits = []
        for line in out.splitlines():
            p = line.split("\t")
            if len(p) >= 2 and p[0]:
                hits.append({"id": p[0], "title": p[1], "channel": p[2] if len(p) > 2 and p[2] != "NA" else ""})
        return hits

    def _resolve(self, vid: str) -> str:
        """A single stream with picture and sound together (Qt's player plays one URL), up to videoMaxHeight."""
        h = self.max_height
        out = self._run("-f", f"best[height<={h}][vcodec!=none][acodec!=none]/best[vcodec!=none][acodec!=none]",
                        "--print", "%(url)s", f"https://www.youtube.com/watch?v={vid}")
        url = out.strip().splitlines()[-1] if out.strip() else ""
        if not url.startswith("http"):
            raise RuntimeError("no playable stream")
        return url
