#!/usr/bin/env bash
# Room's voice — wake word, speech recognition, spoken answers, all on the Surface. Safe to run again.
#   bash scripts/voice.sh                      (whisper model: base.en)
#   WHISPER_MODEL=small.en bash scripts/voice.sh   (more accurate, ~2× slower)
set -euo pipefail
trap 'echo "✗ Voice setup stopped at line $LINENO — paste the lines above to Claude"' ERR
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$HOME/.local/share/room/voice"
WDIR="$HOME/.local/share/room/whisper"
SRC="$HOME/.local/src"
MODEL="${WHISPER_MODEL:-base.en}"
mkdir -p "$DATA/oww" "$WDIR" "$SRC" "$HOME/.local/bin"

echo "▸ Voice: system packages"
sudo dnf install -y -q --skip-unavailable cmake gcc-c++ git pipewire-utils curl python3-pip uv
if ! command -v uv >/dev/null; then
  echo "  uv isn't packaged here — installing it with pip"
  python3 -m pip install -q --user uv
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v cmake >/dev/null || { echo "✗ cmake didn't install"; exit 1; }

echo "▸ Voice: its own Python (3.12) and packages"
cd "$HERE/voice"
# Fedora's uv doesn't fetch Pythons by itself — ask it to (once; it's kept in ~/.local/share/uv)
uv python install -q 3.12
[ -x .venv/bin/python ] || uv venv -q --python 3.12 .venv
uv pip install -q --python .venv/bin/python -r requirements.txt
uv pip install -q --python .venv/bin/python --no-deps "openwakeword==0.6.0"

echo "▸ Voice: wake word + speaking models"
get() { if [ ! -s "$2" ]; then curl -fL --retry 3 -# -o "$2.part" "$1" && mv "$2.part" "$2"; fi; }
OWW=https://github.com/dscripka/openWakeWord/releases/download/v0.5.1
for f in alexa_v0.1.onnx melspectrogram.onnx embedding_model.onnx silero_vad.onnx; do get "$OWW/$f" "$DATA/oww/$f"; done
K=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
get "$K/kokoro-v1.0.int8.onnx" "$DATA/kokoro.onnx"
get "$K/voices-v1.0.bin" "$DATA/voices.bin"

echo "▸ Voice: whisper.cpp (builds once, a few minutes)"
if [ -d "$SRC/whisper.cpp/.git" ]; then git -C "$SRC/whisper.cpp" pull -q --ff-only || true
else git clone -q --depth 1 https://github.com/ggml-org/whisper.cpp "$SRC/whisper.cpp"; fi
cd "$SRC/whisper.cpp"
if [ ! -x "$HOME/.local/bin/room-whisper-server" ] || [ "$(git rev-parse HEAD)" != "$(cat "$WDIR/built" 2>/dev/null)" ]; then
  cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF -DWHISPER_SDL2=OFF -DGGML_NATIVE=ON >/dev/null
  cmake --build build -j"$(nproc)" --target whisper-server >/dev/null
  install -m 755 build/bin/whisper-server "$HOME/.local/bin/room-whisper-server"
  git rev-parse HEAD > "$WDIR/built"
fi
get "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin" "$WDIR/ggml-$MODEL.bin"

echo "▸ Voice: speech recognition service (room-whisper)"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/room-whisper.service <<UNIT
[Unit]
Description=Room speech recognition (whisper.cpp)
After=default.target

[Service]
ExecStart=$HOME/.local/bin/room-whisper-server -m $WDIR/ggml-$MODEL.bin --host 127.0.0.1 --port 8910 -t 4 -l en
Restart=on-failure
RestartSec=5
Nice=5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now room-whisper.service >/dev/null
systemctl --user restart room-whisper.service

echo "▸ Voice: echo cancellation stays off (on the Surface it distorted the mic and made the speakers crackle)"
if [ -f ~/.config/pipewire/pipewire.conf.d/60-room-echo-cancel.conf ]; then
  rm -f ~/.config/pipewire/pipewire.conf.d/60-room-echo-cancel.conf
  systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
  sleep 2
  systemctl --user restart room-airplay.service 2>/dev/null || true
fi

echo "▸ room-update now also keeps voice up to date"
cat > ~/.local/bin/room-update <<UPD
#!/usr/bin/env bash
exec bash "$HERE/scripts/update.sh" "\$@"
UPD
chmod +x ~/.local/bin/room-update

systemctl --user restart room.service 2>/dev/null || true
echo "✓ Voice is set up. Say “Alexa”."
