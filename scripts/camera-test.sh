#!/usr/bin/env bash
# camera-test — does the Surface's camera work? Grabs a few seconds from the front camera (or the back one with
# "back") at its full size, keeps the last frame (the first ones are dark while the exposure settles) and saves it as a photo:
#   bash ~/room/scripts/camera-test.sh          → ~/room-camera-front.jpg
#   bash ~/room/scripts/camera-test.sh back     → ~/room-camera-back.jpg
# Nothing else is kept: the frames go to a temporary folder that's deleted at the end. Needs libcamera-tools (cam).
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WHICH="${1:-front}"
command -v cam >/dev/null || { echo "  First: sudo dnf install -y libcamera-tools"; exit 1; }
# the camera's number: "2: Internal front camera (…)"
N=$(cam --list 2>/dev/null | sed -n "s/^\([0-9]\): Internal $WHICH camera.*/\1/p" | head -1)
[ -n "$N" ] || { echo "  No $WHICH camera found (cam --list shows what there is)."; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# the sensor's full picture (the front one is 2592×1944, 5 MP); libcamera picks the nearest size it can give
W=2592; H=1944
echo "▸ The $WHICH camera (camera $N), 90 frames — look at the Surface: does a light come on by the camera?"
start=$(date +%s%N)
cam -c "$N" --capture=90 --stream "role=still,width=$W,height=$H,pixelformat=NV12" --file="$T/frame-#.bin" >"$T/cam.log" 2>&1 \
  || { echo "  cam failed:"; tail -5 "$T/cam.log"; exit 1; }
took=$(( ($(date +%s%N) - start) / 1000000000 ))
n=$(ls "$T"/frame-*.bin 2>/dev/null | wc -l)
last=$(ls "$T"/frame-*.bin | sort | tail -1)
# what it actually gave: "configuring streams: (0) 2592x1944-NV12/sYCC" — the size, and how its colours are coded
conf=$(grep -o 'configuring streams: (0) [^ ]*' "$T/cam.log" | tail -1 | sed 's/.*(0) //')
echo "  $n frames in about $took s · ${conf:-format not reported}"
OUT="$HOME/room-camera-$WHICH.jpg"
# NV12 (what the camera gives) → a photo: the assistant's Python has numpy for the colours, Room's has Qt to write a JPEG
"$HERE/assistant/.venv/bin/python" - "$last" "$W" "$H" "$T/frame.ppm" "$conf" <<'PY'
import re, sys, numpy as np
path, w, h, out, conf = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
m = re.match(r"(\d+)x(\d+)-\w+(?:/(\S+))?", conf)
if m:
    w, h = int(m.group(1)), int(m.group(2))
space = (m.group(3) or "") if m else ""
raw = np.fromfile(path, dtype=np.uint8)
stride = len(raw) * 2 // (h * 3)                     # rows may be padded past the width
y = raw[: stride * h].reshape(h, stride)[:, :w].astype(np.float32)
uv = raw[stride * h : stride * h * 3 // 2].reshape(h // 2, stride)[:, :w].astype(np.float32)
u = np.repeat(np.repeat(uv[:, 0::2], 2, 0), 2, 1) - 128
v = np.repeat(np.repeat(uv[:, 1::2], 2, 0), 2, 1) - 128
# full range (sYCC / JPEG: 0–255) or video range (16–235); the first test assumed video range, which crushed the
# shadows and blew the highlights of a full-range picture
full = space in ("sYCC", "JPEG") or (not space and (np.percentile(y, 0.5) < 12 or np.percentile(y, 99.5) > 243))
if full:
    r, g, b = y + 1.402 * v, y - 0.344 * u - 0.714 * v, y + 1.772 * u
elif space.startswith("Rec709"):
    y = (y - 16) * 1.164; u *= 1.138; v *= 1.138
    r, g, b = y + 1.575 * v, y - 0.187 * u - 0.468 * v, y + 1.856 * u
else:
    y = (y - 16) * 1.164; u *= 1.138; v *= 1.138
    r, g, b = y + 1.402 * v, y - 0.344 * u - 0.714 * v, y + 1.772 * u
rgb = np.stack([r, g, b], -1).clip(0, 255).astype(np.uint8)
with open(out, "wb") as f:
    f.write(b"P6\n%d %d\n255\n" % (w, h)); f.write(rgb.tobytes())
print(f"  {w}×{h} · colours read as {'full range' if full else 'video range'}{' (' + space + ')' if space else ''} · brightness {y.mean():.0f} of 255")
PY
"$HERE/.venv/bin/python" -c "
import sys
from PySide6.QtGui import QImage
sys.exit(0 if QImage(sys.argv[1]).save(sys.argv[2], 'JPG', 92) else 1)" "$T/frame.ppm" "$OUT"
echo "  ✓ $OUT — from the Mac: scp surface:$(basename "$OUT") ~/Downloads/"
