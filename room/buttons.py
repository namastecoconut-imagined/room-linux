"""The Surface's own buttons — volume up, volume down, power — read straight from the hardware.

Room used to hear them only as keys in its own window, and a window only gets keys while it's in front: with the web
browser open (Firefox over Room), the presses went to Firefox, which does nothing with them. Read here, from the
buttons' own input devices ("gpio-keys"), they reach Room whatever is in front.

Reading those devices needs a permission scripts/buttons.sh gives (once): whoever is signed in at the screen may read
them — only those buttons, not the keyboard. Without it this says so once in the log, and the buttons work as before
(while Room is in front). While Room is in front a press arrives both ways; Room.button keeps one.
"""
import glob
import os
import selectors
import struct
import threading
import time

from PySide6.QtCore import QObject, Signal

EVENT = struct.Struct("llHHi")       # struct input_event: the time (2 longs), type, code, value — 24 bytes here
EV_KEY = 1
KEYS = {114: "down", 115: "up", 116: "power"}      # KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_POWER


class Buttons(QObject):
    pressed = Signal(str, bool)      # "up" · "down" · "power", and whether it's the button held down (a repeat)

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    @staticmethod
    def _devices():
        for d in sorted(glob.glob("/sys/class/input/event*")):
            try:
                with open(os.path.join(d, "device", "name")) as f:
                    if f.read().strip() == "gpio-keys":
                        yield os.path.join("/dev/input", os.path.basename(d))
            except OSError:
                pass

    def _run(self):
        said = None
        while True:
            files, denied = [], []
            for path in self._devices():
                try:
                    files.append(open(path, "rb", buffering=0))
                except PermissionError:
                    denied.append(os.path.basename(path))
                except OSError:
                    pass
            if files:
                note = "reading the Surface's buttons directly (" + ", ".join(os.path.basename(f.name) for f in files) + ")"
            elif denied:
                note = ("can't read the Surface's buttons (" + ", ".join(denied) + ") — run scripts/buttons.sh once; until "
                        "then they work only while Room is in front")
            else:
                note = "the Surface's buttons weren't found — they work only while Room is in front"
            if note != said:
                said = note
                print(f"[room] buttons: {note}", flush=True)
            if not files:
                time.sleep(30)               # (the permission may come later: looked at again)
                continue
            sel = selectors.DefaultSelector()
            for f in files:
                sel.register(f, selectors.EVENT_READ)
            try:
                while True:
                    for key, _ in sel.select():
                        data = key.fileobj.read(EVENT.size * 16)
                        if not data:
                            raise OSError("the device went away")
                        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                            _, _, typ, code, value = EVENT.unpack_from(data, i)
                            kind = KEYS.get(code) if typ == EV_KEY else None
                            if kind and (value == 1 or (value == 2 and kind != "power")):
                                self.pressed.emit(kind, value == 2)
            except OSError as e:
                print(f"[room] buttons: {e} — looking again", flush=True)
            finally:
                sel.close()
                for f in files:
                    try:
                        f.close()
                    except OSError:
                        pass
            time.sleep(5)
