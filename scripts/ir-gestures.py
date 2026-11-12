"""ir-gestures — the gesture test's eyes, and its guide. Reads raw IR frames from stdin (the IPU3's packing: 25 ten-bit
pixels in 32 bytes) while the IR lights flash on every other frame, and walks you through it step by step — what to
do now, a countdown, a line for every gesture it catches, and how each step went. Keeps nothing. Run by
ir-gestures.sh, which sets up the camera and the lights.

    python ir-gestures.py WIDTH HEIGHT BYTES_PER_ROW NEAR MIRROR(0/1) FLASH_MS

What it looks at: every 4th pixel each way (160×120, stood upright to 120×160) — plenty for a hand, and about 1 ms
of work a frame. A lit frame minus the unlit one next to it is only what the lights reach; light falls off fast with
distance, so a hand near the screen is far brighter there than anything across the room. What's always there and
near (a table edge, a wall, a reflection) is learned while you keep still and taken off, so only what's new counts.
"Near" is how much brighter than that (of 1023) counts as a hand.
"""
import collections
import math
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
COOLDOWN = 0.6             # after a gesture, the next one waits this long

# what to do, for how long, and what it should catch
STEPS = [   # what to say, how long, what it should catch, and how long at its start doesn't count (getting into place)
    ("Get ready: face the Surface, a forearm's length away (30–50 cm). Hands down.", 5, None, 0),
    ("Keep still, hands down — it's learning what the room looks like", 4, "still", 0),
    ("Swipe RIGHT to LEFT across the screen, 3 times (one every second or so)", 9, "←", 0),
    ("Swipe LEFT to RIGHT, 3 times", 9, "→", 0),
    ("Hold your palm up, facing the screen, still — until it says ✋", 6, "✋", 0),
    ("Hands down and step back 2 metres or more (you have 3 s), then wave both arms. This should NOT count", 11, "far", 3),
]
TOTAL = sum(st[1] for st in STEPS)

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


def out(line="", end="\n"):
    sys.stdout.write("\r\033[K" + line + end)
    sys.stdout.flush()


# ---------------------------------------------------------------- the walk-through
step, step_at = -1, 0.0
seen = collections.Counter()            # what was caught in this step
stats = {}                              # this step's brightest hand and largest area
results = []


def begin(i, t):
    global step, step_at, seen, stats
    step, step_at, seen, stats = i, t, collections.Counter(), {"peak": 0.0, "area": 0.0, "seen": 0, "sweep": 0.0}
    text, secs = STEPS[i][:2]
    out(f"\n  ▸ {i} of {len(STEPS) - 1} · {text}  ({secs} s)" if i else f"  ▸ {text}  ({secs} s)")


def finish(t):
    want = STEPS[step][2]
    pk, ar = stats["peak"], stats["area"]
    how = (f" · brightest hand {pk:.0f} (counts above {NEAR:.0f}), largest {ar * 100:.0f} %"
           f" · seen {stats['seen'] / max(1.0, n / max(t, 1.0)):.1f} s")
    if want is None:
        return
    if want == "still":
        line = "    ✓ learned" + (f" · the nearest thing that's always there: {np.percentile(bg, 99.5):.0f}" if bg is not None else "")
    elif want in ("←", "→"):
        other = "→" if want == "←" else "←"
        line = f"    caught {want} {seen[want]} of 3"
        if seen[other]:
            line += f" · and {seen[other]} the other way" + (" — the picture may be mirrored" if seen[other] > seen[want] else "")
        line += how + f" · widest sweep {stats['sweep'] * 100:.0f} % (a swipe needs {SWIPE * 100:.0f})"
        results.append(f"{want} {seen[want]} of 3" + (f" ({seen[other]} reversed)" if seen[other] else ""))
    elif want == "✋":
        line = ("    ✓ caught" if seen["✋"] else "    ✗ not caught") + how
        results.append("✋ " + ("caught" if seen["✋"] else "missed"))
    else:
        k = sum(seen.values())
        line = ("    ✓ nothing counted" if not k else f"    ✗ counted {k} time{'s' * (k > 1)}") + f" · brightest {pk:.0f} (counts above {NEAR:.0f})"
        results.append("far away: " + ("ignored" if not k else f"counted {k}"))
    out(line)


