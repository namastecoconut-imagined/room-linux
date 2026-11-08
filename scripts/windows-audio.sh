#!/usr/bin/env bash
# Read-only: how Windows' Realtek driver set up this Surface's mics (and speakers), next to how Linux has the same chip
# set up — so the Fedora fix copies what Windows did. Uses the driver package mic-report.sh downloaded. Also a sound
# report (where Room's voice goes and how loud each step is). Writes ~/room-windows-audio.txt.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HOME/room-windows-audio.txt"
X="$HOME/.cache/room/sp6-driver"
exec > >(tee "$OUT") 2>&1
[ -d "$X" ] || { echo "The driver package isn't unpacked yet — run: bash ~/room/scripts/mic-report.sh first"; exit 1; }

echo "=== Windows: every setting the Realtek driver applies to this Surface's chip (subsystem 10CC)"
python3 - "$X" <<'P'
import re, sys, glob, os
X = sys.argv[1]
def read(p):
    b = open(p, "rb").read()
    return b.decode("utf-16") if b[:2] in (b"\xff\xfe", b"\xfe\xff") else b.decode("latin-1")
inf = [p for p in glob.glob(X + "/**/HDXSSTM.inf", recursive=True)][0]
t = read(inf)
secs = {}
for m in re.finditer(r"^\[([^\]]+)\]\s*$", t, re.M):
    secs.setdefault(m.group(1), (m.end(), None))
names = list(secs)
bounds = sorted((v[0], k) for k, v in secs.items())
body = {}
for i, (start, k) in enumerate(bounds):
    end = bounds[i + 1][0] if i + 1 < len(bounds) else len(t)
    body[k] = t[start:end].rsplit("\n[", 1)[0]
strings = dict(re.findall(r'^\s*([A-Za-z0-9_.]+)\s*=\s*"?([^"\n;]*)"?', body.get("Strings", ""), re.M))
def expand(l): return re.sub(r"%([^%]+)%", lambda m: strings.get(m.group(1), m.group(0)), l)
seen = set()
def show(n, depth=0):
    if n in seen or n not in body or depth > 4: return
    seen.add(n)
    lines = [l.strip() for l in body[n].splitlines() if l.strip() and not l.strip().startswith(";")]
    lines = [l for l in lines if "FriendlyName" not in l and "Copyright" not in l]
    print(f"\n[{n}]")
    for l in lines[:400]: print("  " + expand(l)[:220])
    for l in lines:
        m = re.match(r"(AddReg|CopyFiles|Include|Needs)\s*=\s*(.+)", l, re.I)
        if m and m.group(1).lower() == "addreg":
            for s in m.group(2).split(","): show(s.strip(), depth + 1)
for n in [k for k in body if "10CC" in k.upper()]: show(n)
# anything about the mics anywhere in the package (other drivers, settings files)
print("\n=== mic-related lines in every driver file")
for p in glob.glob(X + "/**/*", recursive=True):
    if os.path.isdir(p) or not re.search(r"\.(inf|ini|xml|txt|cfg|json)$", p, re.I): continue
    try: s = read(p)
    except Exception: continue
    hits = sorted(set(l.strip() for l in s.splitlines() if re.search(r"dmic|invert|phase|micarray|mic_array|geometry|beam|"
                                                                      r"noisesup|\bns\b|aec|agc|micboost|mic_boost|"
                                                                      r"capturegain|recgain|channelmap", l, re.I)))
    hits = [h for h in hits if not h.startswith(";") and "FriendlyName" not in h and "DeviceName" not in h][:60]
    if hits:
        print(f"\n--- {os.path.relpath(p, X)}")
        for h in hits: print("  " + expand(h)[:220])
P

echo; echo "=== Linux: the same chip — the mic pins and processing"
C=/proc/asound/card0/codec#0
grep -iE "^Codec|Subsystem|Vendor" $C
awk '/^Node 0x12|^Node 0x13|^Node 0x08|^Node 0x09|^Node 0x22|^Node 0x23|^Node 0x20/{p=1} /^Node/ && !/0x12|0x13|0x08|0x09|0x22|0x23|0x20/{p=0} p' $C | head -120
echo "--- kernel"
uname -r
cat /sys/module/snd_hda_intel/parameters/model 2>/dev/null | sed 's/^/model: /'
grep -r . /etc/modprobe.d/ 2>/dev/null | grep -i snd | head

echo; echo "=== Sound: where Room's voice goes"
wpctl status 2>/dev/null | sed -n '/Audio/,/Video/p' | sed -n '/Sinks:/,/Sources:/p'
wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -E "node.name|node.description" | head -3
wpctl get-volume @DEFAULT_AUDIO_SINK@
for id in $(pw-dump 2>/dev/null | python3 -c "import json,sys;[print(n['id']) for n in json.load(sys.stdin) if (n.get('info') or {}).get('props',{}).get('media.class')=='Audio/Sink']"); do
  printf "  sink %s  %s  " "$id" "$(wpctl inspect $id | grep -m1 'node.description' | cut -d'"' -f2)"; wpctl get-volume $id
done
amixer -c 0 sget Master 2>/dev/null | tail -1; amixer -c 0 sget Speaker 2>/dev/null | tail -1
grep -iE "pw-play|pw-cat|room" ~/.local/state/wireplumber/stream-properties 2>/dev/null | head
ls ~/.config/pipewire/pipewire.conf.d/ 2>/dev/null
journalctl --user -u room --since "-3 hours" --no-pager 2>/dev/null | grep -E "aura|duck|tts" | tail -8
echo; echo "✓ Saved to $OUT"
