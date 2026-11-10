#!/usr/bin/env bash
# The Surface's speaker tuning (Dolby_Balanced.conf, made by ee_to_pipewire.py) has its limiter in the middle: the
# "virtual bass" part (two saturators, drive 4) is added AFTER it, so loud music or Room's voice can go over full
# scale and crackle. This adds one more limiter at the very end (−1.5 dB, 5 ms look-ahead), so nothing leaves the
# tuning too loud for the speakers. The original is kept as Dolby_Balanced.conf.orig. Safe to run again.
set -euo pipefail
F="$HOME/.config/pipewire/pipewire.conf.d/Dolby_Balanced.conf"
[ -f "$F" ] || { echo "✗ No speaker tuning at $F"; exit 1; }
if grep -q final_limit "$F"; then echo "✓ The end limiter is already in"; exit 0; fi
cp -n "$F" "$F.orig"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
node = '''                } {
                    type = "lv2"
                    name = "final_limit"
                    plugin = "http://lsp-plug.in/plugins/lv2/limiter_stereo"
                    control = {
                        mode = 0
                        g_in = 1
                        g_out = 1
                        th = 0.8413951416
                        lk = 5
                        at = 1
                        rt = 20
                        slink = 100
                        alr = 1
                        alr_at = 10
                        alr_rt = 200
                        knee = 1
                        smooth = -5
                        boost = 0
                    }
                } ]
                links = [ {'''
a = "                } ]\n                links = [ {"
assert s.count(a) == 1, "nodes end not found"
s = s.replace(a, node, 1)
links = '''                } {
                    output = "vbe_mix_l:Out"
                    input = "final_limit:in_l"
                } {
                    output = "vbe_mix_r:Out"
                    input = "final_limit:in_r"
                } ]
                inputs = ['''
b = "                } ]\n                inputs = ["
assert s.count(b) == 1, "links end not found"
s = s.replace(b, links, 1)
c = 'outputs = [ "vbe_mix_l:Out" "vbe_mix_r:Out" ]'
assert s.count(c) == 1, "outputs not found"
s = s.replace(c, 'outputs = [ "final_limit:out_l" "final_limit:out_r" ]', 1)
open(p, "w").write(s)
PY
echo "▸ Restarting the sound system (a second of silence; a Bluetooth speaker may need reconnecting)"
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 4
if wpctl status | grep -qi dolby; then
  echo "✓ Speaker tuning back, now with the end limiter"
else
  echo "✗ The tuning didn't load — putting the original back"
  cp "$F.orig" "$F"; systemctl --user restart pipewire pipewire-pulse wireplumber
fi
