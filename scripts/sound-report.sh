#!/usr/bin/env bash
# Read-only: where sound is going and how loud each step is set. Plays one test phrase through Room's voice path.
# Writes ~/room-sound-report.txt.
OUT="$HOME/room-sound-report.txt"
exec > >(tee "$OUT") 2>&1
echo "=== outputs (* = default)"
wpctl status 2>/dev/null | sed -n '/Audio/,/Video/p' | sed -n '/Sinks:/,/Sources:/p'
echo; echo "=== default output"
wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -E "node.name|node.description|media.class|factory.name" | head
wpctl get-volume @DEFAULT_AUDIO_SINK@
echo; echo "=== every output's volume"
for id in $(pw-dump 2>/dev/null | python3 -c "import json,sys;[print(n['id']) for n in json.load(sys.stdin) if (n.get('info') or {}).get('props',{}).get('media.class')=='Audio/Sink']"); do
  printf "%s  %s  " "$id" "$(wpctl inspect $id | grep -m1 'node.description' | cut -d'"' -f2)"; wpctl get-volume $id
done
echo; echo "=== hardware speaker controls"
amixer -c 0 sget Master 2>/dev/null | tail -2
amixer -c 0 sget Speaker 2>/dev/null | tail -2
echo; echo "=== remembered app volumes (WirePlumber)"
grep -iE "pw-play|pw-cat|room" ~/.local/state/wireplumber/stream-properties 2>/dev/null | head -10
echo; echo "=== speaker filters"
ls ~/.config/pipewire/pipewire.conf.d/ ~/.config/pipewire/filter-chain.conf.d/ 2>/dev/null
echo; echo "=== a test: Room's voice path at full volume (a 1 s tone)"
python3 -c "
import math,struct,sys
sys.stdout.buffer.write(b''.join(struct.pack('<h',int(16000*math.sin(2*math.pi*440*i/24000))) for i in range(24000)))" \
  | pw-play --volume 1.0 -P '{ application.name = "Room voice" }' --raw --rate 24000 --channels 1 --format s16 - && echo "  played"
echo "✓ Saved to $OUT"
