#!/usr/bin/env bash
# Room's full audit — looks at everything, changes nothing. About two minutes (one of them sitting still).
#   sudo bash ~/room/scripts/audit.sh
# Health (temperatures, throttling, battery, power, disk, memory), every service, timer and startup item marked
# NEEDED / OFF / ASK, what's installed beyond the kiosk (slim.py's plan), clutter, and experiment leftovers.
# Everything goes to ~/room-audit.txt (send that file to Claude). Nothing is removed: that's the next step, item by
# item, once you've chosen. (It doesn't read config.json's keys or AirPlay's metadata pipe. Like health.sh, which it
# runs, it does tidy Room's own permission files: the old speech-boost one goes, the power-meter one is set.)
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo bash ~/room/scripts/audit.sh"; exit 1; }
U=${SUDO_USER:-$(id -un)}
UHOME=$(getent passwd "$U" | cut -d: -f6)
OUT="$UHOME/room-audit.txt"
us() { systemctl --user --machine="$U@" "$@" 2>/dev/null; }

# What the kiosk needs (system services): Room's own, sound, network, AirPlay, touch, heat and power, sign-in, logging
NEED_SYS="greetd NetworkManager wpa_supplicant bluetooth avahi-daemon nqptp sshd firewalld chronyd thermald tuned
iptsd iio-sensor-proxy upower rtkit-daemon auditd smartd sssd systemd-journald systemd-logind systemd-udevd
systemd-resolved systemd-oomd systemd-timesyncd dbus dbus-broker polkit accounts-daemon udisks2 power-profiles-daemon
getty@ serial-getty@ user@ user-runtime-dir@ fwupd irqbalance alsa-state"
NEED_USER="room room-assistant room-airplay room-spotify room-watch pipewire pipewire-pulse wireplumber dbus
dbus-broker xdg-permission-store xdg-document-portal xdg-desktop-portal at-spi-dbus-bus p11-kit-server"
# What lean.sh already switched off (should show as off)
LEAN="cups ModemManager rsyslog atd gssproxy stratisd switcheroo-control uresourced vmtoolsd vgauthd vboxservice
qemu-guest-agent packagekit packagekit-offline-update crond dnf-makecache plocate-updatedb raid-check unbound-anchor"
mark() {   # unit-name → NEEDED / OFF? / ASK
  local n=${1%.*}; n=${n%%@*}
  for k in $NEED_SYS $NEED_USER; do [ "${k%@}" = "$n" ] && { echo "NEEDED"; return; }; done
  for k in $LEAN; do [ "$k" = "$n" ] && { echo "SHOULD BE OFF (lean.sh)"; return; }; done
  echo "ASK"
}

