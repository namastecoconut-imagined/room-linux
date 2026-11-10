#!/usr/bin/env bash
# Keeps the Surface cool: Room's own tuned profile — Fedora's "balanced", except the CPU leans to saving power
# (energy_performance_preference = balance_power). On "balanced" all cores sat at 2.6 GHz doing almost nothing and
# the case ran warm; with this they idle at 1 GHz and still speed up the moment Room needs them (its voice is fine).
# Not Fedora's "powersave" profile: that also sleeps the sound chip and Wi-Fi (clipped first words, AirPlay stutter).
# Safe to run again. Undo: sudo tuned-adm profile balanced
set -e
command -v tuned-adm >/dev/null || { echo "  (tuned isn't installed — skipped)"; exit 0; }
d=/etc/tuned/profiles; [ -d "$d" ] || d=/etc/tuned
sudo mkdir -p "$d/room"
printf '[main]\nsummary=Room: balanced, but the CPU leans to saving power (cooler)\ninclude=balanced\n\n[cpu]\nenergy_performance_preference=balance_power\n' \
  | sudo tee "$d/room/tuned.conf" >/dev/null
sudo tuned-adm profile room
echo "▸ Cool: $(tuned-adm active | sed 's/.*: //') · CPU $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
