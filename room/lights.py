"""Rooms of named lights from config.json, and what the screen shows for each room.
Commands take a room (or every room), like the iPhone panel's 'one room / all lights' calls."""
from PySide6.QtCore import QObject, Signal

from .wiz import WizClient, norm_mac


def k_name(k: int) -> str:
    return "Candle" if k < 2600 else "Warm" if k < 3300 else "Neutral" if k < 4500 else "Cool" if k < 5600 else "Daylight"


COLOURS = {"Coral": (255, 110, 80), "Amber": (255, 165, 50), "Pink": (255, 70, 160),
           "Violet": (140, 100, 255), "Sky": (60, 160, 255), "Mint": (60, 210, 150)}


def colour_name(c) -> str:
    best, bd = "Colour", 10 ** 9
    for n, x in COLOURS.items():
        d = sum(abs(a - b) for a, b in zip(x, c))
        if d < bd:
            best, bd = n, d
    return best if bd < 120 else "Colour"


def glow_of(k: int | None, rgb) -> list[int]:
    if rgb:
        return list(rgb)
    k = k or 2700
    return [255, 190, 122] if k < 3000 else [255, 226, 189] if k < 4500 else [227, 236, 255]


class Lights(QObject):
    changed = Signal()

    def __init__(self, rooms: list[dict], here: str):
        super().__init__()
        self.here = here or ""
        # the room the panel is in comes first — it's the one you reach for
        self.rooms = sorted(rooms, key=lambda r: 0 if r.get("name") == self.here else 1)
        devices = [d for r in self.rooms for d in r.get("devices", [])]
        self.wiz = WizClient([d.get("ip", "") for d in devices if d.get("type") == "wiz"])
        self.wiz.changed.connect(self.changed)

    def start(self):
        self.wiz.start()

    def _bulbs(self, room: dict):
        for d in room.get("devices", []):
            if d.get("type") == "wiz":
                b = self.wiz.bulbs.get(norm_mac(d.get("mac", "")))
                if b:
                    yield b

    def snapshot(self) -> list[dict]:
        out = []
        for r in self.rooms:
            bulbs = list(self._bulbs(r))
            total = len(r.get("devices", []))
            reach = [b for b in bulbs if b.reachable]
            on = [b for b in reach if b.on]
            bri = round(sum(b.dimming for b in on) / len(on)) if on else 0
            ks = [b.temp for b in on if b.temp]
            k = round(sum(ks) / len(ks)) if ks else None
            rgb = next((b.rgb for b in on if b.rgb), None)
            if not reach:
                sub = "Not found"
            elif not on:
                sub = "Off"
            elif rgb and not k:
                sub = colour_name(rgb)
            else:
                sub = f"{k_name(k or 2700)} · {k or 2700}K"
            out.append({
                "name": r.get("name", ""),
                "here": r.get("name") == self.here,
                "total": total, "reachable": len(reach), "on": len(on),
                "level": bri, "kelvin": k or 2700, "rgb": list(rgb) if rgb else [],
                "glow": glow_of(k, rgb), "sub": sub,
                "lamps": self._lamps(r),
            })
        return out

    def _lamps(self, room: dict) -> list[dict]:
        out = []
        for i, d in enumerate(room.get("devices", [])):
            b = self.wiz.bulbs.get(norm_mac(d.get("mac", ""))) if d.get("type") == "wiz" else None
            out.append({"id": norm_mac(d.get("mac", "")) or str(i), "name": d.get("name") or f"Lamp {i + 1}",
                        "reachable": bool(b and b.reachable), "on": bool(b and b.reachable and b.on),
                        "level": b.dimming if b else 0})
        return out

    def lamps_now(self) -> list[dict]:
        """Every light, for the assistant: id, name, room, on/off and what it's set to."""
        out = []
        for r in self.rooms:
            for i, d in enumerate(r.get("devices", [])):
                b = self.wiz.bulbs.get(norm_mac(d.get("mac", ""))) if d.get("type") == "wiz" else None
                o = {"id": norm_mac(d.get("mac", "")) or f"{r.get('name')}-{i}", "name": d.get("name") or f"lamp {i + 1}",
                     "room": r.get("name", ""), "state": "unavailable" if not (b and b.reachable) else ("on" if b.on else "off")}
                if b and b.on:
                    o["brightness"] = b.dimming
                    if b.temp: o["kelvin"] = b.temp
                    if b.rgb: o["rgb"] = list(b.rgb)
                out.append(o)
        return out

    def set_lamps(self, ids, on=None, level=None, kelvin=None, rgb=None) -> int:
        n = 0
        for mac in ids:
            b = self.wiz.bulbs.get(norm_mac(mac))
            if b:
                self.wiz.set(b.mac, on=on, dimming=level, kelvin=kelvin, rgb=rgb); n += 1
        self.changed.emit()
        return n

    def toggle_lamp(self, mac: str):
        b = self.wiz.bulbs.get(norm_mac(mac))
        if b:
            self.wiz.set(b.mac, on=not b.on)
            self.changed.emit()

    def counts(self):
        s = self.snapshot()
        return sum(r["on"] for r in s), sum(r["total"] for r in s)

    def _targets(self, name: str | None):
        return [r for r in self.rooms if name in (None, "", "*") or r.get("name") == name]

    def set_room(self, name, on=None, level=None, kelvin=None, rgb=None):
        for r in self._targets(name):
            for b in self._bulbs(r):
                self.wiz.set(b.mac, on=on, dimming=level, kelvin=kelvin, rgb=rgb)
        self.changed.emit()

    def toggle_room(self, name):
        rooms = [x for x in self.snapshot() if x["name"] == name]
        self.set_room(name, on=not (rooms and rooms[0]["on"] > 0))

    def dim_all(self):
        for r in self.rooms:
            for b in self._bulbs(r):
                if b.on:
                    self.wiz.set(b.mac, dimming=max(10, b.dimming // 2))
        self.changed.emit()
