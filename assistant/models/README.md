# Models (shipped with Room — nothing to download)

- `alexa.onnx` — Room's wake word (below)
- `silero_vad.onnx` — when you've finished talking (Silero VAD)
- `alexa_v0.1.onnx`, `melspectrogram.onnx`, `embedding_model.onnx` — openWakeWord's stock "alexa", only a fallback

## The wake word

`alexa.onnx` — Room's own "Alexa", trained with LiveKit WakeWord (`livekit-wakeword`, 5000 steps on the M1, 10 Nov 2026).
The assistant uses it straight from here (assistant/listen.py `Wake`); the stock openWakeWord "alexa" is only a
fallback if this file is missing or won't load.

| | stock openWakeWord | this model |
|---|---|---|
| LiveKit's test (500 "Alexa"s, 1 h of other speech) | — | 92.8 % caught, 0 false alarms / h |
| Surface raw mic, quiet room | 7 / 10 | 10 / 10 |
| Surface raw mic, over music | 3 / 20 | 18 / 20 |
| Surface raw mic, music only (false alarms) | 0 | 0 |

Threshold 0.5 (config.json `"assistant": {"wakeThreshold": …}`): lower it if it misses you, raise it if it wakes by
itself. The live log shows the score at the moment it crossed the threshold (so mostly just above 0.5), not the peak.

To retrain (on the Mac): `livekit-wakeword train` in `~/alexa-wake`, then replace this file, commit, `room-update`;
score it first with `python -m assistant.bench.wake_eval ~/room-wake-test/<time>`.
