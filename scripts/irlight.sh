#!/usr/bin/env bash
# irlight — Room's IR-lights helper: the one thing Room may do as root, switching the IR lights beside the camera on
# and off (for hand gestures). Asks for your password once.
#   bash ~/room/scripts/irlight.sh            set it up (again after an update changes it: room-update says so)
#   bash ~/room/scripts/irlight.sh remove     take it all off
# What it puts on the Surface, and nothing else:
#   /usr/local/libexec/room-irlight                  the helper (scripts/irlight-helper.py), root-owned — the copy in
#                                                    your home folder is never the one that runs
#   /etc/systemd/system/room-irlight.socket          /run/room-irlight.sock, which only root and your group can use
#   /etc/systemd/system/room-irlight@.service        runs the helper once per request, locked down (below)
#   /etc/modules-load.d/room-irlight.conf            loads i2c-dev at start (how the helper reaches the camera chip)
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
G=$(id -gn)
BIN=/usr/local/libexec/room-irlight
UNITS=/etc/systemd/system

if [ "${1:-}" = remove ]; then
  sudo systemctl disable --now room-irlight.socket 2>/dev/null || true
  sudo rm -f "$UNITS/room-irlight.socket" "$UNITS/room-irlight@.service" "$BIN" /etc/modules-load.d/room-irlight.conf
  sudo systemctl daemon-reload
  echo "✓ The IR-lights helper is off the Surface (gestures stay off until it's set up again)."
  exit 0
fi

echo "▸ Setting up the IR-lights helper (your password, once)"
sudo install -D -m 0755 -o root -g root "$HERE/scripts/irlight-helper.py" "$BIN"
printf 'i2c-dev\n' | sudo tee /etc/modules-load.d/room-irlight.conf >/dev/null
sudo modprobe i2c-dev
sudo tee "$UNITS/room-irlight.socket" >/dev/null <<UNIT
[Unit]
Description=Room: requests to switch the Surface's IR lights

[Socket]
ListenStream=/run/room-irlight.sock
SocketUser=root
SocketGroup=$G
SocketMode=0660
Accept=yes
MaxConnections=4

[Install]
WantedBy=sockets.target
UNIT
sudo tee "$UNITS/room-irlight@.service" >/dev/null <<'UNIT'
[Unit]
Description=Room: switch the Surface's IR lights (one request)

[Service]
ExecStart=/usr/bin/python3 -I /usr/local/libexec/room-irlight
StandardInput=socket
StandardOutput=socket
StandardError=journal
RuntimeMaxSec=10
# all it needs: to read /sys and to use the I2C devices
DevicePolicy=closed
DeviceAllow=char-i2c rw
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateNetwork=yes
NoNewPrivileges=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX
CapabilityBoundingSet=CAP_DAC_OVERRIDE
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now room-irlight.socket >/dev/null 2>&1
# a check through the socket, as Room will ask it (the camera isn't streaming now, so it should say so)
ans=$(python3 -c '
import socket
s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect("/run/room-irlight.sock")
s.sendall(b"status\n"); print(s.recv(200).decode().strip())' 2>&1 || true)
echo "  the helper says: $ans"
case "$ans" in
  ok*|"error: the camera isn't answering"*|"error: the camera isn't streaming"*)
    echo "✓ Set up. Room switches the IR lights through it only while it's watching for gestures." ;;
  *) echo "✗ Something's off — the helper's log: journalctl -u 'room-irlight@*' -n 20"; exit 1 ;;
esac
