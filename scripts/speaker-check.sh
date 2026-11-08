#!/usr/bin/env bash
# Read and set: the Surface's own speakers at full, every level along the way printed, and a test sentence-length
# sound played straight to them at full — to tell whether it's Room or the speakers themselves that are quiet.
R=$(pw-dump | python3 -c "import json,sys;print(next((n['id'] for n in json.load(sys.stdin) if (n.get('info') or {}).get('props',{}).get('media.class')=='Audio/Sink' and (n['info']['props'].get('node.name','')).startswith('alsa_output.pci') and 'hdmi' not in n['info']['props'].get('node.name','')),''))")
echo "Surface speakers: sink $R  $(wpctl get-volume $R)"
wpctl set-volume "$R" 1.0; wpctl set-mute "$R" 0
for c in Master Speaker PCM; do amixer -c 0 sget "$c" 2>/dev/null | grep -E "Playback|Mono|Front" | head -2 | sed "s/^/  $c: /"; amixer -q -c 0 sset "$c" 100% unmute 2>/dev/null; done
echo "after: $(wpctl get-volume $R)"; amixer -c 0 sget Master 2>/dev/null | tail -1
echo "Playing a loud test sound on the Surface's speakers for 3 s…"
python3 -c "
import math,struct,sys
sys.stdout.buffer.write(b''.join(struct.pack('<h',int(29000*math.sin(2*math.pi*(600+400*math.sin(i/3000))*i/24000))) for i in range(72000)))" \
 | pw-play --target "$(pw-dump | python3 -c "import json,sys;print(next((n['info']['props']['node.name'] for n in json.load(sys.stdin) if (n.get('info') or {}).get('props',{}).get('media.class')=='Audio/Sink' and n['info']['props'].get('node.name','').startswith('alsa_output.pci') and 'hdmi' not in n['info']['props']['node.name']),''))")" --volume 1.0 --raw --rate 24000 --channels 1 --format s16 -
echo "done — was that loud?"
