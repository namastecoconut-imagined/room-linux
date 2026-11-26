# Room — Surface Pro 6 (Fedora)

The Room panel as a native Qt Quick app. The screens are drawn on the GPU, and the logic is in Python. It's the living-room version of the iPhone panel. It reads the same `config.json`, talks to the same WiZ bulbs over the local network, and uses the same Spotify login and calendar link.

## Set up (once)

1. **Touch.** Install the linux-surface kernel and `iptsd`, which fix jumpy touch and ghost touches. Follow the Fedora steps at https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup, then reboot.
2. **Battery.** In the Surface UEFI (hold volume-up while powering on), turn on **Battery Limit**. This caps the charge at 50% so the battery doesn't swell while the Surface is always plugged in.
3. **Config.** Copy `config.json` from the Mac (`Downloads/RoomPanel/config.json`) to `~/.config/room/config.json`
   (with `"anthropicKey"` and `"sarvamKey"` for the assistant). Keys live only there, never in this repo.
   Everyday settings are made on the panel instead (Settings → More settings): the cats, the 12/24-hour clock, when
   night is, how long before standby, the microphone, waking on a sound, AirPlay to the speaker, the speaker limit.
   Room keeps those in `~/.config/room/settings.json`; it never writes config.json, and what's set on the panel wins.
   **Display font:** the clock, big numbers and Alexa's words are set in Kasero when `~/.config/room/fonts/Kasero.otf`
   is there. It's a licensed font, so it isn't in this public repo; without it Room uses Instrument Serif, which ships here.
   **Room's voice:** the assistant speaks with Room's own Piper voice, `en_US-room-medium.onnx` and its `.onnx.json`
   in `~/.local/share/room/voices/`. It isn't in this public repo either; without it answers are shown, not spoken.
4. **Room — everything, in one go:**
   ```bash
   git clone https://github.com/namastecoconut-imagined/room-linux ~/room && bash ~/room/scripts/install.sh
   ```
   The panel, AirPlay ("Room"), Spotify Connect ("Room", asks for the Soloist key once), the voice assistant,
   never-suspend, the sound fixes, and the `room-update` / `room-kiosk` commands.
5. **Kiosk** (just the panel, no desktop; signs in by itself): `room-kiosk on`, restart. Back to GNOME: `room-kiosk off`.

What runs (all user services, the same under GNOME and in kiosk mode):

| service | what | log |
|---|---|---|
| `room` | the panel | `journalctl --user -u room -f` |
| `room-assistant` | "Alexa" (`assistant/`) | `journalctl --user -u room-assistant -f` |
| `room-airplay` | AirPlay receiver (shairport-sync) | `journalctl --user -u room-airplay -f` |
| `room-spotify` | Spotify Connect speaker (Soloist) | `journalctl --user -u room-spotify -f` |

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

