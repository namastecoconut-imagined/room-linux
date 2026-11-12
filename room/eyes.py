"""Hand gestures for the music, with the Surface's IR camera — the face-login one beside the front camera, an
OmniVision OV7251 (640 × 480, greyscale, no picture is ever kept or sent anywhere).

  swipe right to left → next track · swipe left to right → previous · hold your palm up still → play / pause

It watches only while music is playing or paused (Backend.want_eyes), through the camera's raw stream (v4l2-ctl,
underneath libcamera, which doesn't offer this camera). Its IR lights flash on every other frame, switched by
Room's IR-lights helper (scripts/irlight.sh — the one thing Room does as root): a lit frame minus the unlit one
beside it is only what the lights reach, and light falls off fast with distance, so a hand near the screen stands
far above the room behind it, whatever the daylight or the lamps. What's always there is learned and taken off.

Gentle on the lights (they were made for a few seconds of face login): a short flash (1.9 ms; Windows uses about
three times that), on every other frame, 15 frames a second while nothing's near and 30 only while a hand is —
about 1.5 % of the time lit at most — and never more than LIGHT_CAP seconds of light in an hour: past that it stops
until the hour is up. If Room stops or crashes, the camera stops and the sensor forgets the lights by itself.
Every number here was measured with scripts/ir-gestures.sh (12 Nov): a hand at a forearm's length came out at
~960–985 of 1023 above the room, 11–25 % of the picture, and was followed 51–73 % across in a swipe.

config.json: "gestures": {"enabled": true, "near": 300, "gain": 96}.
"""
import collections
import os
import re
import socket
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Signal

try:                        # (Room's own Python has it from requirements; without it, gestures stay off — Room runs)
    import numpy as np
except Exception:           # noqa: BLE001
    np = None

W, H = 640, 480
EXPOSURE = 100              # lines: the exposure, and the flash lasts as long
GAIN = 96                   # amplification (16ths: 6×) — instead of more light
FPS_IDLE, FPS_ACTIVE = 15, 30
NEAR = 300                  # how much brighter than the room (of 1023) counts as a hand
MIN_AREA = 0.02             # a hand covers at least 2 % of the picture…
HOLD_AREA = 0.20            # …and a held palm at most 20 % (more is a person standing close, not a hand)
HOLD_BRIGHT = 650           # …and close: half of it this bright at least (a face a forearm away was ~700 at its
                            # brightest point, a palm ~960 — the palm is nearer, so brighter all over)
SWIPE_AREA = 0.35           # a swipe is a hand: something bigger crossing is a person walking past
SWIPE = 0.35                # a swipe crosses at least 35 % of the picture…
WINDOW = 0.8                # …within 0.8 s, and mostly sideways
HOLD = 1.0                  # a palm held this long, nearly still, is a hold…
STILL = 0.05                # …("nearly still": wandering less than 5 % of the picture)…
FRESH = 2.5                 # …and it must have come into view just before (someone standing there isn't a hold)
COOLDOWN = 0.6              # after a gesture, the next waits this long
OPPOSITE = 1.0              # …and the other direction this long (the hand coming back isn't a swipe)
ABSORB = 10.0               # anything still in view this long becomes part of the room
LIGHT_CAP = 90.0            # seconds of light in any hour, at most
SOCK = "/run/room-irlight.sock"


def log(*a):
    print("[room] gestures:", *a, flush=True)


def helper(cmd: str) -> str:
    """Room's IR-lights helper (scripts/irlight-helper.py, run as root by systemd): "on <lines>", "off", "status"."""
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(5)
            s.connect(SOCK)
            s.sendall(cmd.encode() + b"\n")
            return s.recv(200).decode(errors="replace").strip() or "error: no answer"
    except OSError as e:
        return f"error: {e.strerror or e}"


def run(*cmd) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout


