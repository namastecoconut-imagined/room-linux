"""AirPlay: the Surface shows up as a speaker called "Room" (shairport-sync does the receiving and plays the sound
through PipeWire). Room reads shairport-sync's metadata pipe for the title, artist, album, cover and position, and
sends play/pause/next/previous back over D-Bus (MPRIS) when shairport-sync offers it.

Metadata pipe items look like:
  <item><type>636f7265</type><code>6d696e6d</code><length>5</length>
  <data encoding="base64">RmlkZWxpbw==</data></item>
type/code are 4-char codes in hex: core/minm = title, core/asar = artist, core/asal = album, ssnc/PICT = cover,
ssnc/pbeg|pend = session begin/end, ssnc/prsm = resumed, ssnc/pfls|paus = paused, ssnc/prgr = "start/now/end" in
RTP frames (44.1 kHz), ssnc/pvol = volume, ssnc/snam = the sending device's name.

Where the song is: AirPlay 2 senders don't send prgr. They send their Now Playing info instead (POST /command,
"updateMRNowPlayingInfo"), which shairport-sync passes on whole as ssnc/copl, a binary plist: ElapsedTime (s),
Timestamp (when that was true, UTC), PlaybackRate (1 playing, 0 paused) and Duration. That gives the true position
for any app — YouTube Music, Apple Music, podcasts — where before Room could only count up from when the title came.
"""
import base64
import datetime
import errno
import os
import plistlib
import re
import time

from PySide6.QtCore import QObject, QSocketNotifier, QTimer, Signal
from PySide6.QtGui import QImage

from .config import STATE_DIR
from .spotify import colours
from .art import wash

PIPE = os.environ.get("ROOM_AIRPLAY_PIPE", "/tmp/shairport-sync-metadata")
ITEM = re.compile(rb"<item><type>([0-9a-f]{8})</type><code>([0-9a-f]{8})</code><length>(\d+)</length>"
                  rb"(?:\s*<data encoding=\"base64\">\s*(.*?)\s*</data>)?\s*</item>", re.S)
RATE = 44100


def fourcc(h: bytes) -> str:
    try:
        return bytes.fromhex(h.decode()).decode("latin-1")
    except Exception:
        return ""


