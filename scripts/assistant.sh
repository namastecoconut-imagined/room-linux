#!/usr/bin/env bash
# Room's assistant — its own program with its own Python (assistant/.venv), separate from the panel. Sets up what the
# steps built so far need, then starts it. Safe to run again.
set -euo pipefail
trap 'echo "✗ Assistant setup stopped at line $LINENO — paste the lines above to Claude"' ERR
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

echo "▸ Assistant: system packages"
sudo dnf install -y -q --skip-unavailable portaudio pipewire-utils uv
if ! command -v uv >/dev/null; then
  python3 -m pip install -q --user uv
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "▸ Assistant: its own Python (3.12) and packages"
cd "$HERE/assistant"
uv python install -q 3.12
[ -x .venv/bin/python ] || uv venv -q --python 3.12 .venv
# exactly the versions Room is tested with (the wake-word engines without their heavy training extras)
if [ -f requirements.lock ]; then
  uv pip sync -q --python .venv/bin/python requirements.lock
else
  uv pip install -q --python .venv/bin/python -r requirements.txt
  uv pip install -q --python .venv/bin/python --no-deps "openwakeword==0.6.0" "livekit-wakeword==2.1.1"
fi

# (the wake word and end-of-speech models ship with Room, in assistant/models)
get() { if [ ! -s "$2" ]; then curl -fsSL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; fi; }
echo "▸ Assistant: Room's voice (Kokoro)"
K="$HOME/.local/share/room/assistant/kokoro"; mkdir -p "$K"
KURL=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
for f in kokoro-v1.0.fp16.onnx voices-v1.0.bin; do get "$KURL/$f" "$K/$f"; done

echo "▸ Assistant: its service (starts with the Surface, restarts if it stops)"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/room-assistant.service <<UNIT
[Unit]
Description=Room's voice assistant
After=pipewire.service wireplumber.service pipewire-pulse.service
Wants=pipewire.service

[Service]
WorkingDirectory=$HERE
ExecStart=$HERE/assistant/.venv/bin/python -u -m assistant
Restart=always
RestartSec=3
Nice=-5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable room-assistant.service >/dev/null
systemctl --user restart room-assistant.service
sleep 6
journalctl --user -u room-assistant -n 8 --no-pager -o cat
echo "✓ Assistant set up and running. Its log: journalctl --user -u room-assistant -f"
