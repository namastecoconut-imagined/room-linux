"""ir-gestures — the gesture test's eyes, and its guide. Reads raw IR frames from stdin (the IPU3's packing: 25 ten-bit
pixels in 32 bytes) while the IR lights flash on every other frame, and walks you through it at your pace: each step
says what to do and waits for Enter, counts you in, watches for a few seconds (● whenever it sees your hand, a line
for every gesture it catches), then says how that step went. Keeps nothing. Run by ir-gestures.sh, which sets up the
camera and the lights; it reads Enter from the terminal (/dev/tty), since stdin is the camera.

    python ir-gestures.py WIDTH HEIGHT BYTES_PER_ROW NEAR MIRROR(0/1) FLASH_MS

What it looks at: every 4th pixel each way (160×120, stood upright to 120×160) — plenty for a hand, and about 1 ms
of work a frame. A lit frame minus the unlit one next to it is only what the lights reach; light falls off fast with
distance, so a hand near the screen is far brighter there than anything across the room. What's always there and
near (a table edge, a wall, you standing in front of it) is learned while you keep still and taken off, so only
what's new counts. "Near" is how much brighter than that (of 1023) counts as a hand.
"""
import collections
import math
import select
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
COUNT_IN = 3               # "3, 2, 1" after Enter

# what to do; how long it watches; what it should catch; how long at the start doesn't count (getting into place)
STEPS = [
    ("Stand facing the Surface, a forearm's length away (30–50 cm), hands down.\n"
     "    It learns what's in front of it while you keep still.", 4, "still", 0),
    ("Swipe RIGHT to LEFT, 3 times, one every second or so.\n"
     "    Through the air in front of the camera (the top edge of the screen): level with it, a hand's length out,\n"
     "    not along the glass. ● shows whenever it sees your hand.", 8, "←", 0),
    ("Swipe LEFT to RIGHT, 3 times, the same way.", 8, "→", 0),
    ("Hold your palm up in front of the camera, facing it, and keep it still until ✋ appears.", 6, "✋", 0),
    ("Put your hands down and step back 2 metres or more (you have 3 s), then wave both arms.\n"
     "    This one should NOT count.", 10, "far", 3),
]

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
        k = sys.stdin.buffer.readinto(view[got:])
        if not k:
            return None
        got += k
    return np.frombuffer(buf, np.uint8).reshape(H, BPL)


def out(line="", end="\n"):
    sys.stdout.write("\r\033[K" + line + end)
    sys.stdout.flush()


try:                                    # the keyboard (stdin is the camera)
    TTY = open("/dev/tty")
except OSError:
    TTY = None


def enter():
    if TTY is None:
        return None
    if select.select([TTY], [], [], 0)[0]:
        TTY.readline()
        return True
    return False


# ---------------------------------------------------------------- the walk-through
step, phase, phase_at = 0, "wait", 0.0          # wait (for Enter) → count (3, 2, 1) → live (watching) → next step
seen = collections.Counter()                    # what was caught in this step
stats = {}
results = []


def show_step():
    text, secs = STEPS[step][:2]
    out(f"\n  ▸ {step + 1} of {len(STEPS)} · {text}")
    out("    Press Enter when you're ready" if TTY else "    (starting in a moment)", end="")


def finish(fps):
    want = STEPS[step][2]
    pk, ar = stats["peak"], stats["area"]
    how = (f" · brightest hand {pk:.0f} (counts above {NEAR:.0f}), largest {ar * 100:.0f} %"
           f" · seen {stats['seen'] / max(fps, 1.0):.1f} s")
    if want == "still":
        line = "    ✓ learned" + (f" · the brightest thing in front of it: {np.percentile(bg, 99.5):.0f}" if bg is not None else "")
    elif want in ("←", "→"):
        other = "→" if want == "←" else "←"
        line = f"    caught {want} {seen[want]} of 3" + (f" · and {seen[other]} the other way" if seen[other] else "")
        line += how + f" · widest sweep {stats['sweep'] * 100:.0f} % (a swipe needs {SWIPE * 100:.0f})"
        results.append(f"{want} {seen[want]} of 3" + (f" (+{seen[other]} {other})" if seen[other] else ""))
    elif want == "✋":
        line = ("    ✓ caught" if seen["✋"] else "    ✗ not caught") + how + (f" · and {sum(seen.values()) - seen['✋']} swipes" if sum(seen.values()) > seen["✋"] else "")
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
flash_gain, shown, t = [], None, 0.0
done = False

while (raw := read_frame()) is not None:
    now = time.monotonic()
    start = start if start is not None else now
    t = now - start
    fps = n / t if t > 0.5 else 30.0
    want, secs, grace = STEPS[step][2], STEPS[step][1], STEPS[step][3]

    # ---- the steps
    if n == 0:
        show_step()
    if phase == "wait":
        e = enter()
        if e or (e is None and t - phase_at > 5):
            phase, phase_at, shown = "count", t, None
    elif phase == "count":
        c = COUNT_IN - int(t - phase_at)
        if c <= 0:
            phase, phase_at, shown = "live", t, None
            seen, stats = collections.Counter(), {"peak": 0.0, "area": 0.0, "seen": 0, "sweep": 0.0}
            track.clear()           # (not "held": a palm still up from the last step isn't a new hold)
        elif shown != c:
            shown = c
            out(f"    {c}…", end="")
    else:
        if t - phase_at >= secs:
            finish(fps)
            step += 1
            if step == len(STEPS):
                done = True
                break
            phase, phase_at, shown = "wait", t, None
            show_step()
            want, secs, grace = STEPS[step][2], STEPS[step][1], STEPS[step][3]
        else:
            left = max(1, math.ceil(phase_at + secs - t))
            inview = bool(track) and want != "still"
            if (left, inview) != shown:
                shown = (left, inview)
                go = "go!  " if t - phase_at < 1 else ""
                out(f"    {go}{left} s" + ("   ● your hand" if inview else ""), end="")

    # ---- the picture
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
        live = phase == "live" and want != "still" and t - phase_at >= grace
        # learn what's always there: all of it, quickly, while you keep still; slowly while it watches (never where
        # a hand is); not at all while you read and get ready
        if phase == "live" and want == "still":
            bg += 0.15 * (near - bg)
        elif phase == "live":
            bg += np.where(mask, 0, 0.01 * (near - bg))
        area = float(mask.mean())
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
        if not live:
            track.clear()
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
                bad = "  ← shouldn't have counted" if want == "far" else ""
                out(f"    {what}{bad}")
                shown = None
    prev = f
    n += 1

if not done and n < 4:
    out("  ✗ no frames came from the camera")
    sys.exit(3)
if not done:
    if phase == "live":
        finish(n / max(t, 1.0))
    out(f"  (the camera stopped — the test has a limit of a few minutes)")
else:
    out()
    print("  ── how it went: " + " · ".join(results))
print(f"  the lights: {lit_frames} flashes of {FLASH_MS:.1f} ms = {lit_frames * FLASH_MS / 1000:.1f} s lit in {t:.0f} s ·"
      f" lit frames {np.median(flash_gain) if flash_gain else 0:.0f} brighter (≈0 = the lights didn't fire)")
