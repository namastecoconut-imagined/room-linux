# Room's assistant

Its own program, separate from the panel: it owns the mic and its voice, and talks to Room over a local connection.
If it stops, Room carries on. Built one step at a time, each with a test that has to pass before the next:

1. Bluetooth stays in music mode while the mic's in use — 10/10
2. **The speaker** (`player.py`) — one stream, kept open, fed from a buffer: no gaps — `bench/play_test.py`
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
| wake word | LiveKit WakeWord, your own trained "Alexa" (stock openWakeWord until then) | stock caught 3–7/10 |
| finished talking | Silero VAD: 1 s of quiet once you've started; up to 5 s to start | |
| words | Sarvam (saarika), the whole request at once | 7.1 % word errors, all the Hinglish right, 0.4 s — Whisper turbo 18.6 % in 12 s on the Surface |
| understanding | Claude (Haiku), the home's state with every request | |
| voice | Kokoro "Heart" (fp16) on the Surface, played by `player.py` | your pick; fp16 the fastest build on this CPU |

Files: `__main__.py` the loop · `listen.py` mic, wake word, end of speech, Sarvam · `brain.py` Claude · `tts.py` +
`player.py` the voice · `duck.py` music down/up · `link.py` the line to Room (`room/voice.py` on the other end).
Settings in config.json: `"assistant": {"wakeThreshold": 0.5, "micLevel": 0.65, "voice": "af_heart", "enabled": true}`.
