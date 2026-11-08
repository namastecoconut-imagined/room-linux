#!/usr/bin/env bash
# A real request, measured: records what reaches the Surface's speakers for 25 s while you talk to Room normally, and
# every second notes the volume of each sound stream (to catch anything turning Room's voice down mid-answer).
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/voice/.venv/bin/python"
RAW=$(pw-dump | python3 -c "import json,sys;print(next((n['info']['props']['node.name'] for n in json.load(sys.stdin) if (n.get('info') or {}).get('props',{}).get('media.class')=='Audio/Sink' and n['info']['props'].get('node.name','').startswith('alsa_output.pci') and 'hdmi' not in n['info']['props']['node.name']),''))")
echo "Now say: \"Alexa, what's the weather like tomorrow?\" — and let it answer. Recording 25 s…"
pw-record --target "$RAW" -P '{ stream.capture.sink = true }' --raw --rate 24000 --channels 1 --format s16 - 2>/dev/null | head -c $((24000*2*25)) > /tmp/rl.raw &
: > /tmp/rl-streams.txt
for i in $(seq 1 25); do
  pw-dump 2>/dev/null | "$PY" -I -c "
import json,sys
for n in json.load(sys.stdin):
    p=(n.get('info') or {}).get('props') or {}
    if p.get('media.class')=='Stream/Output/Audio':
        v=[x for x in (n['info'].get('params') or {}).get('Props',[]) if 'channelVolumes' in x]
        cv=v[0]['channelVolumes'] if v else '?'
        print($i, p.get('application.name') or p.get('node.name'), '→', p.get('target.object') or '', 'volume', cv)
" >> /tmp/rl-streams.txt
  sleep 1
done
wait
"$PY" -I - <<'P'
import numpy as np, wave, os
b = open("/tmp/rl.raw", "rb").read()
x = np.frombuffer(b, "<i2").astype(float) / 32768
with wave.open(os.path.expanduser("~/room-live.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(b)
w = np.sqrt(np.mean(x[: len(x) // 12000 * 12000].reshape(-1, 12000) ** 2, 1))
print("Reaching the Surface's speakers, every ½ s:")
print("  " + " ".join(f"{v:.2f}" for v in w))
P
echo "Sound streams while it ran:"; sort -u -k2 /tmp/rl-streams.txt | sort -n | uniq | head -40
journalctl --user -u room --since "-40 s" --no-pager | grep -E "voice|aura|Alexa|heard" | tail -12
rm -f /tmp/rl.raw /tmp/rl-streams.txt
