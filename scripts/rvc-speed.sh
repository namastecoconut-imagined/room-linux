#!/usr/bin/env bash
# The voice-conversion speed test (14 Nov): can the Surface turn Room's voice into another voice fast enough? Sets up
# everything in ~/rvc-test (its own Python 3.12, CPU-only PyTorch ~200 MB, RVC's model code from GitHub — no voice is
# downloaded: the test runs RVC's models with blank weights, which is the same amount of work), then runs
# assistant/bench/rvc_speed.py with Room, the cats and the assistant running as usual. Changes nothing in Room.
# Take it all off: bash ~/room/scripts/experiments.sh clean
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="$HOME/rvc-test"; mkdir -p "$T"; cd "$T"
command -v uv >/dev/null || { echo "uv is missing (the assistant's setup installs it)"; exit 1; }
echo "▸ its own Python and PyTorch (CPU only) — a few minutes the first time"
[ -x venv/bin/python ] || uv venv -q --python 3.12 venv
uv pip install -q --python venv/bin/python --index-url https://download.pytorch.org/whl/cpu torch
uv pip install -q --python venv/bin/python "transformers>=4.49,<5" librosa scipy numpy
echo "▸ RVC's model code (only its infer/ folder)"
if [ ! -d repo ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI.git repo
  git -C repo sparse-checkout set infer
fi
echo "▸ the test (about a minute; the Surface's fan may come on)"
venv/bin/python -W ignore "$HERE/assistant/bench/rvc_speed.py" 2>&1 | grep -v "WeightNorm"
