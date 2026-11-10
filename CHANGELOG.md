# Room — changelog

Room is the living-room panel on a Surface Pro 6, running Fedora 45 with the linux-surface kernel. It's a native Qt
Quick app (PySide6) with its own voice assistant. This covers 8–10 November 2026: 215 commits, from an empty repo to
**v1.0, commit `cb07492`**.

---

## v1.0 — 10 Nov 2026: what Room is now

### The panel
- **Home**: glass cards over the current song's slowly moving colours.
  - A floating dot-matrix clock, with one line under it: *"Tuesday evening, 10 November."* then *"20° and overcast, rain around 4 pm."*
  - The **Next** card (calendar), the **music** card and the **lights** card.
  - With nothing playing, the music card offers Liked Songs and what you last played.
  - Top bar: Alarms · Weather · Reminders · Scenes · All off · Dim · Night · the assistant's mic · Settings.
- **Inner screens**: room, clock, weather, reminders, settings.
  - Settings covers brightness and Bluetooth (search, pair, connect, forget), and can switch to the desktop.
- **Laid out around the touch screen's dead band** (stage y 114–500, measured with sensor tests). Only things to read sit there; every control is in the top bar or the lower part. Touches starting on the two faulty sensor lines are dropped.
- **Music player**: the cover, up-next stack, playlists (arrows, three at a time), a swipe on the cover to skip, and a volume slider.
  - Covers cross-fade, and colours and words ease in with each new song.
- **Music standby**, the Zune way: artist, title and album drift across as giant lowercase words, over the cover's moving colours.
- **Standby**: a calm dashboard showing the running timer and the next alarm.
- **Standby timing**:
  - Home with music playing goes to music standby after 30 s.
  - Home with nothing playing goes to standby after 5 min.
  - The music player waits 5 min; menus wait 3 min.
- **Screen off when the room is quiet** (5 min on standby). It comes back on at a lasting sound, a touch, "Alexa" or an alarm.
  - The power button turns the screen off and on; a long press still powers off.
- **Volume buttons** show an Apple-style capsule (frosted glass, speaker with 0–3 waves).
- **Burn-in care**:
  - Slow pixel drift (±6 px awake, ±28 px on standby), and backgrounds reach 60 px past the edges so the drift never shows one.
  - A nightly one-minute colour refresh on standby.
- **Never suspends** (`no-suspend.sh`). Asleep, nothing ran and only the power button woke it.

### Music and sound
- **AirPlay 2** receiver "Room" (shairport-sync). When the phone is playing Spotify, Room borrows the queue, progress and seeking from Spotify.
- **Spotify Connect** speaker "Room", via Spotify Soloist (Spotify's own headless player).
- **One thing plays at a time**: AirPlay starting pauses the Surface's Spotify, and the Surface's Spotify starting pauses AirPlay.
- **Bluetooth speaker**:
  - Music (AirPlay and Spotify) goes to it whenever it's connected, checked against where each stream actually plays. It returns to the Surface when the speaker disconnects.
  - It never drops to its low-quality "headset" mode.
- **Volume**:
  - The slider and the volume buttons set the speaker the music is playing on (Bluetooth or the Surface), instantly.
  - Room's own Spotify is kept at 100%.
  - The phone's AirPlay volume moves the speaker and the slider.
  - The slider is hidden while Spotify plays on another device.
- **The Surface's speakers**:
  - Everything goes through the Windows Dolby tuning, rebuilt for PipeWire.
  - An extra limiter sits at the very end of that tuning.
  - The chip's Master is held 4 dB under full, which ended the crackling at the top of the volume range.
  - Streams that PipeWire remembered at a low level are put back to full.

### The voice assistant (`assistant/`, its own program and service)
- Room's own **"Alexa"** wake word, trained for Room with LiveKit WakeWord:

  | Surface raw mic | stock openWakeWord | Room's model |
  |---|---|---|
  | quiet room | 7 / 10 | **10 / 10** |
  | over music | 3 / 20 | **18 / 20** |
  | false alarms (music only) | 0 | **0** |

- **Echo cancelling**, Room's own linear canceller:
  - The mic and whatever every speaker is being sent arrive together in one stream, and the music is taken back out.
  - Live, with music at 80–85% on the Surface's speakers: "Alexa" went from **3/9 to 9/9**.
  - On the Xiaomi it's 10/10 either way.
  - It can never make the mic worse, and it rests while Room speaks.
- **Hearing a request**: the raw mic is held at 65%. Silero VAD decides when you've finished (1 s of quiet once you've started).
- **Speech to text**: Sarvam (saarika, en-IN), with the whole request sent at once.
  - 7.1% word error, all the Hinglish right, 0.4 s.
  - For comparison on the Surface: Whisper turbo 18.6% error in 12 s; Parakeet 47%.
- **Thinking**: Claude Haiku, given the home's state with every request.
  - It controls lights, music, volume, speakers, timers, alarms, reminders and the sleep timer.
  - It can also look things up and remember things.
- **Speaking**:
  - The voice is Kokoro "Heart" (fp16), made on the Surface itself.
  - Playback is one stream kept open and fed from a buffer.
  - Music dips to 15% while you talk and goes back exactly to where it was.
  - Room's voice is never quieter than 40% (the speaker is lifted for the conversation, then put back).