# ---------------------------------------------------------------- what it sees
start = None
means = collections.deque(maxlen=16)            # (frame number, mean): which of the alternating frames are lit
track = collections.deque()                     # (t, x, y, area) while a hand is in view
prev = bg = None
n = lit_frames = 0
held = False
quiet_until = gone_at = 0.0
flash_gain, countdown, t_end = [], -1, 0.0

while (raw := read_frame()) is not None:
    now = time.monotonic()
    start = start if start is not None else now
    t = now - start
    while step + 1 < len(STEPS) and t >= sum(st[1] for st in STEPS[:step + 1]):
        if step >= 0:
            finish(t)
        begin(step + 1, t)
        track.clear()       # (not "held": a palm still up from the last step isn't a new hold)
    if step >= 0 and t >= TOTAL:
        finish(t); step = -2
        break
    t_end = t
    left = max(1, math.ceil(step_at + STEPS[step][1] - t))
    if left != countdown:
        countdown = left
        out(f"    {left} s", end="")

    f = small(raw)
    means.append((n, float(f.mean())))
    if prev is not None:
        even = [m for i, m in means if i % 2 == 0]
        odd = [m for i, m in means if i % 2 == 1]
        lit_par = 0 if np.mean(even) >= np.mean(odd) else 1
        flash_gain.append(abs(np.mean(even) - np.mean(odd)))
        lit, dark = (f, prev) if n % 2 == lit_par else (prev, f)
        lit_frames += n % 2 == lit_par
        near = (lit - dark).clip(0)
        if bg is None:
            bg = near.copy()
        fg = near - bg
        mask = fg > NEAR
        # learn what's always there: all of it, quickly, while you get ready and keep still (the lights come on
        # during that, and everything they reach is new then); after that slowly, and never where a hand is
        if STEPS[step][2] in (None, "still"):
            bg += 0.15 * (near - bg)
        else:
            bg += np.where(mask, 0, 0.01 * (near - bg))
        area = float(mask.mean())
        live = STEPS[step][2] not in (None, "still") and t - step_at >= STEPS[step][3]
        if live:
            stats["peak"] = max(stats["peak"], float(np.percentile(fg, 99.5)))
            stats["area"] = max(stats["area"], area)
            stats["seen"] += area >= MIN_AREA
        if area >= MIN_AREA and live:
            ys, xs = np.nonzero(mask)
            x, y = xs.mean() / mask.shape[1], ys.mean() / mask.shape[0]
            if MIRROR:
                x = 1 - x
            track.append((t, x, y, area))
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
            stats["sweep"] = max(stats["sweep"], abs(dx))
            xs_, ys_, ar = [p[1] for p in track], [p[2] for p in track], [p[3] for p in track]
            got = None
            if abs(dx) >= SWIPE and abs(dx) >= 1.5 * abs(dy):
                got = "←" if dx > 0 else "→"            # the camera faces you: the picture's right is your left
                track.clear()
            elif (not held and t - t0 >= HOLD - 0.1 and max(xs_) - min(xs_) <= STILL and max(ys_) - min(ys_) <= STILL
                  and max(ar) <= 1.6 * min(ar)):
                got = "✋"; held = True
            if got:
                seen[got] += 1; quiet_until = t + COOLDOWN
                what = {"←": "← right to left (next track)", "→": "→ left to right (previous track)", "✋": "✋ hold (play/pause)"}[got]
                bad = "  ← shouldn't have counted" if STEPS[step][2] == "far" else ""
                out(f"    {what}{bad}")
                countdown = -1
    prev = f
    n += 1

if step >= 0:                               # the camera stopped first: still say how the last step went
    finish(t_end)
while sys.stdin.buffer.readinto(view):      # let the camera finish its last frames
    pass
out()
el = t_end if start is not None else 0
if n < 4:
    print("  ✗ too few frames came through")
    sys.exit(1)
print("  ── how it went: " + " · ".join(results))
print(f"  the lights: {lit_frames} flashes of {FLASH_MS:.1f} ms = {lit_frames * FLASH_MS / 1000:.1f} s lit in {el:.0f} s ·"
      f" lit frames {np.median(flash_gain):.0f} brighter (≈0 = the lights didn't fire) · {n / max(el, 1):.0f} frames a second")
