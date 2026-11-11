#!/usr/bin/env python3
"""Room's lean kiosk, part 2: uninstalls what the kiosk never uses — the GNOME desktop and its apps, LibreOffice and
Java, printing and scanning, containers, installers, input methods, … — and keeps everything Room, the system and
Firefox need. Run with sudo (so it sees what the system's own services have loaded):

  sudo python3 scripts/slim.py          the plan only: what would go, what stays and why → ~/room-slim-plan.txt
  sudo python3 scripts/slim.py check    the plan, proven, still changing nothing → ~/room-slim-check.txt:
                                          · a removal test of exactly that list — rpm checks that nothing staying
                                            needs anything going (whatever is needed stays, found automatically)
                                          · dnf's own preview of the same list
  sudo python3 scripts/slim.py apply    removes exactly the list check wrote (plus the Flatpak apps and GNOME's
                                        leftover caches), then rebuilds the boot image without them → ~/room-slim-apply.log
  Undo: sudo dnf history undo <the number apply prints> — every package comes back.

What stays: (1) every package owning a running program or a library one has loaded — so Room, AirPlay, Spotify and
the assistant must be running when this runs (check refuses otherwise), (2) KEEP and STAY below, Fedora's core group,
and the disk tools this disk needs, (3) everything those require, all the way down — including "rich" requirements
like (a if b), whose every name is kept. Everything else installed goes.
"""
import fnmatch, glob, os, pwd, re, shutil, signal, subprocess, sys, time
import rpm

# the kiosk's own needs, and the system's
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

# from reading the first plan by hand: candidates that stay anyway
STAY = {
    "microcode_ctl": "the processor's microcode updates (stability and security fixes)",
    "grubby": "the boot menu's tool — kernel updates use it",
    "kmscon*": "the text console (Ctrl+Alt+F3) stays readable",
    "plymouth*": "the boot screen",
    "fedora-logos": "the boot screen's logo",
    "dosfstools": "checks the boot partition (FAT) at start-up",
    "cracklib-dicts": "changing a password",
    "passwdqc*": "changing a password",
    "libsss_sudo": "sudo asks it first — without it, sudo complains every time",
    "cyrus-sasl-plain": "sign-in plumbing",
    "smartmontools-selinux": "the disk-health monitor's security rules",
    "logrotate": "keeps old logs from piling up",
    "mailcap": "file types (Python reads them)",
    "nano-default-editor": "nano stays the editor",
    "default-editor": "nano stays the editor",
    "openssl": "the TLS tool, for checking certificates",
    "gpg-pubkey": "the repositories' signing keys",
    "google-noto-sans-*": "song titles in other scripts: Chinese, Japanese, Korean, Tamil, Bengali, Arabic, …",
    "rit-meera-new-fonts": "Malayalam song titles",
}
NOT_STAY = ["google-noto-sans-mono-cjk*"]          # (the monospace Chinese/Japanese/Korean — nothing shows code)

# also goes with apply: what the removed apps leave behind (sizes in the check)
LEFTOVERS = ["/var/lib/flatpak", "/var/cache/PackageKit", "/var/lib/PackageKit", "/var/cache/app-info", "/var/lib/gdm",
             "~/.local/share/flatpak", "~/.var/app", "~/.local/share/gnome-shell", "~/.cache/tracker3",
             "~/.cache/gnome-software", "~/.cache/thumbnails", "~/.cache/evolution", "~/.local/share/evolution"]

# what Room needs running while this looks (their libraries count as in use only if they're loaded)
ROOM_UNITS = ["room", "room-assistant", "room-airplay", "room-spotify"]

