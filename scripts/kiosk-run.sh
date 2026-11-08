#!/usr/bin/env bash
# Runs inside the "Room (panel only)" session: cage shows whatever window opens, full screen — Room. Room itself is
# still the room.service you know (so room-update, logs and restarts work exactly as before).
# No automatic restart: if Room stops and stays stopped for 20 s, this session ends and you're at the login screen,
# where you can pick GNOME or Room again.
systemctl --user import-environment WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP 2>/dev/null
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP 2>/dev/null
systemctl --user restart room.service
down=0
while sleep 5; do
  if systemctl --user is-active --quiet room.service; then
    down=0
  else
    down=$((down + 5))
    [ $down -ge 20 ] && { echo "Room stopped — leaving the panel session"; exit 0; }
  fi
done
