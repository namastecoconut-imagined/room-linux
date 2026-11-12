#!/usr/bin/env bash
# ir-capture — photos from the Surface's IR camera (the OV7251, 640×480 greyscale), stood upright
#   bash ~/room/scripts/ir-capture.sh              one frame, the sensor's own exposure                  → ~/room-ir.jpg
#   bash ~/room/scripts/ir-capture.sh long         the longest exposure and more gain (a dark room)
#   bash ~/room/scripts/ir-capture.sh lit          with the IR lights on (asks for your password)         → ~/room-ir-lit.jpg
#   bash ~/room/scripts/ir-capture.sh lit long     both
# libcamera doesn't offer this camera, so this goes underneath it: it switches on the sensor's link to its CSI-2
# receiver (off by default), sets the format, and reads raw frames from the CIO2 (10-bit, packed 25 pixels per
# 32 bytes — the IPU3's own format). Nothing is kept but the photo. Needs v4l-utils (and i2c-tools for "lit").
#
# The IR lights: on the Surface Pro 5 and 6 they're wired to the sensor's STROBE pin, which Linux's driver leaves
# switched off — not a GPIO, so nothing shows in /sys/class/leds (found by linux-surface,
# github.com/linux-surface/kernel/pull/181, not in any kernel yet). "lit" writes the same sensor registers that
# change does, straight over I2C while the camera streams. The sensor forgets them when the stream stops, so
# nothing stays changed. As on Windows, the lights flash on every other frame: a lit frame minus an unlit one is
# only what the lights reach (a hand near the screen), with the daylight taken out.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
LONG=0; LIT=0
for a in "$@"; do
  case "$a" in long) LONG=1 ;; lit) LIT=1 ;; *) echo "  bash ~/room/scripts/ir-capture.sh [lit] [long]"; exit 1 ;; esac
done
command -v media-ctl >/dev/null || { echo "  First: sudo dnf install -y v4l-utils"; exit 1; }
[ $LIT = 0 ] || command -v i2ctransfer >/dev/null || { echo "  First: sudo dnf install -y i2c-tools"; exit 1; }

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

