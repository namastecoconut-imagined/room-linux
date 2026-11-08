#!/usr/bin/env bash
# Records 8 seconds and saves it three ways, to hear what the panel hears:
#   ~/room-mic-1-raw.wav        straight off the mics (left channel), nothing done
#   ~/room-mic-2-heard.wav      both mics steered + evened out — exactly what goes to speech recognition
#   ~/room-mic-3-cleaned.wav    the same with noise suppression — what the "Alexa" detector gets
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/voice/.venv/bin/python"
echo "Speak from where you'd normally sit — say \"Alexa, what's the weather like tomorrow?\" and anything else."
sleep 1; echo "  recording 8 s…"
pw-record --raw --rate 16000 --channels 2 --format s16 - 2>/dev/null | head -c $((16000 * 4 * 8)) > /tmp/room-sample.raw
echo "  ok"
cd "$HERE/voice" && ROOM_VOICE_CFG="$(python3 -c "import json,os;c=json.load(open(os.path.expanduser('~/.config/room/config.json')));print(json.dumps(c.get('voiceSettings',{})))" 2>/dev/null || echo '{}')" "$PY" - <<'P'
import os, sys, wave, numpy as np
sys.path.insert(0, ".")
import roomvoice as rv
from beam import Beam
a = np.frombuffer(open("/tmp/room-sample.raw", "rb").read(), "<i2").reshape(-1, 2)
def save(name, x):
    p = os.path.expanduser(f"~/room-mic-{name}.wav")
    with wave.open(p, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(x.astype("<i2").tobytes())
    r = np.sqrt(np.mean((x.astype(np.float32) / 32768) ** 2))
    print(f"  {p}  (level {r:.4f}, peak {np.abs(x).max() / 32768:.2f})")
save("1-raw", a[:, 0].copy())
e, b = rv.Ears.__new__(rv.Ears), Beam()
e.floor = 0.002
heard, clean = [], []
for i in range(0, len(a) - rv.CHUNK + 1, rv.CHUNK):
    clean.append(e.even(b.mix(a[i:i + rv.CHUNK]))); heard.append(e.plain)
save("2-heard", np.concatenate(heard))
save("3-cleaned", np.concatenate(clean))
P
rm -f /tmp/room-sample.raw
echo "✓ Done — send me the three files (or play them: pw-play ~/room-mic-2-heard.wav)"
