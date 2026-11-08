#!/usr/bin/env bash
# Local speech recognition on this Surface vs Deepgram, on what Room kept in ~/room-heard. Installs faster-whisper in
# its own folder (~/.local/share/room/bench) the first time — Room's own setup isn't touched.
HERE="$(cd "$(dirname "$0")/.." && pwd)"
V=~/.local/share/room/bench
if [ ! -x "$V/bin/python" ]; then
  echo "▸ setting up (once, a few minutes)…"
  python3 -m venv "$V" && "$V/bin/pip" install -q faster-whisper || { echo "✗ couldn't install faster-whisper"; exit 1; }
fi
"$V/bin/python" "$HERE/voice/sttbench.py"
