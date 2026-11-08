"""Philips WiZ over the local network — JSON over UDP port 38899, no cloud. Same protocol as the iPhone panel.

  poll:     {"method":"getPilot","params":{}}
  control:  {"method":"setPilot","params":{"state":true,"dimming":60,"temp":2700}}
  colour:   {"method":"setPilot","params":{"r":255,"g":120,"b":0,"dimming":80}}

Bulbs are matched by MAC, so a bulb that gets a new IP from the router is still found by the broadcast.
"""
import json
import time

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtNetwork import QHostAddress, QNetworkInterface, QUdpSocket, QAbstractSocket

PORT = 38899


class Bulb:
    __slots__ = ("mac", "ip", "on", "dimming", "temp", "rgb", "seen", "pending_until")

    def __init__(self, mac, ip):
        self.mac, self.ip = mac, ip
        self.on, self.dimming, self.temp, self.rgb = False, 100, None, None
        self.seen = 0.0
        self.pending_until = 0.0  # ignore polls for a moment after we change it, so sliders don't jump back

    @property
    def reachable(self):
        return time.time() - self.seen < 20


def norm_mac(m: str) -> str:
    return (m or "").lower().replace(":", "").replace("-", "")


class WizClient(QObject):
    changed = Signal()

    def __init__(self, known_ips: list[str]):
        super().__init__()
        self.known_ips = [ip for ip in known_ips if ip]
        self.bulbs: dict[str, Bulb] = {}
        self.sock = QUdpSocket(self)
        self.sock.bind(QHostAddress(QHostAddress.SpecialAddress.AnyIPv4), 0,
                       QAbstractSocket.BindFlag.ShareAddress | QAbstractSocket.BindFlag.ReuseAddressHint)
        self.sock.readyRead.connect(self._read)
        self._get = json.dumps({"method": "getPilot", "params": {}}).encode()

    def start(self):
        self.discover()
        t1 = QTimer(self); t1.timeout.connect(self.poll); t1.start(8000)
        t2 = QTimer(self); t2.timeout.connect(self.discover); t2.start(60000)
        self._timers = (t1, t2)

    def _send(self, payload: bytes, ip: str):
        self.sock.writeDatagram(payload, QHostAddress(ip), PORT)

    @staticmethod
    def broadcast_addresses() -> list[str]:
        out = []
        for iface in QNetworkInterface.allInterfaces():
            if not (iface.flags() & QNetworkInterface.InterfaceFlag.IsUp) or iface.flags() & QNetworkInterface.InterfaceFlag.IsLoopBack:
                continue
            for e in iface.addressEntries():
                b = e.broadcast()
                if not b.isNull() and b.protocol() == QAbstractSocket.NetworkLayerProtocol.IPv4Protocol:
                    out.append(b.toString())
        return out

    def discover(self):
        for ip in self.broadcast_addresses() + ["255.255.255.255"] + self.known_ips:
            self._send(self._get, ip)

    def poll(self):
        ips = {b.ip for b in self.bulbs.values()} | set(self.known_ips)
        for ip in ips:
            self._send(self._get, ip)

    def _read(self):
        dirty = False
        while self.sock.hasPendingDatagrams():
            dg = self.sock.receiveDatagram()
            try:
                obj = json.loads(bytes(dg.data().data()))
            except Exception:
                continue
            if obj.get("method") != "getPilot":
                continue
            r = obj.get("result") or {}
            mac = norm_mac(r.get("mac", ""))
            if not mac:
                continue
            ip = dg.senderAddress().toString().replace("::ffff:", "")
            b = self.bulbs.get(mac) or Bulb(mac, ip)
            b.ip, b.seen = ip, time.time()
            if time.time() > b.pending_until:
                b.on = bool(r.get("state", b.on))
                if isinstance(r.get("dimming"), int):
                    b.dimming = r["dimming"]
                if r.get("temp"):
                    b.temp, b.rgb = int(r["temp"]), None
                elif all(k in r for k in ("r", "g", "b")):
                    b.rgb, b.temp = [r["r"], r["g"], r["b"]], None
            self.bulbs[mac] = b
            dirty = True
        if dirty:
            self.changed.emit()

    def set(self, mac: str, on=None, dimming=None, kelvin=None, rgb=None):
        mac = norm_mac(mac)
        b = self.bulbs.get(mac)
        if not b:
            return
        p = {}
        if on is not None:
            p["state"] = bool(on); b.on = bool(on)
        if dimming is not None:
            v = max(10, min(100, int(dimming)))
            p.update(dimming=v, state=True); b.dimming = v; b.on = True
        if kelvin is not None:
            v = max(2200, min(6500, int(kelvin)))
            p.update(temp=v, state=True); b.temp, b.rgb, b.on = v, None, True
        if rgb is not None:
            v = [max(0, min(255, int(c))) for c in rgb]
            p.update(r=v[0], g=v[1], b=v[2], state=True); b.rgb, b.temp, b.on = v, None, True
        if not p:
            return
        b.pending_until = time.time() + 3
        self._send(json.dumps({"method": "setPilot", "params": p}).encode(), b.ip)
        self.changed.emit()
