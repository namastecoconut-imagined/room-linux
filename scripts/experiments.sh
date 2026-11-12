#!/usr/bin/env bash
# experiments — what trying things out has left on the Surface, and how to take it back off.
#   bash ~/room/scripts/experiments.sh          list what's still there (changes nothing)
#   bash ~/room/scripts/experiments.sh clean    remove it all (asks for your password for the packages)
# Every experiment adds its leftovers below as it goes: packages it installed, files it wrote, services it added.
# A package is removed by undoing the very dnf transaction that installed it, so whatever it pulled in goes too and
# nothing that was there before is touched.
set -uo pipefail
CLEAN=$([ "${1:-}" = clean ] && echo 1 || echo 0)

# ---------------------------------------------------------------- the list
# packages installed for an experiment (the dnf command line that installed each)
PACKAGES=(
  "libcamera-tools"     # 12 Nov · the camera tests (cam)
  "v4l-utils"           # 12 Nov · the IR camera tests (media-ctl, v4l2-ctl)
  "i2c-tools"           # 12 Nov · the IR lights test (i2ctransfer, for ir-capture.sh lit)
)
# files an experiment wrote in your home folder
FILES=(
  "$HOME/room-camera-front.jpg"   # 12 Nov · camera-test.sh
  "$HOME/room-camera-back.jpg"    # 12 Nov · camera-test.sh back
  "$HOME/room-ir.jpg"             # 12 Nov · ir-capture.sh
  "$HOME/room-ir-lit.jpg"         # 12 Nov · ir-capture.sh lit
)
# services an experiment added (none so far)
SERVICES=()
# Not on the Surface — on the Mac, delete by hand when done: ~/Downloads/room-camera-front.jpg, ~/Downloads/room-ir.jpg,
# ~/Downloads/room-ir-lit.jpg, ~/Downloads/RoomPanel/Kasero.otf (the copy for installing the font; the font itself
# lives in ~/.config/room/fonts).
# In the repo, the experiment's scripts (camera-test.sh, ir-check.sh, ir-capture.sh) go in a commit when an
# experiment ends without becoming a feature. Gone by themselves at the next restart: the IR camera's pipeline link
# and the i2c-dev kernel module (both from ir-capture.sh); the IR lights' sensor settings go when each capture stops.

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
  if [ "$CLEAN" = 1 ]; then rm -f "$f" && echo "  ✓ $(basename "$f") removed"; else echo "  • $f"; fi
done

echo "== Services"
[ ${#SERVICES[@]} -eq 0 ] && echo "  · none added"
for s in "${SERVICES[@]}"; do
  if [ "$CLEAN" = 1 ]; then systemctl --user disable --now "$s" 2>/dev/null; rm -f "$HOME/.config/systemd/user/$s"; echo "  ✓ $s removed"
  else systemctl --user is-enabled "$s" >/dev/null 2>&1 && echo "  • $s" || echo "  · $s — not there"; fi
done
[ "$CLEAN" = 1 ] || echo; [ "$CLEAN" = 1 ] || echo "  (bash ~/room/scripts/experiments.sh clean removes the • ones)"
