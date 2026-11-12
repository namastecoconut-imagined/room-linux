#!/usr/bin/env bash
# ir-gestures — tries hand gestures with the IR camera. It walks you through it at your pace: each step (keep still,
# swipe each way, hold your palm, wave from far away) says what to do and waits for Enter, counts you in, watches for
# a few seconds — ● whenever it sees your hand, a line for each gesture — then says how it went.
#   bash ~/room/scripts/ir-gestures.sh               (Ctrl-C stops it early)
#   bash ~/room/scripts/ir-gestures.sh near=200      how much brighter than the room counts as "a hand" (default 300 of 1023)
# More options: gain=N (the sensor's amplification, in 16ths: default 96 = 6×; its lowest is 16 = 1×) · mirror (if ← and → come out the
# wrong way round). The IR lights run gently while it does: a flash of about 1.5 ms on every other frame (Windows'
# face login flashes about three times as long), and only for as long as this runs. The sensor forgets the light
# settings when the stream stops,
# and its exposure and gain go back to what they were. Keeps nothing. Needs v4l-utils and i2c-tools; asks for your
# password (the lights are switched on by writing to the sensor directly, as in ir-capture.sh lit).
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
NEAR=300; GAIN=96; MIRROR=0
EXPOSURE=100                  # in lines (about 15 µs each): a short exposure, and the flash lasts as long
for a in "$@"; do
  case "$a" in
    near=*) NEAR=${a#near=} ;; gain=*) GAIN=${a#gain=} ;; mirror) MIRROR=1 ;;
    *) echo "  bash ~/room/scripts/ir-gestures.sh [near=300] [gain=96] [mirror]"; exit 1 ;;
  esac
done
command -v media-ctl >/dev/null || { echo "  First: sudo dnf install -y v4l-utils"; exit 1; }
command -v i2ctransfer >/dev/null || { echo "  First: sudo dnf install -y i2c-tools"; exit 1; }