class AirPlay(QObject):
    changed = Signal()
    volumeSet = Signal(int)         # the phone's volume was changed (0–100): Room sets the speaker to it

    def __init__(self):
        super().__init__()
        self.fd = None
        self.notifier = None
        self.buf = b""
        self.active = False         # a sender is connected
        self.playing = False
        self.title = self.artist = self.album = self.source = ""
        self.art_url = ""
        self.rgb, self.rgb2 = [60, 56, 52], [20, 18, 16]
        self.wash = ""
        self.duration = 0.0
        self.position = 0.0
        self.at = 0.0
        self.npi_title, self.npi_at = "", 0.0    # the last Now Playing info (copl): its song, and when it came
        self.volume = 50
        self.last_seen = 0.0
        self.audio_at = 0.0          # when AirPlay's sound was last seen flowing in PipeWire (room/output.py)
        self.art_dir = STATE_DIR / "airplay"
        self.art_dir.mkdir(parents=True, exist_ok=True)
        for old in self.art_dir.glob("cover-*.jpg"):       # last run's covers: start clean
            old.unlink(missing_ok=True)

    def start(self):
        self._open()
        # the pipe appears when shairport-sync starts; keep trying until it's there
        self.retry = QTimer(self); self.retry.timeout.connect(self._open); self.retry.start(5000)

    def _open(self):
        if self.fd is not None:
            return
        try:
            self.fd = os.open(PIPE, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            return
        self.notifier = QSocketNotifier(self.fd, QSocketNotifier.Type.Read, self)
        self.notifier.activated.connect(self._read)

    def _reopen(self):
        if self.notifier:
            self.notifier.setEnabled(False); self.notifier.deleteLater(); self.notifier = None
        if self.fd is not None:
            try: os.close(self.fd)
            except OSError: pass
            self.fd = None
        QTimer.singleShot(1000, self._open)

    def _read(self, *_):
        try:
            chunk = os.read(self.fd, 1 << 16)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                return
            return self._reopen()
        if not chunk:   # the writer went away (shairport-sync restarted)
            return self._reopen()
        self.feed(chunk)

    def feed(self, chunk: bytes):
        self.buf += chunk
        dirty, end = False, 0
        for m in ITEM.finditer(self.buf):
            end = m.end()
            t, c = fourcc(m.group(1)), fourcc(m.group(2))
            data = base64.b64decode(m.group(4)) if m.group(4) else b""
            dirty |= self._item(t, c, data)
        if end:
            self.buf = self.buf[end:]
        if len(self.buf) > 4 << 20:   # never let a broken stream grow without bound
            self.buf = b""
        if dirty:
            self.last_seen = time.time()
            self.changed.emit()

    def _item(self, t, c, d) -> bool:
        s = lambda: d.decode("utf-8", "replace")
        if t == "core":
            if c == "astm" and len(d) == 4:              # the song's length in ms (AirPlay 2 sends this, not prgr)
                ms = int.from_bytes(d, "big")
                # only when the Now Playing info hasn't given it: astm also comes for other songs (the queue)
                if ms > 0 and not self.duration and not self._npi_fresh(self.title):
                    self.duration = ms / 1000
                return True
            if c == "minm":
                if s() != self.title and not self._npi_fresh(s()):
                    # a new song starts at 0 — unless its Now Playing info (the true position) just came: the
                    # title can arrive after it, and resetting then put a song you joined halfway back at 0
                    self.duration = 0.0; self.position = 0.0; self.at = time.time()
                self.title = s(); return True
            if c == "asar": self.artist = s(); return True
            if c == "asal": self.album = s(); return True
            return False
        if t != "ssnc":
            return False
        if c in ("pbeg", "abeg"):
            self.active = True; return True
        if c in ("pend", "aend"):
            self.active = self.playing = False; return True
        if c in ("prsm", "pres"):
            self.active = self.playing = True; self.at = time.time(); return True
        if c in ("pfls", "paus"):
            # remember where we stopped
            if self.playing: self.position += time.time() - self.at
            self.playing = False; self.at = time.time(); return True
        if c == "snam":
            self.source = s(); return True
        if c == "prgr":
            try:
                a, now, b = (int(x) for x in s().split("/"))
                self.duration = max(0.0, (b - a) / RATE)
                self.position = max(0.0, (now - a) / RATE)
                self.at = time.time(); self.active = self.playing = True
            except ValueError:
                pass
            return True
        if c == "copl":
            return self._now_playing(d)
        if c == "pvol":
            try:   # "airplay_volume,volume,lowest,highest" — airplay_volume is −30…0 (−144 = muted)
                av = float(s().split(",")[0])
                self.volume = 0 if av <= -30 else int(round((av + 30) / 30 * 100))
                self.volumeSet.emit(self.volume)
            except ValueError:
                pass
            return True
        if c == "PICT":
            if d:
                img = QImage.fromData(d)
                if not img.isNull():
                    self._n = getattr(self, "_n", 0) + 1
                    path = self.art_dir / f"cover-{int(time.time() * 1000)}-{self._n}.jpg"
                    if not img.save(str(path), "JPG", 92):
                        print(f"[room] airplay: couldn't save the cover to {path}", flush=True)
                        return True
                    # keep the few written most recently — the cover flow still shows the last couple of songs.
                    # (By the order Room wrote them, not the files' dates: when the clock was wrong at start-up,
                    # covers dated in the "future" made every new cover look oldest — and it was deleted the moment
                    # it was written, so the screen had nothing to show.)
                    self._written = (getattr(self, "_written", []) + [path])
                    for old in self._written[:-5]:
                        old.unlink(missing_ok=True)
                    self._written = self._written[-5:]
                    self.art_url = path.as_uri()
                    self.rgb, self.rgb2 = colours(img)
                    self.wash, self.rgb = wash(img)
            return True
        return False

    def _now_playing(self, d: bytes) -> bool:
        """The sender's Now Playing info (see the top): the song's true position, length and play/pause."""
        try:
            pl = plistlib.loads(d)
        except Exception:
            return False
        if not isinstance(pl, dict) or pl.get("type") != "updateMRNowPlayingInfo":
            return False
        npi = ((pl.get("params") or {}).get("params")) or {}
        if not isinstance(npi, dict):
            return False
        k = lambda name: npi.get("kMRMediaRemoteNowPlayingInfo" + name)
        dur, el, rate, ts = k("Duration"), k("ElapsedTime"), k("PlaybackRate"), k("Timestamp")
        if isinstance(k("Title"), str) and k("Title"):
            self.npi_title = k("Title")
        self.npi_at = time.time()
        changed = False
        if isinstance(dur, (int, float)) and dur > 0:
            self.duration = float(dur); changed = True
        # It may say "playing", never "paused": these messages can arrive late and still say paused just after the
        # song resumed — that left Room thinking AirPlay was paused while it played (the phone's volume was ignored,
        # and after 5 min the music card and its slider went away). Pauses come from AirPlay's own pause (ssnc/paus).
        moving = isinstance(rate, (int, float)) and rate > 0
        if isinstance(el, (int, float)):
            pos = float(el)
            playing = moving
            if playing and isinstance(ts, datetime.datetime):
                # elapsed was true at the Timestamp (UTC): move it on to now — unless the clocks disagree wildly
                now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
                late = (now - ts).total_seconds()
                if 0 <= late < 30:
                    pos += late * float(rate)
            if self.duration:
                pos = min(pos, self.duration)
            self.position, self.at = max(0.0, pos), time.time()
            if moving:
                self.playing = self.active = True
            changed = True
            print(f"[room] airplay: now playing {self.npi_title!r} at {self.position:.1f} of {self.duration:.1f} s"
                  f" ({'playing' if moving else 'sender says paused'})", flush=True)
        elif moving and not self.playing:
            self.playing, self.at = True, time.time()
            changed = True
        return changed

    def _npi_fresh(self, title: str) -> bool:
        """Did this song's Now Playing info come in the last few seconds?"""
        return bool(title) and title.strip().lower() == self.npi_title.strip().lower() and time.time() - self.npi_at < 15

    @property
    def showing(self) -> bool:
        """AirPlay owns the music card while a sender is connected and has played in the last few minutes — or while
        its sound is actually flowing (seen by room/output.py), whatever the metadata last said."""
        if time.time() - self.audio_at < 45:
            return True
        return self.active and (self.playing or time.time() - self.last_seen < 300)

    def snapshot(self) -> dict:
        return {
            "enabled": True, "exists": bool(self.title or self.artist), "playing": self.playing,
            "title": self.title, "artist": self.artist, "album": self.album,
            "duration": self.duration, "position": self.position, "at": self.at,
            "device": "AirPlay" + (f" · {self.source}" if self.source else ""),
            "volume": self.volume, "art": self.art_url, "rgb": self.rgb, "rgb2": self.rgb2, "wash": self.wash,
            "error": "", "source": "airplay",
        }

    # ---- controls, over MPRIS (shairport-sync's D-Bus interface, when it's built with one)
    def _call(self, method: str):
        try:
            from PySide6.QtDBus import QDBusConnection, QDBusInterface
        except Exception:
            return
        for bus in (QDBusConnection.sessionBus(), QDBusConnection.systemBus()):
            i = QDBusInterface("org.mpris.MediaPlayer2.ShairportSync", "/org/mpris/MediaPlayer2",
                               "org.mpris.MediaPlayer2.Player", bus)
            if i.isValid():
                i.call(method)
                return

    def play_pause(self):
        self.playing = not self.playing; self.at = time.time(); self.changed.emit()
        self._call("PlayPause")

    def pause(self):
        """Pause the sender (the phone stops too — shairport-sync passes it on)."""
        if self.playing:
            if self.at: self.position += time.time() - self.at
            self.playing = False; self.at = time.time(); self.changed.emit()
        self._call("Pause")

    def next(self):
        self._call("Next")

    def previous(self):
        self._call("Previous")
