#!/usr/bin/env bash
# Room without the GNOME desktop: the Surface starts straight into Room — cage (a tiny full-screen window host) and
# Room, no GNOME shell, panels, search, notifications or animations. GNOME stays installed; nothing is uninstalled.
#
# It starts through greetd, a tiny login manager made for kiosks, not GDM: GDM brought up its own login screen a few
# seconds after signing in by itself, over Room — asking for the password, and going back to Room once given.
#   room-kiosk on [now]    from the next start (or right now), the Surface boots straight into Room via greetd
#   room-kiosk off [now]   back to GDM and the GNOME desktop from the next start (or right now)
#   room-kiosk             which one is set
# Escape hatches: SSH always works; Ctrl+Alt+F3 gives a text login; and if Room stops for good, greetd shows a text
# login on the screen — sign in, then room-kiosk off.
set -e
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
U="$(id -un)"
ACC="/org/freedesktop/Accounts/User$(id -u)"
session() { busctl get-property org.freedesktop.Accounts "$ACC" org.freedesktop.Accounts.User Session 2>/dev/null | cut -d'"' -f2; }
set_session() {
  busctl call org.freedesktop.Accounts "$ACC" org.freedesktop.Accounts.User SetSession s "$1" >/dev/null 2>&1 && return
  if ! sudo busctl call org.freedesktop.Accounts "$ACC" org.freedesktop.Accounts.User SetSession s "$1" >/dev/null 2>&1; then
    # older AccountsService: the same setting, in its file
    F="/var/lib/AccountsService/users/$U"
    sudo touch "$F"
    sudo sed -i '/^Session=/d;/^XSession=/d' "$F"
    sudo grep -q '^\[User\]' "$F" 2>/dev/null || echo "[User]" | sudo tee -a "$F" >/dev/null
    sudo sed -i "/^\[User\]/a Session=$1" "$F"
  fi
}

case "$1" in
on)
  echo "▸ cage (the full-screen host)"
  rpm -q cage >/dev/null 2>&1 || sudo dnf install -y -q cage

  echo "▸ The power button: screen off / on (Room handles it), not shutting down"
  # Without GNOME, a press of the power button shuts the Surface down (the system default). Now the system leaves a
  # press to Room — screen off; press again (or a sound, a touch) and it's back. Holding the
  # button for a few seconds still turns the Surface off.
  sudo mkdir -p /etc/systemd/logind.conf.d
  printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=poweroff\nHandleSuspendKey=ignore\n' \
    | sudo tee /etc/systemd/logind.conf.d/room-panel.conf >/dev/null
  sudo systemctl kill -s HUP systemd-logind 2>/dev/null || true

  bash "$(dirname "$(readlink -f "$0")")/no-suspend.sh"

  echo "▸ Wi-Fi passwords where the system can reach them without the desktop"
  # Saved from GNOME's settings, a Wi-Fi password usually lives in your desktop keyring, which won't be running
  # without GNOME — the Surface would come up with no Wi-Fi. Each saved network's password is copied to the system.
  nmcli -t -f NAME,TYPE connection show | while IFS=: read -r name type; do
    [ "$type" = "802-11-wireless" ] || continue
    flags=$(nmcli -g 802-11-wireless-security.psk-flags connection show "$name" 2>/dev/null | cut -c1 || true)
    [ "$flags" = "1" ] || continue
    psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$name" 2>/dev/null || true)
    if [ -n "$psk" ]; then
      sudo nmcli connection modify "$name" 802-11-wireless-security.psk-flags 0 802-11-wireless-security.psk "$psk" \
        && echo "  ✓ $name"
    else
      echo "  ! $name — couldn't read its password (connect to it once in GNOME, then run this again)"
    fi
  done

  echo "▸ The \"Room (panel only)\" session"
  sudo tee /usr/local/bin/room-panel-session >/dev/null <<EOF
#!/bin/sh
# Room's panel session (made by $HERE/scripts/kiosk.sh)
export XDG_CURRENT_DESKTOP=Room XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland
exec cage -d -s -- "$HERE/scripts/kiosk-run.sh"
EOF
  sudo chmod +x /usr/local/bin/room-panel-session
  sudo tee /usr/share/wayland-sessions/room-panel.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Room (panel only)
