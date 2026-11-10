#!/usr/bin/env bash
# Puts the Surface's sound back to full: output through the Dolby speaker tuning, every level at full except Master (4 dB under — the speakers crackle at the very top), nothing muted.
D=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -i dolby | grep -oE '[0-9]+\.' | head -1 | tr -d .)
R=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -i "Built-in Audio" | grep -oE '[0-9]+\.' | head -1 | tr -d .)
[ -n "$R" ] && { wpctl set-volume "$R" 1.0; wpctl set-mute "$R" 0; }
if [ -n "$D" ]; then wpctl set-default "$D"; wpctl set-volume "$D" 1.0; wpctl set-mute "$D" 0; fi
for c in Speaker PCM; do amixer -q -c 0 sset "$c" 100% unmute 2>/dev/null; done
amixer -q -c 0 sset Master -4dB unmute 2>/dev/null     # a little under the top: the speakers crackle at full
echo "Output now:"; wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -v Sources
amixer -c 0 sget Master 2>/dev/null | tail -1
