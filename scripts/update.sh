#!/usr/bin/env bash
# What room-update runs: pull the latest Room, refresh its packages, restart.
set -e
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$HERE"
git pull --ff-only
"$HERE/.venv/bin/pip" install -q -r requirements.txt
# the old voice assistant is gone: its Python, models and state go too
if [ -d "$HERE/voice" ] && [ -z "$(git ls-files voice)" ]; then rm -rf "$HERE/voice"; fi
rm -rf "$HOME/.local/share/room/voice" "$HOME/.local/state/room/wake-paused"
# AirPlay: bigger sound buffers (crackles came from the Surface not keeping up with small ones — the speaker tuning,
# the screen and listening all share it). ~85 ms more delay, unnoticeable for music.
D=~/.config/systemd/user/room-airplay.service.d
if [ -f ~/.config/systemd/user/room-airplay.service ] && [ ! -f "$D/buffers.conf" ]; then
  mkdir -p "$D"
  printf '[Service]\nEnvironment=PIPEWIRE_LATENCY=4096/48000\nEnvironment=PULSE_LATENCY_MSEC=85\n' > "$D/buffers.conf"
  systemctl --user daemon-reload
  systemctl --user restart room-airplay.service
fi
# the helper command
mkdir -p ~/.local/bin && ln -sf "$HERE/scripts/kiosk.sh" ~/.local/bin/room-kiosk
systemctl --user restart room.service
echo "Room updated to $(git log -1 --format='%h · %s')"
