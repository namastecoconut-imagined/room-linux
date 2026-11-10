#!/usr/bin/env bash
# Room's assistant — its own program with its own Python (assistant/.venv), separate from the panel. Sets up what the
# steps built so far need; run it again after each step (safe to repeat). It doesn't start anything yet.
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
uv pip install -q --python .venv/bin/python -r requirements.txt
# the wake-word engines (their heavy training extras aren't needed to run them)
uv pip install -q --python .venv/bin/python --no-deps "openwakeword==0.6.0" "livekit-wakeword==2.1.1"

echo "▸ Assistant: wake-word models"
M="$HOME/.local/share/room/assistant/models"; mkdir -p "$M"
get() { if [ ! -s "$2" ]; then curl -fsSL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; fi; }
OWW=https://github.com/dscripka/openWakeWord/releases/download/v0.5.1
for f in alexa_v0.1.onnx melspectrogram.onnx embedding_model.onnx; do get "$OWW/$f" "$M/$f"; done
get https://raw.githubusercontent.com/snakers4/silero-vad/master/src/silero_vad/data/silero_vad.onnx "$M/silero_vad.onnx"
echo "✓ Assistant set up."
