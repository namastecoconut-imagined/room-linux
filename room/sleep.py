"""The screen goes properly off when nobody's around, and comes back the moment the room hears something.

On standby, once the room has been quiet for 5 minutes (no sound above the room's own background, no touch, nothing
playing, no alarm), the backlight goes off and nothing is drawn. While music plays it never goes off by itself, and
music starting brings it back (music stopping starts the 5 minutes again).

While it's off, a small sound brings it back: anything slightly over the room's background — a snap of the fingers,
a knock, a word. "wakeAbove" in config.json is how far over, in dB (10 if it isn't set; lower wakes on smaller
sounds). It's judged on the loudest 50 ms of every third of a second, so a sound as short as a snap counts; the log
says once a minute how loud the loudest sound was, to set it by. "Alexa", a touch, an alarm, a timer and the power
button bring it back too; the power button also switches it off by hand.

The background is learnt as it goes: it follows quiet stretches down quickly and rises only slowly, so a fan or the
fridge becomes "silence" while a voice still stands out. The loudness comes from room/mic.py (loudness only —
nothing is recognised or kept).
"""
import collections
import math
import time

from PySide6.QtCore import QObject, QTimer, Signal


class Sleep(QObject):
    changed = Signal()

    QUIET_FOR = 300.0          # seconds of a quiet room (on standby) before the screen goes off
    # dB over the room's background that counts as someone there. 12, then 8 (11 Nov, to wake on footsteps) — but on
    # the raw mic every small sound passed 8: the screen woke and stayed on all night (wakes logged at 8–18 dB over a
    # −45 dB room). Now 16, and it has to last (below): a voice across the room, not a rustle.
    ABOVE = 16.0
    LOUDEST_QUIET = -48.0      # dBFS: anything quieter than this is never "someone there" (the noise-suppressed mic, used until 11 Nov,
                               # gives near-digital silence in a still room, so the background alone read ~ −100 dB
                               # and every tiny tick counted as a sound — the screen never went off)
    # …and it has to last: 4 of the last 6 readings (~3 a second, so ~2 s) — speech has gaps between words, a click
    # or a bump is one reading
    NEED, OF = 4, 6
    # …while the screen is off, much less will do: one 50 ms stretch this many dB over the background ("wakeAbove")
    WAKE_ABOVE = 10.0

    def __init__(self, display, busy, wake_above=None):
        super().__init__()
        self.display = display
        self.busy = busy           # () → True while something needs the screen (music, an alarm)
        try:
            self.wake_above = float(wake_above) if wake_above is not None else self.WAKE_ABOVE
        except (TypeError, ValueError):
            self.wake_above = self.WAKE_ABOVE
        self.loudest_over = None   # while off: the loudest sound this minute, dB over the room (for the log)
        self.loudest_at = time.monotonic()
        self.asleep = False
        self.standby = False
        self.floor = None          # the room's background level, dB
        self.sound_at = time.monotonic()
        self.input_at = time.monotonic()
        self.recent = collections.deque(maxlen=self.OF)      # the last few readings: over the line or not
        self.last_power = 0.0
        self.hush_until = 0.0        # just switched off: its own click isn't a reason to come back
        self.why_not = ""
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(5000)

    # ---------------------------------------------------------------- what Room tells it
    def hear(self, rms: float):
        db = 20 * math.log10(max(rms, 1e-6))
        if self.floor is None or db < self.floor:
            self.floor = db if self.floor is None else self.floor + (db - self.floor) * 0.3
        else:
            self.floor += (db - self.floor) * 0.002          # creeps up slowly (~3 min to follow a new hum)
        self.recent.append(db > max(self.floor + self.ABOVE, self.LOUDEST_QUIET))
        if sum(self.recent) >= self.NEED:
            self.sound_at = time.monotonic()
            if self.asleep and time.monotonic() > self.hush_until:
                self.wake(f"sound, {db:.0f} dB against a {self.floor:.0f} dB room")
                self.recent.clear()

    def loudest(self, rms: float):
        """The loudest 50 ms of the last third of a second. While the screen is off: slightly over the room wakes it."""
        if not self.asleep or self.floor is None:
            return
        now = time.monotonic()
        db = 20 * math.log10(max(rms, 1e-6))
        over = db - self.floor
        if self.loudest_over is None or over > self.loudest_over:
            self.loudest_over = over
        if now - self.loudest_at >= 60:
            print(f"[room] screen off: the loudest sound this minute was {self.loudest_over:.0f} dB over a "
                  f"{self.floor:.0f} dB room (wakes at {self.wake_above:g})", flush=True)
            self.loudest_over, self.loudest_at = None, now
        if over >= self.wake_above and db > self.LOUDEST_QUIET and now > self.hush_until:
            self.wake(f"a sound, {over:.0f} dB over a {self.floor:.0f} dB room")

    def music(self, playing: bool):
        """Music started: the screen comes back (and stays on while it plays — busy). Stopped: the 5 quiet minutes
        count from now, not from whenever the room last heard something over the music."""
        if playing:
            self.wake("music started")
        self.input_at = time.monotonic()

    def touched(self):
        self.input_at = time.monotonic()
        if self.asleep:
            self.wake("touch")

    def set_standby(self, on: bool):
        if on and not self.standby:
            self.input_at = time.monotonic()                 # the 5 minutes count from standby starting
        self.standby = on
        if not on and self.asleep:
            self.wake("awake")

    def power_button(self):
        # the Surface reports one press from two places (the ACPI button and its own button driver): a second
        # "press" within a second is the same press — it used to switch the screen off and straight back on
        now = time.monotonic()
        if now - self.last_power < 1.0:
            return
        self.last_power = now
        if self.asleep:
            self.wake("power button")
        else:
            self.sleep("power button")

    # ---------------------------------------------------------------- off and on
    def _tick(self):
        if self.asleep:
            return
        busy = self.busy()
        why = "" if not self.standby else (busy or "")
        quiet = time.monotonic() - max(self.sound_at, self.input_at)
        if self.standby and not busy and quiet <= self.QUIET_FOR:
            why = "hearing the room" if time.monotonic() - self.sound_at < time.monotonic() - self.input_at else "touched"
        if why != self.why_not:              # the log says why the screen is staying on (once per change)
            self.why_not = why
            if why:
                print(f"[room] screen stays on: {why}", flush=True)
        if self.standby and not busy and quiet > self.QUIET_FOR:
            self.sleep("quiet room")

    def sleep(self, why=""):
        if self.asleep:
            return
        self.asleep = True
        self.hush_until = time.monotonic() + 3
        self.loudest_over, self.loudest_at = None, time.monotonic()
        self.display.blank(True)
        print(f"[room] screen off ({why})", flush=True)
        self.changed.emit()

    def wake(self, why=""):
        if not self.asleep:
            return
        self.asleep = False
        self.sound_at = self.input_at = time.monotonic()
        self.display.blank(False)
        print(f"[room] screen on ({why})", flush=True)
        self.changed.emit()
