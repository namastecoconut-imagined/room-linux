# Room — Surface Pro 6 (Fedora)

The Room panel as a native Qt Quick app. The screens are drawn on the GPU, and the logic is in Python. It's the living-room version of the iPhone panel. It reads the same `config.json`, talks to the same WiZ bulbs over the local network, and uses the same Spotify login and calendar link.

## Set up (once)

1. **Touch.** Install the linux-surface kernel and `iptsd`, which fix jumpy touch and ghost touches. Follow the Fedora steps at https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup, then reboot.
2. **Battery.** In the Surface UEFI (hold volume-up while powering on), turn on **Battery Limit**. This caps the charge at 50% so the battery doesn't swell while the Surface is always plugged in.
3. **Room:**
   ```bash
   git clone <this repo> ~/room && cd ~/room && bash scripts/install.sh
   ```
4. **Config.** Copy `config.json` from the Mac (`Downloads/RoomPanel/config.json`) to `~/.config/room/config.json`. Then set `"here": "Living room"` and add the living-room lights under `"rooms"`.

Room starts with the desktop session. It doesn't restart itself while we're still fixing things.

- Stop it: `systemctl --user stop room`
- Run it in a terminal so errors show: `cd ~/room && .venv/bin/python -m room` (Esc leaves full screen, Ctrl-C quits)
- AirPlay only: `bash scripts/airplay.sh`

## Update

```bash
room-update
```

## Work on it

```bash
ROOM_DEMO=1 ROOM_WINDOWED=1 .venv/bin/python -m room                  # sample data, in a window
ROOM_DEMO=1 ROOM_SCREEN=standby ROOM_SHOT=s.png .venv/bin/python -m room  # save a screenshot and quit
journalctl --user -u room -f                                          # live log
```

## What's where

| | |
|---|---|
| `qml/Home.qml` | home screen: time, weather, today · lights · now playing, mic |
| `qml/Standby.qml` + `shaders/standby.frag` | breathing dot field and morning glow (GPU shader), dot clock |
| `qml/MusicStandby.qml` | music standby: cover, blurred-cover background, drifting artist name |
| `qml/DotText.qml` | the 5×7 dot numerals; dots glide to their new places each minute |
| `room/wiz.py` | WiZ bulbs (UDP 38899) |
| `room/spotify.py` | Spotify Web API (shares the iPhone panel's login) |
| `room/weather.py` · `room/calendar.py` | Open-Meteo, Google Calendar iCal |

Shaders are precompiled (`*.qsb`). After editing a `.frag`, recompile it (same for `fade.frag`):
`pyside6-qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/standby.frag.qsb shaders/standby.frag`

## Coming next

The full music player (cover flow, volume, playlists), then voice ("Alexa" wake word, Whisper speech, Claude replies), then AirPlay (shairport-sync).
