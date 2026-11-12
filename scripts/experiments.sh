#!/usr/bin/env bash
# experiments — what trying things out has left on the Surface, and how to take it back off.
#   bash ~/room/scripts/experiments.sh          list what's still there (changes nothing)
#   bash ~/room/scripts/experiments.sh clean    remove it all (asks for your password for the packages)
# Every experiment adds its leftovers below as it goes: packages it installed, files it wrote, services it added.
# A package is removed by undoing the very dnf transaction that installed it, so whatever it pulled in goes too and
# nothing that was there before is touched.
set -uo pipefail
CLEAN=$([ "${1:-}" = clean ] && echo 1 || echo 0)
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

# ---------------------------------------------------------------- the list
# packages installed for an experiment (the dnf command line that installed each)
PACKAGES=(
  "libcamera-tools"     # 12 Nov · the camera tests (cam)
  "v4l-utils"           # 12 Nov · the IR camera tests and gestures (media-ctl, v4l2-ctl)
  "i2c-tools"           # 12 Nov · the IR lights test (i2ctransfer, for ir-capture.sh lit)
)
# files (and folders) an experiment wrote in your home folder
FILES=(
  "$HOME/room-camera-front.jpg"   # 12 Nov · camera-test.sh
  "$HOME/room-camera-back.jpg"    # 12 Nov · camera-test.sh back
  "$HOME/room-ir.jpg"             # 12 Nov · ir-capture.sh
  "$HOME/room-ir-lit.jpg"         # 12 Nov · ir-capture.sh lit
  "$HOME/.cache/room-experiments" # 12 Nov · py-spy, for assistant-profile.sh (a folder)
)
# services an experiment added to your user (none)
SERVICES=()
# system-wide: the IR-lights helper (scripts/irlight.sh, 12 Nov, for gestures — reverted): its socket, its service,
# the helper itself and the i2c-dev module at start
SYSTEM_UNITS=("room-irlight.socket")
SYSTEM_FILES=(
  "/etc/systemd/system/room-irlight.socket"
  "/etc/systemd/system/room-irlight@.service"
  "/usr/local/libexec/room-irlight"
  "/etc/modules-load.d/room-irlight.conf"
)
# Python packages added to Room's own environment (~/room/.venv) for an experiment — removed only while Room's
# requirements.lock doesn't list them
ROOM_PIP=("numpy")                # 12 Nov · gestures (reverted)
# Not on the Surface — on the Mac: ~/Downloads/room-camera-front.jpg, ~/Downloads/room-ir.jpg, ~/Downloads/room-ir-lit.jpg
# (the camera and IR photos), and ~/Downloads/RoomPanel/Kasero.otf (the copy for installing the font; the font itself
# lives in ~/.config/room/fonts — keep that).
# The camera, IR and gesture scripts left the repo when that experiment ended (12 Nov). Gone by themselves at the
# next restart: the IR camera's pipeline link and the i2c-dev kernel module.

# ---------------------------------------------------------------- packages
echo "== Packages"
for p in "${PACKAGES[@]}"; do
  if ! rpm -q "$p" >/dev/null 2>&1; then echo "  · $p — not installed"; continue; fi
  # the transaction whose command line installed it
  id=$(dnf history list 2>/dev/null | awk -v p="$p" '$0 ~ "install" && $0 ~ p {print $1; exit}')
  if [ -z "$id" ]; then echo "  ! $p — installed, but not by a dnf install found in the history; left alone"; continue; fi
  if [ "$CLEAN" = 1 ]; then
    echo "  ▸ $p — undoing dnf transaction $id"; sudo dnf history undo -y "$id" >/dev/null && echo "    ✓ removed"
  else
    echo "  • $p — installed (dnf transaction $id)"
  fi
done

echo "== Files"
for f in "${FILES[@]}"; do
  [ -e "$f" ] || { echo "  · $(basename "$f") — not there"; continue; }
  if [ "$CLEAN" = 1 ]; then rm -rf -- "$f" && echo "  ✓ $(basename "$f") removed"; else echo "  • $f"; fi
done

echo "== Services"
[ ${#SERVICES[@]} -eq 0 ] && echo "  · none added to your user"
for s in "${SERVICES[@]}"; do
  if [ "$CLEAN" = 1 ]; then systemctl --user disable --now "$s" 2>/dev/null; rm -f "$HOME/.config/systemd/user/$s"; echo "  ✓ $s removed"
  else systemctl --user is-enabled "$s" >/dev/null 2>&1 && echo "  • $s" || echo "  · $s — not there"; fi
done

echo "== System (the IR-lights helper)"
there=0
for f in "${SYSTEM_FILES[@]}"; do [ -e "$f" ] && there=1; done
if [ $there = 0 ]; then
  echo "  · not there"
elif [ "$CLEAN" = 1 ]; then
  for u in "${SYSTEM_UNITS[@]}"; do sudo systemctl disable --now "$u" >/dev/null 2>&1 || true; done
  for f in "${SYSTEM_FILES[@]}"; do [ -e "$f" ] && sudo rm -f -- "$f" && echo "  ✓ $f removed"; done
  sudo systemctl daemon-reload
else
  for f in "${SYSTEM_FILES[@]}"; do [ -e "$f" ] && echo "  • $f"; done
fi

echo "== Room's Python"
for p in "${ROOM_PIP[@]}"; do
  if [ ! -x "$HERE/.venv/bin/python" ] || ! "$HERE/.venv/bin/python" -c "import $p" 2>/dev/null; then
    echo "  · $p — not there"
  elif grep -qi "^$p[=<>]" "$HERE/requirements.lock" 2>/dev/null; then
    echo "  · $p — Room needs it now (requirements.lock); left alone"
  elif [ "$CLEAN" = 1 ]; then
    "$HERE/.venv/bin/pip" uninstall -q -y "$p" && echo "  ✓ $p removed"
  else
    echo "  • $p"
  fi
done
[ "$CLEAN" = 1 ] || echo; [ "$CLEAN" = 1 ] || echo "  (bash ~/room/scripts/experiments.sh clean removes the • ones)"
