#!/usr/bin/env bash
# camera-test — does the Surface's camera work? Grabs ~2 s of video from the front camera (or the back one with
# "back"), keeps the last frame (the first ones are dark while the exposure settles) and saves it as a photo:
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
W=1280; H=720
echo "▸ The $WHICH camera (camera $N), 60 frames at ${W}×${H} — look at the Surface: does a light come on by the camera?"
start=$(date +%s%N)
cam -c "$N" --capture=60 --stream "role=viewfinder,width=$W,height=$H,pixelformat=NV12" --file="$T/frame-#.bin" >"$T/cam.log" 2>&1 \
  || { echo "  cam failed:"; tail -5 "$T/cam.log"; exit 1; }
took=$(( ($(date +%s%N) - start) / 1000000000 ))
n=$(ls "$T"/frame-*.bin 2>/dev/null | wc -l)
last=$(ls "$T"/frame-*.bin | sort | tail -1)
echo "  $n frames in about $took s"
# NV12 (what the camera gives) → a photo: the assistant's Python has numpy for the colours, Room's has Qt to write a JPEG
OUT="$HOME/room-camera-$WHICH.jpg"
"$HERE/assistant/.venv/bin/python" - "$last" "$W" "$H" "$T/frame.ppm" <<'PY'
import sys, numpy as np
path, w, h, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
raw = np.fromfile(path, dtype=np.uint8)
stride = len(raw) * 2 // (h * 3)                     # rows may be padded past the width
y = raw[: stride * h].reshape(h, stride)[:, :w].astype(np.float32)
uv = raw[stride * h : stride * h * 3 // 2].reshape(h // 2, stride)[:, :w].astype(np.float32)
u = np.repeat(np.repeat(uv[:, 0::2], 2, 0), 2, 1) - 128
v = np.repeat(np.repeat(uv[:, 1::2], 2, 0), 2, 1) - 128
y = (y - 16) * 1.164
rgb = np.stack([y + 1.596 * v, y - 0.392 * u - 0.813 * v, y + 2.017 * u], -1).clip(0, 255).astype(np.uint8)
with open(out, "wb") as f:
    f.write(b"P6\n%d %d\n255\n" % (w, h)); f.write(rgb.tobytes())
print(f"  brightness {y.mean():.0f} of 255 (dark below ~40)")
PY
"$HERE/.venv/bin/python" -c "
import sys
from PySide6.QtGui import QImage
sys.exit(0 if QImage(sys.argv[1]).save(sys.argv[2], 'JPG', 85) else 1)" "$T/frame.ppm" "$OUT"
echo "  ✓ $OUT — send it over (from the Mac: scp surface:$(basename "$OUT") ~/Downloads/)"
