"""The song's words, timed to it, from LRCLIB (lrclib.net: free, no key) — for the lyric sheet on music standby, the
player and Home (Lyrics.qml). Only timed lyrics are used: words that can't follow the song aren't shown, and the
screens stay as they are.

Each song is looked up once and kept on disk (~/.local/state/room/lyrics/), found or not — a song with no lyrics
isn't asked about again for three days. LRCLIB asks for a User-Agent and a light touch (one look per song is that).
"""
import hashlib
import json
import re
import time
from urllib.parse import urlencode

from PySide6.QtCore import QObject, QTimer, Signal

from . import net
from .config import STATE_DIR

API = "https://lrclib.net/api/"
AGENT = "Room panel v1.0 (https://github.com/namastecoconut-imagined/room-linux)"
DIR = STATE_DIR / "lyrics"
RETRY_NONE = 3 * 86400           # a song LRCLIB didn't have: ask again after this
SMALL = {"and", "the", "a", "an", "of", "to", "in", "on", "at", "but", "or", "so"}
ASKING = 3                       # how songs are looked up (a miss saved by an older way is asked again)
RETRY_FAIL = 120                 # no answer at all (offline): try again after this


def parse(lrc: str) -> list[dict]:
    """LRC ("[01:02.34] words") → [{t, text}] in time order; a blank line is a gap in the singing (text "")."""
    out = []
    for raw in (lrc or "").splitlines():
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", raw)
        if not stamps:
            continue
        text = re.sub(r"\[[^\]]*\]", "", raw).strip()
        for mm, ss in stamps:
            out.append({"t": round(int(mm) * 60 + float(ss), 2), "text": text})
    out.sort(key=lambda l: l["t"])
    return out


def hook(text: str) -> str:
    """The words a line lands on, written big over it: its last two words (one, if the last is long), without a
    trailing "(oh)" or punctuation. Returned exactly as they appear in the line, so the screen can find them."""
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]\s*$", "", text).rstrip(" ,.;:!?…-–—\"'")
    words = t.split()
    if not words:
        return ""
    last = re.sub(r"[^\w']", "", words[-1])
    pick = words[-1:] if len(last) >= 7 or len(words) == 1 else words[-2:]
    if len(pick) == 2 and (len(" ".join(pick)) > 16 or pick[0].lower() in SMALL):
        pick = words[-1:]
    return " ".join(pick)


def shape(lines: list[dict]) -> list[dict]:
    """[{t, text}] → the sung lines only, each with when it ends (the next line or gap) and its hook."""
    out = []
    for i, l in enumerate(lines):
        if not l["text"]:
            continue
        end = lines[i + 1]["t"] if i + 1 < len(lines) else l["t"] + 6
        out.append({"t": l["t"], "end": end, "text": l["text"], "hook": hook(l["text"])})
    return out