main() {
echo "Room audit — $(date '+%Y-%m-%d %H:%M') · $(. /etc/os-release; echo "$PRETTY_NAME") · $(uname -r) · up $(uptime -p | sed 's/^up //')"

echo; echo "################ 1. Health (health.sh, a minute of sitting still)"
bash "$HERE/scripts/health.sh" 60 2>&1 | grep -v '^→'

echo; echo "################ 2. Heat, throttling, battery"
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/temp" 2>/dev/null) || continue
  printf '  %-22s %s °C\n' "$(cat "$z/type")" "$(awk -v t="$t" 'BEGIN {printf "%.1f", t/1000}')"
done
command -v sensors >/dev/null && sensors 2>/dev/null | grep -E 'Package|Core|fan' | sed 's/^/  /'
th=0; for f in /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count; do th=$((th + $(cat "$f" 2>/dev/null || echo 0))); done
echo "  CPU throttled for heat since start: $th times (all cores together)"
for B in /sys/class/power_supply/BAT*; do
  [ -d "$B" ] || continue
  ef=$(cat "$B/energy_full" 2>/dev/null || cat "$B/charge_full" 2>/dev/null); ed=$(cat "$B/energy_full_design" 2>/dev/null || cat "$B/charge_full_design" 2>/dev/null)
  echo "  battery $(basename "$B"): $(cat "$B/capacity")% · $(cat "$B/status") · health $([ -n "$ef" ] && [ -n "$ed" ] && echo "$((100 * ef / ed))% of new" || echo '?') · cycles $(cat "$B/cycle_count" 2>/dev/null || echo '?')"
done
echo "  memory: $(free -h | awk '/Mem:/ {print $3 " used of " $2 ", " $7 " available"}') · swap/zram: $(free -h | awk '/Swap:/ {print $3 " of " $2}')"
echo "  the biggest users of CPU and memory right now:"
ps -eo pcpu,rss,user,comm --sort=-pcpu | awk 'NR==1 || NR<=9 {printf "    %5s %%  %7.0f MB  %-14s %s\n", $1, $2/1024, $3, $4}' | sed '1s/.*/     CPU      memory  user           program/'

echo; echo "################ 3. Services, timers and startup items"
echo "== System services that start at boot"
systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | while read -r u; do
  printf '  %-26s %-8s %s\n' "$(mark "$u")" "$(systemctl is-active "$u" 2>/dev/null)" "$u"; done | sort
echo "== System services running right now that aren't set to start at boot (started by something else)"
comm -13 <(systemctl list-unit-files --type=service --state=enabled --no-legend | awk '{print $1}' | sort) \
  <(systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | sort) | while read -r u; do
  printf '  %-26s %s\n' "$(mark "$u")" "$u"; done
echo "== System timers"
systemctl list-timers --all --no-legend --plain 2>/dev/null | awk '{print $(NF-1)}' | grep '\.timer$' | sort -u | while read -r u; do
  printf '  %-26s %s\n' "$(mark "$u")" "$u"; done
echo "== Your services and timers (Room's side)"
{ us list-unit-files --type=service --state=enabled --no-legend; us list-units --type=service --state=running --no-legend --plain; } \
  | awk '{print $1}' | sort -u | while read -r u; do printf '  %-26s %-8s %s\n' "$(mark "$u")" "$(us is-active "$u")" "$u"; done
us list-timers --all --no-legend --plain | awk '{print $(NF-1)}' | grep '\.timer$' | sed 's/^/  ASK                        /'
echo "== Startup items (autostart)"
ls /etc/xdg/autostart "$UHOME/.config/autostart" 2>/dev/null | grep -v ':$' | grep . | sed 's/^/  /' | head -40
echo "== Sockets that start things on demand"
systemctl list-units --type=socket --state=listening --no-legend --plain 2>/dev/null | awk '{print "  " $1}'

echo; echo "################ 4. Installed beyond the kiosk"
echo "  packages installed: $(rpm -qa | wc -l)"
echo "  kernels: $(rpm -q kernel kernel-surface 2>/dev/null | grep -v 'not installed' | tr '\n' ' ') (running $(uname -r))"
command -v flatpak >/dev/null && { n=$(flatpak list --columns=application 2>/dev/null | grep -c .); echo "  Flatpak apps: $n"; flatpak list --columns=application,size 2>/dev/null | sed 's/^/    /' | head -30; }
echo "  slim.py's plan (what it would uninstall; it changes nothing now):"
python3 "$HERE/scripts/slim.py" plan 2>&1 | sed 's/^/    /' | head -8
[ -s "$UHOME/room-slim-plan.txt" ] && echo "    (the full list is in ~/room-slim-plan.txt — it's appended at the end of this file)"

echo; echo "################ 5. Space and clutter"
df -h / /boot /boot/efi 2>/dev/null | sed 's/^/  /'
echo "== The biggest folders in your home"
du -xh --max-depth=2 "$UHOME" 2>/dev/null | sort -rh | sed -n '2,20p' | sed 's/^/  /'
echo "== Caches, logs and leftovers"
for d in "$UHOME/.cache" "$UHOME/.local/share/Trash" "$UHOME/Downloads" "$UHOME/.mozilla" "$UHOME/.local/share/uv" \
         "$UHOME/.cache/uv" "$UHOME/.cache/pip" "$UHOME/.cache/huggingface" "$UHOME/.cache/torch" "/var/cache/dnf" \
         "/var/cache/PackageKit" "/var/lib/flatpak" "/var/lib/systemd/coredump" "/var/tmp" "/var/log"; do
  [ -e "$d" ] && printf '  %8s  %s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)" "$d"
done
echo "  journal: $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]' | head -1)"
echo "== Files in your home that aren't Room's (top level)"
ls -A "$UHOME" | grep -vE '^(\.|room$|Desktop$|Documents$|Downloads$|Music$|Pictures$|Public$|Templates$|Videos$)' | sed 's/^/  /'

echo; echo "################ 6. Experiment leftovers (experiments.sh)"
sudo -u "$U" bash "$HERE/scripts/experiments.sh" 2>&1 | sed 's/^/  /'

if [ -s "$UHOME/room-slim-plan.txt" ]; then
  echo; echo "################ Appendix: slim.py's full plan"; cat "$UHOME/room-slim-plan.txt"
fi
}
main 2>&1 | tee "$OUT"
chown "$U": "$OUT" 2>/dev/null
echo; echo "→ $OUT — send it over (from the Mac: scp namastecoconut@fedora.local:room-audit.txt ~/Downloads/)"
