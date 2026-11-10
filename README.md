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

Room starts with the session. It doesn't restart itself.

- Just the panel, no desktop (cage, signs in by itself): `room-kiosk on` · back to GNOME: `room-kiosk off`
- AirPlay music ("Room"): `bash scripts/airplay.sh`
- Spotify on the Surface itself (Spotify Connect speaker "Room", via Spotify Soloist): `bash scripts/spotify-connect.sh`
- Teach "Alexa" your voice (about 6 minutes, over SSH, near the panel): `bash scripts/train-alexa.sh`
- Stop it: `systemctl --user stop room` · run it in a terminal: `cd ~/room && .venv/bin/python -m room`
- From the Mac: `ssh namastecoconut@room.local`

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
| `qml/Home.qml` | home: glass cards over the song's moving colours — dot clock, next, music, lights |
| `qml/Standby.qml` + `shaders/standby.frag` | breathing dot field and morning glow (GPU shader), dot clock |
| `qml/MusicStandby.qml` | music standby, the Zune way: moving colours, giant drifting words |
| `qml/ColourWash.qml` · `qml/Glass.qml` | the song's colours as a moving background · frosted cards |
| `qml/VolumeHud.qml` | the volume buttons' capsule |
| `qml/DotText.qml` | the 5×7 dot numerals; dots glide to their new places each minute |
| `room/sleep.py` | screen off in a quiet room (or the power button), back on at a sound, touch, "Alexa" |
| `room/output.py` | music (AirPlay, the Surface's Spotify) to the Bluetooth speaker when one's connected |
| `room/wiz.py` | WiZ bulbs (UDP 38899) |
| `room/spotify.py` | Spotify Web API (shares the iPhone panel's login) |
| `room/weather.py` · `room/calendar.py` | Open-Meteo, Google Calendar iCal |

Shaders are precompiled (`*.qsb`). After editing a `.frag`, recompile it:
`pyside6-qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/standby.frag.qsb shaders/standby.frag`

## Voice

Set up once with `bash scripts/voice.sh` (install.sh runs it too).

- **Listening** (`voice/ears.py`) — the Surface mic (raw, at 70 %) through Room's echo canceller (`voice/aec.py`:
  what's playing on the music speaker taken back out, then a gentle noise filter and level control). "Alexa" is
  spotted on the Surface (openWakeWord, plus a model of your own voice once `train-alexa.sh` has run); what follows
  streams to Sarvam (saaras:v4, en-IN — `sarvamKey`). You've finished after ~0.7 s without speech (Silero VAD).
  Keep the Bluetooth speaker a metre or more from the panel, facing away — that's most of hearing "Alexa" over music.
- **Understanding** — Claude (`room/brain.py`, the iPhone panel's prompt and tool) with a snapshot of the home;
  `room/intents.py`, plain rules, when there's no key or no internet. `room/assistant.py` carries out the actions.
- **Answers** — Deepgram's Aura voice, streamed (`deepgramKey`); Kokoro (`af_heart`) offline. Chimes in `voice/cues`.

The voice side is its own process (`voice/roomvoice.py`, own Python in `voice/.venv`) — if it fails, Room carries on.
Settings in config.json: `"voice": false` turns it off; `"voiceSettings": {"listen": true, "wakeThreshold": 0.4,
"echoCancel": true, "micLevel": 0.70, "wakeVerifier": true, "bargeIn": true, "mic": "<pipewire node>", "voice": "bf_emma", "speed": 1.05, "voiceVolume": 1.0, "voiceMinLevel": 0.75}` —
Room's voice never plays quieter than voiceMinLevel of the speakers (the output is lifted while it talks, then put back).

## Burn-in care

The Surface's LCD is old, so: everything drifts very slowly round a small loop (±6 px in use, ±28 px on standby), and
once a night (`"refreshAt": "04:00"`, `""` to turn it off) while on standby a minute of slow full-screen colour washes
exercises every pixel. A tap stops it.

## Buttons and screen

- Power button: screen off (Room keeps listening); a sound, a touch or "Alexa" brings it back. Hold it to power off.
- Volume buttons: the music's volume while something plays, else the speaker's.
- On standby, after 5 quiet minutes the backlight goes fully off; any real sound brings it back.
- Settings → This panel: switch to the desktop, or shut down.
