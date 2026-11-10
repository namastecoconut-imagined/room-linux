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

Setup: `bash scripts/assistant.sh` (its own Python in `assistant/.venv`).
