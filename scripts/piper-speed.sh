#!/usr/bin/env bash
# The light-voice speed test (14 Nov): can the Surface make speech itself with Piper, fast enough to leave room for
# everything else? Sets up ~/piper-test (its own Python 3.12, piper-tts ~30 MB, two ready-made English voices from
# Piper's own collection, ~80 MB), times them with Room, the cats and the assistant running, then plays one answer
# (the speaker lifted as for an answer, and put back). Changes nothing in Room.
# Take it all off: bash ~/room/scripts/experiments.sh clean
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="$HOME/piper-test"; mkdir -p "$T"; cd "$T"
command -v uv >/dev/null || { echo "uv is missing (the assistant's setup installs it)"; exit 1; }
echo "▸ its own Python and Piper"
[ -x venv/bin/python ] || uv venv -q --python 3.12 venv
uv pip install -q --python venv/bin/python piper-tts
echo "▸ two ready-made English voices (the low and medium sizes)"
for v in en_US-lessac-low en_US-lessac-medium; do
  [ -s "$v.onnx" ] || venv/bin/python -m piper.download_voices --download-dir "$T" "$v" >/dev/null 2>&1 || \
    { echo "  couldn't download $v"; exit 1; }
done
echo "▸ the test (under a minute)"
venv/bin/python -W ignore "$HERE/assistant/bench/piper_speed.py" en_US-lessac-low en_US-lessac-medium
if [ -s "$T/sample.wav" ]; then
  was=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
  wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.86
  pw-play "$T/sample.wav" || true
  wpctl set-volume @DEFAULT_AUDIO_SINK@ "$was"
fi
