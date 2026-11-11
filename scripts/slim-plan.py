#!/usr/bin/env python3
"""Room's lean kiosk, part 2 — the PLAN only (changes nothing): what could be removed, and why everything else stays.

Keep set = (1) every package owning a running program or a library one has loaded, (2) KEEP below (+ Fedora's core
group), (3) everything those require, followed all the way down. Everything installed outside it is a candidate.
Written to ~/room-slim-plan.txt. Removing is a separate step, after the list has been read.
Run with sudo (to see what the system's own services have loaded):  sudo python3 scripts/slim-plan.py
"""
import fnmatch, glob, os, subprocess, sys
import rpm

KEEP = """
kernel* kernel-surface* linux-firmware* *-firmware iptsd libwacom* surface-* grub2* shim* efibootmgr efivar* dracut*
mokutil systemd* dnf* rpm* libdnf* sudo openssh* passwd shadow-utils authselect* pam* sssd* selinux-policy*
policycoreutils* audit* NetworkManager* wpa_supplicant iw iwd crda wireless-regdb bluez* pipewire* wireplumber*
alsa-* avahi* nss-mdns cage greetd* firefox* mozilla-* tuned* thermald iio-sensor-proxy upower* rtkit firewalld*
chrony python3* python-unversioned-command uv git* gcc* make cmake autoconf automake libtool pkgconf* *-devel
curl wget2* unzip tar xz gzip bzip2 zstd less vim-minimal nano which procps-ng util-linux* coreutils* findutils
grep sed gawk diffutils file psmisc lsof strace bash* hostname iproute* iputils ethtool ca-certificates tzdata
glibc* glibc-langpack-en langpacks-core-en langpacks-en smartmontools mcelog fwupd* polkit* dbus* xdg-utils
google-noto-sans-fonts google-noto-sans-mono-fonts google-noto-sans-devanagari* google-noto-emoji* dejavu*
liberation* default-fonts-core* fontconfig* mesa* libglvnd* libdrm vulkan* intel-media* libva* xcb-util* libxkbcommon*
libinput* wlroots* seatd libseat* xorg-x11-server-Xwayland qt6-qtwayland pciutils usbutils lm_sensors
""".split()

def installed():
    ts = rpm.TransactionSet()
    return {h[rpm.RPMTAG_NAME]: h for h in ts.dbMatch()}

def owner(path, ts):
    for h in ts.dbMatch("basenames", path):
        return h[rpm.RPMTAG_NAME]

def running(ts):
    files = set()
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            files.add(os.path.realpath(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/maps") as f:
                for line in f:
                    parts = line.split()
                    p = parts[5] if len(parts) >= 6 else ""
                    if p.startswith("/") and (".so" in p or "/bin/" in p or "/libexec/" in p):
                        files.add(p)
        except (OSError, IndexError):
            pass
    names = set()
    for p in files:
        n = owner(p, ts)
        if n:
            names.add(n)
    return names

def core_group():
    out = subprocess.run(["dnf", "-q", "group", "info", "core"], capture_output=True, text=True).stdout
    return {l.split(":", 1)[-1].strip().split()[0] for l in out.splitlines()
            if l.strip() and ":" in l and l.split(":", 1)[0].strip() in ("Mandatory packages", "Default packages", "")} - {""}

def closure(start, pkgs, ts):
    keep, todo = set(), list(start)
    while todo:
        n = todo.pop()
        if n in keep or n not in pkgs:
            continue
        keep.add(n)
        for req in pkgs[n][rpm.RPMTAG_REQUIRENAME] or []:
            if req.startswith("rpmlib(") or req.startswith("/bin/sh"):
                pass
            for h in ts.dbMatch("providename", req) if not req.startswith("/") else ts.dbMatch("basenames", req):
                m = h[rpm.RPMTAG_NAME]
                if m not in keep:
                    todo.append(m)
    return keep

def main():
    ts = rpm.TransactionSet()
    pkgs = installed()
    run = running(ts)
    explicit = {n for n in pkgs for pat in KEEP if fnmatch.fnmatch(n, pat)}
    core = core_group()
    keep = closure(run | explicit | (core & set(pkgs)), pkgs, ts)
    cand = sorted(set(pkgs) - keep, key=lambda n: -(pkgs[n][rpm.RPMTAG_SIZE] or 0))
    size = lambda n: (pkgs[n][rpm.RPMTAG_SIZE] or 0) / 1048576
    # anything that sounds important but ended up a candidate: shown first, to be checked by eye
    watch = ("pipewire", "wireplumber", "network", "bluez", "mesa", "python", "qt", "libva", "wayland", "drm",
             "firmware", "kernel", "audio", "alsa", "sound", "avahi", "dbus", "polkit", "systemd", "glib2", "gstreamer",
             "openssl", "ffmpeg", "libav", "font", "input", "seat", "ssh", "sudo", "dnf")
    out = [f"Room slim plan — {len(pkgs)} installed · keep {len(keep)} · candidates {len(cand)} "
           f"({sum(size(n) for n in cand):.0f} MB)",
           f"(kept because running: {len(run)} packages · explicit keep list: {len(explicit)} · core group: {len(core)})", "",
           "== candidates that sound important — check these by eye"]
    out += [f"{size(n):7.1f}  {n}  — {pkgs[n][rpm.RPMTAG_SUMMARY]}" for n in cand if any(w in n.lower() for w in watch)]
    out += ["", "== all candidates (largest first)"]
    out += [f"{size(n):7.1f}  {n}  — {pkgs[n][rpm.RPMTAG_SUMMARY]}" for n in cand]
    out += ["", "== kept because something running uses them (for reference)"] + sorted(run)
    who = os.environ.get("SUDO_USER") or ""
    path = os.path.join(os.path.expanduser(f"~{who}"), "room-slim-plan.txt")
    open(path, "w").write("\n".join(out) + "\n")
    if who:
        import pwd
        pw = pwd.getpwnam(who); os.chown(path, pw.pw_uid, pw.pw_gid)
    print(out[0]); print(out[1]); print(f"→ {path}")

if __name__ == "__main__":
    main()
