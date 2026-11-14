#!/usr/bin/env bash
# The Gemini Live ear test (14 Nov): an original cranky-genius character in a few of Gemini's voices, answering
# Room-style requests, each played as it comes (the speaker lifted as for an answer, then put back). Sets up
# ~/gemini-test (its own Python, Google's google-genai library ~20 MB). Needs "geminiKey" in config.json.
# Changes nothing in Room. Take it all off: bash ~/room/scripts/experiments.sh clean
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="$HOME/gemini-test"; mkdir -p "$T"; cd "$T"
command -v uv >/dev/null || { echo "uv is missing (the assistant's setup installs it)"; exit 1; }
echo "▸ its own Python and Google's Gemini library"
[ -x venv/bin/python ] || uv venv -q --python 3.12 venv
uv pip install -q --python venv/bin/python google-genai
was=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
trap 'wpctl set-volume @DEFAULT_AUDIO_SINK@ "$was"' EXIT
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.86
echo "▸ the test (Enter after each answer for the next)"
venv/bin/python -W ignore "$HERE/assistant/bench/gemini_test.py" "$T" | while IFS= read -r line; do
  case "$line" in
    "PLAY "*) pw-play "${line#PLAY }" 2>/dev/null || true
              read -r -p "  (Enter for the next) " _ </dev/tty ;;
    *) echo "$line" ;;
  esac
done
