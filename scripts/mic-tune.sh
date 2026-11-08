#!/usr/bin/env bash
# Finds the cleanest mic setting. The Surface's mic has two gains in the Realtek chip: a preamp ("Internal Mic Boost",
# +0…+30 dB, before the converter) and a digital gain ("Capture Volume", −33.5…+30 dB, after it). Preamp gain lifts
# your voice above the chip's own hiss; digital gain lifts both. So: measure the hiss at every combination (in
# silence), measure your voice once, and pick the combination with the best voice-to-hiss that still has headroom.
# Room is paused while it runs (so nothing else uses the mic or makes sound), then restarted with the result.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/voice/.venv/bin/python"; [ -x "$PY" ] || PY=python3
OUT="$HOME/room-mic-tune.txt"
T=/tmp/room-mic; rm -rf "$T"; mkdir -p "$T"
exec > >(tee "$OUT") 2>&1

rec() { pw-record --raw --rate 16000 --channels 2 --format s16 - 2>/dev/null | head -c $((16000 * 4 * $2 / 10)) > "$T/$1.raw"; }
setmic() { amixer -q -c 0 cset name="Internal Mic Boost Volume" "$1,$1"; amixer -q -c 0 cset name="Capture Volume" "$2,$2"; sleep 0.3; }

echo "▸ Pausing Room"
systemctl --user stop room 2>/dev/null; sleep 1
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1.0; sleep 0.5

echo
echo "▸ Part 1 — stay quiet for about 30 seconds (measuring the hiss at each setting)…"
for b in 0 1 2 3; do for c in 47 67 87 107 127; do setmic $b $c; rec "n-$b-$c" 15; done; done
echo "  done"

echo
echo "▸ Part 2 — from where you'd normally sit, in your normal voice, when it says go:"
echo "  \"Alexa, what's the weather like tomorrow?\""
setmic 1 67
sleep 1; echo "  go"; rec speech 50; echo "  ok"

"$PY" - "$T" <<'P'
import sys, numpy as np, json
T = sys.argv[1]
def load(n):
    a = np.frombuffer(open(f"{T}/{n}.raw", "rb").read(), "<i2").astype(np.float32).reshape(-1, 2) / 32768
    return a - a.mean(0)
def rms(x): return float(np.sqrt(np.mean(x ** 2)))
sp = load("speech")[:, 0]
w = np.sqrt(np.mean(sp[: len(sp) // 800 * 800].reshape(-1, 800) ** 2, 1))
speech, peak = float(np.percentile(w, 95)), float(np.abs(sp).max())
clipped = float(np.mean(np.abs(sp) > 0.97)) * 100
G0 = 10 + 0                                    # the speech was recorded at boost 1 (+10), capture 67 (0 dB)
print(f"\nYour voice at +10 dB preamp, 0 dB digital: level {speech:.4f}, peak {peak:.2f}, clipped {clipped:.2f}%")
rows, best = [], None
for b in range(4):
    for c in (47, 67, 87, 107, 127):
        g = b * 10 + (c - 67) * 0.5
        k = 10 ** ((g - G0) / 20)
        n = rms(load(f"n-{b}-{c}")[3000:, 0])
        s, p = speech * k, peak * k
        snr = 20 * np.log10(s / max(n, 1e-7))
        ok = p < 0.45                           # room to be ~6 dB louder (closer) without distorting
        rows.append((b, c, g, n, s, p, snr, ok))
        if ok and (best is None or snr > best[6] + 0.5 or (abs(snr - best[6]) <= 0.5 and g > best[2])):
            best = (b, c, g, n, s, p, snr, ok)
print("\npreamp  digital   total   hiss     voice    peak   voice-to-hiss")
for b, c, g, n, s, p, snr, ok in rows:
    mark = "  ← best" if best and (b, c) == best[:2] else ("" if ok else "  (too hot)")
    print(f"+{b*10:2d} dB  {(c-67)*0.5:+5.1f} dB  {g:+5.1f}   {n:.4f}   {s:.4f}   {min(p, 9.99):.2f}   {snr:5.1f} dB{mark}")
if best is None or clipped > 0.5:
    best = (0, 67) if best is None else best
json.dump({"micBoost": best[0], "micCapture": best[1]}, open(f"{T}/best.json", "w"))
P

CFG=""; for p in "${ROOM_CONFIG:-}" "$HOME/.config/room/config.json" "$HERE/config.json"; do [ -n "$p" ] && [ -f "$p" ] && { CFG="$p"; break; }; done
"$PY" - "$CFG" "$T/best.json" <<'P'
import json, sys
p, best = sys.argv[1], json.load(open(sys.argv[2]))
c = json.load(open(p)) if p else {}
vs = c.setdefault("voiceSettings", {})
vs.update(best); vs["micVolume"] = 1.0
if p:
    json.dump(c, open(p, "w"), indent=2)
print(f"\nSaved preamp +{best['micBoost']*10} dB, digital {(best['micCapture']-67)*0.5:+.1f} dB → {p}")
P
rm -rf "$T"
systemctl --user start room && echo "Room started again"
echo "✓ Saved to $OUT"
