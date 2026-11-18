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
| finished talking | Smart Turn v3.2 (`turn.py`): at a pause (0.24 s, then 0.72, 1.36) it hears whether the sentence landed or trailed off — finished: done at once; unfinished: up to 2.5 s. Silero VAD finds the pauses; up to 5 s to start | 18 Nov. It was a flat 1.4 s of quiet (1.0 cut people off). Fallback if the model won't load or `"smartTurn": false`: that 1.4 s rule |
| words | Sarvam (saarika), the whole request at once | 7.1 % word errors, all the Hinglish right, 0.4 s — Whisper turbo 18.6 % in 12 s on the Surface |
| understanding | Claude (Haiku), the home's state with every request | |
| voice | Room's own Piper voice (`en_US-room-medium`), made on the Surface sentence by sentence and played by `player.py` as each is ready; levelled to one loudness; short lines kept | 15 Nov: trained on a 5080 from 16 min of Fish Audio speech, fine-tuned from Piper's Lessac voice (2,000 epochs). About 10× faster than it's spoken on the Surface; offline and free. Before: Sarvam Bulbul (online, paid, 14 Nov), and before that Kokoro (made here, but too slow once the screen got busier) |

Files: `__main__.py` the loop · `listen.py` mic, wake word, end of speech, Sarvam · `turn.py` + `whisper_features.py` finished or just pausing · `brain.py` Claude · `tts.py` +
`player.py` the voice · `speaker.py` the Surface's own speakers (the voice always plays there) · `echo.py` echo cancelling · `duck.py` music down/up · `link.py` the line to Room (`room/voice.py` on the other end).
Settings in config.json: `"assistant": {"wakeThreshold": 0.5, "micLevel": 0.65, "echoCancel": true, "enabled": true}`.
The voice files (not in this public repo): `~/.local/share/room/voices/en_US-room-medium.onnx` and `.onnx.json`.
While Room talks the speaker is lifted to the chip's crackle cap (Settings → More settings → Sound), then put back.
