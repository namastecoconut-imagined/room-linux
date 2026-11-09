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

# a software H.264 decoder for Screen Mirroring: Fedora's FFmpeg plugin has none (no avdec_h264), so Cisco's
# OpenH264 (Fedora's openh264 repo); if neither is there, the hardware one (it works, with some blocky frames)
sudo dnf install -y -q --skip-unavailable --enablerepo=fedora-cisco-openh264 gstreamer1-plugin-openh264 >/dev/null 2>&1 || true
if gst-inspect-1.0 openh264dec >/dev/null 2>&1; then DEC="-vd openh264dec"
elif gst-inspect-1.0 avdec_h264 >/dev/null 2>&1; then DEC="-avdec"
else DEC=""; fi
echo "▸ AirPlay video: Screen Mirroring decoder: ${DEC:-hardware (VA-API)}"

# -n/-nh: the name, as is · -p: fixed ports (for the firewall) · waylandsink: drawn straight on the panel
# -hls: YouTube's AirPlay button (it sends the video, not a mirror of the phone) · -nohold: a new phone can take over
cat > ~/.config/systemd/user/room-airplay-video.service <<UNIT
[Unit]
Description=Room AirPlay video and screen mirroring (UxPlay)
After=network-online.target pipewire-pulse.service avahi-daemon.service
Wants=pipewire-pulse.service

[Service]
# no -fs: UxPlay's full-screen switch is X11 code and crashes on Wayland — the panel's compositor (cage) shows the
# window full screen anyway. No DISPLAY either, so none of UxPlay's X11 window handling runs.
UnsetEnvironment=DISPLAY
# -m: its own device id. By default UxPlay uses the Surface's network address as its AirPlay id — the same one AirPlay
# music ("Room", shairport-sync) uses — and the iPhone merges the two, so "Room" vanished behind "Room Screen".
# -vs "waylandsink fullscreen=true": fills the panel (the sink's own full-screen, not UxPlay's X11 one)
# -hls: YouTube's AirPlay button (playbin3; -hls 2's older playbin can't use YouTube's stream at all: no sound either)
# GST_DEBUG=2: GStreamer's warnings in the log, so a failure says why
# $DEC: Screen Mirroring decoded in software — the Intel VA-API decoder garbled it into blocks (its log: "driver
# bug: fd size … bigger than object descriptor size"); a 1080p mirror is light work for the Surface's CPU
Environment=GST_DEBUG=2
ExecStart=/usr/bin/uxplay -n "Room Screen" -nh -m 02:52:4f:4f:4d:56 -p $PORT -vs "waylandsink fullscreen=true" $DEC -hls -nohold
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
