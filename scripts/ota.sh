#!/usr/bin/env bash
# Settings → More settings → Updates: update Room (room-update), then make sure it came back. Started on its own by
# room/update.py (systemd-run), so it carries on while Room restarts. If Room isn't running a minute after, it goes
# back to the version before and restarts that. What happened goes in ~/.local/state/room/update.json.
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$HERE" || exit 1
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/room"; mkdir -p "$STATE"
LOG="$STATE/update.log"
say() { printf '{"ok": %s, "note": "%s", "at": %s}\n' "$1" "$2" "$(date +%s)" > "$STATE/update.json"; }
before=$(git rev-parse HEAD)
echo "── $(date) · updating from $(git log -1 --format='%h')" >> "$LOG"
if ! bash "$HERE/scripts/update.sh" >> "$LOG" 2>&1; then
  echo "update failed — going back to $before" >> "$LOG"
  git reset -q --hard "$before"; ROOM_NO_PULL=1 bash "$HERE/scripts/update.sh" >> "$LOG" 2>&1
  say false "That update didn't go through · still on $(git log -1 --format='%h')"; exit 1
fi
after=$(git rev-parse HEAD)
sleep 60
if systemctl --user is-active --quiet room.service; then
  say true "Updated to $(git log -1 --format='%h · %s' | cut -c1-90)"
  echo "ok: $(git log -1 --format='%h')" >> "$LOG"
else
  echo "Room didn't come back on $after — going back to $before" >> "$LOG"
  git reset -q --hard "$before"; ROOM_NO_PULL=1 bash "$HERE/scripts/update.sh" >> "$LOG" 2>&1
  say false "The new version didn't start · went back to $(git log -1 --format='%h')"
fi
