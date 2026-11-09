"""Bluetooth from the panel: the speakers you've paired, connect / disconnect / forget, and searching for new ones to
pair. Talks to the system's Bluetooth service with `bluetoothctl` on worker threads (nothing here blocks the screen);
a search runs for 25 s while Settings is open. Speakers and headphones pair without a code."""
import re
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Signal

KINDS = {"audio-card": "Speaker", "audio-speakers": "Speaker", "audio-headset": "Headphones",
         "audio-headphones": "Headphones", "phone": "Phone", "computer": "Computer", "input-keyboard": "Keyboard",
         "input-mouse": "Mouse", "input-gaming": "Controller"}


def ctl(*args, timeout=10):
    try:
        r = subprocess.run(["bluetoothctl", *args], capture_output=True, text=True, timeout=timeout + 5)
        return r.stdout
    except Exception as e:
        return f"error {e!r}"


class Bluetooth(QObject):
    changed = Signal()
    connectedChanged = Signal()           # a speaker came or went (AirPlay's route follows it)

    def __init__(self):
        super().__init__()
        self.devices: list = []
        self.searching = False
        self.busy: dict = {}              # mac → "Pairing…" / "Connecting…" / …
        self.note = ""
        self.powered = True
        self._kinds: dict = {}
        self._scan = None
        self._lock = threading.Lock()

    def snapshot(self):
        return {"powered": self.powered, "searching": self.searching, "note": self.note,
                "devices": [dict(d, busy=self.busy.get(d["mac"], "")) for d in self.devices]}

    # ---------------------------------------------------------------- reading
    def refresh(self):
        threading.Thread(target=self._refresh, daemon=True).start()

    def _list(self, which=""):
        out = ctl("devices", *([which] if which else []))
        return {m: n.strip() for m, n in re.findall(r"Device ([0-9A-F:]{17}) (.*)", out)}

    def _refresh(self):
        with self._lock:
            self.powered = "Powered: yes" in ctl("show")
            every, paired, conn = self._list(), self._list("Paired"), self._list("Connected")
            was = {d["mac"] for d in self.devices if d["connected"]}
            out = []
            for mac, name in every.items():
                if not name or re.fullmatch(r"[0-9A-F]{2}([-:][0-9A-F]{2}){5}", name):
                    continue                                      # unnamed: nothing anyone could pick
                if mac not in self._kinds:
                    m = re.search(r"Icon: (\S+)", ctl("info", mac))
                    self._kinds[mac] = KINDS.get(m.group(1), "") if m else ""
                out.append({"mac": mac, "name": name, "kind": self._kinds[mac],
                            "paired": mac in paired, "connected": mac in conn})
            out.sort(key=lambda d: (not d["connected"], not d["paired"], d["name"].lower()))
            self.devices = out
        self.changed.emit()
        if was != {d["mac"] for d in out if d["connected"]}:
            self.connectedChanged.emit()

    # ---------------------------------------------------------------- searching
    def search(self):
        if self.searching:
            return
        self.searching = True
        self.note = ""
        self.changed.emit()

        def go():
            if not self.powered:
                ctl("power", "on")
            self._scan = subprocess.Popen(["bluetoothctl", "--timeout", "25", "scan", "on"],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            while self._scan and self._scan.poll() is None:
                self._refresh()
                time.sleep(2.5)
            self.searching = False
            self._refresh()
        threading.Thread(target=go, daemon=True).start()

    def stop_search(self):
        if self._scan and self._scan.poll() is None:
            self._scan.terminate()
        self._scan = None

    # ---------------------------------------------------------------- doing
    def _do(self, mac, label, steps):
        if mac in self.busy:
            return
        self.busy[mac] = label
        self.note = ""
        self.changed.emit()

        def go():
            for args, ok, fail in steps:
                out = ctl(*args, timeout=25)
                if ok and not re.search(ok, out):
                    self.note = fail
                    break
            self.busy.pop(mac, None)
            self._refresh()
        threading.Thread(target=go, daemon=True).start()

    def pair(self, mac):
        self._do(mac, "Pairing…", [
            (("--timeout", "25", "pair", mac), r"Pairing successful|AlreadyExists|already paired",
             "Couldn't pair — is it in pairing mode?"),
            (("trust", mac), None, ""),
            (("--timeout", "20", "connect", mac), r"Connection successful|already connected", "Paired, but couldn't connect"),
        ])

    def connect(self, mac):
        self._do(mac, "Connecting…", [(("--timeout", "20", "connect", mac), r"Connection successful|already connected",
                                       "Couldn't connect — is it on and nearby?")])

    def disconnect(self, mac):
        self._do(mac, "Disconnecting…", [(("disconnect", mac), None, "")])

    def forget(self, mac):
        self._do(mac, "Forgetting…", [(("remove", mac), None, "")])
