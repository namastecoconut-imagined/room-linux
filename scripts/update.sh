#!/usr/bin/env bash
# What room-update runs: pull the latest Room, refresh its packages (and voice's, if voice is set up), restart.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
git pull --ff-only
"$HERE/.venv/bin/pip" install -q -r requirements.txt
if [ -x "$HERE/voice/.venv/bin/python" ] && { command -v uv || [ -x "$HOME/.local/bin/uv" ]; } >/dev/null; then
  export PATH="$HOME/.local/bin:$PATH"
  uv pip install -q --python "$HERE/voice/.venv/bin/python" -r voice/requirements.txt
fi
# AirPlay: bigger sound buffers (crackles came from the Surface not keeping up with small ones — the speaker tuning,
# the screen and listening all share it). ~85 ms more delay, unnoticeable for music.
D=~/.config/systemd/user/room-airplay.service.d
if [ -f ~/.config/systemd/user/room-airplay.service ] && [ ! -f "$D/buffers.conf" ]; then
  mkdir -p "$D"
  printf '[Service]\nEnvironment=PIPEWIRE_LATENCY=4096/48000\nEnvironment=PULSE_LATENCY_MSEC=85\n' > "$D/buffers.conf"
  systemctl --user daemon-reload
  systemctl --user restart room-airplay.service
fi
systemctl --user restart room.service
echo "Room updated to $(git log -1 --format='%h · %s')"