Or on the panel: Settings → More settings → Updates → **Check for updates**. If there's something new it updates
straight away (the same room-update, run on its own so it carries on while Room restarts), then checks Room came back;
if it didn't, it goes back to the version before. The page shows what changed and how it went
(`~/.local/state/room/update.log` has the details).

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
| `qml/SettingsView.qml` | the Settings screen: brightness, Wi-Fi (join with a password), Bluetooth, web browser / desktop / shut down (asks first); More settings (a sheet): the cats, clock & night, standby, sound, updates |
| `qml/Keyboard.qml` | the on-screen keyboard (the Wi-Fi password): rises when a text box is typed in, lifts the sheet above it |
| `qml/VolumeHud.qml` | the volume buttons' capsule |
| `qml/VoiceOverlay.qml` + `shaders/horizon.frag` | the assistant over the top band: the light line, your words, the answer, buttons under the line |
| `qml/VoiceCard.qml` · `qml/Words.qml` | the card beside an answer (weather, forecast, air, timer, music, schedule, alarm, lights) · words that come in one by one |
| `qml/Cats.qml` · `qml/Cat.qml` | the cats: where they can be on each screen and what they do next · one cat, drawn frame by frame |
| `assets/cats/` · `qml/catsdata.js` · `tools/cats/` | the cats' drawings (sprite sheets), where each drawing is, and the scripts that draw them |
| `room/update.py` · `scripts/ota.sh` | Settings → Updates: check GitHub, update, and go back if the new version doesn't start |
| `room/sleep.py` | screen off in a quiet room (or the power button), back on at a sound or a touch |
| `room/output.py` | music (AirPlay, the Surface's Spotify) to the Bluetooth speaker when one's connected; speaker levels |
| `room/mic.py` | how loud the room is (screen wake; while music plays, the background's swell) |
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
Settings → More settings → Sound turns it off. `room/output.py` keeps the Surface's own speakers at full underneath
the volume slider and puts music streams that were left turned down back to full when Room starts.

## Burn-in care

The Surface's LCD is old, so: everything drifts very slowly round a small loop (±6 px in use, ±28 px on standby), and
once a night (`"refreshAt": "04:00"`, `""` to turn it off) while on standby a minute of slow full-screen colour washes
exercises every pixel. A tap stops it.

## The cats

Bebo and Evan live on Room's screens, always on something real: the tops of the clock's numbers, the music card's
top, the forecast's curve, a list's lines, a sheet's top edge, the bottom edge of the screen (or just below it, about
to peek up). They breathe and blink, wash, yawn, knead, roll over, nap, walk and leap between edges, now and then
chase each other off the side of the screen, push the song's playhead along, nod to music, sit on the assistant's
line of light when it's up (ears up while it listens), swat the clock when the minute changes, race about when an
alarm goes off, and sleep at night, often curled up together. They play together: one stalks the other's tail and
pounces (then it's a chase), they rear up and box, they touch noses and one grooms the other. Every 20–30 minutes in
the daytime, on standby and Home, one comes right up to the glass, big, flops out across the bottom of the screen,
rolls belly up, and wanders off again. They never take a touch. Settings → More settings → Cats turns them off (not loaded at all) or keeps them awake
at night. To check them:
`ROOM_SCREEN=catsdayhome` / `catsdaystandby` (everything happens sooner).

## The pixel display

A 32 × 32 dot display on Bluetooth (an iDotMatrix panel, name `IDM-…`) is run from Room: Home → Pixel. It only shows
what's sent to it and takes one connection at a time, so Room holds the link all the time (`room/pixel/link.py`):
it connects when the display is seen, sets its clock, and reconnects by itself. `[pixel]` lines in the log say what
the link is doing: `journalctl --user -u room | grep '\[pixel\]'`.

- **Clock:** 15 faces, all drawn by Room and sent again each minute (each second with the seconds dot), whatever
  screen Room is on. Only the first still in a run is preceded by the picture-mode command, so the display doesn't
  blank between frames.
- **Art:** 24 loops of 48 frames, sent once; the display plays them by itself.
- **Light:** the display's own 7 effects in 2–7 colours, or one colour.
- **Timers:** a countdown, a stopwatch or a scoreboard — drawn by Room in the clock's digits ("Minimal") or the
  display's own screens ("Built-in"). They're up for now: when one ends, what was showing comes back.
- **Text:** a scrolling message (typed on the on-screen keyboard), in a colour, size, speed and typeface.
- **Library:** GIFs and pictures kept in `~/.local/state/room/pixel-library/` on the Surface — copy files in from the
  Mac (`scp picture.gif namastecoconut@fedora.local:.local/state/room/pixel-library/`). Tap one to show it; tick
  some and start a slideshow (it carries on after a restart).
- **Setup:** the assistant's face (the chosen Library pictures take turns on the display, from the moment the
  assistant hears "Alexa" until it's done); night dimming (the display dims itself between two times); picture tuning (presets, or value by value —
  what's showing is sent again with each change); flip 180°; a connection check; and Release display, which lets
  go of the link so the web app or the phone app can connect (Take it back to return).
- Brightness and on / off are in the screen's top bar. What's showing and every choice are kept in
  `~/.local/state/room/pixel.json`, so the display comes back the same after a restart or a power cut.
- The pictures are drawn in `qml/pixeldata.js` (from pixelcontrol.html, the web app this was ported from), and
  `room/pixel/proto.py` turns them into the display's bytes — the same bytes as the web app's.
- If the screen ever stops answering: `systemctl --user kill -s USR1 room` writes where every thread is to the log
  (`journalctl --user -u room -n 80`), without stopping Room.
- `"pixel": false` in config.json: no link at all (so the web app or the phone app can connect to the display).

## Buttons and screen

- Power button: screen off; a sound or a touch brings it back. Hold it to power off.
- Volume buttons: the music's volume while something plays, else the speaker's.
- Both work whatever is in front (the web browser too): Room reads them from the hardware, once
  `scripts/buttons.sh` has run (`undo` takes it back).
- On standby, after 5 quiet minutes the backlight goes fully off — never while music plays on the Surface or through
  it (its speakers, or a speaker it sends to; not Spotify on the phone), and music starting there brings it back. While it's off, a small sound brings it back: anything slightly over the room's background, like a
  snap of the fingers. Settings → More settings → Sound sets how far over, in dB (10 unless set; lower wakes on smaller
  sounds); the log says once a minute how loud the loudest sound was, to set it by.
- Settings → This panel: switch to the desktop, or shut down.
