#!/usr/bin/env bash
# Room's lean kiosk, part 1: switches off background services and timers the kiosk never uses (nothing of GNOME yet).
# Everything is disabled, not uninstalled — `bash lean.sh undo` turns it all back on. Safe to run again.
# Kept on purpose: NetworkManager + wpa_supplicant (Wi-Fi), bluetooth, avahi + nqptp (AirPlay), sshd, firewalld,
# chronyd, thermald (fanless heat control), tuned (the cool profile), iptsd (touch), iio-sensor-proxy, upower,
# rtkit, PipeWire, auditd, smartd, sssd (sign-in).
# Not started at boot, but still there when asked: accounts-daemon (room-kiosk and Settings' "switch to desktop" ask
# it, and it starts by itself then) and udisks2 (a USB drive) — each only while something can still start it on demand.
set -u
SERVICES=(
  cups.service cups.socket cups.path            # printing — no printer
  ModemManager.service                          # mobile modems — none
  rsyslog.service                               # a second copy of every log line (journald keeps them)
  atd.service                                   # one-off scheduled jobs — none
  gssproxy.service                              # Kerberos / network logins — none
  stratisd.service                              # Stratis storage — not used
  switcheroo-control.service                    # dual graphics — one GPU
  uresourced.service                            # GNOME's resource tuning for desktop sessions
  vmtoolsd.service vgauthd.service vboxservice.service qemu-guest-agent.service   # VM helpers — real hardware
)
TIMERS=(
  dnf-makecache.timer        # downloads package lists in the background — updates happen when you run them
  plocate-updatedb.timer     # indexes every file daily — nothing searches
  raid-check.timer           # RAID checks — no RAID
  unbound-anchor.timer       # DNSSEC trust anchor for unbound — not used
)
MASK=(packagekit.service packagekit-offline-update.service)   # GNOME's background updater (21 % CPU seen)
# started only when something asks for them (over D-Bus) — never at boot: service and the name it's asked by
ON_DEMAND=(
  "accounts-daemon.service org.freedesktop.Accounts"   # GNOME's list of users — room-kiosk and "switch to desktop" ask it
  "udisks2.service org.freedesktop.UDisks2"            # mounts USB drives by itself — none plugged in
)

if [ "${1:-}" = "undo" ]; then
  sudo systemctl unmask "${MASK[@]}" 2>/dev/null
  for u in "${SERVICES[@]}" "${TIMERS[@]}" crond.service; do
    systemctl cat "$u" >/dev/null 2>&1 && sudo systemctl enable --now "$u" 2>/dev/null && echo "  on: $u"
  done
  for e in "${ON_DEMAND[@]}"; do
    u=${e%% *}; systemctl cat "$u" >/dev/null 2>&1 && sudo systemctl enable --now "$u" 2>/dev/null && echo "  on: $u"
  done
  homed=$(systemctl list-unit-files systemd-homed.service --no-legend 2>/dev/null)
  [ -n "$homed" ] && sudo systemctl enable --now systemd-homed.service systemd-homed-activate.service 2>/dev/null
  echo "✓ Undone (the 'Install package?' prompt comes back with: sudo dnf install PackageKit-command-not-found)"
  exit 0
fi

echo "▸ Background services the kiosk doesn't use"
for u in "${SERVICES[@]}" "${TIMERS[@]}"; do
  if systemctl cat "$u" >/dev/null 2>&1; then
    if systemctl is-enabled -q "$u" 2>/dev/null || systemctl is-active -q "$u" 2>/dev/null; then
      sudo systemctl disable --now "$u" >/dev/null 2>&1 && echo "  off: $u"
    fi
  fi
done
echo "▸ Only when asked, not at boot (accounts-daemon, udisks2)"
for e in "${ON_DEMAND[@]}"; do
  u=${e%% *}; bus=${e#* }
  systemctl cat "$u" >/dev/null 2>&1 || continue
  # only if D-Bus can still start it on demand — otherwise whatever asks for it would just fail
  if [ ! -f "/usr/share/dbus-1/system-services/$bus.service" ]; then echo "  kept: $u (nothing would start it when asked)"; continue; fi
  if systemctl is-enabled -q "$u" 2>/dev/null || systemctl is-active -q "$u" 2>/dev/null; then
    sudo systemctl disable --now "$u" >/dev/null 2>&1 && echo "  off at boot: $u"
  fi
done
echo "▸ crond (old-style scheduled jobs) — only if there aren't any"
if systemctl is-enabled -q crond.service 2>/dev/null || systemctl is-active -q crond.service 2>/dev/null; then
  # its own plumbing (0hourly, 0anacron) aside: lines in /etc/crontab, files in the cron folders, anyone's crontab
  jobs=$( { grep -hvE '^[[:space:]]*(#|$|[A-Za-z_]+=)' /etc/crontab 2>/dev/null
            sudo find /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /var/spool/cron \
              -mindepth 1 -maxdepth 1 ! -name 0hourly ! -name 0anacron ! -name '.*' 2>/dev/null; } )
  if [ -z "$jobs" ]; then
    sudo systemctl disable --now crond.service >/dev/null 2>&1 && echo "  off: crond (no jobs)"
  else
    echo "  kept: crond has jobs —"; echo "$jobs" | sed 's/^/     /'
  fi
fi
echo "▸ PackageKit (GNOME's updater) — dnf still works whenever you run it"
sudo systemctl stop "${MASK[@]}" 2>/dev/null; sudo systemctl mask "${MASK[@]}" >/dev/null 2>&1 && echo "  masked: ${MASK[*]}"
if rpm -q PackageKit-command-not-found >/dev/null 2>&1; then
  sudo dnf remove -y -q PackageKit-command-not-found >/dev/null 2>&1 && echo "  removed: the 'Install package X?' prompt"
fi
echo "▸ systemd-homed (special home directories) — only if no account uses it"
if systemctl is-active -q systemd-homed.service 2>/dev/null; then
  if [ -z "$(homectl list --no-legend 2>/dev/null)" ]; then
    sudo systemctl disable --now systemd-homed.service systemd-homed-activate.service >/dev/null 2>&1 && echo "  off: systemd-homed"
  else
    echo "  kept: an account uses it"
  fi
fi
echo "✓ Lean. Still running: $(systemctl list-units --type=service --state=running --no-legend | wc -l) system services"
echo "  (undo: bash $(readlink -f "$0") undo)"