class Camera:
    """The OV7251's pipeline: its media graph, linked and set to 640 × 480 10-bit, and its controls."""
    def __init__(self):
        self.m = ""
        for m in sorted(f"/dev/{d}" for d in os.listdir("/dev") if d.startswith("media")):
            if re.search(r"entity \d+: ov7251 ", run("media-ctl", "-d", m, "-p")):
                self.m = m
                break
        if not self.m:
            raise RuntimeError("the IR camera isn't in any media graph")
        topo = run("media-ctl", "-d", self.m, "-p")
        self.ov = re.search(r"entity \d+: (ov7251 [\d-]+) ", topo).group(1)
        after = topo.split(f": {self.ov} ", 1)[1]
        self.csi = re.search(r'-> "([^"]+)"', after).group(1)
        self.cio = self.csi.replace("ipu3-csi2", "ipu3-cio2")
        self.vid = run("media-ctl", "-d", self.m, "-e", self.cio).strip()
        self.sub = run("media-ctl", "-d", self.m, "-e", self.ov).strip()

    def setup(self):
        f = f"fmt:Y10_1X10/{W}x{H}"
        run("media-ctl", "-d", self.m, "-l", f'"{self.ov}":0 -> "{self.csi}":0[1]')
        run("media-ctl", "-d", self.m, "-V", f'"{self.ov}":0 [{f}]')
        run("media-ctl", "-d", self.m, "-V", f'"{self.csi}":0 [{f}]')
        run("media-ctl", "-d", self.m, "-V", f'"{self.csi}":1 [{f}]')
        run("v4l2-ctl", "-d", self.vid, f"--set-fmt-video=width={W},height={H},pixelformat=ip3y")
        bpl = re.search(r"Bytes per Line\s*:\s*(\d+)", run("v4l2-ctl", "-d", self.vid, "--get-fmt-video"))
        self.bpl = int(bpl.group(1)) if bpl else 832

    def get(self, name):
        m = re.search(r":\s*(-?\d+)", run("v4l2-ctl", "-d", self.sub, "--get-ctrl", name))
        return int(m.group(1)) if m else None

    def set(self, **kv):
        args = []
        for k, v in kv.items():
            args += ["--set-ctrl", f"{k}={v}"]
        run("v4l2-ctl", "-d", self.sub, *args)

    def vblank(self, fps):
        """The vertical blanking for this many frames a second (a frame is (height + blanking) lines)."""
        rate, hb = self.get("pixel_rate") or 48_000_000, self.get("horizontal_blanking") or 288
        return max(1, int(rate / ((W + hb) * fps)) - H)

    def flash_s(self):
        rate, hb = self.get("pixel_rate") or 48_000_000, self.get("horizontal_blanking") or 288
        return EXPOSURE * (W + hb) / rate


