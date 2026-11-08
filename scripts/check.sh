#!/usr/bin/env bash
# Renders every screen with sample data and fails if any QML error appears. Run before pushing.
cd "$(dirname "$0")/.." || exit 1
PY="${PY:-python3}"; fail=0
for s in home standby musicstandby music room clock weather reminders assistant; do
  out=$(ROOM_DEMO=1 ROOM_WINDOWED=1 ROOM_SCREEN=$s ROOM_SHOT="/tmp/room-check-$s.png" ROOM_SHOT_MS=2500 \
        timeout -s KILL 40 ${XVFB:-xvfb-run -a -s "-screen 0 1368x912x24"} $PY -m room 2>&1 | grep -E "qml|QML|Error|Traceback|unavailable" )
  if [ -n "$out" ] || [ ! -s "/tmp/room-check-$s.png" ]; then echo "✗ $s"; echo "$out" | head -5; fail=1; else echo "✓ $s"; fi
  rm -f "/tmp/room-check-$s.png"
done
exit $fail