KINDS = [
    ("GNOME desktop and its apps", """gnome-* gdm mutter* nautilus* gjs mozjs* papers* loupe snapshot showtime decibels
      ptyxis yelp* sushi tecla malcontent* xdg-desktop-portal-* gvfs* localsearch tinysparql evolution-* libgweather*
      gweather-* geoclue* zenity *thumbnailer* glycin-* oo7-* libportal* libhandy libwnck3 vte* gtk2 gtkmm* glibmm*
      cairomm* pangomm* libsigc++* libgtop2 libgee webkitgtk* javascriptcoregtk* epiphany-* *backgrounds*
      fedora-workstation-* fedora-chromium-* fedora-flathub-remote fedora-third-party redhat-menus libcanberra* gsound
      sound-theme-freedesktop wl-clipboard xdg-user-dirs* libmediaart totem-pl-parser rygel gupnp* geocode-glib rest
      msgraph libphonenumber libical-glib colord-gtk4 libeis startup-notification ibus-gtk* xorg-x11-x* xhost xrdb
      xmodmap setxkbmap xdriinfo gcr libspelling gtksourceview* sassc libsass"""),
    ("LibreOffice and Java", """libreoffice* java-* tzdata-java javapackages-* autocorr-* hunspell* hyphen-* mythes*
      libmwaw libetonyek libstaroffice libwps libcdr libvisio libmspub libfreehand libqxp libzmf libpagemaker libabw
      libe-book libepubgen libodfgen librevenge libwpd libwpg liborcus libcmis clucene* libnumbertext liblangtag*
      libexttextcat lpsolve Box2D unoconv antiword libeot raptor2 rasqal redland boost-* xmlsec1* libgsf"""),
    ("Printing and scanning", """cups* hplip* gutenprint* sane* libsane* ipp-usb system-config-printer* paps mpage
      braille-printer-app libieee1284 libgphoto2 net-snmp-libs"""),
    ("Containers, virtual machines, installers, app stores", """podman* toolbox skopeo netavark aardvark-dns crun conmon
      catatonit fuse-overlayfs criu* passt* container* composefs* ostree-libs flatpak* anaconda* livesys-scripts
      kdump-anaconda-addon isomd5sum mediawriter osinfo-db* libosinfo open-vm-tools* virtualbox-* qemu-guest-agent
      spice-* hyperv* PackageKit* appstream-data shadow-utils-subid"""),
    ("Fonts for other scripts and styles", "*-fonts default-fonts-*"),
    ("Typing in other languages", "ibus* anthy* libpinyin* libchewing libhangul m17n* kasumi* cldr-emoji-annotation* unicode-ucd"),
    ("Accessibility and speech", "orca brltty speech-dispatcher* espeak-ng pcaudiolib liblouis*"),
    ("Disk, storage and network-share tools", """btrfs-progs xfsprogs lvm2* stratis* udisks2-* libblockdev-* device-mapper-*
      kpartx cryptsetup clevis* luksmeta libluksmeta tpm2-* nvme-cli ntfs* exfatprogs f2fs-tools nilfs-utils udftools
      hfsplus-tools compsize iscsi* isns-* nfs* rpcbind samba-* cifs-utils wsdd ndctl* daxctl* cxl-*"""),
    ("Remote access, web server, admin console, reporting", """cockpit* httpd* mod_* apr* sscg freerdp* libwinpr
      libvncserver realmd sos fpaste libreport* rsyslog libestr libfastjson mariadb-* xmlrpc-c*"""),
    ("Media codecs and image tools", """gstreamer1* gst-* ffmpeg-free soundtouch libao libmpeg2 liba52 faad2-libs wavpack
      libshout libsrtp pulseaudio-utils libmediainfo libzen taglib exiv2* libgexiv2 exempi LibRaw ImageMagick*
      openexr-libs imath libheif-* libultrahdr kf6-* kde-filesystem qt6-* libmtp usbmuxd"""),
    ("Developer, debugging and network tools", """gdb* binutils cpp libmpc gettext ctags source-highlight libipt tcl tmux
      bc time tree ed xxd zip 7zip dos2unix symlinks lrzsz pinfo man-pages graphviz-libs gd perl-* deltarpm
      distribution-gpg-keys rsync whois* mkpasswd mtr traceroute tcpdump nmap-ncat net-tools bind-* dnsmasq libreswan
      iptables-* ipset* iptstate wcurl"""),
    ("Everything else (libraries the above used, small tools)", "*"),
]
KINDS = [(k, p.split()) for k, p in KINDS]

