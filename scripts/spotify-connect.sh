#!/usr/bin/env bash
# Spotify Connect for Room: the Surface becomes a Spotify speaker called "Room", so "Alexa, play …" plays on the
# Surface itself — no phone, no AirPlay. Uses go-librespot (github.com/devgianlu/go-librespot), an open-source
# Spotify Connect player, as a small background service. AirPlay is untouched. Needs Spotify Premium. Safe to run again.
#
# First time only: open Spotify on your phone (same Wi-Fi), tap the speaker icon, pick "Room" — that logs it in, and
# it remembers.
set -euo pipefail
trap 'echo "✗ Spotify Connect setup stopped at line $LINENO — paste the lines above to Claude"' ERR
BIN="$HOME/.local/bin/go-librespot"
CONF="$HOME/.config/go-librespot"
mkdir -p "$HOME/.local/bin" "$CONF" ~/.config/systemd/user

echo "▸ Spotify Connect: libraries it plays with (asks for your password)"
sudo dnf install -y -q libogg libvorbis flac-libs mpg123-libs alsa-lib pulseaudio-libs >/dev/null

echo "▸ Spotify Connect: downloading go-librespot"
python3 - "$BIN" <<'PY'
import json, sys, tarfile, io, urllib.request, os, platform
arch = {"x86_64": ("x86_64", "amd64"), "aarch64": ("arm64", "aarch64")}[platform.machine()]
rel = json.load(urllib.request.urlopen("https://api.github.com/repos/devgianlu/go-librespot/releases/latest", timeout=20))
asset = next(a for a in rel["assets"] if "linux" in a["name"].lower() and any(x in a["name"].lower() for x in arch)
             and a["name"].endswith((".tar.gz", ".tgz")))
data = urllib.request.urlopen(asset["browser_download_url"], timeout=120).read()
with tarfile.open(fileobj=io.BytesIO(data)) as t:
    m = next(m for m in t.getmembers() if m.isfile() and os.path.basename(m.name) in ("go-librespot", "daemon"))
    open(sys.argv[1], "wb").write(t.extractfile(m).read())
os.chmod(sys.argv[1], 0o755)
print("  ", rel["tag_name"], "·", asset["name"])
PY

cat > "$CONF/config.yml" <<'YML'
device_name: Room
device_type: speaker
audio_backend: pulseaudio
initial_volume: 60
volume_steps: 100
zeroconf_enabled: true
zeroconf_port: 4070
credentials:
  type: zeroconf
  zeroconf:
    persist_credentials: true
server:
  enabled: true
  address: localhost
  port: 3678
YML

echo "▸ Spotify Connect: making Room findable on the network"
sudo systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd -q --permanent --add-service=mdns
  sudo firewall-cmd -q --permanent --add-port=4070/tcp
  sudo firewall-cmd -q --reload
fi

cat > ~/.config/systemd/user/room-spotify.service <<'UNIT'
[Unit]
Description=Room Spotify Connect speaker (go-librespot)
After=pipewire-pulse.service network-online.target
Wants=pipewire-pulse.service

[Service]
ExecStart=%h/.local/bin/go-librespot -config_dir %h/.config/go-librespot
Environment=PULSE_LATENCY_MSEC=85
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room-spotify.service >/dev/null
systemctl --user restart room-spotify.service
sleep 2
if systemctl --user is-active -q room-spotify.service; then
  echo "✓ Spotify Connect is on. If you haven't yet: open Spotify on your phone (same Wi-Fi), tap the speaker icon"
  echo "  and pick \"Room\" once. That logs it in for good; after that \"Alexa, play …\" plays on the Surface."
else
  echo "✗ Spotify Connect didn't start — here's why:"; journalctl --user -u room-spotify -n 25 --no-pager
fi
