#!/usr/bin/env bash
# AirPlay for Room: the Surface appears as a speaker called "Room" on your iPhone and Mac.
# shairport-sync receives the audio and plays it through PipeWire (so it comes out of whatever speaker the
# Surface is using, including Bluetooth), and writes what's playing to a pipe Room reads. Safe to run again.
set -euo pipefail

echo "▸ AirPlay: installing shairport-sync"
sudo dnf install -y -q shairport-sync avahi >/dev/null
# AirPlay 2 builds also need nqptp for timing; install it if Fedora has it (AirPlay 1 works without)
if shairport-sync -V 2>/dev/null | grep -qi airplay2; then
  sudo dnf install -y -q nqptp >/dev/null 2>&1 && sudo systemctl enable --now nqptp >/dev/null 2>&1 || true
fi

echo "▸ AirPlay: making Room findable on the network"
sudo systemctl enable --now avahi-daemon >/dev/null
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd -q --permanent --add-service=mdns
  sudo firewall-cmd -q --permanent --add-port=5000/tcp --add-port=7000/tcp --add-port=6000-6011/udp --add-port=319-320/udp
  sudo firewall-cmd -q --reload
fi

# run it as you (not as a system service) so it plays through your PipeWire session
sudo systemctl disable --now shairport-sync >/dev/null 2>&1 || true

mkdir -p ~/.config/room ~/.config/systemd/user
cat > ~/.config/room/shairport-sync.conf <<'CONF'
general = {
  name = "Room";
  output_backend = "pa";
  volume_range_db = 50;
};
pa = { application_name = "Room · AirPlay"; };
metadata = {
  enabled = "yes";
  include_cover_art = "yes";
  pipe_name = "/tmp/shairport-sync-metadata";
  pipe_timeout = 5000;
};
mpris = { enabled = "yes"; };
CONF

cat > ~/.config/systemd/user/room-airplay.service <<'UNIT'
[Unit]
Description=Room AirPlay receiver
After=pipewire-pulse.service network-online.target
Wants=pipewire-pulse.service

[Service]
ExecStart=/usr/bin/shairport-sync -c %h/.config/room/shairport-sync.conf
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now room-airplay.service >/dev/null
systemctl --user restart room-airplay.service
sleep 2
if systemctl --user is-active -q room-airplay.service; then
  echo "✓ AirPlay is on. Look for \"Room\" in the AirPlay list on your iPhone or Mac."
else
  echo "✗ AirPlay didn't start — here's why:"; journalctl --user -u room-airplay -n 20 --no-pager
fi
