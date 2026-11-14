# Room's assistant

Its own program, separate from the panel: it owns the mic and its voice, and talks to Room over a local connection.
If it stops, Room carries on. Built one step at a time, each with a test that has to pass before the next:

1. Bluetooth stays in music mode while the mic's in use — 10/10
2. **The speaker** (`player.py`) — one stream, kept open, fed from a buffer: no gaps — (tested with a play test, since removed)
3. Wake word on the raw mic vs the noise-suppressed one; a custom "Alexa"; music ducked at once — 18/20 over music
4. Speech-to-text: on the Surface (Parakeet, Whisper) vs AssemblyAI, on 30 of your commands
5. Knowing when you've finished — ≤1 cut-off in 30 with pauses
6. Claude, the actions, Room's voice, the link to the panel, the listening screen
7. Taking its own voice back out of the mic, so you can talk over it
8. Three days running

Setup: `bash scripts/assistant.sh` (its own Python in `assistant/.venv`, its own service `room-assistant`).
Its log: `journalctl --user -u room-assistant -f`.

What it runs on (each chosen by a test on this Surface):

| | | why |
|---|---|---|
| mic | the raw Surface mic, held at 65 % | 100 % clipped; the noise-suppressed mic was worse for every speech-to-text option |
| echo | Room's own linear canceller (`echo.py`): the mic and what every speaker is sent, in one stream, the music taken back out | live, music at 80–85 % on the Surface's speakers: "Alexa" 3/9 → 9/9. Xiaomi: 10/10 either way (it's across the room; its delay slides 375 → 220 ms as it settles, so little to take out). WebRTC's AEC3 ate the voice (1/10) |
| wake word | Room's own "Alexa" (LiveKit WakeWord, `models/alexa.onnx`) | 10/10 quiet, 18/20 over music, 0 false (stock: 7/10, 3/20) |
| finished talking | Silero VAD: 1 s of quiet once you've started; up to 5 s to start | |
| words | Sarvam (saarika), the whole request at once | 7.1 % word errors, all the Hinglish right, 0.4 s — Whisper turbo 18.6 % in 12 s on the Surface |
| understanding | Claude (Haiku), the home's state with every request | |
| voice | Sarvam Bulbul v4 Flash, "Ishita · customer", streamed and played by `player.py` as it arrives; levelled to one loudness; short lines kept on the Surface | your pick (14 Nov). It was Kokoro "Heart", made on the Surface: it only just kept up with playback, and once the screen got busier it fell behind (pauses between sentences) |

Files: `__main__.py` the loop · `listen.py` mic, wake word, end of speech, Sarvam · `brain.py` Claude · `tts.py` +
`player.py` the voice · `echo.py` echo cancelling · `duck.py` music down/up · `link.py` the line to Room (`room/voice.py` on the other end).
Settings in config.json: `"assistant": {"wakeThreshold": 0.5, "micLevel": 0.65, "voice": "ishita_en_customer", "echoCancel": true, "enabled": true}`.
