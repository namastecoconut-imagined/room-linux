#!/usr/bin/env bash
# Renders every screen with sample data and fails if any QML error appears. Run before pushing.
cd "$(dirname "$0")/.." || exit 1
PY="${PY:-python3}"; fail=0
for s in home standby musicstandby music room clock clockedit weather reminders settings setconfirm setwifi setjoin volhud \
         setmore setmore-night setmore-standby setmore-sound setmore-updates catsdayhome catsdaystandby \
         sb-roofs-day sb-room-eve sb-wall-night sb-garden-day sb-garden-night sb-room-night-40 sbdemo roommap roommap-1 roommapdemo pixel pixel-art pixel-light pixel-lost pixel-timers pixel-timers-score pixel-text pixel-face pixel-face-up pixel-library pixel-setup pixel-tune; do
  out=$(ROOM_DEMO=1 ROOM_WINDOWED=1 ROOM_SCREEN=$s ROOM_SHOT="/tmp/room-check-$s.png" ROOM_SHOT_MS=2500 \
        timeout -s KILL 40 ${XVFB:-xvfb-run -a -s "-screen 0 1368x912x24"} $PY -m room 2>&1 | grep -E "qml|QML|Error|Traceback|unavailable" )
  if [ -n "$out" ] || [ ! -s "/tmp/room-check-$s.png" ]; then echo "✗ $s"; echo "$out" | head -5; fail=1; else echo "✓ $s"; fi
  rm -f "/tmp/room-check-$s.png"
done
# the music screens with a song that has no lyrics (they're as they were)
for s in musicstandby music home; do
  out=$(ROOM_DEMO=1 ROOM_DEMO_LYRICS=0 ROOM_WINDOWED=1 ROOM_SCREEN=$s ROOM_SHOT="/tmp/room-check-$s.png" ROOM_SHOT_MS=2500 \
        timeout -s KILL 40 ${XVFB:-xvfb-run -a -s "-screen 0 1368x912x24"} $PY -m room 2>&1 | grep -E "qml|QML|Error|Traceback|unavailable" )
  if [ -n "$out" ] || [ ! -s "/tmp/room-check-$s.png" ]; then echo "✗ $s (no lyrics)"; echo "$out" | head -5; fail=1; else echo "✓ $s (no lyrics)"; fi
  rm -f "/tmp/room-check-$s.png"
done
# the assistant over Home: each state, and an answer with each card
for v in listen remlisten think miss error speak:weather speak:forecast speak:air speak:timer speak:music speak:schedule speak:alarm speak:lights speak:reminder speak:none; do
  out=$(ROOM_DEMO=1 ROOM_WINDOWED=1 ROOM_SCREEN=voice ROOM_DEMO_VOICE=${v%%:*} ROOM_DEMO_CARD=${v#*:} ROOM_SHOT="/tmp/room-check-voice.png" \
        ROOM_SHOT_MS=2500 timeout -s KILL 40 ${XVFB:-xvfb-run -a -s "-screen 0 1368x912x24"} $PY -m room 2>&1 | grep -E "qml|QML|Error|Traceback|unavailable" )
  if [ -n "$out" ] || [ ! -s "/tmp/room-check-voice.png" ]; then echo "✗ voice $v"; echo "$out" | head -5; fail=1; else echo "✓ voice $v"; fi
  rm -f "/tmp/room-check-voice.png"
done
exit $fail
