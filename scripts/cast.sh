#!/usr/bin/env bash
# YouTube cast for Room: the Surface shows up as "Room" in the YouTube app's Cast menu (same Wi-Fi), like a TV.
# Casting plays the video full screen (mpv, with yt-dlp from Room's own packages); stop casting and the panel is back.
# Runs as a small background service (cast/receiver.mjs). Safe to run again.
set -euo pipefail
trap 'echo "✗ YouTube cast setup stopped at line $LINENO — paste the lines above to Claude"' ERR
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
mkdir -p ~/.config/systemd/user

echo "▸ YouTube cast: the video player and Node (asks for your password)"
sudo dnf install -y -q mpv nodejs npm >/dev/null

echo "▸ YouTube cast: the receiver (a minute the first time)"
( cd "$HERE/cast" && npm install --omit=dev --no-audit --no-fund --loglevel=error )

echo "▸ YouTube cast: making Room findable on the network"
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd -q --permanent --add-port=1900/udp --add-port=8099/tcp     # DIAL: discovery, then the app
  sudo firewall-cmd -q --reload
fi

cat > ~/.config/systemd/user/room-cast.service <<UNIT
[Unit]
Description=Room YouTube cast receiver
After=network-online.target pipewire-pulse.service

[Service]
WorkingDirectory=$HERE/cast
# yt-dlp (and deno, which it needs for YouTube) live in Room's own packages
Environment=PATH=$HERE/.venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/node $HERE/cast/receiver.mjs
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room-cast.service >/dev/null
systemctl --user restart room-cast.service
sleep 4
if systemctl --user is-active -q room-cast.service; then
  echo "✓ YouTube cast is on. In the YouTube app (same Wi-Fi): Cast → \"Room\"."
  journalctl --user -u room-cast -n 5 --no-pager -o cat
else
  echo "✗ YouTube cast didn't start — here's why:"; journalctl --user -u room-cast -n 25 --no-pager
fi
