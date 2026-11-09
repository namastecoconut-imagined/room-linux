#!/usr/bin/env bash
# Room's voice and ears — speaking (Deepgram's Aura online, Kokoro offline) and listening ("Alexa" on the Surface,
# Sarvam for what follows). Safe to run again.
set -euo pipefail
trap 'echo "✗ Voice setup stopped at line $LINENO — paste the lines above to Claude"' ERR
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
DATA="$HOME/.local/share/room/voice"
mkdir -p "$DATA" "$HOME/.local/bin"

echo "▸ Voice: system packages"
sudo dnf install -y -q --skip-unavailable pipewire-utils curl python3-pip uv
if ! command -v uv >/dev/null; then
  echo "  uv isn't packaged here — installing it with pip"
  python3 -m pip install -q --user uv
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "▸ Voice: its own Python (3.12) and packages"
cd "$HERE/voice"
# Fedora's uv doesn't fetch Pythons by itself — ask it to (once; it's kept in ~/.local/share/uv)
uv python install -q 3.12
[ -x .venv/bin/python ] || uv venv -q --python 3.12 .venv
uv pip install -q --python .venv/bin/python -r requirements.txt
uv pip install -q --python .venv/bin/python --no-deps "openwakeword==0.6.0"

echo "▸ Voice: the wake word and the offline speaking voice"
get() { if [ ! -s "$2" ]; then curl -fL --retry 3 -# -o "$2.part" "$1" && mv "$2.part" "$2"; fi; }
mkdir -p "$DATA/oww"
OWW=https://github.com/dscripka/openWakeWord/releases/download/v0.5.1
for f in alexa_v0.1.onnx melspectrogram.onnx embedding_model.onnx silero_vad.onnx; do get "$OWW/$f" "$DATA/oww/$f"; done
K=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
get "$K/kokoro-v1.0.int8.onnx" "$DATA/kokoro.onnx"
get "$K/voices-v1.0.bin" "$DATA/voices.bin"

echo "▸ room-update now also keeps voice up to date"
cat > ~/.local/bin/room-update <<UPD
#!/usr/bin/env bash
exec bash "$HERE/scripts/update.sh" "\$@"
UPD
chmod +x ~/.local/bin/room-update

systemctl --user restart room.service 2>/dev/null || true
echo "✓ Room’s voice and ears are set up — say “Alexa”."
