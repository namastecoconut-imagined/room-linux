#!/usr/bin/env bash
# assistant-profile — where the assistant's time goes. Watches the running assistant for 30 s from the outside
# (py-spy samples it 100 times a second without pausing it; nothing in it changes) and lists what it was doing:
# how busy each of its threads was, and which code that time went to. For the quiet-room case: nothing playing,
# nobody talking, while it runs.
#   bash ~/room/scripts/assistant-profile.sh [seconds]
# Asks for your password (looking inside another program needs it). py-spy goes in its own folder,
# ~/.cache/room-experiments/py-spy (on the experiments.sh list); nothing else is kept.
set -euo pipefail
SECS=${1:-30}
V="$HOME/.cache/room-experiments/py-spy"
PID=$(systemctl --user show -p MainPID --value room-assistant 2>/dev/null || true)
[ -n "$PID" ] && [ "$PID" != 0 ] || { echo "  The assistant isn't running (systemctl --user status room-assistant)."; exit 1; }
if [ ! -x "$V/bin/py-spy" ]; then
  echo "▸ Getting py-spy (once, into $V)…"
  python3 -m venv "$V" && "$V/bin/pip" install -q "py-spy==0.4.2"
fi
echo "▸ Looking inside another program needs your password"
sudo -v
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# the system's own count of each thread's processor time, before and after (catches native threads too)
snap() { for d in /proc/"$PID"/task/*; do [ -r "$d/stat" ] && echo "$(basename "$d") $(cat "$d/comm" 2>/dev/null | tr ' ' '_') $(awk '{print $14 + $15}' "$d/stat" 2>/dev/null)"; done; }
snap > "$T/before"
echo "▸ Watching the assistant (pid $PID) for $SECS s — keep the room quiet: nothing playing, nobody talking"
sudo "$V/bin/py-spy" record --pid "$PID" --duration "$SECS" --rate 100 --format raw --threads --nonblocking \
  --output "$T/raw.txt" >"$T/log" 2>&1 || { echo "  py-spy couldn't:"; tail -4 "$T/log" | sed 's/^/    /'; exit 1; }
snap > "$T/after"
sudo chown "$(id -u)" "$T/raw.txt" 2>/dev/null || true

python3 - "$T/before" "$T/after" "$T/raw.txt" "$SECS" "$(getconf CLK_TCK)" <<'PY'
import collections, re, sys
before, after, raw, secs, hz = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])

def ticks(path):
    d = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3:
            d[p[0]] = (p[1], int(p[2]))
    return d

a, b = ticks(before), ticks(after)
per = {tid: (name, (t - a.get(tid, (name, 0))[1]) / hz / secs * 100) for tid, (name, t) in b.items()}
total = sum(p for _, p in per.values())
print(f"  measured by the system: the assistant used {total:.1f} % of one core, in {len(per)} threads")
names = {}
samples = collections.Counter(); incl = collections.Counter(); own = collections.Counter(); n = 0
for line in open(raw):
    line = line.rstrip("\n")
    stack, _, c = line.rpartition(" ")
    if not c.isdigit():
        continue
    c = int(c); n += c
    frames = stack.split(";")
    m = re.match(r"thread \((\w+)\)(?::\s*(.*))?", frames[0])
    if m:
        tid = str(int(m.group(1), 0)) if m.group(1).startswith("0x") else m.group(1)
        names[tid] = m.group(2) or names.get(tid, "")
        samples[tid] += c
        frames = frames[1:]
    keys = []
    for f in frames:
        fm = re.match(r"(.*) \((.*?):\d+\)$", f)
        fn, path = (fm.group(1), fm.group(2)) if fm else (f, "")
        if path.endswith(("threading.py", "runpy.py")) or fn == "<module>":
            continue
        path = re.sub(r".*/(site-packages|lib/python3\.\d+)/", "", path)
        path = re.sub(r".*/(assistant|room)/", r"\1/", path)
        keys.append(f"{fn}  ({path})" if path else fn)
    for k in dict.fromkeys(keys):
        incl[k] += c
    if keys:
        own[keys[-1]] += c
pct = lambda c: c / (secs * 100) * 100
print("  its threads, busiest first (% of one core; the name in [ ] is the Python thread's, where py-spy saw it):")
for tid, (name, p) in sorted(per.items(), key=lambda kv: -kv[1][1])[:10]:
    if p >= 0.2:
        print(f"     {p:5.1f} %  {name}" + (f"  [{names[tid]}]" if names.get(tid) else ""))
print(f"  in Python code: {pct(n):.1f} % of one core (the rest is native: the sound library, onnxruntime's own threads)")
print("  where that went — including what each calls:")
for k, c in incl.most_common(14):
    print(f"     {pct(c):5.1f} %  {k}")
print("  doing the work itself:")
for k, c in own.most_common(10):
    print(f"     {pct(c):5.1f} %  {k}")
PY