OPS = {"=", "<", ">", "<=", ">=", "<>"}
WORDS = {"if", "else", "and", "or", "with", "without", "unless"}


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def user_home():
    who = os.environ.get("SUDO_USER") or ""
    home = os.path.expanduser(f"~{who}") if who else os.path.expanduser("~")
    return who, home


def write(path, text, who):
    open(path, "w").write(text)
    if who:
        p = pwd.getpwnam(who)
        os.chown(path, p.pw_uid, p.pw_gid)


def matches(name, pats):
    return any(fnmatch.fnmatch(name, p) for p in pats)


def names_in(req):
    """The package names a requirement mentions — for a rich one like (a if b): a and b (keeping both is safe)."""
    if not req.startswith("("):
        return [req.split()[0]]
    out, skip = [], False
    for t in re.findall(r"[^\s()]+", req):
        if skip:
            skip = False
        elif t in OPS:
            skip = True
        elif t not in WORDS:
            out.append(t)
    return out


class Db:
    def __init__(self):
        self.ts = rpm.TransactionSet()
        self.pkgs = {}
        for h in self.ts.dbMatch():
            self.pkgs.setdefault(h[rpm.RPMTAG_NAME], h)
        self._prov = {}

    def provided(self, req):
        """Installed packages providing a requirement (all names in a rich one)."""
        if req in self._prov:
            return self._prov[req]
        got = set()
        for n in names_in(req):
            mi = self.ts.dbMatch("basenames", n) if n.startswith("/") else self.ts.dbMatch("providename", n)
            for h in mi:
                got.add(h[rpm.RPMTAG_NAME])
        self._prov[req] = got
        return got

    def closure(self, start, have=()):
        keep, todo = set(have), [n for n in start if n in self.pkgs]
        while todo:
            n = todo.pop()
            if n in keep:
                continue
            keep.add(n)
            for req in self.pkgs[n][rpm.RPMTAG_REQUIRENAME] or []:
                if not req.startswith("rpmlib("):
                    todo.extend(m for m in self.provided(req) if m not in keep)
        return keep

    def owner(self, path):
        for h in self.ts.dbMatch("basenames", path):
            return h[rpm.RPMTAG_NAME]

    def size(self, n):
        return (self.pkgs[n][rpm.RPMTAG_SIZE] or 0) if n in self.pkgs else 0

    def summary(self, n):
        return self.pkgs[n][rpm.RPMTAG_SUMMARY] if n in self.pkgs else ""


def running(db):
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
    return {n for n in map(db.owner, files) if n}


def core_group():
    out = sh(["dnf", "-q", "group", "info", "core"]).stdout
    return {l.split(":", 1)[-1].strip().split()[0] for l in out.splitlines()
            if l.strip() and ":" in l and l.split(":", 1)[0].strip() in ("Mandatory packages", "Default packages", "")} - {""}


def disk_keeps():
    """Tools this disk itself needs (Fedora's default is btrfs, no LVM, no encryption — but look)."""
    words = set(sh(["lsblk", "-rno", "TYPE,FSTYPE"]).stdout.split())
    k = {}
    if "btrfs" in words:
        k["btrfs-progs"] = "this disk is btrfs"
    if "xfs" in words:
        k["xfsprogs"] = "this disk has XFS"
    if words & {"lvm", "LVM2_member"}:
        k.update({p: "this disk uses LVM" for p in ("lvm2*", "device-mapper*", "kpartx", "libblockdev-lvm*", "udisks2-lvm2")})
    if words & {"crypt", "crypto_LUKS"}:
        k.update({p: "this disk is encrypted" for p in ("cryptsetup", "clevis*", "luksmeta", "libluksmeta", "jose",
                                                       "libjose", "tpm2-tools", "tpm2-tss*")})
    return k


