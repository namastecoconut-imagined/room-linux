# Wake-word models

`alexa.onnx` — Room's own "Alexa", trained with LiveKit WakeWord (`livekit-wakeword`, 5000 steps on the M1, 10 Nov 2026).
On LiveKit's own test (500 "Alexa"s, an hour of other speech): 92.8 % caught at threshold 0.5, 0 false alarms an hour,
3.8 % of sound-alikes accepted.

It isn't used until it's copied where the assistant looks (`~/.local/share/room/assistant/models`) — score it on the
Surface's own recordings first (`python -m assistant.bench.wake_eval ~/room-wake-test/<time>`), then:

    cp ~/room/assistant/models/alexa.onnx ~/.local/share/room/assistant/models/ && systemctl --user restart room-assistant

To go back to the stock openWakeWord "alexa", delete that copy and restart the assistant.
