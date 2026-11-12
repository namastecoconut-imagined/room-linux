#!/usr/bin/env bash
# Room's health check, about a minute: is every part running (since when, how many restarts), is logging working,
# anything failing — then how hard the Surface works: CPU (each program's share), power, temperatures, clocks.
#   sudo bash ~/room/scripts/health.sh [seconds]     (default 60; sudo: the processor's power meter is root-only)
# Changes nothing — except, once, it lets your group read the power meter, so Room's tracker can log watts too.
# Everything printed also goes to ~/room-health.txt.
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SECS=${1:-60}
U=${SUDO_USER:-$(id -un)}
UHOME=$(getent passwd "$U" | cut -d: -f6)
OUT="$UHOME/room-health.txt"
[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo bash ~/room/scripts/health.sh"; exit 1; }

us() { systemctl --user --machine="$U@" "$@" 2>/dev/null; }
row() {   # scope unit — state, restarts, since
  local S=(systemctl) st n since
  [ "$1" = user ] && S=(systemctl --user --machine="$U@")
  st=$("${S[@]}" is-active "$2" 2>/dev/null); st=${st:-unknown}
  n=$("${S[@]}" show -p NRestarts --value "$2" 2>/dev/null)
  since=$("${S[@]}" show -p ActiveEnterTimestamp --value "$2" 2>/dev/null | awk '{print $2, $3}')
  printf '  %s %-28s %-9s %s\n' "$([ "$st" = active ] && echo ✓ || echo ✗)" "$2" "$st" \
    "${since:+since ${since}}${n:+ · restarts $n}"
  if [ "${n:-0}" -gt 0 ]; then    # why: the last exit the journal has for it since this start
    local J=(journalctl -b -q --no-pager -u "$2"); [ "$1" = user ] && J=(journalctl -b -q --no-pager "_SYSTEMD_USER_UNIT=$2.service")
    "${J[@]}" -g 'exited|Failed|failed|code=|Stopped|Started' 2>/dev/null | grep -v 'Started' | tail -1 | cut -d' ' -f5- | cut -c1-150 \
      | sed 's/^/        why: /'
  fi
}

main() {
echo "Room health — $(date '+%Y-%m-%d %H:%M') · up $(uptime -p | sed 's/^up //') · $(uname -r)"
echo "  power profile: $(tuned-adm active 2>/dev/null | sed 's/.*: //') · CPU leaning: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"

echo; echo "== Room's parts"
for u in room room-assistant room-airplay room-spotify pipewire pipewire-pulse wireplumber room-watch; do row user "$u"; done
for u in greetd nqptp bluetooth NetworkManager avahi-daemon sshd tuned thermald systemd-journald; do row system "$u"; done
for u in $(systemctl list-units --plain --no-legend 'iptsd*' 2>/dev/null | awk '{print $1}'); do row system "$u"; done
pgrep -x cage >/dev/null && echo "  ✓ cage (the screen) running" || echo "  ✗ cage (the screen) isn't running"
f=$(systemctl --failed --plain --no-legend 2>/dev/null; us --failed --plain --no-legend)
[ -n "$f" ] && { echo "  ✗ failed:"; echo "$f" | sed 's/^/     /'; } || echo "  ✓ nothing failed"

echo; echo "== Since this start: crashes and errors"
c=$(journalctl -b -q --no-pager -g 'dumped core|core-dump|code=killed|code=dumped' 2>/dev/null | wc -l)
echo "  crashes or kills logged: $c"
[ "$c" -gt 0 ] && journalctl -b -q --no-pager -g 'dumped core|core-dump|code=killed|code=dumped' | tail -5 | cut -c1-200 | sed 's/^/     /'
# known and harmless on this Surface: the kernel has no BPF security module (systemd notes it), Intel SGX/TDX are
# off in its firmware, and its Marvell Bluetooth chip sends one stray event when it starts
HARMLESS='bpf-restrict-fs|SGX disabled|TDX not supported|unexpected event for opcode 0x0000'
e=$(journalctl -b -q --no-pager -p err 2>/dev/null)
n=$(printf '%s' "$e" | grep -c .); h=$(printf '%s' "$e" | grep -cE "$HARMLESS")
echo "  error lines: $n ($h of them known and harmless)"
[ $((n - h)) -gt 0 ] && printf '%s\n' "$e" | grep -vE "$HARMLESS" | cut -d' ' -f5- | sed 's/\[[0-9]*\]//' | cut -c1-160 \
  | sort | uniq -c | sort -rn | head -8 | sed 's/^/     /'

echo; echo "== Logging"
echo "  journal: $([ -d /var/log/journal ] && echo 'kept across restarts' || echo 'in memory only (lost at restart)') · $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?B?' | head -1) on disk · $(journalctl --list-boots -q 2>/dev/null | wc -l) starts kept"
sup=$(journalctl -b -q --no-pager -g 'Suppressed [0-9]+ messages' 2>/dev/null | wc -l)
[ "$sup" -gt 0 ] && echo "  ! journald dropped messages $sup time(s) (something logs too fast)"
for u in room room-assistant room-airplay room-spotify; do
  n=$(journalctl -b -q --no-pager "_SYSTEMD_USER_UNIT=$u.service" 2>/dev/null | wc -l)
  last=$(journalctl -b -q --no-pager -n1 -o short "_SYSTEMD_USER_UNIT=$u.service" 2>/dev/null | awk '{print $3}')
  printf '  %-15s %6s lines since this start%s\n' "$u" "$n" "${last:+ · last at $last}"
done
W="$UHOME/.local/state/room/watch.log"
m=$([ -s "$W" ] && echo $(($(wc -l < "$W") - 1)) || echo 0)
if [ "$m" -gt 0 ]; then echo "  tracker: $m minutes logged · last: $(tail -1 "$W" | cut -f1) ($W)"
else echo "  tracker: started — its first line comes a minute after it starts ($W)"; fi

echo; echo "== Room's permissions (set again at every start)"
# by group NUMBER: the start-up's first stage (the boot image) can't look names up — with the name, the speech
# boost's line logged "Unknown group" there at every start
G=$(id -g "$U")
for R in /etc/tmpfiles.d/room-boost.conf /etc/tmpfiles.d/room-power.conf; do
  if [ -f "$R" ] && grep -qE '^z .* root [^0-9 ][^ ]* ' "$R"; then
    sed -i -E "s/^(z .* root )[^0-9 ][^ ]*( .*)$/\1$G\2/" "$R" && echo "  ▸ $(basename "$R"): your group by number now"
  fi
done
# the tracker logs watts too when your group may read the power meter (once; at every start after)
R=/etc/tmpfiles.d/room-power.conf
[ -f "$R" ] || printf '# Room: its tracker (scripts/watch.py) reads the processor'"'"'s power meter\nz /sys/class/powercap/intel-rapl:*/energy_uj 0440 root %s - -\n' "$G" > "$R"
systemd-tmpfiles --create $(ls /etc/tmpfiles.d/room-boost.conf "$R" 2>/dev/null) 2>&1 | sed 's/^/  ! /'
p=$(stat -Lc '%A' /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference 2>/dev/null)
echo "  $([ "${p:5:1}" = w ] && echo ✓ || echo ✗) speech boost: the assistant may raise the CPU's speed while it talks ($p)"
p=$(stat -Lc '%A' /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null)
echo "  $([ "${p:4:1}" = r ] && echo ✓ || echo ✗) power meter: the tracker may read it ($p)"

echo; echo "== Working (sit still for $SECS s — no touching)"
python3 "$HERE/scripts/watch.py" --report "$SECS"
fr=$(journalctl -b -q --no-pager "_SYSTEMD_USER_UNIT=room.service" -g "frames a second" 2>/dev/null | tail -1 | sed 's/.*\[room\] //')
echo "  Screen: ${fr:-not logged yet (Room logs it once a minute)}"
echo "  Disk: $(df -h / | awk 'NR==2 {print $3 " used of " $2 " (" $5 ")"}')"
OLD="$UHOME/room-watch.log"
if [ -s "$OLD" ]; then
  echo; echo "== Before the slim (the earlier tracker: its columns, then a few lines from an hour before it stopped)"
  head -1 "$OLD" | cut -c1-200
  tail -n 70 "$OLD" | head -3 | cut -c1-200
fi
}
main 2>&1 | tee "$OUT"
chown "$U": "$OUT" 2>/dev/null
echo "→ $OUT"
