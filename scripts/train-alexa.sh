#!/usr/bin/env bash
# Teach Room's "Alexa" your voice: about 6 minutes — 28 "Alexa"s after beeps (8 of them over music), 30 s of ordinary
# talk, 20 s of the room with music. Run it over SSH, standing where you'd talk to the panel. Safe to run again (it starts over).
# To undo: rm ~/.local/share/room/voice/alexa_verifier.pkl && systemctl --user restart room
set -e
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
"$HERE/voice/.venv/bin/python" "$HERE/voice/train_alexa.py"
systemctl --user restart room
echo "Room restarted — try \"Alexa\"."