def plan(db):
    run = running(db)
    names = set(db.pkgs)
    explicit = {n for n in names if matches(n, KEEP)}
    core = core_group() & names
    base = db.closure(run | explicit | core)
    stay_pats, disk = dict(STAY), disk_keeps()
    stay_pats.update(disk)
    stay = {n for n in names - base if matches(n, stay_pats) and not matches(n, NOT_STAY)}
    keep = db.closure(stay, have=base)
    why = {}
    for n in keep - base:
        pat = next((p for p in stay_pats if fnmatch.fnmatch(n, p)), None) if n in stay else None
        why[n] = stay_pats[pat] if pat else "needed by one of these"
    cand = names - keep
    return dict(run=run, explicit=explicit, core=core, base=base, keep=keep, why=why, cand=cand, disk=disk)


def removal_test(db, cand):
    """rpm's dry run of removing exactly `cand`. Whatever something staying needs moves back to staying (with what
    it needs), until the dry run passes. Returns (cand, moved {name: reason}, error or "")."""
    cand, moved = set(cand), {}
    for _ in range(40):
        if not cand:
            return cand, moved, ""
        r = sh(["rpm", "-e", "--test", "--allmatches", *sorted(cand)])
        text = r.stdout + r.stderr
        need = re.findall(r"^\s+(.+?) is needed by \(installed\) (\S+)\s*$", text, re.M)
        if r.returncode == 0 and not need:
            return cand, moved, ""
        if not need:
            return cand, moved, text.strip()[-1500:]
        back = set()
        for cap, by in need:
            for p in db.provided(cap) & cand:
                back.add(p)
                moved.setdefault(p, f"{names_in(cap)[0]} is needed by {by}")
        if not back:
            return cand, moved, "couldn't tell which package provides: " + "; ".join(c for c, _ in need[:5])
        more = db.closure(back) & cand
        for p in more - back:
            moved.setdefault(p, "needed by " + ", ".join(sorted(back)[:3]))
        cand -= more
    return cand, moved, "the removal test didn't settle"


DNF_TRIES = [["--setopt=clean_requirements_on_remove=False", "--disablerepo=*"],
             ["--setopt=clean_requirements_on_remove=False"], []]


def dnf_preview(cand):
    """dnf's own dry run of the same list: (output, how many it would remove, the dnf options that worked)."""
    out = ""
    for opts in DNF_TRIES:
        r = sh(["dnf", "remove", "--assumeno", *opts, *sorted(cand)])
        out = r.stdout + r.stderr
        m = re.search(r"(?im)^\s*remov(?:e|ing):?\s+(\d+)\s+packages?\b", out)
        if m:
            rows = set(re.findall(r"(?m)^ (\S+)\s+(?:x86_64|noarch|i686)\s", out))
            return out, int(m.group(1)), rows, opts
    return out, None, set(), []


def du(path):
    r = sh(["du", "-sb", path])
    try:
        return int(r.stdout.split()[0])
    except (IndexError, ValueError):
        return 0


def leftovers(home):
    out = []
    for p in LEFTOVERS:
        p = p.replace("~", home, 1)
        if os.path.lexists(p):
            out.append((p, du(p)))
    return out


def flatpaks(who):
    if not shutil.which("flatpak"):
        return []
    apps = [(a, "system") for a in sh(["flatpak", "list", "--system", "--columns=application"]).stdout.split()]
    if who:
        apps += [(a, "yours") for a in sh(["sudo", "-u", who, "flatpak", "list", "--user", "--columns=application"]).stdout.split()]
    return apps


def room_down(who):
    """Room's services that are clearly not running (a state systemd can't report counts as fine)."""
    if not who:
        return []
    down = []
    for u in ROOM_UNITS:
        state = sh(["systemctl", "--user", f"--machine={who}@", "is-active", f"{u}.service"]).stdout.strip()
        if state in ("inactive", "failed", "activating", "deactivating"):
            down.append(u)
    return down


