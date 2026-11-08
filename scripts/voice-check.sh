#!/usr/bin/env bash
# Measures what actually reaches the Surface's speakers: the "Alexa" chime, then a sentence in Room's voice, each
# recorded from the speakers' own output (their "monitor"), plus every volume on the way. Prints the numbers.
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/voice/.venv/bin/python"
RAW=$(pw-dump | python3 -c "import json,sys;print(next((n['info']['props']['node.name'] for n in json.load(sys.stdin) if (n.get('info') or {}).get('props',{}).get('media.class')=='Audio/Sink' and n['info']['props'].get('node.name','').startswith('alsa_output.pci') and 'hdmi' not in n['info']['props']['node.name']),''))")
echo "Surface speakers: $RAW"
CFG=$(python3 -c "import json,os;c=json.load(open(os.path.expanduser('~/.config/room/config.json')));v=dict(c.get('voiceSettings') or {});v['deepgramKey']=c.get('deepgramKey','');v['listen']=False;print(json.dumps(v))")
rec() { pw-record --target "$RAW" -P '{ stream.capture.sink = true }' --raw --rate 24000 --channels 1 --format s16 - 2>/dev/null | head -c $((24000*2*$1)) > "$2" & }
measure() { "$PY" -I - "$1" "$2" <<'P'
import sys, wave, os, numpy as np
b = open(sys.argv[1], "rb").read()
x = np.frombuffer(b, "<i2").astype(float) / 32768
with wave.open(os.path.expanduser(f"~/room-check-{sys.argv[2].split()[0].lower()}.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(b)
w = np.sqrt(np.mean(x[: len(x) // 1200 * 1200].reshape(-1, 1200) ** 2, 1))
print(f"  {sys.argv[2]:<12} loud parts {np.percentile(w, 90):.3f}   peak {np.abs(x).max():.2f}")
P
}
echo "1) the chime"
rec 3 /tmp/rc.raw; sleep 0.5
pw-play --target "$RAW" --volume 0.9 "$HERE/voice/cues/listen.wav"; wait
echo "2) Room's voice"
rm -f /tmp/rsent.raw
rec 14 /tmp/rv.raw; sleep 0.5
(echo '{"cmd":"say","text":"This is how loud Room sounds when it answers you."}'; sleep 12) | \
  ROOM_VOICE_DUMP=/tmp/rsent.raw ROOM_VOICE_CFG="$CFG" "$PY" "$HERE/voice/roomvoice.py" 2>&1 | sed 's/^/    /'
wait
echo "Reaching the speakers:"
measure /tmp/rc.raw chime; measure /tmp/rv.raw "Room voice"
[ -s /tmp/rsent.raw ] && measure /tmp/rsent.raw "sent" || echo "  (Room's voice sent nothing — the online voice didn't play)"
echo "Volumes:"; wpctl get-volume @DEFAULT_AUDIO_SINK@ | sed 's/^/  output: /'
amixer -c 0 sget Master 2>/dev/null | tail -1 | sed 's/^/  chip Master:/'
grep -i "room" ~/.local/state/wireplumber/stream-properties 2>/dev/null | sed 's/^/  remembered: /'
rm -f /tmp/rc.raw /tmp/rv.raw /tmp/rsent.raw
echo "(recordings: ~/room-check-chime.wav and ~/room-check-room.wav)"
