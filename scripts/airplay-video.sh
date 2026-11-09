#!/usr/bin/env bash
# AirPlay video for Room: the Surface shows up as "Room Screen" for AirPlay video and Screen Mirroring on your iPhone,
# iPad and Mac — the AirPlay button in YouTube and other video apps, or Screen Mirroring in Control Center. It plays
# full screen; stop AirPlay on the phone and the window closes, the panel is back. Uses UxPlay
# (github.com/FDH2/UxPlay, in Fedora). AirPlay music ("Room", shairport-sync) is untouched. Safe to run again.
set -euo pipefail
trap 'echo "✗ AirPlay video setup stopped at line $LINENO — paste the lines above to Claude"' ERR
PORT=7200          # UxPlay uses 7200–7202 (TCP and UDP); AirPlay music has 7000 and 5000
mkdir -p ~/.config/systemd/user

echo "▸ AirPlay video: UxPlay and the video decoders (asks for your password)"
sudo dnf install -y -q --skip-unavailable uxplay gstreamer1-plugins-base gstreamer1-plugins-good \
     gstreamer1-plugins-bad-free gstreamer1-plugin-openh264 gstreamer1-plugin-libav libva-intel-media-driver \
     avahi >/dev/null

echo "▸ AirPlay video: making Room Screen findable on the network"
sudo systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd -q --permanent --add-service=mdns
  sudo firewall-cmd -q --permanent --add-port=$PORT-$((PORT + 2))/tcp --add-port=$PORT-$((PORT + 2))/udp
  sudo firewall-cmd -q --reload
fi

# -n/-nh: the name, as is · -p: fixed ports (for the firewall) · -fs + waylandsink: full screen on the panel
# -hls: YouTube's AirPlay button (it sends the video, not a mirror of the phone) · -nohold: a new phone can take over
cat > ~/.config/systemd/user/room-airplay-video.service <<UNIT
[Unit]
Description=Room AirPlay video and screen mirroring (UxPlay)
After=network-online.target pipewire-pulse.service avahi-daemon.service
Wants=pipewire-pulse.service

[Service]
ExecStart=/usr/bin/uxplay -n "Room Screen" -nh -p $PORT -fs -vs waylandsink -hls -nohold
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room-airplay-video.service >/dev/null
systemctl --user restart room-airplay-video.service
sleep 3
if systemctl --user is-active -q room-airplay-video.service; then
  echo "✓ AirPlay video is on. On your iPhone (same Wi-Fi): Screen Mirroring → \"Room Screen\", or the AirPlay"
  echo "  button in YouTube → \"Room Screen\"."
else
  echo "✗ AirPlay video didn't start — here's why:"; journalctl --user -u room-airplay-video -n 25 --no-pager
fi
