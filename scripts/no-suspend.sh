#!/usr/bin/env bash
# The panel never goes to sleep (suspend). Asleep, nothing runs — no "Alexa", no screen coming back at a sound, no
# AirPlay — and only the power button wakes it. GNOME suspends an idle computer after a while (its "suspending
# soon" notice), and closing the Type Cover counts as closing a lid. Room turns the *screen* off on its own; the
# computer stays awake. Safe to run again; `sudo systemctl unmask sleep.target suspend.target hibernate.target
# hybrid-sleep.target` undoes it.
set -euo pipefail
echo "▸ Never suspend (whatever is running: GNOME or the panel session)"
sudo systemctl mask -q sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nIdleAction=ignore\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' \
  | sudo tee /etc/systemd/logind.conf.d/room-no-suspend.conf >/dev/null
sudo systemctl kill -s HUP systemd-logind 2>/dev/null || true
# GNOME's own idle suspend (it would otherwise keep trying, and keep showing its notice)
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
fi
echo "✓ The Surface won't suspend any more. (Room still turns the screen off by itself in a quiet room.)"
