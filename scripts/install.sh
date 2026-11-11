#!/usr/bin/env bash
# Room — the whole setup on a fresh Fedora (Surface Pro 6), in one go. Safe to run again.
#   git clone https://github.com/namastecoconut-imagined/room-linux ~/room && bash ~/room/scripts/install.sh
# Sets up: the panel (room.service), AirPlay, Spotify Connect, the voice assistant, never-suspend, the sound fixes,
# and the room-update / room-kiosk commands. Kiosk mode (just the panel, no desktop) is one more command at the end.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
echo "▸ Room → $HERE"

echo "▸ System packages (asks for your password once)"
sudo dnf install -y -q python3 python3-pip git xcb-util-cursor mesa-dri-drivers mesa-libEGL \
     pipewire pipewire-pulseaudio libxkbcommon >/dev/null

echo "▸ Python environment"
python3 -m venv "$HERE/.venv"
"$HERE/.venv/bin/pip" install -q --upgrade pip
# the exact versions Room is tested with (requirements.lock)
if [ -f "$HERE/requirements.lock" ]; then "$HERE/.venv/bin/pip" install -q -r "$HERE/requirements.lock"
else "$HERE/.venv/bin/pip" install -q -r "$HERE/requirements.txt"; fi

echo "▸ Config"
mkdir -p ~/.config/room
if [ ! -f ~/.config/room/config.json ]; then
  echo "  ! No config yet. Copy config.json from the Mac (Downloads/RoomPanel/config.json) to ~/.config/room/config.json"
  echo "    Then set \"here\" to \"Living room\" and add the living-room lights under \"rooms\"."
fi

echo "▸ Starts with your desktop session (no automatic restart while we are still fixing things)"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/room.service <<UNIT
[Unit]
Description=Room panel
PartOf=graphical-session.target
After=graphical-session.target

[Service]
WorkingDirectory=$HERE
ExecStart=$HERE/.venv/bin/python -m room
# no automatic restart while we're still fixing things — a crash stays visible in the log
Restart=no
Environment=QT_QPA_PLATFORM=wayland;xcb

[Install]
WantedBy=graphical-session.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room.service >/dev/null

echo "▸ Panel behaviour: no screen blanking, no lock screen, no on-screen keyboard popping up"
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
  gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false 2>/dev/null || true
  gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null || true
fi

bash "$HERE/scripts/airplay.sh"
bash "$HERE/scripts/spotify-connect.sh"
bash "$HERE/scripts/assistant.sh"
bash "$HERE/scripts/no-suspend.sh"
bash "$HERE/scripts/cool.sh"

echo "▸ Sound"
# a Bluetooth speaker stays a speaker: never switched to its low-quality "headset" mode when something listens
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
printf 'wireplumber.settings = { bluetooth.autoswitch-to-headset-profile = false }\n' \
  > ~/.config/wireplumber/wireplumber.conf.d/90-room-no-headset.conf
# every level where it belongs
bash "$HERE/scripts/sound-fix.sh" >/dev/null || true

echo "▸ Room in the app grid"
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
cp "$HERE/assets/room.svg" ~/.local/share/icons/hicolor/scalable/apps/room-panel.svg
cat > ~/.local/share/applications/room-panel.desktop <<DESK
[Desktop Entry]
Type=Application
Name=Room
Comment=The room panel
Exec=systemctl --user restart room.service
Icon=room-panel
Categories=Utility;
DESK
update-desktop-database -q ~/.local/share/applications 2>/dev/null || true

echo "▸ room-update command"
mkdir -p ~/.local/bin
cat > ~/.local/bin/room-update <<UPD
#!/usr/bin/env bash
exec bash "$HERE/scripts/update.sh" "\$@"
UPD
chmod +x ~/.local/bin/room-update
ln -sf "$HERE/scripts/kiosk.sh" ~/.local/bin/room-kiosk
# the rest of what room-update keeps in place (sound buffers for AirPlay and Spotify, …), without pulling
ROOM_NO_PULL=1 bash "$HERE/scripts/update.sh" >/dev/null || true

systemctl --user restart room.service
echo "✓ Room is running. Update any time with:  room-update"
echo "  Just the panel, no desktop (from the next start):  room-kiosk on   ·   back to GNOME:  room-kiosk off"
