"""How loud the room is — nothing more. Room doesn't understand or keep anything it hears; it only measures loudness,
for three things: the screen coming back on when someone's around (room/sleep.py), the dots rippling on standby,
and the music screen's beat.

The Surface's raw mic (the one the assistant listens on), read by pw-record in a thread at 16 kHz — light, and a
pw-record that stops is started again. "roomMic": false in config.json turns it off.

It used to read the noise-suppressed "Surface Mic". That filter keeps voices and removes everything else — footsteps,
a door, someone moving about — so the screen didn't wake for them, and it cost the sound system 14 % of every cycle,
all day, for a loudness meter. The raw mic's steady hum is learnt as the room's background (room/sleep.py), and the
standby ripple starts above it (backend._sound_level). If the raw mic can't be found, the default mic is used.
"""
import array
import json
import math
import subprocess
import threading
import time

from PySide6.QtCore import QObject, QTimer, Signal


class RoomMic(QObject):
    level = Signal(float)      # ~20 a second: loudness, RMS 0…1 (the standby ripple, the beat)
    heard = Signal(float)      # ~3 a second: the average over that stretch (the room's background; someone talking)
    loudest = Signal(float)    # …and with it, the loudest 50 ms in that stretch (a snap or a knock — the screen's wake)

    RATE = 16000
    PIECE = 800                # samples: 50 ms

    def __init__(self, parent=None):
        super().__init__(parent)
        self.proc = None
        self.stopping = False
        self._now = 0.0
        self._sum, self._n = 0.0, 0
        self._peak = 0.0
        self._tick = QTimer(self); self._tick.timeout.connect(self._out)
        self._slow = 0

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()
        self._tick.start(50)

    def stop(self):
        self.stopping = True
        p = self.proc
        if p and p.poll() is None:
            p.terminate()

    @staticmethod
    def _raw_mic():
        """The Surface's raw mic (node name), or None (then: the default mic)."""
        try:
            nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
        except Exception:
            return None
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if p.get("media.class") == "Audio/Source" and p.get("node.name", "").startswith("alsa_input"):
                return p["node.name"]
        return None

    def _run(self):
        said = None
        while not self.stopping:
            try:
                mic = self._raw_mic()
                if mic != said:
                    said = mic
                    print(f"[room] sound level: listening on {mic or 'the default mic'}", flush=True)
                self.proc = subprocess.Popen(
                    ["pw-record", "--raw", "--rate", str(self.RATE), "--channels", "1", "--format", "s16"]
                    + (["--target", mic] if mic else []) + [
                     "--latency", "100ms", "-P", "{ application.name = \"Room sound level\" node.description = \"Room sound level\" }", "-"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                want = self.PIECE * 2
                while not self.stopping:
                    raw = self.proc.stdout.read(want)
                    if not raw or len(raw) < want:
                        break
                    a = array.array("h", raw)
                    rms = math.sqrt(sum(x * x for x in a[::2]) / (len(a) // 2)) / 32768
                    self._now = rms
                    self._sum += rms; self._n += 1
                    if rms > self._peak:
                        self._peak = rms
            except Exception as e:
                print(f"[room] sound level: {e!r}", flush=True)
            if self.proc and self.proc.poll() is None:
                self.proc.terminate()
            if not self.stopping:
                time.sleep(5)          # the mic went away (or PipeWire restarted): try again shortly

    def _out(self):
        self.level.emit(self._now)
        self._slow += 1
        if self._slow >= 6 and self._n:
            self._slow = 0
            avg, self._sum, self._n = self._sum / self._n, 0.0, 0
            peak, self._peak = self._peak, 0.0
            self.heard.emit(avg)
            self.loudest.emit(peak)