if [ $LIT = 1 ]; then
  # the sensor's I2C bus and address, from its name: "ov7251 3-0060" → bus 3, address 0x60
  BUS=${OV#* }; BUS=${BUS%-*}; ADDR=0x${OV##*-}
  echo "  this Surface: $(cat /sys/class/dmi/id/product_sku 2>/dev/null || echo unknown)"
  echo "▸ The lights are switched on by writing to the sensor directly, which needs your password"
  sudo -v
  [ -e "/dev/i2c-$BUS" ] || sudo modprobe i2c-dev
  [ -e "/dev/i2c-$BUS" ] || { echo "  /dev/i2c-$BUS isn't there"; exit 1; }
fi
# one of the sensor's registers: read (→ "0x08") and write. -f because the camera driver owns the address; the
# bus takes one transfer at a time, so the two don't trip over each other.
reg()     { sudo i2ctransfer -f -y "$BUS" "w2@$ADDR" $(( $1 >> 8 )) $(( $1 & 0xff )) r1 2>/dev/null; }
set_reg() { sudo i2ctransfer -f -y "$BUS" "w3@$ADDR" $(( $1 >> 8 )) $(( $1 & 0xff )) $(( $2 )); }
strobe_on() {
  # wait until the sensor streams (0x0100 = 1): until then the driver is still writing its own settings over these
  local i ex span rv
  for i in $(seq 50); do [ "$(reg 0x0100)" = 0x01 ] && break; sleep 0.1; done
  [ "$(reg 0x0100)" = 0x01 ] || { echo "  ✗ the sensor didn't start streaming"; return 1; }
  ex=$(v4l2-ctl -d "$SUB" --get-ctrl exposure | sed 's/.*: *//')
  span=$(( ex < 52 ? 52 : ex > 776 ? 776 : ex ))   # the flash lasts as long as the exposure, within the Surface's range
  # the pad turned into an output, the pins' drive, the pattern (0xaa = every other frame), and the flash's length
  for rv in 0x3005=0x08 0x3016=0x10 0x3017=0x00 0x3018=0x00 0x301a=0x00 0x301b=0x00 0x301c=0x00 0x3664=0xf0 \
            0x3b81=0xaa 0x3b8b=0x00 0x3b8c=0x00 0x3b8d=0x00 0x3b8e=$(( span >> 8 )) 0x3b8f=$(( span & 0xff )) 0x3b96=0xc0; do
    set_reg "${rv%=*}" "${rv#*=}" || { echo "  ✗ couldn't write ${rv%=*}"; return 1; }
  done
  echo "  strobe on: pin $(reg 0x3005) (0x08 = on) · pattern $(reg 0x3b81) · flash $span lines"
}

W=640; H=480
media-ctl -d "$M" -l "\"$OV\":0 -> \"$CSI\":0[1]"
media-ctl -d "$M" -V "\"$OV\":0 [fmt:Y10_1X10/${W}x${H}]"
media-ctl -d "$M" -V "\"$CSI\":0 [fmt:Y10_1X10/${W}x${H}]"
media-ctl -d "$M" -V "\"$CSI\":1 [fmt:Y10_1X10/${W}x${H}]" 2>/dev/null || true

echo "  the sensor's controls:"
v4l2-ctl -d "$SUB" -l 2>/dev/null | sed 's/^/    /' | head -12
if [ $LONG = 1 ]; then
  ex=$(v4l2-ctl -d "$SUB" -l 2>/dev/null | sed -n 's/.*exposure .*max=\([0-9]*\).*/\1/p' | head -1)
  ga=$(v4l2-ctl -d "$SUB" -l 2>/dev/null | sed -n 's/.*analogue_gain .*max=\([0-9]*\).*/\1/p' | head -1)
  [ -n "$ex" ] && v4l2-ctl -d "$SUB" --set-ctrl "exposure=$ex" && echo "  exposure → $ex (the longest)"
  [ -n "$ga" ] && v4l2-ctl -d "$SUB" --set-ctrl "analogue_gain=$(( ga / 2 ))" && echo "  analogue gain → $(( ga / 2 ))"
fi

PID=""; T=$(mktemp -d); trap '[ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$T"' EXIT
v4l2-ctl -d "$VID" --set-fmt-video="width=$W,height=$H,pixelformat=ip3y"
BPL=$(v4l2-ctl -d "$VID" --get-fmt-video | sed -n 's/.*Bytes per Line *: *\([0-9]*\).*/\1/p')
# "lit" streams about 10 s (300 frames) so there's time to look, and keeps the last 60
if [ $LIT = 1 ]; then SKIP=240; KEEP=60; else SKIP=0; KEEP=45; fi
v4l2-ctl -d "$VID" --stream-mmap=4 --stream-skip=$SKIP --stream-count=$KEEP --stream-to="$T/ir.raw" 2>"$T/v4l2.log" &
PID=$!
if [ $LIT = 1 ]; then
  echo "▸ About 10 seconds with the lights on: look at the top edge of the Surface through your phone's selfie camera"
  strobe_on || true
else
  echo "▸ $KEEP frames…"
fi
wait "$PID" || { PID=""; echo "  capture failed:"; tail -5 "$T/v4l2.log"; exit 1; }
PID=""
echo "  $(( $(stat -c %s "$T/ir.raw") / (BPL * H) )) frames · $BPL bytes a row"

OUT="$HOME/room-ir.jpg"; [ $LIT = 0 ] || OUT="$HOME/room-ir-lit.jpg"
"$HERE/assistant/.venv/bin/python" - "$T/ir.raw" "$W" "$H" "$BPL" "$T/ir.pgm" "$LIT" <<'PY'
import sys, numpy as np
path, w, h, bpl, out, lit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6] == "1"
data = np.fromfile(path, dtype=np.uint8)
size = bpl * h
n = len(data) // size
blocks = bpl // 32

