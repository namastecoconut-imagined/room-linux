#!/usr/bin/env bash
# What room-update runs: pull the latest Room, refresh its packages, restart.
set -e
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$HERE"
[ -n "${ROOM_NO_PULL:-}" ] || git pull --ff-only
# the exact versions Room is tested with (requirements.lock); nothing newer sneaks in on an update
if [ -f requirements.lock ]; then "$HERE/.venv/bin/pip" install -q -r requirements.lock; else "$HERE/.venv/bin/pip" install -q -r requirements.txt; fi
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
# AirPlay: the phone's volume is the speaker's volume (Room sets the speaker to it), not a second, quieter
# volume on top inside AirPlay
C=~/.config/room/shairport-sync.conf
if [ -f "$C" ] && ! grep -q ignore_volume_control "$C"; then
  sed -i 's/^\(\s*\)volume_range_db = 50;/&\n\1ignore_volume_control = "yes";/' "$C"
  grep -q ignore_volume_control "$C" && systemctl --user try-restart room-airplay.service 2>/dev/null || true
fi
# the assistant's models ship with Room now (assistant/models): the old downloaded copies go
rm -rf "$HOME/.local/share/room/assistant/models"
# a Bluetooth speaker stays a speaker (never its low-quality "headset" mode) — kept in place
W=~/.config/wireplumber/wireplumber.conf.d/90-room-no-headset.conf
if [ ! -f "$W" ]; then
  mkdir -p "$(dirname "$W")"
  printf 'wireplumber.settings = { bluetooth.autoswitch-to-headset-profile = false }\n' > "$W"
fi
# the assistant goes first when the Surface is busy (its voice is made as it plays — late, it broke up); the Surface
# stays on its balanced power profile (performance kept it warm)
D=~/.config/systemd/user/room-assistant.service.d
if [ -f ~/.config/systemd/user/room-assistant.service ] && [ ! -f "$D/perf.conf" ]; then
  mkdir -p "$D"
  printf '[Service]\nCPUWeight=1000\nIOWeight=1000\n' > "$D/perf.conf"
  systemctl --user daemon-reload
fi
command -v powerprofilesctl >/dev/null && [ "$(powerprofilesctl get 2>/dev/null)" = performance ] && powerprofilesctl set balanced 2>/dev/null || true
# the assistant (its own Python and service), if it's set up
if [ -x "$HERE/assistant/.venv/bin/python" ]; then
  export PATH="$HOME/.local/bin:$PATH"
  # exactly the locked set: anything else (old test tools) is removed
  if [ -f assistant/requirements.lock ]; then
    command -v uv >/dev/null && uv pip sync -q --python "$HERE/assistant/.venv/bin/python" assistant/requirements.lock || true
  else
    command -v uv >/dev/null && uv pip install -q --python "$HERE/assistant/.venv/bin/python" -r assistant/requirements.txt || true
  fi
  systemctl --user try-restart room-assistant.service 2>/dev/null || true
fi
# the Surface's own Spotify (Soloist): the same bigger sound buffers as AirPlay — it crackled on the Surface's
# speakers once the assistant was also running
D=~/.config/systemd/user/room-spotify.service.d
if [ -f ~/.config/systemd/user/room-spotify.service ] && [ ! -f "$D/buffers.conf" ]; then
  mkdir -p "$D"
  printf '[Service]\nEnvironment=PIPEWIRE_LATENCY=4096/48000\nEnvironment=PULSE_LATENCY_MSEC=85\n' > "$D/buffers.conf"
  systemctl --user daemon-reload
  systemctl --user restart room-spotify.service
fi
# the helper command
mkdir -p ~/.local/bin && ln -sf "$HERE/scripts/kiosk.sh" ~/.local/bin/room-kiosk
systemctl --user restart room.service
echo "Room updated to $(git log -1 --format='%h · %s')"
