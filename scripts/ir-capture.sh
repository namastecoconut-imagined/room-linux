#!/usr/bin/env bash
# ir-capture — one frame from the Surface's IR camera (the OV7251, 640×480 greyscale) → ~/room-ir.jpg
#   bash ~/room/scripts/ir-capture.sh              the sensor's own exposure
#   bash ~/room/scripts/ir-capture.sh long         the longest exposure and more gain (a dark room)
# libcamera doesn't offer this camera, so this goes underneath it: it switches on the sensor's link to its CSI-2
# receiver (off by default), sets the format, and reads raw frames from the CIO2 (10-bit, packed 25 pixels per
# 32 bytes — the IPU3's own format), then unpacks the last frame. Nothing is kept but the photo. Needs v4l-utils.
# While it runs, look at the Surface through your phone's camera: infrared shows there as a purple glow — that's
# how to see whether the IR lights beside the camera come on.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
MODE="${1:-}"
command -v media-ctl >/dev/null || { echo "  First: sudo dnf install -y v4l-utils"; exit 1; }

# the media graph that has the OV7251, and its pieces: "ov7251 3-0060" → "ipu3-csi2 2" → "ipu3-cio2 2" (/dev/videoN)
M=""; for m in /dev/media*; do media-ctl -d "$m" -p 2>/dev/null | grep -q 'entity [0-9]*: ov7251' && M=$m && break; done
[ -n "$M" ] || { echo "  The IR sensor isn't in any media graph (run ir-check.sh)."; exit 1; }
TOPO=$(media-ctl -d "$M" -p)
OV=$(echo "$TOPO" | sed -n 's/.*entity [0-9]*: \(ov7251 [0-9-]*\) .*/\1/p' | head -1)
CSI=$(echo "$TOPO" | awk -v ov="$OV" '$0 ~ "entity [0-9]+: "ov" " {f=1; next} f && /-> "/ {match($0, /"[^"]+"/); print substr($0, RSTART+1, RLENGTH-2); exit}')
CIO=${CSI/ipu3-csi2/ipu3-cio2}
VID=$(media-ctl -d "$M" -e "$CIO")
SUB=$(media-ctl -d "$M" -e "$OV")
echo "▸ $OV → $CSI → $CIO ($VID)"

W=640; H=480
media-ctl -d "$M" -l "\"$OV\":0 -> \"$CSI\":0[1]"
media-ctl -d "$M" -V "\"$OV\":0 [fmt:Y10_1X10/${W}x${H}]"
media-ctl -d "$M" -V "\"$CSI\":0 [fmt:Y10_1X10/${W}x${H}]"
media-ctl -d "$M" -V "\"$CSI\":1 [fmt:Y10_1X10/${W}x${H}]" 2>/dev/null || true

echo "  the sensor's controls:"
v4l2-ctl -d "$SUB" -l 2>/dev/null | sed 's/^/    /' | head -12
if [ "$MODE" = long ]; then
  ex=$(v4l2-ctl -d "$SUB" -l 2>/dev/null | sed -n 's/.*exposure .*max=\([0-9]*\).*/\1/p' | head -1)
  ga=$(v4l2-ctl -d "$SUB" -l 2>/dev/null | sed -n 's/.*analogue_gain .*max=\([0-9]*\).*/\1/p' | head -1)
  [ -n "$ex" ] && v4l2-ctl -d "$SUB" --set-ctrl "exposure=$ex" && echo "  exposure → $ex (the longest)"
  [ -n "$ga" ] && v4l2-ctl -d "$SUB" --set-ctrl "analogue_gain=$(( ga / 2 ))" && echo "  analogue gain → $(( ga / 2 ))"
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
v4l2-ctl -d "$VID" --set-fmt-video="width=$W,height=$H,pixelformat=ip3y"
BPL=$(v4l2-ctl -d "$VID" --get-fmt-video | sed -n 's/.*Bytes per Line *: *\([0-9]*\).*/\1/p')
echo "▸ 45 frames (look through your phone camera for a purple glow beside the camera)…"
v4l2-ctl -d "$VID" --stream-mmap=4 --stream-count=45 --stream-to="$T/ir.raw" 2>"$T/v4l2.log" \
  || { echo "  capture failed:"; tail -5 "$T/v4l2.log"; exit 1; }
echo "  $(( $(stat -c %s "$T/ir.raw") / (BPL * H) )) frames · $BPL bytes a row"

OUT="$HOME/room-ir.jpg"
"$HERE/assistant/.venv/bin/python" - "$T/ir.raw" "$W" "$H" "$BPL" "$T/ir.pgm" <<'PY'
import sys, numpy as np
path, w, h, bpl, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
data = np.fromfile(path, dtype=np.uint8)
size = bpl * h
frame = data[(len(data) // size - 1) * size:][:size].reshape(h, bpl)
# the IPU3's packing: each 32 bytes hold 25 ten-bit pixels, least significant bits first
blocks = bpl // 32
bits = np.unpackbits(frame[:, : blocks * 32].reshape(h, blocks, 32), axis=2, bitorder="little")
pix = bits[:, :, :250].reshape(h, blocks, 25, 10).astype(np.uint16)
img = (pix << np.arange(10, dtype=np.uint16)).sum(axis=3).reshape(h, blocks * 25)[:, :w].astype(np.float32)
lo, hi = np.percentile(img, 1), np.percentile(img, 99.5)
print(f"  levels: median {np.median(img):.0f} of 1023 · 1–99.5 % {lo:.0f}–{hi:.0f}  (all near 0 = it saw nothing)")
view = ((img - lo) / max(1.0, hi - lo)).clip(0, 1) ** 0.8 * 255         # stretched so whatever it saw shows
with open(out, "wb") as f:
    f.write(b"P5\n%d %d\n255\n" % (w, h)); f.write(view.astype(np.uint8).tobytes())
PY
"$HERE/.venv/bin/python" -c "
import sys
from PySide6.QtGui import QImage
sys.exit(0 if QImage(sys.argv[1]).save(sys.argv[2], 'JPG', 92) else 1)" "$T/ir.pgm" "$OUT"
echo "  ✓ $OUT — from the Mac: scp surface:$(basename "$OUT") ~/Downloads/"
