#!/usr/bin/env bash
# Runs inside the "Room (panel only)" session: cage shows whatever window opens, full screen — Room. Room itself is
# still the room.service you know (so room-update, logs and restarts work exactly as before).
# No automatic restart: if Room stops and stays stopped for 20 s, this session ends and you're at a text login on the
# screen (greetd's) — SSH works as always.
systemctl --user import-environment WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP 2>/dev/null
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP 2>/dev/null
systemctl --user restart room.service
# everything else Room uses starts with the session anyway; make sure (no-op when they're already running)
for s in room-assistant room-airplay room-spotify; do
  systemctl --user cat "$s.service" >/dev/null 2>&1 && systemctl --user start "$s.service"
done
down=0
while sleep 5; do
  if systemctl --user is-active --quiet room.service; then
    down=0
  else
    down=$((down + 5))
    [ $down -ge 20 ] && { echo "Room stopped — leaving the panel session"; exit 0; }
  fi
done
