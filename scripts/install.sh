#!/usr/bin/env bash
# Room — one-time setup on Fedora (Surface Pro 6). Safe to run again.
#   bash scripts/install.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
echo "▸ Room → $HERE"

echo "▸ System packages (asks for your password once)"
sudo dnf install -y -q python3 python3-pip git xcb-util-cursor mesa-dri-drivers mesa-libEGL \
     pipewire pipewire-pulseaudio libxkbcommon >/dev/null

echo "▸ Python environment"
python3 -m venv "$HERE/.venv"
"$HERE/.venv/bin/pip" install -q --upgrade pip
"$HERE/.venv/bin/pip" install -q -r "$HERE/requirements.txt"

echo "▸ Config"
mkdir -p ~/.config/room
if [ ! -f ~/.config/room/config.json ]; then
  echo "  ! No config yet. Copy config.json from the Mac (Downloads/RoomPanel/config.json) to ~/.config/room/config.json"
  echo "    Then set \"here\" to \"Living room\" and add the living-room lights under \"rooms\"."
fi

echo "▸ Starts with your desktop session, and comes back if it ever quits"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/room.service <<UNIT
[Unit]
Description=Room panel
PartOf=graphical-session.target
After=graphical-session.target

[Service]
WorkingDirectory=$HERE
ExecStart=$HERE/.venv/bin/python -m room
Restart=always
RestartSec=2
Environment=QT_QPA_PLATFORM=wayland;xcb

[Install]
WantedBy=graphical-session.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room.service >/dev/null

echo "▸ Panel behaviour: no screen blanking, no lock screen, no on-screen keyboard popping up"
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.session idle-delay 0 || true
  gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
  gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false || true
  gsettings set org.gnome.desktop.notifications show-banners false || true
fi

echo "▸ room-update command"
mkdir -p ~/.local/bin
cat > ~/.local/bin/room-update <<UPD
#!/usr/bin/env bash
set -e
cd "$HERE"
git pull --ff-only
"$HERE/.venv/bin/pip" install -q -r requirements.txt
systemctl --user restart room.service
echo "Room updated to \$(git log -1 --format='%h · %s')"
UPD
chmod +x ~/.local/bin/room-update

systemctl --user restart room.service
echo "✓ Room is running. Update any time with:  room-update"
