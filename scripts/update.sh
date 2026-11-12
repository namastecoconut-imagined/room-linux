#!/usr/bin/env bash
# What room-update runs: pull the latest Room, refresh its packages, restart.
set -e
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$HERE"
if [ -z "${ROOM_NO_PULL:-}" ]; then
  before=$(git rev-parse HEAD)
  git pull --ff-only
  # the pull may have changed this very script — but bash is still running the old copy, so every change to these
  # steps only took effect on the NEXT room-update. Start again with the new copy.
  [ "$(git rev-parse HEAD)" = "$before" ] || ROOM_NO_PULL=1 exec bash "$HERE/scripts/update.sh" "$@"
fi
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
# …and Bluetooth only ever does music (A2DP): no headset/hands-free roles at all, so a speaker can't come back as a
# low-quality mono "headset" (it did once, after a reconnect). Takes effect the next time WirePlumber starts.
W=~/.config/wireplumber/wireplumber.conf.d/91-room-bluetooth-music-only.conf
if [ ! -f "$W" ]; then
  mkdir -p "$(dirname "$W")"
  printf '# Room: Bluetooth is for music only (A2DP) — never a headset (HSP/HFP), never mono\nmonitor.bluez.properties = {\n  bluez5.roles = [ a2dp_sink a2dp_source ]\n}\n' > "$W"
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
# Room's cool power profile (scripts/cool.sh, needs the password once — so room-update only reminds)
command -v tuned-adm >/dev/null && ! tuned-adm active 2>/dev/null | grep -q ': room$' && \
  echo "  (the Surface isn't on Room's cool power profile — run: bash $HERE/scripts/cool.sh)" || true
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
# The sound system doesn't look for AirPlay speakers on the network (PipeWire's RAOP discovery): Room is an AirPlay
# receiver, never a sender. It found the Macs — and Room's own receiver, as a speaker called "Room": sound sent there
# would loop back into itself. (Takes effect the next time PipeWire starts.)
N=~/.config/pipewire/pipewire.conf.d/90-room-no-airplay-speakers.conf
if [ ! -f "$N" ]; then
  mkdir -p "$(dirname "$N")"
  printf '# Room: no AirPlay speakers (RAOP discovery) — Room only receives AirPlay\ncontext.properties = { module.raop = false }\n' > "$N"
fi
# AirPlay and Spotify go down and come back up with the sound system. When PipeWire restarted (once, after a burst of
# volume changes) they kept running but had lost their sound connection: silence until restarted by hand. Bound to it,
# a PipeWire restart is a short blip for them too.
# The assistant too: its chime and voice go out through one stream it keeps open, and after a PipeWire restart that
# stream was dead — it still heard "Alexa" but played nothing.
for s in room-airplay room-spotify room-assistant; do
  if [ -f ~/.config/systemd/user/$s.service ] && [ ! -f ~/.config/systemd/user/$s.service.d/pipewire.conf ]; then
    mkdir -p ~/.config/systemd/user/$s.service.d
    printf '[Unit]\nBindsTo=pipewire.service\nAfter=pipewire.service\n' > ~/.config/systemd/user/$s.service.d/pipewire.conf
    systemctl --user daemon-reload
    systemctl --user add-wants pipewire.service $s.service >/dev/null 2>&1 || true
  fi
done
# Room's tracker: how hard the Surface works — CPU per program, power, temperatures — one line a minute to
# ~/.local/state/room/watch.log (scripts/watch.py; 14 days kept). A service, so it carries on after every restart.
T=~/.config/systemd/user/room-watch.service
want="[Unit]
Description=Room's tracker: CPU, power, temperatures, one line a minute (~/.local/state/room/watch.log)

[Service]
ExecStart=/usr/bin/python3 $HERE/scripts/watch.py
Nice=10
Restart=on-failure
RestartSec=60

[Install]
WantedBy=default.target"
if [ "$(cat "$T" 2>/dev/null)" != "$want" ]; then
  mkdir -p "$(dirname "$T")" && printf '%s\n' "$want" > "$T"
  systemctl --user daemon-reload
  systemctl --user enable room-watch.service >/dev/null 2>&1 || true
fi
systemctl --user restart room-watch.service || true
# the helper command
mkdir -p ~/.local/bin && ln -sf "$HERE/scripts/kiosk.sh" ~/.local/bin/room-kiosk && ln -sf "$HERE/scripts/calendar.sh" ~/.local/bin/room-calendar
systemctl --user restart room.service
echo "Room updated to $(git log -1 --format='%h · %s')"
