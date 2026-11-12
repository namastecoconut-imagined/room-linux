# Room — Surface Pro 6 (Fedora)

The Room panel as a native Qt Quick app. The screens are drawn on the GPU, and the logic is in Python. It's the living-room version of the iPhone panel. It reads the same `config.json`, talks to the same WiZ bulbs over the local network, and uses the same Spotify login and calendar link.

## Set up (once)

1. **Touch.** Install the linux-surface kernel and `iptsd`, which fix jumpy touch and ghost touches. Follow the Fedora steps at https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup, then reboot.
2. **Battery.** In the Surface UEFI (hold volume-up while powering on), turn on **Battery Limit**. This caps the charge at 50% so the battery doesn't swell while the Surface is always plugged in.
3. **Config.** Copy `config.json` from the Mac (`Downloads/RoomPanel/config.json`) to `~/.config/room/config.json`
   (with `"anthropicKey"` and `"sarvamKey"` for the assistant). Keys live only there, never in this repo.
   **Display font:** the clock, big numbers and Alexa's words are set in Kasero when `~/.config/room/fonts/Kasero.otf`
   is there. It's a licensed font, so it isn't in this public repo; without it Room uses Instrument Serif, which ships here.
4. **Room — everything, in one go:**
   ```bash
   git clone https://github.com/namastecoconut-imagined/room-linux ~/room && bash ~/room/scripts/install.sh
   ```
   The panel, AirPlay ("Room"), Spotify Connect ("Room", asks for the Soloist key once), the voice assistant,
   never-suspend, the sound fixes, and the `room-update` / `room-kiosk` commands.
5. **Kiosk** (just the panel, no desktop; signs in by itself): `room-kiosk on`, restart. Back to GNOME: `room-kiosk off`.
6. **Hand gestures** (optional): `bash ~/room/scripts/irlight.sh` (your password once). It sets up the IR-lights
   helper, the one thing Room does as root: switching the IR lights beside the camera on and off. While music plays
   or is paused, a swipe right to left is next, left to right previous, and a palm held up still plays or pauses
   (`room/eyes.py`; a small warm light at the top of the screen while the camera watches). `irlight.sh remove` takes
   it off; `"gestures": {"enabled": false}` in config.json turns gestures off.

What runs (all user services, the same under GNOME and in kiosk mode):

| service | what | log |
|---|---|---|
| `room` | the panel | `journalctl --user -u room -f` |
| `room-assistant` | "Alexa" (`assistant/`) | `journalctl --user -u room-assistant -f` |
| `room-airplay` | AirPlay receiver (shairport-sync) | `journalctl --user -u room-airplay -f` |
| `room-spotify` | Spotify Connect speaker (Soloist) | `journalctl --user -u room-spotify -f` |
| `room-irlight` (system) | the IR-lights helper, run once per request | `journalctl -u 'room-irlight@*'` |

Room itself doesn't restart on its own (a crash stays visible); the others do.
Versions are locked: `requirements.lock` (the panel) and `assistant/requirements.lock` (the assistant) — installs
and updates use exactly those. To change one, edit `requirements.txt`, test, and re-lock.

- Stop it: `systemctl --user stop room` · run it in a terminal: `cd ~/room && .venv/bin/python -m room`
- From the Mac: `ssh namastecoconut@room.local`

## Update

```bash
room-update
```

Pulls, installs the locked versions, keeps the fixes in place, restarts Room and the assistant.

## Work on it

```bash
ROOM_DEMO=1 ROOM_WINDOWED=1 .venv/bin/python -m room                  # sample data, in a window
ROOM_DEMO=1 ROOM_SCREEN=standby ROOM_SHOT=s.png .venv/bin/python -m room  # save a screenshot and quit
journalctl --user -u room -f                                          # live log
```

## What's where

| | |
|---|---|
| `qml/Scene.qml` | Home, the player, standby and a room as one scene: each piece glides to where the view puts it |
| `qml/Field.qml` + `shaders/field.frag` | the background: four soft lights in the cover's colours, drifting, swelling with sound (GPU shader) |
| `qml/StandbyWords.qml` | music standby's giant drifting words, blurred sideways |
| `qml/RoomView.qml` · `qml/Sheet.qml` | one room's controls · the scenes, speakers and library sheets |
| `qml/ClockView.qml` | the Clock screen: next alarm, timers, alarms, the alarm editor sheet |
| `qml/WeatherView.qml` | the Weather screen: now, the rain to expect, the next 12 hours as one line, three days |
| `qml/RemindersView.qml` | the Reminders screen: two columns (tap to tick, hold to delete); new ones are asked for (the assistant) |
| `qml/SettingsView.qml` | the Settings screen: brightness, Wi-Fi (join with a password), Bluetooth, web browser / desktop / shut down (asks first) |
| `qml/Keyboard.qml` | the on-screen keyboard (the Wi-Fi password): rises when a text box is typed in, lifts the sheet above it |
| `qml/VolumeHud.qml` | the volume buttons' capsule |
| `qml/VoiceOverlay.qml` + `shaders/horizon.frag` | the assistant over the top band: the light line, your words, the answer, buttons under the line |
| `qml/VoiceCard.qml` · `qml/Words.qml` | the card beside an answer (weather, forecast, air, timer, music, schedule, alarm, lights) · words that come in one by one |
| `room/sleep.py` | screen off in a quiet room (or the power button), back on at a sound or a touch |
| `room/output.py` | music (AirPlay, the Surface's Spotify) to the Bluetooth speaker when one's connected; speaker levels |
| `room/mic.py` | how loud the room is (screen wake; while music plays, the background's swell) |
| `room/eyes.py` | hand gestures for the music, with the IR camera (its lights through `scripts/irlight-helper.py`) |
| `room/wiz.py` | WiZ bulbs (UDP 38899) |
| `room/wifi.py` · `room/bluetooth.py` | Wi-Fi through NetworkManager (`nmcli`) · Bluetooth through `bluetoothctl` |
| `room/spotify.py` | Spotify Web API (shares the iPhone panel's login) |
| `room/weather.py` · `room/calendar.py` | Open-Meteo, Google Calendar iCal (several, merged; add one with `room-calendar add`) |

Shaders are precompiled (`*.qsb`). After editing a `.frag`, recompile it:
`pyside6-qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/field.frag.qsb shaders/field.frag`

## The voice assistant

Its own program in `assistant/` (its own service, `room-assistant`; see `assistant/README.md`). Room shows it
(`qml/VoiceOverlay.qml`) and carries out what it decides (`room/voice.py`); if it isn't running, Room is unchanged.

## Room's sound

`room/mic.py` measures how loud the room is (the default mic, through pw-record) — loudness only, nothing is recognised
or kept. It brings the screen back at a sound, and while music plays the background's lights swell with it.
`"roomMic": false` in config.json turns it off. `room/output.py` keeps the Surface's own speakers at full underneath
the volume slider and puts music streams that were left turned down back to full when Room starts.

## Burn-in care

The Surface's LCD is old, so: everything drifts very slowly round a small loop (±6 px in use, ±28 px on standby), and
once a night (`"refreshAt": "04:00"`, `""` to turn it off) while on standby a minute of slow full-screen colour washes
exercises every pixel. A tap stops it.

## Buttons and screen

- Power button: screen off; a sound or a touch brings it back. Hold it to power off.
- Volume buttons: the music's volume while something plays, else the speaker's.
- On standby, after 5 quiet minutes the backlight goes fully off; any real sound brings it back.
- Settings → This panel: switch to the desktop, or shut down.
