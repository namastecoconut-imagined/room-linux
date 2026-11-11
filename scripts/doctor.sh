#!/usr/bin/env bash
# room-doctor: everything worth knowing about Room's health, in one go — to read, or to paste to whoever's helping.
# Read-only: it changes nothing. Takes ~6 s (it measures the sound system's CPU over 5 s).
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
h() { printf '\n== %s\n' "$1"; }
j() { journalctl --user -u "$1" --since "${2:--1h}" --no-pager -o cat 2>/dev/null; }

echo "Room doctor · $(date '+%a %d %b %H:%M') · $(cd "$HERE" && git log -1 --format='%h %s' | cut -c1-70)"
uptime | sed 's/^ *//'

h "services"
for s in room room-assistant room-airplay room-spotify pipewire wireplumber; do
  printf '%-15s %s\n' "$s" "$(systemctl --user is-active $s 2>/dev/null)"
done
bash "$HERE/scripts/kiosk.sh" 2>/dev/null | head -1

h "heat and power"
echo "profile $(tuned-adm active 2>/dev/null | sed 's/.*: //') · CPU $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null) · $(awk '/MHz/{s+=$4;n++} END{printf "%.0f MHz avg", s/n}' /proc/cpuinfo)"
for z in /sys/class/thermal/thermal_zone*; do [ -f $z/type ] || continue; t=$(cat $z/type); case $t in x86_pkg_temp|B0D4|pch_skylake) printf '%s %s°C  ' "$t" $(( $(cat $z/temp) / 1000 ));; esac; done; echo
ps -eo pcpu,comm --sort=-pcpu | sed -n '2,6p' | awk '{printf "%s%% %s · ", $1, $2} END{print ""}'

h "sound system"
p=$(pgrep -x pipewire)
if [ -n "$p" ]; then
  a=$(ps -o times= -p $p); sleep 5; b=$(ps -o times= -p $p)
  echo "pipewire: $(( (b - a) * 20 ))% of a core now (5 s) · up $(ps -o etime= -p $p | tr -d ' ') · killed $(journalctl --user -u pipewire -b 2>/dev/null | grep -c KILL)× this boot"
fi
echo "-- working right now (busy per cycle):"
timeout 4 pw-top -b -n 2 2>/dev/null | awk 'NR>1 && $1=="R" && $6!="0.0us" && $6!="---" {printf "  %-45s %s busy, %s of the cycle\n", $NF, $6, $8}' | sort -u
pw-dump 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "[]")
except ValueError:
    d = []
n = {}
for o in d:
    if o.get("type", "").endswith("Node"):
        p = o["info"]["props"]; n[o["id"]] = p.get("node.description") or p.get("node.name")
        nm = p.get("node.name") or ""
        if p.get("application.name") == "Room assistant" or nm.startswith(("bluez_output", "alsa_output")):
            codec = p.get("api.bluez5.codec")
            print("  node  %s · %s%s" % (n[o["id"]], o["info"]["state"], " · codec " + codec if codec else ""))
for o in d:
    if o.get("type", "").endswith("Link"):
        i = o["info"]; a, b = n.get(i["output-node-id"]), n.get(i["input-node-id"])
        if any(k in (x or "") for x in (a, b) for k in ("Dolby", "Built-in Audio Analog", "Xiaomi", "bluez")):
            print("  link  %s → %s · %s · %s" % (a, b, "passive" if i.get("props", {}).get("link.passive") else "active", i["state"]))
' | sort -u

h "assistant"
j room-assistant -24h | grep -E "wake word:|listening on" | tail -2
j room-assistant -1h | grep -E "voice: speaker (resting|awake)|reconnect|fell|turned it off|couldn't|failed|Traceback" | tail -6
echo "-- last requests:"
j room-assistant -1h | grep -E "Alexa \(|heard |broke up" | tail -6

h "screen and room"
j room -24h | grep -E "screen (off|on)|sound level" | tail -4
j room -1h | grep -E "output:|volume:" | tail -3

h "errors (last hour)"
journalctl --user --since -1h -p err --no-pager -o short 2>/dev/null | grep -v "^-- " | tail -8
echo
