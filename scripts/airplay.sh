#!/usr/bin/env bash
# AirPlay 2 for Room: the Surface appears as a speaker called "Room" on your iPhone and Mac, works in AirPlay 2
# multi-room groups, and Room can play/pause/skip from the panel.
#
# Fedora's shairport-sync package is AirPlay 1 only, so this builds shairport-sync with AirPlay 2 from its
# official source (github.com/mikebrady/shairport-sync), plus nqptp — the timing service AirPlay 2 needs.
# Takes a few minutes the first time. Safe to run again.
set -euo pipefail
SRC="$HOME/.cache/room-airplay"
mkdir -p "$SRC"

if /usr/local/bin/shairport-sync -V 2>/dev/null | grep -qi airplay2; then
  echo "▸ AirPlay 2 is already built"
else
  echo "▸ AirPlay 2: build tools and libraries (asks for your password)"
  sudo dnf install -y -q gcc gcc-c++ make autoconf automake libtool git pkgconf-pkg-config xxd \
       popt-devel libconfig-devel openssl-devel avahi-devel pulseaudio-libs-devel soxr-devel \
       ffmpeg-free-devel libplist-devel libsodium-devel libgcrypt-devel libuuid-devel glib2-devel avahi >/dev/null

  echo "▸ AirPlay 2: nqptp (timing)"
  rm -rf "$SRC/nqptp" && git clone -q --depth 1 https://github.com/mikebrady/nqptp.git "$SRC/nqptp"
  ( cd "$SRC/nqptp" && autoreconf -fi >/dev/null 2>&1 && ./configure --with-systemd-startup >/dev/null && make -s -j"$(nproc)" >/dev/null && sudo make -s install >/dev/null )
  sudo systemctl daemon-reload
  sudo systemctl enable --now nqptp >/dev/null

  echo "▸ AirPlay 2: shairport-sync (a few minutes)"
  rm -rf "$SRC/shairport-sync" && git clone -q --depth 1 https://github.com/mikebrady/shairport-sync.git "$SRC/shairport-sync"
  ( cd "$SRC/shairport-sync" && autoreconf -fi >/dev/null 2>&1 && \
    ./configure --sysconfdir=/etc --with-pa --with-soxr --with-avahi --with-ssl=openssl \
                --with-airplay-2 --with-metadata --with-mpris-interface --with-dbus-interface >/dev/null && \
    make -s -j"$(nproc)" >/dev/null && sudo make -s install >/dev/null )
  # the AirPlay 1 package from before would clash — remove it
  sudo systemctl disable --now shairport-sync >/dev/null 2>&1 || true
  sudo dnf remove -y -q shairport-sync >/dev/null 2>&1 || true
fi
/usr/local/bin/shairport-sync -V

echo "▸ AirPlay: making Room findable on the network"
sudo systemctl enable --now avahi-daemon >/dev/null
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd -q --permanent --add-service=mdns
  sudo firewall-cmd -q --permanent --add-port=7000/tcp --add-port=5000/tcp --add-port=319-320/udp --add-port=6000-6011/udp
  sudo firewall-cmd -q --reload
fi

mkdir -p ~/.config/room ~/.config/systemd/user
cat > ~/.config/room/shairport-sync.conf <<'CONF'
general = {
  name = "Room";
  output_backend = "pa";
  volume_range_db = 50;
  mpris_service_bus = "Session";
  dbus_service_bus = "Session";
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
Description=Room AirPlay 2 receiver
After=pipewire-pulse.service network-online.target
Wants=pipewire-pulse.service

[Service]
ExecStart=/usr/local/bin/shairport-sync -c %h/.config/room/shairport-sync.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room-airplay.service >/dev/null
systemctl --user restart room-airplay.service
sleep 2
if systemctl --user is-active -q room-airplay.service; then
  echo "✓ AirPlay 2 is on. Look for \"Room\" in the AirPlay list on your iPhone or Mac."
else
  echo "✗ AirPlay didn't start — here's why:"; journalctl --user -u room-airplay -n 25 --no-pager
fi