# the media graph that has the OV7251, and its pieces: "ov7251 3-0060" → "ipu3-csi2 2" → "ipu3-cio2 2" (/dev/videoN)
M=""; for m in /dev/media*; do media-ctl -d "$m" -p 2>/dev/null | grep -q 'entity [0-9]*: ov7251' && M=$m && break; done
[ -n "$M" ] || { echo "  The IR sensor isn't in any media graph (run ir-check.sh)."; exit 1; }
TOPO=$(media-ctl -d "$M" -p)
OV=$(echo "$TOPO" | sed -n 's/.*entity [0-9]*: \(ov7251 [0-9-]*\) .*/\1/p' | head -1)
CSI=$(echo "$TOPO" | awk -v ov="$OV" '$0 ~ "entity [0-9]+: "ov" " {f=1; next} f && /-> "/ {match($0, /"[^"]+"/); print substr($0, RSTART+1, RLENGTH-2); exit}')
CIO=${CSI/ipu3-csi2/ipu3-cio2}
VID=$(media-ctl -d "$M" -e "$CIO")
SUB=$(media-ctl -d "$M" -e "$OV")
BUS=${OV#* }; BUS=${BUS%-*}; ADDR=0x${OV##*-}       # "ov7251 3-0060" → I2C bus 3, address 0x60

echo "▸ The lights are switched on by writing to the sensor directly, which needs your password"
sudo -v
[ -e "/dev/i2c-$BUS" ] || sudo modprobe i2c-dev
[ -e "/dev/i2c-$BUS" ] || { echo "  /dev/i2c-$BUS isn't there"; exit 1; }
reg()     { sudo i2ctransfer -f -y "$BUS" "w2@$ADDR" $(( $1 >> 8 )) $(( $1 & 0xff )) r1 2>/dev/null; }
set_reg() { sudo i2ctransfer -f -y "$BUS" "w3@$ADDR" $(( $1 >> 8 )) $(( $1 & 0xff )) $(( $2 )); }
strobe_on() {   # as in ir-capture.sh: once the sensor streams, its STROBE pin on, every other frame, flash = exposure
  local i span rv
  for i in $(seq 50); do [ "$(reg 0x0100)" = 0x01 ] && break; sleep 0.1; done
  [ "$(reg 0x0100)" = 0x01 ] || { echo "  ✗ the sensor didn't start streaming"; return 1; }
  span=$(( EXPOSURE < 52 ? 52 : EXPOSURE > 776 ? 776 : EXPOSURE ))
  for rv in 0x3005=0x08 0x3016=0x10 0x3017=0x00 0x3018=0x00 0x301a=0x00 0x301b=0x00 0x301c=0x00 0x3664=0xf0 \
            0x3b81=0xaa 0x3b8b=0x00 0x3b8c=0x00 0x3b8d=0x00 0x3b8e=$(( span >> 8 )) 0x3b8f=$(( span & 0xff )) 0x3b96=0xc0; do
    set_reg "${rv%=*}" "${rv#*=}" || { echo "  ✗ couldn't write ${rv%=*}"; return 1; }
  done
}

W=640; H=480
media-ctl -d "$M" -l "\"$OV\":0 -> \"$CSI\":0[1]"
media-ctl -d "$M" -V "\"$OV\":0 [fmt:Y10_1X10/${W}x${H}]"
media-ctl -d "$M" -V "\"$CSI\":0 [fmt:Y10_1X10/${W}x${H}]"
media-ctl -d "$M" -V "\"$CSI\":1 [fmt:Y10_1X10/${W}x${H}]" 2>/dev/null || true
v4l2-ctl -d "$VID" --set-fmt-video="width=$W,height=$H,pixelformat=ip3y"
BPL=$(v4l2-ctl -d "$VID" --get-fmt-video | sed -n 's/.*Bytes per Line *: *\([0-9]*\).*/\1/p')

# a short exposure (the flash lasts as long) and amplification instead: that costs no light; put back afterwards
ctl() { v4l2-ctl -d "$SUB" --get-ctrl "$1" | sed 's/.*: *//'; }
EX0=$(ctl exposure); GA0=$(ctl analogue_gain)
PIPE=""; T=$(mktemp -d)
cleanup() {
  [ -n "$PIPE" ] && { pkill -P "$PIPE" 2>/dev/null; kill "$PIPE" 2>/dev/null; wait "$PIPE" 2>/dev/null; }
  v4l2-ctl -d "$SUB" --set-ctrl "exposure=$EX0" --set-ctrl "analogue_gain=$GA0" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT; trap 'exit 130' INT TERM
v4l2-ctl -d "$SUB" --set-ctrl "exposure=$EXPOSURE" --set-ctrl "analogue_gain=$GAIN"
# the frame's timing, from the sensor: a line is (width + horizontal blanking) pixels at the pixel rate, a frame
# (height + vertical blanking) lines — so how long the flash lasts, and how many frames a second
RATE=$(ctl pixel_rate 2>/dev/null || true); HB=$(ctl horizontal_blanking); VB=$(ctl vertical_blanking)
[[ "$RATE" =~ ^[0-9]+$ ]] || RATE=48000000
FLASH_MS=$(awk -v e="$EXPOSURE" -v l=$(( W + HB )) -v r="$RATE" 'BEGIN { printf "%.1f", e * l / r * 1000 }')
FPS=$(awk -v r="$RATE" -v l=$(( W + HB )) -v f=$(( H + VB )) 'BEGIN { printf "%.0f", r / (l * f) }')

echo "▸ $FPS frames a second · flash $FLASH_MS ms ($EXPOSURE lines; exposure was $EX0) · gain $GAIN (was $GA0) ·"
echo "  a hand: $NEAR brighter than the room. Each step waits for you to press Enter."
echo
# (the walk-through's own result decides: when it finishes first, the camera's end is just the pipe closing on it)
( set +o pipefail
  v4l2-ctl -d "$VID" --stream-mmap=4 --stream-count=$(( 180 * FPS )) --stream-to=- 2>"$T/v4l2.log" \
    | "$HERE/assistant/.venv/bin/python" "$HERE/scripts/ir-gestures.py" "$W" "$H" "$BPL" "$NEAR" "$MIRROR" "$FLASH_MS" ) &
PIPE=$!
strobe_on || echo "  (carrying on without the lights)"
rc=0; wait "$PIPE" || rc=$?
PIPE=""
[ $rc = 0 ] || { echo "  stopped (code $rc) — the camera said:"; tail -3 "$T/v4l2.log" | sed 's/^/    /'; exit 1; }
echo "  exposure and gain back to $EX0 and $GA0 · the lights went off with the stream"
