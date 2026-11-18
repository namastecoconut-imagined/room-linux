#!/usr/bin/env bash
# A walk through the four standby scenes, in order, on the panel — then Room goes back to normal.
#   bash ~/room/scripts/scene-tour.sh            (from the Mac: ssh namastecoconut@fedora.local "bash ~/room/scripts/scene-tour.sh")
# Room restarts into the tour (standby straight away; each scene draws on, stays 20 s, then the next), and restarts
# again as usual at the end, or if you stop it with Ctrl+C. Don't touch the screen meanwhile: a tap leaves standby.
set -u
back() {
  systemctl --user unset-environment ROOM_SCREEN
  systemctl --user restart room.service
  echo "Room's back to normal."
}
trap back EXIT
trap 'exit 1' INT TERM
systemctl --user set-environment ROOM_SCREEN=sbtour
systemctl --user restart room.service
echo "Room restarted into the tour: Rooftops, Their room, The shelf wall, The garden (about 2½ minutes)."
n=0
while read -r line; do
  case "$line" in
    *"standby scene: "*)
      n=$((n + 1))
      [ $n -gt 4 ] && break
      echo "  $n of 4 · ${line##*standby scene: }"
      ;;
  esac
done < <(timeout 200 journalctl --user -u room -f -n 0 -o cat)