Comment=Just the Room panel, no desktop
Exec=/usr/local/bin/room-panel-session
Type=Application
DesktopNames=Room
EOF
  chmod +x "$HERE/scripts/kiosk-run.sh"

  echo "▸ Start straight into Room with greetd (no login screen)"
  # greetd: a tiny login manager made for kiosks. At boot it signs in by itself and runs the Room session above;
  # if Room ever stops for good, it shows a plain text login on the screen (sign in, then room-kiosk off for GNOME).
  # It replaces GDM, which brought up its own login screen over Room a few seconds after signing in by itself.
  rpm -q greetd >/dev/null 2>&1 || sudo dnf install -y -q greetd
  G=$(getent passwd greetd >/dev/null && echo greetd || echo greeter)
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
# Room's kiosk (scripts/kiosk.sh): sign in by itself into the Room session; a text login if it ever ends
[terminal]
vt = 1

[default_session]
command = "agreety --cmd /bin/bash"
user = "$G"

[initial_session]
command = "/usr/local/bin/room-panel-session"
user = "$U"
TOML
  # (an earlier try ran the session as its own system service — it never got a working screen; gone)
  if [ -f /etc/systemd/system/room-panel.service ]; then
    sudo systemctl disable -q room-panel.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/room-panel.service /etc/pam.d/room-panel
  fi
  sudo systemctl daemon-reload
  if [ "${2:-}" = "now" ]; then
    # switch live, without restarting — SSH keeps working; room-kiosk off brings GDM back the same way
    sudo systemctl stop gdm.service 2>/dev/null || true
    sudo systemctl start greetd.service
    echo "  greetd is running now — Room should be on the screen in a few seconds"
  fi
  sudo systemctl disable -q gdm.service 2>/dev/null || true
  sudo systemctl enable -q greetd.service 2>/dev/null || true
  # it has to be THE display manager for the boot to start it (its unit is usually an alias of display-manager)
  if [ "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" != "$(systemctl show -p FragmentPath --value greetd.service)" ]; then
    sudo ln -sf "$(systemctl show -p FragmentPath --value greetd.service)" /etc/systemd/system/display-manager.service
    sudo systemctl daemon-reload
  fi
  sudo systemctl set-default -q graphical.target
  command -v agreety >/dev/null || echo "  ! agreety (greetd's text login) isn't installed — if Room ever stops, use SSH or Ctrl+Alt+F3"
  echo "  boot display manager: $(basename "$(readlink -f /etc/systemd/system/display-manager.service)")"

  echo "▸ (GDM keeps signing in by itself into Room too, for room-kiosk off and back)"
  if ! grep -q "^AutomaticLogin=$U" /etc/gdm/custom.conf 2>/dev/null; then
    sudo cp -n /etc/gdm/custom.conf /etc/gdm/custom.conf.before-room 2>/dev/null || true
    sudo python3 - "$U" <<'P'
import sys, re
u, p = sys.argv[1], "/etc/gdm/custom.conf"
try:
    s = open(p).read()
except FileNotFoundError:
    s = "[daemon]\n"
if "[daemon]" not in s:
    s = "[daemon]\n" + s
s = re.sub(r"(?m)^\s*#?\s*AutomaticLoginEnable\s*=.*\n", "", s)
s = re.sub(r"(?m)^\s*#?\s*AutomaticLogin\s*=.*\n", "", s)
s = s.replace("[daemon]\n", f"[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin={u}\n", 1)
open(p, "w").write(s)
P
  fi
  set_session room-panel
  echo "✓ Set. Restart the Surface and it comes up as just the panel (room-kiosk off to go back)."
  echo "  If it ever comes up to a black screen: Ctrl+Alt+F3, sign in, room-kiosk off, restart."
  ;;
off)
  sudo systemctl disable -q room-panel.service 2>/dev/null || true
  sudo systemctl disable -q greetd.service 2>/dev/null || true
  sudo systemctl enable -q gdm.service
  if [ "${2:-}" = "now" ]; then
    sudo systemctl stop greetd.service 2>/dev/null || true
    sudo systemctl start gdm.service
  fi
  set_session gnome
  echo "✓ Back to GNOME from the next start (signing in by itself stays on). Restart the Surface when you like."
  ;;
*)
  if systemctl is-enabled -q greetd.service 2>/dev/null; then echo "Starts into: Room only, via greetd (room-kiosk off for GNOME)"
  else s=$(session); echo "Starts into: ${s:-GNOME} (room-kiosk on for Room only)"; fi
  ;;
esac
