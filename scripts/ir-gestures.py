"""ir-gestures — the gesture test's eyes. Reads raw IR frames from stdin (the IPU3's packing: 25 ten-bit pixels in
32 bytes) while the IR lights flash on every other frame, and shows what it sees: a live line, each gesture as it
happens, and a summary at the end. Keeps nothing. Run by ir-gestures.sh, which sets up the camera and the lights.

    python ir-gestures.py WIDTH HEIGHT BYTES_PER_ROW NEAR MIRROR(0/1) FLASH_MS

What it looks at: every 4th pixel each way (160×120, stood upright to 120×160) — plenty for a hand, and about
1 ms of work a frame. A lit frame minus the unlit one next to it is only what the lights reach; light falls off
fast with distance, so a hand near the screen is far brighter there than someone across the room. "Near" is
the brightness (of 1023) that counts as a hand.
"""
import collections
import sys
import time

import numpy as np

W, H, BPL = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
NEAR, MIRROR, FLASH_MS = float(sys.argv[4]), sys.argv[5] == "1", float(sys.argv[6])
SIZE = BPL * H
MIN_AREA = 0.02            # a hand covers at least 2 % of the picture
SWIPE = 0.35               # …and a swipe crosses at least 35 % of its width
WINDOW = 0.8               # …within 0.8 s
HOLD = 0.8                 # a palm held this long, nearly still, is a hold
STILL = 0.05               # "nearly still": wanders less than 5 % of the picture
COOLDOWN = 0.8             # after a gesture, the next one waits this long

# every 4th pixel, read straight out of the packing: pixel c is at bit (c // 25) * 256 + (c % 25) * 10 of its row
_cols = np.arange(0, W, 4)
_bit = (_cols // 25) * 256 + (_cols % 25) * 10
BYTE, SHIFT = _bit // 8, (_bit % 8).astype(np.uint16)


def small(raw):
    r = raw[::4].astype(np.uint16)
    img = ((r[:, BYTE] | (r[:, BYTE + 1] << 8)) >> SHIFT) & 0x3FF
    return np.rot90(img).astype(np.float32)      # the sensor sits sideways: a quarter turn anticlockwise


buf = bytearray(SIZE)
view = memoryview(buf)


def read_frame():
    got = 0
    while got < SIZE:
        n = sys.stdin.buffer.readinto(view[got:])
        if not n:
            return None
        got += n
    return np.frombuffer(buf, np.uint8).reshape(H, BPL)


def say(line):
    sys.stdout.write("\r\033[K" + line + "\n")
    sys.stdout.flush()


start = time.monotonic()
means = collections.deque(maxlen=16)            # (frame number, mean): which of the alternating frames are lit
track = collections.deque()                     # (t, x, y, area) while a hand is in view
prev = last_dark = None
n = lit_frames = 0
held = False
quiet_until = gone_at = 0.0
counts = collections.Counter()
peaks, areas, moving_all, flash_gain = [], [], [], []
status_at = 0.0
ambient = moving = peak = gain = 0.0

while (raw := read_frame()) is not None:
    t = time.monotonic() - start
    f = small(raw)
    means.append((n, float(f.mean())))
    if prev is not None:
        even = [m for i, m in means if i % 2 == 0]
        odd = [m for i, m in means if i % 2 == 1]
        lit_par = 0 if np.mean(even) >= np.mean(odd) else 1
        gain = abs(np.mean(even) - np.mean(odd))           # how much brighter the lit frames are, on average
        lit, dark = (f, prev) if n % 2 == lit_par else (prev, f)
        if n % 2 == lit_par:
            lit_frames += 1
        else:                                               # an unlit frame: the room as it is, and what moved in it
            ambient = float(f.mean())
            if last_dark is not None:
                d = np.abs(f - last_dark)
                moving = float((d > max(10.0, 4 * float(np.median(d)))).mean())
                moving_all.append(moving)
            last_dark = f
        near = (lit - dark).clip(0)
        peak = float(np.percentile(near, 99.5))
        mask = near > NEAR
        area = float(mask.mean())
        peaks.append(peak)
        flash_gain.append(gain)
        if area >= MIN_AREA:
            ys, xs = np.nonzero(mask)
            x, y = xs.mean() / mask.shape[1], ys.mean() / mask.shape[0]
            if MIRROR:
                x = 1 - x
            track.append((t, x, y, area))
            areas.append(area)
            gone_at = 0.0
        elif track and not gone_at:
            gone_at = t
        if gone_at and t - gone_at > 0.25:                  # the hand has gone
            track.clear(); held = False; gone_at = 0.0
        while track and t - track[0][0] > WINDOW:
            track.popleft()
        if track and t >= quiet_until and area >= MIN_AREA:
            t0, x0, y0, _ = track[0]
            dx, dy = x - x0, y - y0
            xs_, ys_ = [p[1] for p in track], [p[2] for p in track]
            ar = [p[3] for p in track]
            if abs(dx) >= SWIPE and abs(dx) >= 1.5 * abs(dy):
                # the camera faces you: moving to the picture's right is moving to your left
                name = "← swipe right to left  (would be: next track)" if dx > 0 else "→ swipe left to right  (would be: previous track)"
                counts["←" if dx > 0 else "→"] += 1
                say(f"  {t:5.1f} s  {name}   [crossed {abs(dx) * 100:.0f} % in {t - t0:.2f} s]")
                track.clear(); quiet_until = t + COOLDOWN
            elif (not held and t - t0 >= HOLD - 0.1 and max(xs_) - min(xs_) <= STILL and max(ys_) - min(ys_) <= STILL
                  and max(ar) <= 1.6 * min(ar)):
                counts["✋"] += 1
                say(f"  {t:5.1f} s  ✋ hold  (would be: play/pause)   [{area * 100:.0f} % of the picture]")
                held = True; quiet_until = t + COOLDOWN
        if t - status_at >= 0.25:
            status_at = t
            fps = n / t if t > 0 else 0
            hand = f" · hand {area * 100:3.0f} % at {x:.2f},{y:.2f}" if area >= MIN_AREA else " · no hand"
            sys.stdout.write(f"\r\033[K  {t:5.1f} s · {fps:4.1f} fps · room light {ambient:4.0f} · moving {moving * 100:3.0f} %"
                             f" · lights +{gain:3.0f} · nearest {peak:4.0f}{hand}")
            sys.stdout.flush()
    prev = f
    n += 1

t = time.monotonic() - start
sys.stdout.write("\r\033[K")
if n < 4:
    print("  ✗ too few frames came through")
    sys.exit(1)
pk = np.array(peaks)
print(f"  {n} frames in {t:.0f} s ({n / t:.1f} a second)")
print(f"  the lights: {lit_frames} flashes of {FLASH_MS:.1f} ms = {lit_frames * FLASH_MS / 1000:.1f} s lit in all;"
      f" lit frames {np.median(flash_gain):.0f} brighter on average (≈0 = the lights didn't fire)")
print(f"  nearest thing (lit minus unlit, of 1023): usually {np.median(pk):.0f}, at most {pk.max():.0f}"
      f" · a hand counts above {NEAR:.0f}")
print(f"  a hand was in view {len(areas) / max(1, len(peaks)) * 100:.0f} % of the time"
      + (f", covering {np.median(areas) * 100:.0f} % of the picture (largest {max(areas) * 100:.0f} %)" if areas else ""))
if moving_all:
    print(f"  movement in the room: usually {np.median(moving_all) * 100:.0f} %, at most {max(moving_all) * 100:.0f} % of the picture")
print(f"  gestures: ← {counts['←']} · → {counts['→']} · ✋ {counts['✋']}")
