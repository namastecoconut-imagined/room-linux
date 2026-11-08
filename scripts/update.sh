#!/usr/bin/env bash
# What room-update runs: pull the latest Room, refresh its packages (and voice's, if voice is set up), restart.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
git pull --ff-only
"$HERE/.venv/bin/pip" install -q -r requirements.txt
if [ -x "$HERE/voice/.venv/bin/python" ] && command -v uv >/dev/null; then
  uv pip install -q --python "$HERE/voice/.venv/bin/python" -r voice/requirements.txt
fi
systemctl --user restart room.service
echo "Room updated to $(git log -1 --format='%h · %s')"
