"""The Bluetooth link to the pixel display: finds it, connects, stays connected, and sends what it's given.

The display (Bluetooth name IDM-…) only shows what's pushed to it and takes one connection at a time, so Room holds
the link all the time: it connects as soon as the display is seen, sets its clock (it forgets it when unplugged) and
reconnects by itself whenever the link drops — a moment after it drops, then every 20 s, then once a minute.

Runs on Qt's Bluetooth (in PySide6 already — nothing extra installed) on Room's main thread: everything here is
signals, nothing blocks the screen. Writes go out one packet at a time, each waiting for the display's confirmation;
a picture's 4096-byte parts each wait for the display's "got it" as well, so a long upload can't outrun it.
"""
import json
import subprocess
import threading
import time

from PySide6.QtBluetooth import (QBluetoothAddress, QBluetoothDeviceDiscoveryAgent, QBluetoothDeviceInfo, QBluetoothUuid,
                                 QLowEnergyController, QLowEnergyService)
from PySide6.QtCore import QByteArray, QObject, QTimer, QUuid, Signal

from . import proto


def _uid(text):
    return QBluetoothUuid(QUuid(text))


def _log(text):
    print("[pixel] " + text, flush=True)


class Link(QObject):
    changed = Signal()            # state, name or progress changed
    ready = Signal()              # just connected and set up: send it what it should be showing
    mtuRead = Signal(int)

    def __init__(self, address="", name=""):
        super().__init__()
        self.state = "off"        # off · searching · connecting · on
        self.address, self.name = address, name
        self.info = {}
        self.packet = 20
        self.sent, self.total = 0, 0      # the picture going up now, in bytes
        self._wanted = False
        self._ctl = self._svc = self._wr = self._agent = self._found = None
        self._jobs = []           # ("cmd", bytes) · ("part", bytes, generation)
        self._busy = None         # the packets of the job going out now
        self._gen = 0
        self._tries = 0
        self._retry = QTimer(self); self._retry.setSingleShot(True); self._retry.timeout.connect(self._seek)
        self._watch = QTimer(self); self._watch.setSingleShot(True); self._watch.timeout.connect(self._stalled)
        self._ack = QTimer(self); self._ack.setSingleShot(True); self._ack.timeout.connect(self._next_job)
        self._setup = QTimer(self); self._setup.setSingleShot(True); self._setup.timeout.connect(self._begin)
        self.mtuRead.connect(self._got_mtu)

    # ---------------------------------------------------------------- finding it and connecting
    def start(self):
        self._wanted = True
        # Room was restarted: the system may still hold the old connection, and a display that's connected can't be
        # found or connected to again — let go of it first
        self._release()
        self._retry.start(1500)

    def _release(self):
        def go(address):
            try:
                subprocess.run(["bluetoothctl", "disconnect", address], capture_output=True, timeout=8)
            except Exception:
                pass
        if self.address:
            threading.Thread(target=go, args=(self.address,), daemon=True).start()

    def stop(self):
        """Let go of the display (so something else can connect to it)."""
        self._wanted = False
        self._retry.stop()
        self._drop("off")

    def _set(self, state):
        if state != self.state:
            self.state = state
            self.changed.emit()

    def _seek(self):
        if not self._wanted or self.state in ("connecting", "on"):
            return
        self._tries += 1
        # straight to its address when it's known (no search: a search shares the radio with the speaker's music);
        # a search the first time, and every other try in case the system no longer knows the address
        if self.address and self._tries % 2 == 1:
            info = QBluetoothDeviceInfo(QBluetoothAddress(self.address), self.name, 0)
            info.setCoreConfigurations(QBluetoothDeviceInfo.CoreConfiguration.LowEnergyCoreConfiguration)
            self._connect(info)
            return
        self._set("searching")
        self._found = None
        self._release()
        self._agent = QBluetoothDeviceDiscoveryAgent(self)
        self._agent.setLowEnergyDiscoveryTimeout(12000)
        self._agent.deviceDiscovered.connect(self._seen)
        self._agent.finished.connect(self._scan_done)
        self._agent.errorOccurred.connect(lambda e: self._scan_done())
        self._agent.start(QBluetoothDeviceDiscoveryAgent.DiscoveryMethod.LowEnergyMethod)

    def _seen(self, info):
        if self._found is None and info.name().startswith("IDM-") and (not self.address or info.address().toString() == self.address
                                                                         or self._tries > 6):
            self._found = info
            self._agent.stop()
            self._connect(info)

    def _scan_done(self):
        if self._found is None and self.state == "searching":
            self._again()

    def _again(self):
        """Not there (or it dropped): look again — soon at first, then every 20 s, then once a minute."""
        self._set("searching" if self._wanted else "off")
        if self._wanted:
            self._retry.start(3000 if self._tries < 2 else 20000 if self._tries < 8 else 60000)

    def _connect(self, info):
        self._set("connecting")
        self._ctl = ctl = QLowEnergyController.createCentral(info, self)
        ctl.connected.connect(lambda: ctl is self._ctl and ctl.discoverServices())
        ctl.discoveryFinished.connect(lambda: ctl is self._ctl and self._services())
        ctl.errorOccurred.connect(lambda e: ctl is self._ctl and self._lost("couldn't connect (" + ctl.errorString() + ")"))
        ctl.disconnected.connect(lambda: ctl is self._ctl and self._lost("the link dropped"))
        self._watch.start(25000)
        ctl.connectToDevice()

    def _services(self):
        uuid = _uid(proto.SERVICE)
        if not any(u == uuid for u in self._ctl.services()):
            return self._lost("it doesn't offer the display's service")
        self._svc = svc = self._ctl.createServiceObject(uuid, self)
        svc.stateChanged.connect(lambda s: svc is self._svc and self._details(s))
        svc.characteristicChanged.connect(lambda c, v: svc is self._svc and self._reply(bytes(v.data())))
        svc.characteristicWritten.connect(lambda c, v: svc is self._svc and self._written())
        svc.errorOccurred.connect(lambda e: svc is self._svc and self._lost(f"a write was refused ({e})"))
        svc.discoverDetails()

    def _details(self, state):
        if state != QLowEnergyService.ServiceState.RemoteServiceDiscovered or self.state == "on":
            return
        self._wr = self._svc.characteristic(_uid(proto.WRITE))
        if not self._wr.isValid():
            return self._lost("its write channel is missing")
        rd = self._svc.characteristic(_uid(proto.READ))
        if rd.isValid():
            cccd = rd.descriptor(QBluetoothUuid(QBluetoothUuid.DescriptorType.ClientCharacteristicConfiguration))
            if cccd.isValid():
                self._svc.writeDescriptor(cccd, QByteArray.fromHex(b"0100"))
        self.address = self._ctl.remoteAddress().toString()
        self.name = self._ctl.remoteName() or self.name
        self.packet = 20
        threading.Thread(target=self._read_mtu, args=(self.address,), daemon=True).start()
        self._setup.start(700)            # (its reply channel a moment to open, and the packet size to be read)

    def _read_mtu(self, address):
        """How big a packet this link takes: the system knows (BlueZ's MTU for the write channel), Qt doesn't say."""
        mtu = 0
        try:
            out = subprocess.run(["busctl", "--system", "--json=short", "call", "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
                                  "GetManagedObjects"], capture_output=True, text=True, timeout=5).stdout
            dev = "/dev_" + address.replace(":", "_")
            for path, faces in json.loads(out)["data"][0].items():
                ch = faces.get("org.bluez.GattCharacteristic1")
                if ch and dev in path and ch.get("UUID", {}).get("data", "").startswith("0000fa02"):
                    mtu = int(ch.get("MTU", {}).get("data", 0))
        except Exception:
            pass
        self.mtuRead.emit(mtu)

    def _got_mtu(self, mtu):
        if mtu > 23 and self.state in ("connecting", "on"):
            self.packet = max(20, min(244, mtu - 3))
            _log(f"packet size {self.packet} bytes (the link takes {mtu})")

    def _begin(self):
        if self._svc is None or self.state == "on":
            return
        self._watch.stop()
        self._tries = 0
        self._jobs, self._busy, self.sent, self.total = [], None, 0, 0
        self._set("on")
        _log(f"connected to {self.name or self.address}")
        self.command(proto.set_time(time.localtime()))
        self.ready.emit()

    def _lost(self, why):
        if self.state == "on" or self._tries <= 2:      # (not a line a minute while the display is unplugged)
            _log(why)
        self._drop("searching")
        self._again()

    def _drop(self, state):
        self._watch.stop(); self._ack.stop(); self._setup.stop()
        ctl, self._ctl, self._svc, self._wr = self._ctl, None, None, None
        self._jobs, self._busy, self.sent, self.total = [], None, 0, 0
        if self._agent is not None:
            try:
                self._agent.stop()
            except Exception:
                pass
        if ctl is not None:
            try:
                ctl.disconnectFromDevice()
            except Exception:
                pass
            ctl.deleteLater()
        self._set(state)

    def _stalled(self):
        self._lost("no answer from it")

    # ---------------------------------------------------------------- sending
    def command(self, data):
        """A short command (power, brightness, clock…): goes out after whatever is already waiting."""
        if self.state == "on":
            self._jobs.append(("cmd", bytes(data)))
            self._pump()

    def picture(self, kind, data):
        """A still ("png") or an animation ("gif"). The newest picture wins: one still waiting to go is dropped."""
        if self.state != "on":
            return
        self._gen += 1
        self._jobs = [j for j in self._jobs if j[0] == "cmd"]
        if kind == "png":
            self._jobs.append(("cmd", proto.image_mode()))
        parts = proto.png_payloads(data) if kind == "png" else proto.gif_payloads(data)
        self.sent, self.total = 0, sum(len(p) for p in parts)
        self._jobs += [("part", p, self._gen) for p in parts]
        self.changed.emit()
        self._pump()

    def _pump(self):
        if self._busy is not None or self._ack.isActive() or self._svc is None:
            return
        if not self._jobs:
            if self.total:
                self.sent = self.total = 0
                self.changed.emit()
            return
        job = self._jobs.pop(0)
        data = job[1]
        self._busy = {"packets": [data[i:i + self.packet] for i in range(0, len(data), self.packet)], "part": job[0] == "part"}
        self._write()

    def _write(self):
        self._watch.start(8000)
        self._svc.writeCharacteristic(self._wr, QByteArray(self._busy["packets"][0]), QLowEnergyService.WriteMode.WriteWithResponse)

    def _written(self):
        if self._busy is None:
            return
        self._watch.stop()
        done = self._busy["packets"].pop(0)
        if self._busy["part"]:
            self.sent += len(done)
            if self.total > 8000:           # (a long upload: the screen shows how far it is)
                self.changed.emit()
        if self._busy["packets"]:
            return self._write()
        part, self._busy = self._busy["part"], None
        if part:
            self._ack.start(4000)           # the display says when it has the part (or 4 s pass)
        else:
            self._pump()

    def _next_job(self):
        self._pump()

    def _reply(self, d):
        info = proto.details(d)
        if info:
            if info != self.info:
                self.info = info
                _log(f"firmware {info['firmware']}, {info['size']}×{info['size']}")
                self.changed.emit()
        elif proto.is_upload_ack(d) and self._ack.isActive():
            self._ack.stop()
            self._pump()
