#!/usr/bin/env bash
# Spotify Connect for Room: the Surface becomes a Spotify speaker called "Room", so "Alexa, play …" plays on the
# Surface itself — no phone, no AirPlay. Uses Spotify Soloist, Spotify's own headless Spotify Connect player
# (developer.spotify.com/documentation/soloist), run by scripts/soloist-run.sh, which also keeps it up to date.
# AirPlay is untouched. Needs Spotify Premium and a Soloist API key (free). Safe to run again.
set -euo pipefail
trap 'echo "✗ Spotify Connect setup stopped at line $LINENO — paste the lines above to Claude"' ERR
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ENVF="$HOME/.config/room/soloist.env"
mkdir -p ~/.config/room ~/.config/systemd/user

if ! grep -q '^SOLOIST_API_KEY=.' "$ENVF" 2>/dev/null; then
  echo "▸ Paste your Soloist API key (developer.spotify.com/dashboard/soloist) and press Enter:"
  read -rs KEY; echo
  [ -n "$KEY" ] || { echo "✗ No key given"; exit 1; }
  ( umask 077; printf 'SOLOIST_API_KEY=%q\n' "$KEY" > "$ENVF" )
fi

echo "▸ Spotify Connect: making Room findable on the network"
sudo systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd -q --permanent --add-service=mdns
  sudo firewall-cmd -q --reload
fi

cat > ~/.config/systemd/user/room-spotify.service <<UNIT
[Unit]
Description=Room Spotify Connect speaker (Spotify Soloist)
After=pipewire-pulse.service network-online.target
Wants=pipewire-pulse.service

[Service]
ExecStart=/usr/bin/env bash $HERE/scripts/soloist-run.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room-spotify.service >/dev/null
systemctl --user restart room-spotify.service
echo "▸ Spotify Connect: starting (downloads Soloist the first time)"
sleep 8
if systemctl --user is-active -q room-spotify.service; then
  echo "✓ Spotify Connect is on. On your phone (same Wi-Fi): Spotify → speaker icon → \"Room\", and play something."
  journalctl --user -u room-spotify -n 6 --no-pager -o cat
else
  echo "✗ Spotify Connect didn't start — here's why:"; journalctl --user -u room-spotify -n 25 --no-pager
fi
