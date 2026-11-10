"""The screen goes properly off when nobody's around, and comes back the moment the room hears something.

On standby, once the room has been quiet for 5 minutes (no sound above the room's own background, no touch, nothing
playing, no alarm), the backlight goes off and nothing is drawn. Any sound clearly above the
background (a voice, a door, footsteps — 12 dB over the room's usual hum) brings the standby screen back; so does a
touch, an alarm or a timer. The power button does the same by hand: off now, on again.

The background is learnt as it goes: it follows quiet stretches down quickly and rises only slowly, so a fan or the
fridge becomes "silence" while a voice still stands out. The loudness comes from room/mic.py (loudness only —
nothing is recognised or kept).
"""
import math
import time

from PySide6.QtCore import QObject, QTimer, Signal


class Sleep(QObject):
    changed = Signal()

    QUIET_FOR = 300.0          # seconds of a quiet room (on standby) before the screen goes off
    ABOVE = 12.0               # dB over the room's background that counts as someone there
    LOUDEST_QUIET = -48.0      # dBFS: anything quieter than this is never "someone there" (the noise-suppressed mic
                               # gives near-digital silence in a still room, so the background alone read ~ −100 dB
                               # and every tiny tick counted as a sound — the screen never went off)
    NEED = 2                   # …and it has to last: two readings in a row (~0.6 s), not one click

    def __init__(self, display, busy):
        super().__init__()
        self.display = display
        self.busy = busy           # () → True while something needs the screen (music, an alarm)
        self.asleep = False
        self.standby = False
        self.floor = None          # the room's background level, dB
        self.sound_at = time.monotonic()
        self.input_at = time.monotonic()
        self.loud = 0
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
        if db > max(self.floor + self.ABOVE, self.LOUDEST_QUIET):
            self.loud += 1
            if self.loud >= self.NEED:
                self.sound_at = time.monotonic()
                if self.asleep and time.monotonic() > self.hush_until:
                    self.wake(f"sound, {db:.0f} dB over a {self.floor:.0f} dB room")
        else:
            self.loud = 0

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