def frame(i):
    raw = data[i * size:(i + 1) * size].reshape(h, bpl)
    # the IPU3's packing: each 32 bytes hold 25 ten-bit pixels, least significant bits first
    bits = np.unpackbits(raw[:, : blocks * 32].reshape(h, blocks, 32), axis=2, bitorder="little")
    pix = bits[:, :, :250].reshape(h, blocks, 25, 10).astype(np.uint16)
    img = (pix << np.arange(10, dtype=np.uint16)).sum(axis=3).reshape(h, blocks * 25)[:, :w].astype(np.float32)
    return np.rot90(img)                     # the sensor sits sideways: a quarter turn anticlockwise stands it up

def view(img, lo, hi):                       # stretched so whatever it saw shows
    return (((img - lo) / max(1.0, hi - lo)).clip(0, 1) ** 0.8 * 255).astype(np.uint8)

if not lit:
    img = frame(n - 1)
    lo, hi = np.percentile(img, 1), np.percentile(img, 99.5)
    print(f"  levels: median {np.median(img):.0f} of 1023 · 1–99.5 % {lo:.0f}–{hi:.0f}  (all near 0 = it saw nothing)")
    pic = view(img, lo, hi)
else:
    frames = np.stack([frame(i) for i in range(n)])
    means = frames.reshape(n, -1).mean(axis=1)
    a = 0 if means[0::2].mean() >= means[1::2].mean() else 1          # which of the alternating frames are the lit ones
    lit_f, dark_f = frames[a::2].mean(axis=0), frames[1 - a::2].mean(axis=0)
    gain = lit_f.mean() - dark_f.mean()
    noise = max(means[a::2].std(), means[1 - a::2].std())
    print("  each frame's level, oldest first (lit and unlit take turns if it works): "
          + " ".join(f"{m:.0f}" for m in means[-16:]))
    print(f"  lit frames {lit_f.mean():.0f} · unlit {dark_f.mean():.0f} of 1023 → "
          + ("✓ the IR lights work" if gain > max(3.0, 3 * noise) else "✗ no difference: the lights didn't come on"))
    lo, hi = np.percentile(dark_f, 1), np.percentile(lit_f, 99.5)    # one scale for both, so they compare honestly
    diff = (lit_f - dark_f).clip(0)
    gap = np.zeros((lit_f.shape[0], 12), np.uint8)
    pic = np.hstack([view(lit_f, lo, hi), gap, view(dark_f, lo, hi), gap, view(diff, 0, max(4.0, np.percentile(diff, 99.5)))])
with open(out, "wb") as f:
    f.write(b"P5\n%d %d\n255\n" % (pic.shape[1], pic.shape[0])); f.write(np.ascontiguousarray(pic).tobytes())
PY
LABELS=""; [ $LIT = 0 ] || LABELS="IR lights on|off|only what the lights reach"
QT_QPA_PLATFORM=offscreen "$HERE/.venv/bin/python" - "$T/ir.pgm" "$OUT" "$LABELS" <<'PY'
import sys
from PySide6.QtCore import QRect, Qt
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QPainter
src, out, labels = sys.argv[1], sys.argv[2], sys.argv[3]
img = QImage(src)
if labels:                                   # a line naming each of the three pictures above it
    app = QGuiApplication([])
    names = labels.split("|"); pw = (img.width() - 12 * (len(names) - 1)) // len(names)
    canvas = QImage(img.width(), img.height() + 44, QImage.Format.Format_RGB32); canvas.fill(QColor("black"))
    p = QPainter(canvas); p.drawImage(0, 44, img)
    p.setPen(QColor("white")); f = QFont(); f.setPixelSize(20); p.setFont(f)
    for i, t in enumerate(names):
        p.drawText(QRect(i * (pw + 12), 0, pw, 44), Qt.AlignmentFlag.AlignCenter, t)
    p.end(); img = canvas
sys.exit(0 if img.save(out, "JPG", 92) else 1)
PY
echo "  ✓ $OUT — from the Mac: scp surface:$(basename "$OUT") ~/Downloads/"