def gb(b):
    return f"{b / (1 << 30):.1f} GB" if b >= 1 << 30 else f"{b / (1 << 20):.0f} MB"


# ------------------------------------------------------------------------------------------------------------ modes

def do_plan(db, who, home):
    p = plan(db)
    cand = sorted(p["cand"], key=lambda n: -db.size(n))
    out = [f"Room slim plan — {len(db.pkgs)} installed · keep {len(p['keep'])} · would remove {len(cand)} "
           f"({gb(sum(map(db.size, cand)))})",
           f"(running: {len(p['run'])} · keep list: {len(p['explicit'])} · core group: {len(p['core'])})", "",
           "== stays anyway — reviewed by hand, or this disk needs it"]
    out += [f"  {n}  — {w}" for n, w in sorted(p["why"].items())]
    out += ["", "== would remove (largest first)"]
    out += [f"{db.size(n) / 1048576:7.1f}  {n}  — {db.summary(n)}" for n in cand]
    out += ["", "== kept because something running uses them"] + sorted(p["run"])
    path = os.path.join(home, "room-slim-plan.txt")
    write(path, "\n".join(out) + "\n", who)
    print(out[0]); print(out[1]); print(f"→ {path}")


def do_check(db, who, home):
    down = room_down(who)
    if down:
        print(f"✗ Not running: {', '.join(down)} — start {'it' if len(down) == 1 else 'them'} first, so everything "
              f"{'it uses' if len(down) == 1 else 'they use'} counts as in use. Nothing was changed.")
        sys.exit(1)
    p = plan(db)
    cand, moved, err = removal_test(db, p["cand"])
    preview, count, rows, opts = dnf_preview(cand) if cand and not err else ("", None, set(), [])
    expect = sum(1 for n in cand for _ in db.ts.dbMatch("name", n))     # (a name installed twice counts twice)
    extra = (rows - cand) if count != expect else set()
    left = leftovers(home)
    apps = flatpaks(who)
    size = sum(map(db.size, cand))
    # the start-up has to go through greetd already — removing GDM while it's still the login screen would leave none
    dm_ok = "greetd" in os.path.basename(os.path.realpath("/etc/systemd/system/display-manager.service"))
    ok = bool(cand) and not err and count == expect and dm_ok
    k = os.uname().release
    others = sorted(os.path.basename(v)[8:] for v in glob.glob("/boot/vmlinuz-*") if not v.endswith(k) and "rescue" not in v)

    head = [f"Room slim check — remove {len(cand)} packages ({gb(size)}) + {gb(sum(s for _, s in left))} of Flatpak "
            f"apps and GNOME leftovers"]
    head.append(f"  {'✓' if not err else '✗'} the removal test: " +
                (f"nothing that stays needs any of them" + (f" ({len(moved)} more stay because something does)" if moved else "")
                 if not err else err.splitlines()[-1] if err.splitlines() else err))
    if not err:
        head.append(f"  {'✓' if count == expect else '✗'} dnf's own preview: " +
                    (f"the same {count} packages" if count == expect else
                     f"{count} packages, not {expect}{' — also ' + ', '.join(sorted(extra)[:8]) if extra else ''} (see the end of the file)"
                     if count is not None else "didn't run — its message is at the end of the file"))
    head.append("  ✓ start-up: greetd → Room (GDM isn't needed)" if dm_ok else
                "  ✗ start-up still goes through GDM — run  room-kiosk on  first")
    head.append("  ✓ ready: sudo python3 ~/room/scripts/slim.py apply" if ok else "  ✗ not ready — nothing to apply")

    body = ["", "== stays anyway — reviewed by hand, or this disk needs it"]
    body += [f"  {n}  — {w}" for n, w in sorted(p["why"].items())]
    body += ["", "== stays — the removal test found something staying needs it"]
    body += [f"  {n}  — {w}" for n, w in sorted(moved.items())] or ["  (none)"]
    body += ["", "== also goes: Flatpak apps and leftovers"]
    body += [f"  app  {a} ({where})" for a, where in apps]
    body += [f"  {gb(s):>8}  {path}" for path, s in left] or ["  (none)"]
    body += ["", f"== boot image: running kernel {k}; " + (f"rebuilt by apply — the other kernels stay as they are, to fall "
             f"back on: {', '.join(others)}" if others else "left as it is by apply (no other kernel to fall back on)")]
    body += ["", f"== removes {len(cand)} packages, by kind"]
    rest = set(cand)
    for kind, pats in KINDS:
        these = sorted((n for n in rest if matches(n, pats)), key=lambda n: -db.size(n))
        rest -= set(these)
        if these:
            body += ["", f"  -- {kind}: {len(these)} · {gb(sum(map(db.size, these)))}"]
            body += [f"  {db.size(n) / 1048576:7.1f}  {n}  — {db.summary(n)}" for n in these]
    body += ["", "== dnf's own preview" + (f" (options: {' '.join(opts)})" if opts else ""), preview]
    write(os.path.join(home, "room-slim-check.txt"), "\n".join(head + body) + "\n", who)
    lst = [f"# Room slim — checked {time.strftime('%Y-%m-%d %H:%M')} · dnf options: {' '.join(opts)}"] + sorted(cand)
    listf = os.path.join(home, "room-slim-list.txt")
    if ok:
        write(listf, "\n".join(lst) + "\n", who)
    elif os.path.exists(listf):
        os.remove(listf)
    print("\n".join(head)); print(f"  → {os.path.join(home, 'room-slim-check.txt')}")


