#!/usr/bin/env bash
# One-time clean-up: everything the listening experiments put on the Surface comes off, and the mics go back to
# Fedora's own defaults. Room's speaking voice, the Claude brain, the speakers (your Dolby tuning) and AirPlay are left
# alone. Safe to run twice.
set -uo pipefail
echo "▸ Stopping and removing the offline speech recognition (whisper)"
systemctl --user disable --now room-whisper.service 2>/dev/null
rm -f ~/.config/systemd/user/room-whisper.service ~/.local/bin/room-whisper-server
systemctl --user daemon-reload
rm -rf ~/.local/share/room/whisper ~/.local/src/whisper.cpp

echo "▸ Removing the listening packages from Room's voice Python"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
if [ -x "$HERE/voice/.venv/bin/python" ] && command -v uv >/dev/null; then
  uv pip uninstall -q --python "$HERE/voice/.venv/bin/python" openwakeword webrtc-noise-gain pvporcupine scikit-learn \
    websockets scipy tqdm 2>/dev/null || true
fi

echo "▸ Removing the wake-word models and Room's mic leftovers"
rm -rf ~/.local/share/room/voice/oww ~/.local/share/room/voice/cues

echo "▸ Removing recordings, reports and downloads"
rm -rf ~/room-heard ~/.cache/room/sp6-driver
rm -f ~/.cache/room/SurfacePro6*.msi* ~/Downloads/SurfacePro6*.msi
rm -f ~/room-mic-*.wav ~/room-mic-report.txt ~/room-mic-tune.txt ~/room-mic-check.txt ~/room-mic-stereo.wav \
      ~/room-sound-report.txt ~/room-windows-audio.txt ~/room-log.txt

echo "▸ Taking the mic settings out of Room's config"
python3 - <<'P'
import json, os
for p in (os.path.expanduser("~/.config/room/config.json"), os.path.expanduser("~/room/config.json")):
    if not os.path.exists(p):
        continue
    c = json.load(open(p))
    vs = c.get("voiceSettings") or {}
    gone = [k for k in list(vs) if k.startswith("mic") or k in ("noiseSuppression", "highPassHz", "maxGain", "beam",
            "wakeThreshold", "wakeCandidate", "wakeConfident", "bargeIn", "keepAudio", "language", "endpointMs",
            "echoCancel", "deepgramModel", "picovoiceKey", "whisperURL")]
    for k in gone:
        vs.pop(k)
    json.dump(c, open(p, "w"), indent=2)
    print("  removed:", ", ".join(gone) or "nothing to remove", "→", p)
P

echo "▸ Mics back to Fedora's defaults"
# forget the input levels PipeWire remembered, then let it set the chip up its own way again
ST=~/.local/state/wireplumber
for f in "$ST/default-routes" "$ST/default-nodes" "$ST/stream-properties"; do
  [ -f "$f" ] && sed -i -E '/:input:|alsa_input|^Input\/Audio/d' "$f"
done
systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null; sleep 3
systemctl --user restart room-airplay.service 2>/dev/null
echo "  mic: $(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)  ·  chip: boost $(amixer -c 0 cget name='Internal Mic Boost Volume' 2>/dev/null | grep -o 'values=[0-9,]*' | tail -1), capture $(amixer -c 0 cget name='Capture Volume' 2>/dev/null | grep -o 'values=[0-9,]*' | tail -1)"

systemctl --user restart room.service 2>/dev/null
echo "✓ Clean. Room still talks and thinks; listening is off until it's rebuilt."
