#!/usr/bin/env bash
# Read-only: what Windows did to the Surface's mics (from Microsoft's Surface Pro 6 driver package) next to what Linux
# does now. Changes nothing. Writes ~/room-mic-report.txt.
set -uo pipefail
OUT="$HOME/room-mic-report.txt"
CACHE="$HOME/.cache/room"; X="$CACHE/sp6-driver"
mkdir -p "$CACHE"
exec > >(tee "$OUT") 2>&1

echo "=== Linux: the mic hardware and its controls"
for c in /proc/asound/card*/codec#*; do echo "--- $c"; grep -iE '^Codec|Subsystem' "$c"; done
arecord -l 2>/dev/null
amixer -c 0 contents 2>/dev/null | grep -iA3 -E "mic|capture|boost|dmic" | head -60
echo "--- PipeWire source"
wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -E "node.name|node.description|audio.channels|audio.position|api.alsa.path" | head
wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null
echo "--- kernel"
uname -r; sudo dmesg 2>/dev/null | grep -iE "dmic|sof|snd_hda|autoconfig|input.*mic" | head -15

echo; echo "=== Windows: the driver package"
command -v msiextract >/dev/null || sudo dnf install -y -q msitools >/dev/null
MSI=$(ls -t "$HOME"/Downloads/SurfacePro6*.msi "$CACHE"/SurfacePro6*.msi 2>/dev/null | head -1 || true)
if [ -z "$MSI" ]; then
  URL=$(curl -sL "https://www.microsoft.com/en-us/download/details.aspx?id=57514" | grep -oE 'https://download\.microsoft\.com/[^"]*SurfacePro6_Win1[01]_[^"]*\.msi' | sort -u | tail -1 || true)
  if [ -z "$URL" ]; then
    echo "✗ couldn't find the download link. Download the SurfacePro6 …msi from"
    echo "  https://www.microsoft.com/en-us/download/details.aspx?id=57514"
    echo "  into Downloads, then run me again."
    exit 1
  fi
  MSI="$CACHE/$(basename "$URL")"
  echo "downloading $(basename "$URL")…"
  curl -sL --fail -o "$MSI.part" "$URL" && mv "$MSI.part" "$MSI"
fi
echo "$MSI"
if [ ! -d "$X" ]; then mkdir -p "$X"; (cd "$X" && msiextract -q "$MSI" >/dev/null 2>&1 || msiextract "$MSI" >/dev/null); fi
echo "--- audio driver files"
find "$X" -iname "*.inf" | grep -iE "hdx|realtek|audio|sst|intcaudio|dmic|mic|rtk" | head -20
INFS=$(find "$X" -iname "*.inf" -exec grep -liE "10EC|0298|DAX2|Realtek|IntcSST|DMIC" {} + 2>/dev/null | head -12)
echo "--- mic / capture settings in them"
for f in $INFS; do
  echo "##### $(basename "$f")"
  grep -iE "mic|capture|record|dmic|array|beam|noise|aec|agc|boost|geometry|_MIC|SFX|MFX|EFX|APO|KSNODETYPE" "$f" \
    | grep -viE "^;|copyright|DriverVer" | sort -u | head -80
done
echo "--- Dolby presets for capture, if any"
grep -hioE "DAX2Preset[0-9A-F]+_[A-Z]+" $INFS 2>/dev/null | sort | uniq -c | head -20
echo; echo "✓ Saved to $OUT"
