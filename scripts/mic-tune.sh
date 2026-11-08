#!/usr/bin/env bash
# Measures the Surface's mic at each preamp boost (+0 … +30 dB) while you talk, and keeps the loudest one that doesn't
# distort. Also shows what Windows' driver set for this model (subsystem 10CC). Saves micBoost and micVolume to Room's
# config.json and restarts Room. Takes about a minute; you talk four times.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/voice/.venv/bin/python"; [ -x "$PY" ] || PY=python3
INF=$(find "$HOME/.cache/room/sp6-driver" -name HDXSSTM.inf 2>/dev/null | head -1)
CTL="Internal Mic Boost Volume"
OUT="$HOME/room-mic-tune.txt"
exec > >(tee "$OUT") 2>&1

if [ -n "$INF" ]; then
  echo "=== What Windows' driver sets for this Surface (10CC)"
  "$PY" - "$INF" <<'P'
import re, sys
t = open(sys.argv[1], encoding="utf-16" if open(sys.argv[1], "rb").read(2) in (b"\xff\xfe", b"\xfe\xff") else "latin-1", errors="replace").read()
secs = dict(re.findall(r"^\[([^\]]+)\]\s*\n(.*?)(?=^\[)", t, re.S | re.M))
want = [n for n in secs if "10CC" in n.upper()]
seen = set()
def show(n, depth=0):
    if n in seen or depth > 2 or n not in secs: return
    seen.add(n)
    lines = [l.strip() for l in secs[n].splitlines() if l.strip() and not l.strip().startswith(";")]
    hits = [l for l in lines if re.search(r"mic|rec|capt|boost|gain|agc|ns|beam|array|geometry|dmic|input|aec", l, re.I)]
    if hits:
        print(f"[{n}]"); [print("  " + l[:160]) for l in hits[:40]]
    for l in lines:
        m = re.match(r"AddReg\s*=\s*(.+)", l, re.I)
        if m:
            for sub in m.group(1).split(","): show(sub.strip(), depth + 1)
for n in want: show(n)
print("(sections for 10CC: " + ", ".join(want) + ")")
P
  echo
fi

echo "=== Now: boost $(amixer -c 0 cget name="$CTL" | grep -o ': values=.*'), PipeWire level $(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)"
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1.0
echo "PipeWire mic level set to 100% (it was throwing signal away)"
echo
echo "First, 3 seconds of quiet — don't talk…"
pw-record --raw --rate 16000 --channels 2 --format s16 - 2>/dev/null | head -c $((16000*2*2*3)) > /tmp/room-q.raw
for b in 0 1 2 3; do
  amixer -q -c 0 cset name="$CTL" "$b,$b"
  echo
  echo "Boost +$((b*10)) dB — from where you'd normally sit, say: \"Alexa, what's the weather like tomorrow?\""
  sleep 1; echo "  go"
  pw-record --raw --rate 16000 --channels 2 --format s16 - 2>/dev/null | head -c $((16000*2*2*4)) > /tmp/room-b$b.raw
  echo "  ok"
done
echo
"$PY" - <<'P'
import numpy as np
def load(p):
    a = np.frombuffer(open(p, "rb").read(), "<i2").astype(np.float32).reshape(-1, 2) / 32768
    return a - a.mean(0)
q = load("/tmp/room-q.raw")
best = 0
print("boost   noise    speech   peak   clipped   speech-to-noise")
for b in range(4):
    x = load(f"/tmp/room-b{b}.raw")
    w = np.sqrt(np.mean(x.reshape(-1, 800, 2)[:, :, 0] ** 2, 1))       # 50 ms windows, left mic
    speech = float(np.percentile(w, 95)); noise = float(np.percentile(w, 15))
    pk = float(np.abs(x).max()); clip = float(np.mean(np.abs(x) > 0.97)) * 100
    snr = 20 * np.log10(speech / max(noise, 1e-6))
    ok = clip < 0.05 and pk < 0.95
    if ok and speech > 0.003: best = b
    print(f"+{b*10:2d} dB  {noise:.4f}   {speech:.4f}   {pk:.2f}   {clip:5.2f}%    {snr:4.1f} dB{'' if ok else '   ← distorts'}")
qn = float(np.sqrt(np.mean(q[:, 0] ** 2)))
print(f"room quiet (at the starting boost): {qn:.4f}")
open("/tmp/room-best", "w").write(str(best))
print(f"\nBest: +{best*10} dB")
P
B=$(cat /tmp/room-best)
amixer -q -c 0 cset name="$CTL" "$B,$B"
CFG=""; for p in "${ROOM_CONFIG:-}" "$HOME/.config/room/config.json" "$HERE/config.json"; do [ -n "$p" ] && [ -f "$p" ] && { CFG="$p"; break; }; done
if [ -n "$CFG" ]; then
  "$PY" - "$CFG" "$B" <<'P'
import json, sys
p, b = sys.argv[1], int(sys.argv[2])
c = json.load(open(p))
vs = c.setdefault("voiceSettings", {})
vs["micBoost"] = b; vs["micVolume"] = 1.0
json.dump(c, open(p, "w"), indent=2)
print(f"saved micBoost {b}, micVolume 1.0 → {p}")
P
fi
rm -f /tmp/room-q.raw /tmp/room-b?.raw /tmp/room-best
systemctl --user restart room 2>/dev/null && echo "Room restarted"
echo "✓ Saved to $OUT"
