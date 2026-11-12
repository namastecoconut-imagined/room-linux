#!/usr/bin/env bash
# Lets Room read the Surface's own buttons (volume up/down, power) straight from the hardware (room/buttons.py), so
# they work whatever window is in front — the web browser too: a window only gets keys while it's in front.
# Only those buttons (the "gpio-keys" devices — not the keyboard), and only for whoever is signed in at the screen
# (udev's "uaccess", the same way the sound and the touchscreen are given). Safe to run again.
#   bash ~/room/scripts/buttons.sh          give it
#   bash ~/room/scripts/buttons.sh undo     take it back (the buttons then work only while Room is in front)
set -e
R=/etc/udev/rules.d/70-room-buttons.rules
again() { sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=input --action=change && sudo udevadm settle; }
if [ "${1:-}" = undo ]; then
  sudo rm -f "$R"; again; echo "✓ Undone: the buttons work only while Room is in front"; exit 0
fi
printf '%s\n' "# Room (scripts/buttons.sh): the Surface's volume and power buttons, for whoever is signed in at the screen" \
  'SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="gpio-keys", TAG+="uaccess"' | sudo tee "$R" >/dev/null
again
found=0
for d in /sys/class/input/event*; do
  [ "$(cat "$d/device/name" 2>/dev/null)" = gpio-keys ] || continue
  found=1; e=/dev/input/$(basename "$d")
  if [ -r "$e" ]; then echo "  ✓ $e — Room can read it"; else echo "  ✗ $e — not readable yet (is someone signed in at the screen?)"; fi
done
[ $found = 1 ] || echo "  ✗ no gpio-keys device found"
echo "✓ Room picks it up within 30 s (or now: systemctl --user restart room)"