class Eyes(QObject):
    gesture = Signal(str, str)          # next · previous · playpause, and what was seen (for the log)
    watchingChanged = Signal()

    def __init__(self, cfg: dict | None = None):
        super().__init__()
        cfg = cfg or {}
        self.enabled = cfg.get("enabled", True) is not False
        self.near = float(cfg.get("near", NEAR))
        self.gain = int(cfg.get("gain", GAIN))
        self.watching = False
        self._session = None                    # the running one: {"stop", "proc", "thread"}
        self._light = collections.deque()       # (when, seconds of light) for the hourly cap
        self._rest_until = 0.0
        self._said = set()

    # ---- on and off (from the main thread; Backend asks every time the music changes, and every 30 s)
    def want(self, on: bool):
        if np is None:
            if on:
                self._once("numpy", "off — numpy isn't installed for Room (room-update installs it)")
            return
        on = bool(on) and self.enabled and time.time() >= self._rest_until
        s = self._session
        running = bool(s and s["thread"].is_alive() and not s["stop"].is_set())
        if on and not running:
            new = {"stop": threading.Event(), "proc": None}
            new["thread"] = threading.Thread(target=self._run, args=(new, s), name="eyes", daemon=True)
            self._session = new
            new["thread"].start()
        elif not on and running:
            s["stop"].set()
            p = s["proc"]
            if p and p.poll() is None:
                p.terminate()

    def _once(self, key, *a):
        if key not in self._said:
            self._said.add(key)
            log(*a)

    def _watching(self, on):
        if on != self.watching:
            self.watching = on
            self.watchingChanged.emit()

    def light_last_hour(self):
        now = time.time()
        while self._light and now - self._light[0][0] > 3600:
            self._light.popleft()
        return sum(s for _, s in self._light)

    # ---- the camera (its own thread)
    def _run(self, me, before):
        cam = saved = None
        if before and before["thread"].is_alive():     # the last one still letting go of the camera
            before["thread"].join(5)
        try:
            if not os.path.exists(SOCK):
                self._once("helper", "off — the IR-lights helper isn't set up (bash ~/room/scripts/irlight.sh)")
                return
            cam = Camera()
            cam.setup()
            saved = {k: cam.get(k) for k in ("exposure", "analogue_gain", "vertical_blanking")}
            idle, active = cam.vblank(FPS_IDLE), cam.vblank(FPS_ACTIVE)
            cam.set(exposure=EXPOSURE, analogue_gain=self.gain, vertical_blanking=idle)
            flash = cam.flash_s()
            if me["stop"].is_set():
                return
            me["proc"] = subprocess.Popen(["v4l2-ctl", "-d", cam.vid, "--stream-mmap=4", "--stream-to=-"],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self._watch(me, cam, flash, idle, active)
        except Exception as e:
            log(f"stopped — {e!r}")
        finally:
            p = me["proc"]
            if p and p.poll() is None:
                p.terminate()
                try:
                    p.wait(3)
                except Exception:
                    p.kill()
            if cam and saved:
                try:
                    cam.set(**{k: v for k, v in saved.items() if v is not None})
                except Exception:
                    pass
            if me["stop"].is_set():
                log("stopped (no music now)")
            me["stop"].set()            # (ended by itself: Backend's next check starts it again if still wanted)
            if self._session is me:
                self._watching(False)

    def _watch(self, me, cam, flash, idle, active):
        size = cam.bpl * H
        buf = bytearray(size)
        view = memoryview(buf)
        cols = np.arange(0, W, 4)
        bit = (cols // 25) * 256 + (cols % 25) * 10        # every 4th pixel, straight from the IPU3's packing
        byte, shift = bit // 8, (bit % 8).astype(np.uint16)
        out = me["proc"].stdout
        means = collections.deque(maxlen=16)
        track = collections.deque()
        prev = bg = None
        n = 0
        start = time.monotonic()
        lights_on = False
        fast = False
        near_at = 0.0
        held = False
        armed = True
        quiet_until = 0.0
        last_dir, last_dir_at = "", -9.0
        gone_at = 0.0
        seen_at = 0.0
        hour_said = cap_at = time.time()
        while not me["stop"].is_set():
            got = 0
            while got < size:
                k = out.readinto(view[got:])
                if not k:
                    return
                got += k
            t = time.monotonic() - start
            if not lights_on:
                ans = helper(f"on {EXPOSURE}")
                if not ans.startswith("ok"):
                    if n > 30:
                        log(f"stopped — the IR lights wouldn't come on ({ans})")
                        return
                else:
                    lights_on, start = True, time.monotonic()
                    t = 0.0
                    self._watching(True)
                    log(f"watching — IR lights {flash * 1000:.1f} ms on every other frame, {FPS_IDLE} frames a second"
                        f" ({FPS_ACTIVE} while a hand is near)")
            raw = np.frombuffer(buf, np.uint8).reshape(H, cam.bpl)
            r = raw[::4].astype(np.uint16)
            f = np.rot90(((r[:, byte] | (r[:, byte + 1] << 8)) >> shift) & 0x3FF).astype(np.float32)
            means.append((n, float(f.mean())))
            if prev is not None and lights_on:
                even = [m for i, m in means if i % 2 == 0]
                odd = [m for i, m in means if i % 2 == 1]
                lit_par = 0 if np.mean(even) >= np.mean(odd) else 1
                lit, dark = (f, prev) if n % 2 == lit_par else (prev, f)
                if n % 2 == lit_par:
                    self._light.append((time.time(), flash))
                near = (lit - dark).clip(0)
                if bg is None:
                    bg = near.copy()
                fg = near - bg
                mask = fg > self.near
                area = float(mask.mean())
                # what's always there: learned quickly at first, then slowly and never where a hand is — except
                # something that's stood still in view for ABSORB s (someone standing there) becomes the room too
                if t < 2.0:
                    bg += 0.15 * (near - bg)
                elif track and t - seen_at > ABSORB:
                    bg += 0.05 * (near - bg)
                else:
                    bg += np.where(mask, 0, 0.01 * (near - bg))
                present = area >= MIN_AREA and t >= 2.0
                if present:
                    ys, xs = np.nonzero(mask)
                    x, y = xs.mean() / mask.shape[1], ys.mean() / mask.shape[0]
                    if not track:
                        seen_at = t
                    track.append((t, x, y, area))
                    gone_at = 0.0
                    near_at = t
                elif track and not gone_at:
                    gone_at = t
                if gone_at and t - gone_at > 0.15:           # the hand has gone: ready for the next one
                    track.clear(); held = False; armed = True; gone_at = 0.0
                while track and t - track[0][0] > max(WINDOW, HOLD + 0.1):
                    track.popleft()
                # faster while a hand is near, back to idle 3 s after
                want_fast = t - near_at < 3.0 and near_at > 0
                if want_fast != fast:
                    fast = want_fast
                    cam.set(vertical_blanking=active if fast else idle)
                if present and track and t >= quiet_until:
                    sw = [p for p in track if t - p[0] <= WINDOW]          # a swipe: the last WINDOW s
                    t0, x0, y0, _ = sw[0]
                    dx, dy = x - x0, y - y0
                    hold = [p for p in track if t - p[0] <= HOLD]          # a hold: the last HOLD s
                    xs_, ys_, ar = [p[1] for p in hold], [p[2] for p in hold], [p[3] for p in hold]
                    th = hold[0][0]
                    peak = float(np.percentile(fg, 99.5))
                    body = float(np.median(fg[mask]))           # how bright the hand is, all over (not its brightest point)
                    if armed and abs(dx) >= SWIPE and abs(dx) >= 1.5 * abs(dy) and max(p[3] for p in sw) <= SWIPE_AREA:
                        d = "next" if dx > 0 else "previous"    # the camera faces you: the picture's right is your left
                        if not (last_dir and d != last_dir and t - last_dir_at < OPPOSITE):
                            self.gesture.emit(d, f"crossed {abs(dx) * 100:.0f} % in {t - t0:.2f} s · hand"
                                                 f" {area * 100:.0f} % · {body:.0f} bright ({peak:.0f} at most)")
                            last_dir, last_dir_at = d, t
                        track.clear(); armed = False; quiet_until = t + COOLDOWN
                    elif (not held and t - th >= HOLD - 0.1 and t - seen_at <= FRESH + HOLD
                          and max(xs_) - min(xs_) <= STILL and max(ys_) - min(ys_) <= STILL
                          and max(ar) <= 1.6 * min(ar) and max(ar) <= HOLD_AREA and body >= HOLD_BRIGHT):
                        self.gesture.emit("playpause", f"held {t - th:.1f} s · palm {area * 100:.0f} % · {body:.0f} bright"
                                                       f" ({peak:.0f} at most)")
                        held = True; quiet_until = t + COOLDOWN
                # the hourly cap on light (looked at once a minute)
                if time.time() - cap_at > 60 and self.light_last_hour() >= LIGHT_CAP:
                    self._rest_until = time.time() + 600
                    log(f"stopped for 10 min — the IR lights were on {self.light_last_hour():.0f} s in the last hour"
                        f" (the cap is {LIGHT_CAP:.0f} s)")
                    return
                if time.time() - cap_at > 60:
                    cap_at = time.time()
                if time.time() - hour_said > 3600:
                    hour_said = time.time()
                    log(f"the IR lights were on {self.light_last_hour():.0f} s in the last hour")
            prev = f
            n += 1