class Lyrics(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.key = ""                # the song asked about ("title|artist")
        self.lines: list[dict] = []
        self.state = "none"          # none · looking · ok
        self._asking = ""

    def snapshot(self) -> dict:
        return {"key": self.key, "state": self.state, "lines": self.lines}

    def want(self, title: str, artist: str, album: str = "", duration: float = 0):
        """The song now playing (call on every change; only a new song does anything)."""
        key = f"{title}|{artist}"
        if not title or not artist or key == self.key:
            return
        self.key, self.lines, self.state = key, [], "looking"
        self.changed.emit()
        saved = self._read(key)
        if saved is not None and (saved.get("lines") or (saved.get("v") == ASKING
                                                         and time.time() - saved.get("at", 0) < saved.get("retry", RETRY_NONE))):
            self._use(key, saved.get("lines") or [], cached=True)
            return
        self._ask(key, title, artist, album, duration)

    # ---------------------------------------------------------------- LRCLIB
    # Asked in turn until one has timed lyrics: exactly as playing (title, artist, album, length); the plain title
    # and the main artist, with the length and without (Spotify says "Jimmy Cooks (feat. 21 Savage)" by "Drake, 21 Savage", AirPlay can say
    # "Drake & 21 Savage"); a search by those two; a free search with both. A search answer is long for a famous
    # song (hundreds of versions), so the answers get time.
    def _ask(self, key, title, artist, album, duration):
        self._asking = key
        self._args = (key, title, artist, album, duration)
        plain = re.split(r"\s+-\s+", re.sub(r"\s*[\(\[](feat|with|ft)\.?[^\)\]]*[\)\]]", "", title, flags=re.I))[0].strip() or title
        main = re.split(r"\s*(?:,|&|\band\b|\bx\b|\bfeat\.?|\bft\.?|\bwith\b)\s*", artist, flags=re.I)[0].strip() or artist
        dur = int(round(duration)) if duration and 1 <= duration <= 3600 else 0
        steps = [("get", {"track_name": title, "artist_name": artist, "album_name": album, "duration": dur}),
                 ("get", {"track_name": plain, "artist_name": main, "duration": dur}),
                 ("get", {"track_name": plain, "artist_name": main}),
                 ("search", {"track_name": plain, "artist_name": main}),
                 ("search", {"q": f"{plain} {main}"})]
        seen, todo = set(), []
        for kind, p in steps:
            p = {k: v for k, v in p.items() if v}
            sig = kind + urlencode(sorted(p.items()))
            if sig not in seen:
                seen.add(sig); todo.append((kind, p))
        self._try(key, todo, 0, main, dur, offline=False)

    def _try(self, key, todo, i, main, dur, offline):
        if key != self._asking:
            return
        if i >= len(todo):
            return self._done(key, None, 0 if offline else 404)
        kind, p = todo[i]
        def answered(status, data):
            if status == 429:                  # asked too often: not a miss — ask again in a while
                print("[room] lyrics: LRCLIB says too many requests — trying again in 2 min", flush=True)
                return self._done(key, None, 0)
            off = offline or status == 0 or status >= 500
            found = None
            if status == 200:
                try:
                    found = json.loads(data)
                except Exception:
                    found = None
            hit = self._pick(found, main, dur) if kind == "search" else \
                  found if found and (found.get("syncedLyrics") or found.get("instrumental")) else None
            if hit:
                print(f"[room] lyrics: found by {kind} {i + 1} of {len(todo)} ({hit.get('trackName')} · {hit.get('artistName')})", flush=True)
                return self._done(key, hit, 200)
            self._try(key, todo, i + 1, main, dur, off)
        net.request("GET", API + kind + "?" + urlencode(p), answered, {"User-Agent": AGENT}, timeout_ms=30000)

    @staticmethod
    def _pick(found, main, dur):
        """From a search: a version with timed lyrics, by the main artist, as long as the song (closest, within
        6 s) — or, the length not known, the first."""
        if not isinstance(found, list):
            return None
        m = main.lower()
        ok = [f for f in found if f.get("syncedLyrics") and (m in (f.get("artistName") or "").lower()
                                                            or (f.get("artistName") or "").lower() in m)]
        if dur:
            near = sorted((abs((f.get("duration") or 0) - dur), n, f) for n, f in enumerate(ok) if f.get("duration"))
            if near and near[0][0] <= 6:
                return near[0][2]
        return ok[0] if ok and not dur else None

    def _done(self, key, found: dict | None, status: int):
        if key != self._asking:
            return
        lines = shape(parse(found.get("syncedLyrics") or "")) if found and not found.get("instrumental") else []
        offline = status == 0 or status >= 500
        self._write(key, {"at": time.time(), "v": ASKING, "lines": lines, "retry": RETRY_FAIL if offline and not found else RETRY_NONE})
        print(f"[room] lyrics: {key.replace('|', ' · ')} → " + (f"{len(lines)} timed lines" if lines else
              "instrumental" if found and found.get("instrumental") else "no answer (offline?)" if offline else "none"), flush=True)
        self._use(key, lines)
        if offline and not found:              # (no answer: ask again in a while, if it's still the song playing)
            QTimer.singleShot(RETRY_FAIL * 1000, lambda: key == self.key and self.state == "none" and self._ask(*self._args))

    def _use(self, key, lines, cached=False):
        if key != self.key:
            return
        self.lines, self.state = lines, "ok" if lines else "none"
        if cached:
            print(f"[room] lyrics: {key.replace('|', ' · ')} → " + (f"{len(lines)} timed lines (kept)" if lines else "none (kept)"), flush=True)
        self.changed.emit()

    # ---------------------------------------------------------------- kept on disk
    @staticmethod
    def _file(key):
        return DIR / (hashlib.sha1(key.lower().encode()).hexdigest()[:16] + ".json")

    def _read(self, key):
        try:
            return json.loads(self._file(key).read_text())
        except Exception:
            return None

    def _write(self, key, data):
        try:
            DIR.mkdir(parents=True, exist_ok=True)
            tmp = self._file(key).with_suffix(".tmp")
            tmp.write_text(json.dumps(data))
            tmp.replace(self._file(key))
        except Exception as e:
            print(f"[room] lyrics: couldn't keep them ({e})", flush=True)