- **Follow-ups**: if Room asks a question, it listens again without "Alexa".
- **Screen: "Horizon fog"** (designed in Figma: *Room — Assistant & Orb*). A band of glowing cloud with soft rays.
  - Listening: cool blue and mint, with light flowing *up* into the cloud.
  - Thinking: blue with a touch of coral.
  - Speaking: warm amber and coral, with light flowing *down*.
  - It swells deeply but smoothly with your voice, with a quick layer that follows every word.
  - It reacts to speech only, not the room's hum.
- **Home mic button**: the fog falling in from the top, under the mic.
  - States: Ready (breathing), Pressed, Heard you, and the plain mic when the assistant isn't running.

### Kiosk, install and updates
- **Kiosk mode**: `room-kiosk on` boots straight into Room under cage, with no desktop. `room-kiosk off` goes back to GNOME. It also:
  - signs in automatically,
  - copies saved Wi-Fi passwords out of the desktop keyring,
  - leaves the power button to Room.
- **Four user services**, the same under GNOME or kiosk:
  - `room`: the panel. It never restarts itself, so a crash stays visible.
  - `room-assistant`, `room-airplay`, `room-spotify`.
- **One-step install** (`scripts/install.sh`): everything on a fresh Surface.
- **`room-update`**: pulls, installs the locked versions, keeps every fix in place and restarts.
- **Versions locked**: `requirements.lock` (panel) and `assistant/requirements.lock` (assistant).
  - The small models ship with the repo: wake word, end of speech, and the fallback wake word.
  - Only Kokoro (170 MB) is downloaded, from a fixed release.
- **Keys** live only in `~/.config/room/config.json` and `soloist.env`, never in the repo.

---

## How we got here

### 8 Nov — Room on the Surface
- The native Qt Quick panel: home, standby, music standby and the music player. The iPhone panel's screens and timing were ported over.
- AirPlay 2 receiver; `check.sh` renders every screen before each push.
- The first voice assistant: Alexa wake word, whisper.cpp, then Deepgram, then Claude's brain from the phone. It went through many rounds of mic tuning (gain, hum filters, noise suppression, both mics).
- Room's voice was quiet for a long time. **The cause:** the music ducking was also ducking the Dolby tuning's own output stream, down to 3%.
- The listening side was rebuilt from scratch once. Kiosk mode (`room-kiosk`) arrived.

### 9 Nov — the panel grows up
- Settings (brightness, Bluetooth), new home and music standby designs, smooth cover changes.
- Laid out around the touch screen's dead band.
- Spotify Connect: go-librespot was refused the audio, so it moved to Spotify Soloist. Spotify keeps working after the clock jumps at start-up.
- **Tried and removed:** music videos (YouTube via yt-dlp), YouTube cast, and AirPlay video (UxPlay).
- Screen off when the room is quiet; music always goes to the Bluetooth speaker when one is connected.

### 10 Nov — the assistant, rebuilt properly, and v1.0
- **Morning:** fixes to the old assistant (echo canceller, wake training, voice playback). These made things worse, so it was put back to the night before, then **removed completely** to start again.
- **The rebuild, step by step, each step chosen by a test on the Surface:**
  1. The speaker: the ring-buffer player. The old way stuttered 19 times; this one had 4 short pauses.
  2. The wake word: recordings on both mics. The raw mic at 65% won (100% clipped).
  3. Speech to text, five engines on 30 recorded commands: Sarvam won.
  4. The voice: Kokoro fp16 was the fastest on this CPU.
  5. Room's own "Alexa", trained on the Mac and scored on the Surface's recordings.
- **The screen:** fluted glass, then a starburst; the design moved into Figma, with four directions, and Horizon fog was chosen.
- **Sound:**
  - Crackling fixed (an end limiter, and Master 4 dB down).
  - Volume reworked around the speaker the music plays on.
  - The phone's AirPlay volume works with Bluetooth.
  - No more surprise suspends.
- **Echo cancelling:**
  - WebRTC's canceller ate the voice along with the music ("Alexa" 0–1/10).
  - Room's own linear canceller won on the same recordings.
  - Live, it needed the mic and the speakers in one stream before it worked: 3/9 → 9/9.
- **Packaged:**
  - Finished test tools and their packages removed (Whisper, Parakeet, WebRTC canceller).
  - Models shipped with the repo; one-step install; kiosk-ready services; versions locked.

### Tried and not kept
WebRTC echo cancelling, both PipeWire's (distorted the mic) and AEC3 (ate the voice) · Deepgram for listening and for
Room's voice · whisper.cpp / Whisper / Parakeet · live words on screen (the recogniser's guesses were rough) ·
music videos, YouTube cast and AirPlay video · go-librespot · new chimes (the current ones stayed).

---

## Still to do
- Talking over Room while it speaks. The echo canceller already removes Room's voice; listening during the answer is what's left.
- Cancelling the Xiaomi's sound well enough for that: its delay slides from 375 to 220 ms as it settles.
- Update the Figma file's listening and thinking colours to match the app.
