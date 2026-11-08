#!/usr/bin/env bash
# The Surface's speakers, tuned the way Windows tuned them. Windows ran Dolby Audio Premium on them — a per-speaker
# curve (deep bass cut, upper bass +10 dB, boxy mids down, treble up) plus a limiter that keeps them from distorting.
# Linux plays them raw, which is why they sound thin. The tuning is in Microsoft's own Surface Pro 6 driver package;
# speaker-tuning-to-easyeffects reads it and rebuilds it as a PipeWire filter (always on, no app needed).
#
#   bash scripts/speakers.sh          set it up
#   bash scripts/speakers.sh --undo   back to how it was
set -uo pipefail
trap 'echo "✗ stopped at line $LINENO — send me the lines above"' ERR
CONF="$HOME/.config/pipewire/pipewire.conf.d"
BACK="$HOME/.config/pipewire/room-before-dolby"
TOOL="$HOME/.local/share/room/speaker-tuning"
CACHE="$HOME/.cache/room"
mkdir -p "$CONF" "$CACHE"

restart() { systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true; sleep 2; }

if [ "${1:-}" = "--undo" ]; then
  echo "▸ Removing the Dolby tuning"
  rm -f "$CONF"/Dolby_*.conf "$CONF"/Dolby_*.irs "$CONF"/dolby*.conf
  if [ -d "$BACK" ]; then mv "$BACK"/* "$CONF"/ 2>/dev/null || true; rmdir "$BACK" 2>/dev/null || true; echo "  your earlier filters are back"; fi
  restart
  echo "✓ Speakers back to how they were"
  exit 0
fi

echo "▸ Sound chip"
grep -iE '^Codec|Subsystem' /proc/asound/card*/codec#0 2>/dev/null | head -4 || echo "  (couldn't read it — carrying on)"

echo "▸ What the converter needs"
sudo dnf install -y --skip-unavailable python3-numpy python3-scipy lsp-plugins-lv2 lv2-calf-plugins pipewire-utils \
  msitools innoextract git >/dev/null
echo "  ok"

echo "▸ The converter (speaker-tuning-to-easyeffects)"
if [ -d "$TOOL/.git" ]; then git -C "$TOOL" pull -q; else git clone -q https://github.com/antoinecellerier/speaker-tuning-to-easyeffects "$TOOL"; fi
echo "  $(git -C "$TOOL" log -1 --format='%h · %cs')"

echo "▸ Microsoft's Surface Pro 6 driver package"
MSI=$(ls -t "$HOME"/Downloads/SurfacePro6*.msi "$CACHE"/SurfacePro6*.msi 2>/dev/null | head -1 || true)
if [ -z "$MSI" ]; then
  URL=$(curl -sL "https://www.microsoft.com/en-us/download/details.aspx?id=57514" | grep -oE 'https://download\.microsoft\.com/[^"]*SurfacePro6_Win1[01]_[^"]*\.msi' | sort -u | tail -1 || true)
  if [ -z "$URL" ]; then
    echo "  ✗ couldn't find the download link. Open this page, download the SurfacePro6 …msi into Downloads, then run me again:"
    echo "    https://www.microsoft.com/en-us/download/details.aspx?id=57514"
    exit 1
  fi
  MSI="$CACHE/$(basename "$URL")"
  echo "  downloading $(basename "$URL") (a few hundred MB)…"
  curl -L --fail -o "$MSI.part" "$URL" && mv "$MSI.part" "$MSI"
fi
echo "  $MSI"

echo "▸ Moving any earlier speaker filters aside (they'd stack with this one)"
mkdir -p "$BACK"
moved=0
for f in "$CONF"/*.conf; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in Dolby_*) continue;; esac
  if grep -q "filter-chain" "$f"; then mv "$f" "$BACK/"; echo "  moved $(basename "$f")"; moved=1; fi
done
[ $moved = 0 ] && { rmdir "$BACK" 2>/dev/null || true; echo "  none"; }

echo "▸ Reading the Dolby tuning and building the filter"
cd "$TOOL"
if ! python3 dolby_to_pipewire.py "$MSI"; then
  echo "  trying its best guess for this model…"
  python3 dolby_to_pipewire.py "$MSI" --best-guess || { echo "✗ the converter couldn't read the Pro 6 package — send me the lines above"; exit 1; }
fi
restart

echo "▸ Check"
python3 dolby_to_pipewire.py --doctor 2>&1 | tail -15 || true
echo
echo "✓ Done. Play something and compare. If it's worse: bash ~/room/scripts/speakers.sh --undo"
