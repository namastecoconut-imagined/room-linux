#!/usr/bin/env bash
# Keeps the Surface cool: Room's own tuned profile — Fedora's "balanced", except the CPU leans to saving power
# (energy_performance_preference = balance_power). On "balanced" all cores sat at 2.6 GHz doing almost nothing and
# the case ran warm; with this they idle at 1 GHz and still speed up the moment Room needs them (its voice is fine).
# Not Fedora's "powersave" profile: that also sleeps the sound chip and Wi-Fi (clipped first words, AirPlay stutter).
# Safe to run again. Undo: in /etc/tuned/ppd.conf put balanced=balanced (and balanced=balanced-battery under
# [battery]), then sudo systemctl restart tuned-ppd
set -e
command -v tuned-adm >/dev/null || { echo "  (tuned isn't installed — skipped)"; exit 0; }
d=/etc/tuned/profiles; [ -d "$d" ] || d=/etc/tuned
sudo mkdir -p "$d/room"
printf '[main]\nsummary=Room: balanced, but the CPU leans to saving power (cooler)\ninclude=balanced\n\n[cpu]\nenergy_performance_preference=balance_power\n' \
  | sudo tee "$d/room/tuned.conf" >/dev/null
# Fedora's tuned-ppd brings back its remembered mode ("balanced") at every start, over any profile set by hand —
# so "balanced" itself is pointed at Room's profile (on mains and on battery), and anything asking for balanced
# (boot, GNOME) gets the cool one
[ -f /etc/tuned/ppd.conf ] && sudo sed -i -e 's/^balanced=balanced$/balanced=room/' \
  -e 's/^balanced=balanced-battery$/balanced=room/' /etc/tuned/ppd.conf
systemctl is-active -q tuned-ppd 2>/dev/null && sudo systemctl restart tuned-ppd && sleep 2
sudo tuned-adm profile room
# …and the assistant may boost the CPU for the second or two it takes to make speech, then put it back
# (assistant/boost.py): the energy-preference files are made writable by your group, at every start
G=$(id -gn "${SUDO_USER:-$USER}")
printf '# Room: the assistant boosts the CPU while it makes speech (assistant/boost.py)\nz /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference 0664 root %s - -\n' "$G" \
  | sudo tee /etc/tmpfiles.d/room-boost.conf >/dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/room-boost.conf
# …and Room's tracker (scripts/watch.py) may read the processor's power meter, to log watts
printf '# Room: its tracker (scripts/watch.py) reads the processor'"'"'s power meter\nz /sys/class/powercap/intel-rapl:*/energy_uj 0440 root %s - -\n' "$G" \
  | sudo tee /etc/tmpfiles.d/room-power.conf >/dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/room-power.conf
echo "▸ Speech boost: $(ls -l /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference | awk '{print $1, $3, $4}')"
echo "▸ Cool: $(tuned-adm active | sed 's/.*: //') · CPU $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
