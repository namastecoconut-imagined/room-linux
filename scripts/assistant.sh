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
echo "✓ Assistant set up. Test the speaker:  cd ~/room && assistant/.venv/bin/python -m assistant.bench.play_test"
