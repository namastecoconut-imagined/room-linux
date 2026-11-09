"""The screen goes properly off when nobody's around, and comes back the moment the room hears something.

On standby, once the room has been quiet for 5 minutes (no sound above the room's own background, no touch, nothing
playing, no alarm, Room not talking), the backlight goes off and nothing is drawn. Any sound clearly above the
background (a voice, a door, footsteps — 12 dB over the room's usual hum) brings the standby screen back; so does a
touch, "Alexa", an alarm or a timer. The power button does the same by hand: off now, on again.

The background is learnt as it goes: it follows quiet stretches down quickly and rises only slowly, so a fan or the
fridge becomes "silence" while a voice still stands out. Sound comes from the voice process's mic (already open for
"Alexa"), so nothing extra listens.
"""
import math
import time

from PySide6.QtCore import QObject, QTimer, Signal


class Sleep(QObject):
    changed = Signal()

    QUIET_FOR = 300.0          # seconds of a quiet room (on standby) before the screen goes off
    ABOVE = 12.0               # dB over the room's background that counts as someone there

    def __init__(self, display, busy):
        super().__init__()
        self.display = display
        self.busy = busy           # () → True while something needs the screen (music, an alarm, Room talking)
        self.asleep = False
        self.standby = False
        self.floor = None          # the room's background level, dB
        self.sound_at = time.monotonic()
        self.input_at = time.monotonic()
        self.timer = QTimer(self); self.timer.timeout.connect(self._tick); self.timer.start(5000)

    # ---------------------------------------------------------------- what Room tells it
    def hear(self, rms: float):
        db = 20 * math.log10(max(rms, 1e-6))
        if self.floor is None or db < self.floor:
            self.floor = db if self.floor is None else self.floor + (db - self.floor) * 0.3
        else:
            self.floor += (db - self.floor) * 0.002          # creeps up slowly (~3 min to follow a new hum)
        if db > self.floor + self.ABOVE:
            self.sound_at = time.monotonic()
            if self.asleep:
                self.wake("sound")

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
        if self.asleep:
            self.wake("power button")
        else:
            self.sleep("power button")

    # ---------------------------------------------------------------- off and on
    def _tick(self):
        if self.asleep or not self.standby or self.busy():
            return
        if time.monotonic() - max(self.sound_at, self.input_at) > self.QUIET_FOR:
            self.sleep("quiet room")

    def sleep(self, why=""):
        if self.asleep:
            return
        self.asleep = True
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