def do_apply(db, who, home):
    listf = os.path.join(home, "room-slim-list.txt")
    if not os.path.exists(listf):
        print("✗ No checked list — run:  sudo python3 ~/room/scripts/slim.py check"); sys.exit(1)
    if time.time() - os.path.getmtime(listf) > 24 * 3600:
        print("✗ The checked list is over a day old — run check again first."); sys.exit(1)
    lines = open(listf).read().splitlines()
    opts = lines[0].split("dnf options:", 1)[1].split() if lines and "dnf options:" in lines[0] else []
    names = sorted(n for n in (l.strip() for l in lines) if n and not n.startswith("#") and n in db.pkgs)
    if not names:
        print("✓ Nothing left to remove."); return
    log = open(os.path.join(home, "room-slim-apply.log"), "a")
    if who:
        p = pwd.getpwnam(who); os.chown(log.name, p.pw_uid, p.pw_gid)

    def say(s):
        log.write(s + "\n"); log.flush()
        try:
            print(s, flush=True)
        except OSError:            # the SSH connection dropped: carry on, the log has it
            pass
    # a dropped SSH connection mustn't stop dnf halfway: this and dnf ignore the hang-up
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    say(f"\n=== Room slim — apply, {time.strftime('%Y-%m-%d %H:%M')}: {len(names)} packages")

    # still safe? nothing on the list in use right now, and the removal test still passes
    busy = sorted(set(names) & running(db))
    if busy:
        say(f"✗ In use right now: {', '.join(busy[:10])} — run check again. Nothing was changed."); sys.exit(1)
    r = sh(["rpm", "-e", "--test", "--allmatches", *names])
    if r.returncode != 0:
        log.write(r.stdout + r.stderr)
        say("✗ The removal test no longer passes — run check again. Nothing was changed."); sys.exit(1)

    apps = flatpaks(who)
    if apps:
        say(f"▸ Flatpak apps ({len(apps)}): uninstalling")
        for cmd in (["flatpak", "uninstall", "--system", "--all", "-y", "--noninteractive"],
                    ["sudo", "-u", who, "flatpak", "uninstall", "--user", "--all", "-y", "--noninteractive"] if who else None):
            if cmd:
                r = sh(cmd); log.write(r.stdout + r.stderr)

    size = sum(map(db.size, names))
    say(f"▸ Removing {len(names)} packages ({gb(size)}) — a few minutes; dnf's output goes to the log")
    r = subprocess.run(["dnf", "remove", "-y", *opts, *names], stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    log.flush()
    if r.returncode != 0:
        say(f"✗ dnf stopped (exit {r.returncode}) — see ~/room-slim-apply.log. Room's own files weren't touched."); sys.exit(1)
    tid = re.search(r"(?i)transaction id\s*:\s*(\d+)", sh(["dnf", "history", "info", "last"]).stdout)
    undo = f"sudo dnf history undo {tid.group(1)}" if tid else "sudo dnf history list, then  sudo dnf history undo <the remove's number>"
    db2 = Db()
    gone = [n for n in names if n not in db2.pkgs]
    say(f"  ✓ removed {len(gone)} of {len(names)}" + (f" — still installed: {', '.join(sorted(set(names) - set(gone))[:8])}"
                                                     if len(gone) < len(names) else ""))

    # what's running now never gets cleaned up later as "no longer needed"
    run_now = sorted(running(db2))
    dnf5 = "dnf5" in os.path.realpath(shutil.which("dnf") or "") or "dnf5" in sh(["dnf", "--version"]).stdout
    r = sh(["dnf", "-y", *[o for o in opts if o.startswith("--disablerepo")], "mark", "user" if dnf5 else "install", *run_now],
           stdin=subprocess.DEVNULL)
    log.write(r.stdout + r.stderr)
    say(f"▸ {len(run_now)} packages in use marked as wanted (later clean-ups won't take them)")

    freed = 0
    for path, s in leftovers(home):
        shutil.rmtree(path, ignore_errors=True)
        if not os.path.exists(path):
            freed += s
    sh(["dnf", "clean", "all"])
    say(f"▸ Leftovers deleted: {gb(freed)} (Flatpak apps, GNOME's caches, the old updater's downloads)")

    say("▸ Boot image: " + boot_image())
    say(f"✓ Done. Undo everything:  {undo}")
    say("  Restart to finish:  sudo systemctl reboot")


def boot_image():
    """Rebuild this kernel's boot image without the removed parts — now, while we're here, rather than at the next
    kernel update. Only when another kernel stays in the boot menu, untouched, to fall back on."""
    k = os.uname().release
    if not [v for v in glob.glob("/boot/vmlinuz-*") if not v.endswith(k) and "rescue" not in v]:
        return "left as it was (no second kernel to fall back on — the next kernel update rebuilds it)"
    img = f"/boot/initramfs-{k}.img"
    if not os.path.exists(img):
        return "left as it was (this system keeps it somewhere else)"
    new = img + ".new"
    r = sh(["dracut", "-q", "-f", "--kver", k, new])
    if r.returncode != 0 or not os.path.exists(new) or os.path.getsize(new) < 4 << 20:
        if os.path.exists(new):
            os.remove(new)
        return f"left as it was — rebuilding failed: {(r.stderr or r.stdout).strip()[-300:]}"
    st = os.statvfs("/boot")
    before = os.path.getsize(img)
    kept = ""
    if before and st.f_bavail * st.f_frsize > before + (64 << 20):
        shutil.copy2(img, img + ".before-slim")
        kept = f"; the old one is {img}.before-slim"
    os.replace(new, img)
    return f"rebuilt ({before >> 20} → {os.path.getsize(img) >> 20} MB){kept}; the other kernels' are untouched"


def main():
    if os.geteuid() != 0:
        print("Run with sudo:  sudo python3 ~/room/scripts/slim.py " + " ".join(sys.argv[1:])); sys.exit(1)
    who, home = user_home()
    mode = sys.argv[1] if len(sys.argv) > 1 else "plan"
    db = Db()
    {"plan": do_plan, "check": do_check, "apply": do_apply}.get(mode, lambda *a: print(__doc__))(db, who, home)


if __name__ == "__main__":
    main()
