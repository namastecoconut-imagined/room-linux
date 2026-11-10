#!/usr/bin/env bash
# Room without the GNOME desktop: the Surface starts straight into Room — cage (a tiny full-screen window host) and
# Room, no GNOME shell, panels, search, notifications or animations. GNOME stays installed; nothing is uninstalled.
#
# It starts as a system service on the first screen (room-panel.service), not through GDM's automatic sign-in: GDM
# brought up its own login screen a few seconds after signing in by itself, over Room — asking for the password, and
# going back to Room once given. With the service, GDM isn't started at all in kiosk mode (room-kiosk off brings it
# back), and if Room ever stops for good, GDM's login screen comes up so you can pick GNOME.
#   room-kiosk on    from the next start, the Surface boots straight into Room
#   room-kiosk off   back to the normal GNOME desktop from the next start
#   room-kiosk       which one is set
# Escape hatch: Ctrl+Alt+F3 gives a text login at any time; and if Room stops, you land on the login screen, where
# the gear button lets you pick "GNOME".
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

  echo "▸ Start straight into Room (a service on the first screen — no login screen)"
  sudo tee /etc/pam.d/room-panel >/dev/null <<'PAM'
# Room's kiosk session (scripts/kiosk.sh): a logind session on seat0 for cage — no password, no keyring
account  required pam_unix.so
session  required pam_loginuid.so
session  optional pam_keyinit.so force revoke
session  required pam_unix.so
session  required pam_systemd.so
PAM
  sudo tee /etc/systemd/system/room-panel.service >/dev/null <<UNIT
[Unit]
Description=Room panel (kiosk: cage on the first screen, no desktop)
After=systemd-user-sessions.service plymouth-quit-wait.service dbus.socket systemd-logind.service getty@tty1.service
Wants=dbus.socket systemd-logind.service
Conflicts=getty@tty1.service gdm.service
ConditionPathExists=/dev/tty0

[Service]
Type=simple
User=$U
WorkingDirectory=$HOME
PAMName=room-panel
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
Environment=XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SEAT=seat0 XDG_VTNR=1
ExecStart=/usr/local/bin/room-panel-session
# Room stopped and the panel session ended: the normal login screen, to pick GNOME (or Room) there
ExecStopPost=-/usr/bin/systemctl start --no-block gdm.service
Restart=no

[Install]
WantedBy=graphical.target
UNIT
  sudo systemctl daemon-reload
  sudo systemctl disable -q gdm.service
  sudo systemctl enable -q room-panel.service
  sudo systemctl set-default -q graphical.target

  echo "▸ (and GDM's own automatic sign-in into Room, for when GDM is started by hand)"
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
  sudo systemctl enable -q gdm.service
  set_session gnome
  echo "✓ Back to GNOME from the next start (signing in by itself stays on). Restart the Surface when you like."
  ;;
*)
  if systemctl is-enabled -q room-panel.service 2>/dev/null; then echo "Starts into: Room only (room-kiosk off for GNOME)"
  else s=$(session); echo "Starts into: ${s:-GNOME} (room-kiosk on for Room only)"; fi
  ;;
esac
