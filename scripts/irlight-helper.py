#!/usr/bin/python3 -I
"""room-irlight — the one thing Room may do as root: switch the Surface's IR lights on or off.

The IR lights beside the face-login camera (an OmniVision OV7251) are wired to the sensor's STROBE pin, which Linux's
driver leaves switched off (linux-surface/kernel#181). Switching it on means writing a few of the sensor's registers
over I2C, which needs root. This does exactly that and nothing else. systemd starts it for each connection to
/run/room-irlight.sock (room-irlight.socket, Accept=yes; only root and your group can connect), it reads one line,
answers one line, and exits:

    on <lines>   the STROBE pin on, flashing on every other frame, each flash <lines> long (52–776, ~1–15 ms)
    off          the STROBE pin off again
    status       whether the camera is streaming and the pin is on

What keeps it narrow: it finds the OV7251 itself (by its driver, in /sys) and is never told where to write; it only
ever writes the registers listed below; the flash length is clamped to the range the Surface uses and the pattern
is always every other frame, so nothing can make the lights brighter, longer or more frequent than this. The sensor
forgets all of it when its stream stops. Installed root-owned by scripts/irlight.sh (Room's copy in the repo isn't
the one that runs).
"""
import ctypes
import fcntl
import glob
import os
import sys

I2C_RDWR, I2C_M_RD = 0x0707, 0x0001     # one combined transfer per read or write, as i2ctransfer does (it worked here)
SPAN = (52, 776)                  # the flash length, in lines (as linux-surface's driver change clamps it)
ON = [(0x3005, 0x08),             # the STROBE pad: an output
      (0x3016, 0x10), (0x3017, 0x00), (0x3018, 0x00), (0x301a, 0x00), (0x301b, 0x00), (0x301c, 0x00),   # pins' drive
      (0x3664, 0xf0),
      (0x3b81, 0xaa),             # the pattern: every other frame (lit and unlit frames, for taking the room out)
      (0x3b8b, 0x00), (0x3b96, 0xc0)]
OFF = [(0x3005, 0x00)]            # the pad back to what the driver leaves it: no flash
SYS = os.environ.get("ROOM_IRLIGHT_SYS", "/sys")      # (set only by tests; the service unit doesn't)
DEV = os.environ.get("ROOM_IRLIGHT_DEV", "/dev")


def sensor():
    """(bus, address) of the OV7251, from its own entry: v4l-subdev name "ov7251 3-0060", driven by ov7251."""
    for d in glob.glob(os.path.join(SYS, "class/video4linux/*")):
        try:
            name = open(os.path.join(d, "name")).read().strip()
        except OSError:
            continue
        if not name.startswith("ov7251 "):
            continue
        drv = os.path.basename(os.path.realpath(os.path.join(d, "device/driver")))
        if drv != "ov7251":
            continue
        bus, _, addr = name.split(" ", 1)[1].partition("-")
        if bus.isdigit() and addr and all(c in "0123456789abcdefABCDEF" for c in addr):
            return int(bus), int(addr, 16)
    return None


class _Msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16), ("len", ctypes.c_uint16),
                ("buf", ctypes.POINTER(ctypes.c_uint8))]


class _RdWr(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(_Msg)), ("nmsgs", ctypes.c_uint32)]


class Chip:
    """The sensor's registers (16-bit addresses, 8-bit values), over the kernel's I2C_RDWR. The bus takes one
    transfer at a time, so this and the camera driver don't trip over each other."""
    def __init__(self, bus, addr):
        self.fd = os.open(os.path.join(DEV, f"i2c-{bus}"), os.O_RDWR)
        self.addr = addr

    def _xfer(self, *msgs):
        arr = (_Msg * len(msgs))()
        keep = []
        for i, (flags, data) in enumerate(msgs):
            b = (ctypes.c_uint8 * len(data)).from_buffer(data)
            keep.append(b)
            arr[i] = _Msg(self.addr, flags, len(data), ctypes.cast(b, ctypes.POINTER(ctypes.c_uint8)))
        fcntl.ioctl(self.fd, I2C_RDWR, _RdWr(arr, len(msgs)))

    def read(self, reg):
        out = bytearray(1)
        self._xfer((0, bytearray([reg >> 8, reg & 0xff])), (I2C_M_RD, out))
        return out[0]

    def write(self, reg, val):
        self._xfer((0, bytearray([reg >> 8, reg & 0xff, val & 0xff])))


def handle(line):
    words = line.split()
    if not words or words[0] not in ("on", "off", "status") or len(words) > 2:
        return "error: say on <lines>, off or status"
    where = sensor()
    if not where:
        return "error: the IR camera (ov7251) isn't there"
    try:
        chip = Chip(*where)
        streaming = chip.read(0x0100) == 0x01
    except OSError as e:
        return f"error: the camera isn't answering ({e.strerror or e}) — is it streaming?"
    if words[0] == "status":
        return f"ok streaming={int(streaming)} pin={'on' if chip.read(0x3005) == 0x08 else 'off'}"
    if not streaming:
        return "error: the camera isn't streaming (it forgets these when it stops, so they'd be lost)"
    if words[0] == "off":
        for r, v in OFF:
            chip.write(r, v)
        return "ok off"
    try:
        span = int(words[1]) if len(words) > 1 else 100
    except ValueError:
        return "error: the flash length is a number of lines"
    span = max(SPAN[0], min(SPAN[1], span))
    for r, v in ON + [(0x3b8c, 0), (0x3b8d, 0), (0x3b8e, span >> 8), (0x3b8f, span & 0xff)]:
        chip.write(r, v)
    return f"ok on {span} lines · pin {'on' if chip.read(0x3005) == 0x08 else 'NOT on'}"


def main():
    line = sys.stdin.readline(64)
    answer = handle(line)
    print(answer, flush=True)
    print(f"room-irlight: {line.strip()!r} → {answer}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
