#!/usr/bin/env bash
# Checks the Surface's two mics for the classic Realtek fault — one mic wired with its signal upside-down, so anything
# that mixes them to one channel (browsers, Room) cancels your voice out — and sets the gain so a normal voice lands
# at a healthy level without breaking up. Room is paused while it runs. Saves ~/room-mic-stereo.wav and
# ~/room-mic-check.txt.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/voice/.venv/bin/python"; [ -x "$PY" ] || PY=python3
OUT="$HOME/room-mic-check.txt"
exec > >(tee "$OUT") 2>&1
systemctl --user stop room 2>/dev/null; sleep 1
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1.0; sleep 0.5
amixer -q -c 0 cset name="Capture Volume" 67,67          # 0 dB digital
amixer -q -c 0 cset name="Internal Mic Boost Volume" 2,2   # +20 dB preamp
echo "From where you'd normally sit, in your normal voice, when it says go: count from one to ten."
sleep 1; echo "  go"
pw-record --raw --rate 16000 --channels 2 --format s16 - 2>/dev/null | head -c $((16000 * 4 * 6)) > /tmp/room-st.raw
echo "  ok"; echo
"$PY" - <<'P'
import numpy as np, wave, json, os
a = np.frombuffer(open("/tmp/room-st.raw", "rb").read(), "<i2").reshape(-1, 2).astype(np.float32) / 32768
a = a - a.mean(0)
with wave.open(os.path.expanduser("~/room-mic-stereo.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(16000); w.writeframes((a * 32767).astype("<i2").tobytes())
L, R = a[:, 0], a[:, 1]
win = lambda x: np.sqrt(np.mean(x[: len(x) // 800 * 800].reshape(-1, 800) ** 2, 1))
wl, wr = win(L), win(R)
loud = wl > np.percentile(wl, 70)                           # the talking parts
def corr(lag):
    x, y = (L[lag:], R[:len(R) - lag]) if lag >= 0 else (L[:lag], R[-lag:])
    return float(np.dot(x, y) / (np.linalg.norm(x) * np.linalg.norm(y) + 1e-9))
cs = {lag: corr(lag) for lag in range(-24, 25)}
best = max(cs, key=lambda k: abs(cs[k]))
c = cs[best]
mono = (L + R) / 2
e1, e2 = float(np.sqrt(np.mean(L ** 2))), float(np.sqrt(np.mean(R ** 2)))
em = float(np.sqrt(np.mean(mono ** 2)))
print(f"left mic:  speech {np.percentile(wl, 95):.4f}  quiet {np.percentile(wl, 10):.4f}  peak {np.abs(L).max():.2f}")
print(f"right mic: speech {np.percentile(wr, 95):.4f}  quiet {np.percentile(wr, 10):.4f}  peak {np.abs(R).max():.2f}")
print(f"how alike the two mics are: {c:+.2f} at {best:+d} samples")
print(f"mixed to one channel: {em:.4f}  (each mic alone: {e1:.4f} / {e2:.4f})")
inverted = c < -0.3
print("→ ONE MIC IS UPSIDE-DOWN: mixing them cancels your voice. This is the fault." if inverted else
      "→ the mics are wired the same way round (no cancelling).")
sp = float(max(np.percentile(wl, 95), np.percentile(wr, 95)))
pk = float(max(np.abs(L).max(), np.abs(R).max()))
# aim: a normal voice peaking around 0.35 (room for a louder one), never past the ceiling
db = 20 * np.log10(0.35 / max(pk, 1e-4))
db = max(-20.0, min(30.0, db))
total = 20 + db                                              # we recorded at +20 preamp, 0 digital
boost = int(max(0, min(3, round(min(total, 30) / 10))))      # preamp first (cleanest), in 10 dB steps
digital = max(-10.0, min(20.0, total - boost * 10))
cap = int(round(67 + digital * 2))
print(f"\nvoice peak {pk:.2f} at +20 dB → set {total:+.0f} dB: preamp +{boost * 10} dB, digital {digital:+.1f} dB")
json.dump({"micBoost": boost, "micCapture": cap, "micInverted": bool(inverted)}, open("/tmp/room-mic.json", "w"))
P
CFG=""; for p in "${ROOM_CONFIG:-}" "$HOME/.config/room/config.json" "$HERE/config.json"; do [ -n "$p" ] && [ -f "$p" ] && { CFG="$p"; break; }; done
"$PY" - "$CFG" <<'P'
import json, sys
p, best = sys.argv[1], json.load(open("/tmp/room-mic.json"))
c = json.load(open(p)) if p else {}
vs = c.setdefault("voiceSettings", {}); vs.update(best); vs["micVolume"] = 1.0
if p: json.dump(c, open(p, "w"), indent=2)
print(f"saved → {p}")
P
B=$(python3 -c "import json;print(json.load(open('/tmp/room-mic.json'))['micBoost'])")
C=$(python3 -c "import json;print(json.load(open('/tmp/room-mic.json'))['micCapture'])")
amixer -q -c 0 cset name="Internal Mic Boost Volume" "$B,$B"; amixer -q -c 0 cset name="Capture Volume" "$C,$C"
rm -f /tmp/room-st.raw /tmp/room-mic.json
systemctl --user start room && echo "Room started again"
echo "✓ Saved to $OUT — send me that and ~/room-mic-stereo.wav"
