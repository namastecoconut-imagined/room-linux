#!/usr/bin/env python3
"""How hard the Surface is working — CPU (all of it, and each program's share), power, temperatures, clock speeds,
memory. Only reads numbers the kernel keeps anyway; nothing is heard, seen or sent anywhere.

  python3 scripts/watch.py               Room's tracker (the room-watch user service runs it, from room-update):
                                         one line a minute to ~/.local/state/room/watch.log, the last 14 days kept
  python3 scripts/watch.py --report 60   one measurement over 60 s, in detail (scripts/health.sh uses it)

Program shares are "% of one core" (like top): 100 % = one core flat out; the Surface has 8.
Power is the processor's own meter (RAPL): "package" is the processor chip, "platform" the whole board where the
Surface reports it. Reading it needs root, or the permission scripts/health.sh (or cool.sh) gives your group.
"""
import glob, os, sys, time

HZ = os.sysconf("SC_CLK_TCK")
LOG = os.path.expanduser("~/.local/state/room/watch.log")
KEEP = 14 * 24 * 60                      # lines (one a minute)

NAMES = [("shairport-sync", "AirPlay"), ("nqptp", "AirPlay timing"), ("soloist", "Spotify"),
         ("pipewire-pulse", "PipeWire (pulse)"), ("pipewire", "PipeWire"), ("wireplumber", "WirePlumber"),
         ("cage", "cage (the screen)"), ("Xwayland", "Xwayland"), ("systemd-journal", "journald"),
         ("NetworkManager", "NetworkManager"), ("wpa_supplicant", "Wi-Fi"), ("bluetoothd", "Bluetooth"),
         ("iptsd", "touch (iptsd)"), ("avahi-daemon", "avahi"), ("tuned", "tuned"), ("thermald", "thermald"),
         ("iio-sensor-pro", "light sensor"), ("sshd", "SSH"), ("greetd", "greetd"), ("dbus-broker", "D-Bus")]
FIREFOX = ("firefox", "GeckoMain", "Isolated Web", "Web Content", "WebExtensions", "RDD Process", "Socket Process",
           "Privileged Con", "Utility Proces", "Isolated Servi", "forkserver")


def label(comm, cmd):
    """Which program a process belongs to, in plain words."""
    if not cmd:
        return "kernel"
    exe = os.path.basename(cmd[0])
    if exe.startswith("python") or comm.startswith("python"):
        if "-m" in cmd[:-1]:
            m = cmd[cmd.index("-m") + 1]
            return {"room": "Room (the panel)", "assistant": "assistant"}.get(m, f"python -m {m}")
        if any(c.endswith("watch.py") for c in cmd):
            return "this check" if "--report" in cmd else "Room's tracker"
        py = [os.path.basename(c) for c in cmd[1:] if c.endswith(".py")]
        return "python " + (py[0] if py else exe)
    if comm.startswith(FIREFOX) or exe == "firefox":
        return "Firefox"
    for key, name in NAMES:
        if comm.startswith(key) or exe == key:
            return name
    return comm


def read(path, conv=str):
    try:
        with open(path) as f:
            return conv(f.read().strip())
    except (OSError, ValueError):
        return None


def cpu_total():
    f = [int(x) for x in open("/proc/stat").readline().split()[1:]]
    return sum(f[:8]), f[3] + f[4]                      # all time, idle + iowait


def processes():
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            s = open(f"/proc/{pid}/stat").read()
            r = s.rfind(")")
            f = s[r + 2:].split()
            ticks = int(f[11]) + int(f[12])            # utime + stime
            comm = s[s.find("(") + 1:r]
            raw = open(f"/proc/{pid}/cmdline", "rb").read()
            cmd = [c.decode(errors="replace") for c in raw.split(b"\0") if c]
            out[pid] = (ticks, label(comm, cmd))
        except (OSError, IndexError, ValueError):
            pass
    return out


def energy():
    """{meter name: (µJ, wraps at)} — package-0, core, uncore, psys (platform), whatever this processor has."""
    out = {}
    for d in glob.glob("/sys/class/powercap/intel-rapl:*"):
        name, e, rng = read(d + "/name"), read(d + "/energy_uj", int), read(d + "/max_energy_range_uj", int)
        if name and e is not None and rng:
            out[name] = (e, rng)
    return out


def temps():
    t = {}
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        typ, v = read(z + "/type"), read(z + "/temp", int)
        if typ and v and 0 < v / 1000 < 125:
            t[typ] = max(v / 1000, t.get(typ, 0))
    return t


def mhz():
    v = [x for x in (read(p, int) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")) if x]
    return (sum(v) / len(v) / 1000, max(v) / 1000) if v else (None, None)


def gpu_mhz():
    for p in glob.glob("/sys/class/drm/card*/gt_act_freq_mhz") + glob.glob("/sys/class/drm/card*/gt_cur_freq_mhz"):
        v = read(p, int)
        if v is not None:
            return v
    return None


def mem_available_mb():
    for line in open("/proc/meminfo"):
        if line.startswith("MemAvailable:"):
            return int(line.split()[1]) // 1024


def screen():
    for d in glob.glob("/sys/class/backlight/*"):
        b, m, p = read(d + "/brightness", int), read(d + "/max_brightness", int), read(d + "/bl_power", int)
        if b is not None and m:
            return "off" if (p or b == 0) else f"on, {round(100 * b / m)} %"
    return "?"


class Sample:
    def __init__(self):
        self.t = time.monotonic()
        self.cpu = cpu_total()
        self.procs = processes()
        self.energy = energy()


def between(a, b):
    """CPU (whole machine %, programs' % of one core) and average watts from sample a to b."""
    dt = b.t - a.t
    total, idle = b.cpu[0] - a.cpu[0], b.cpu[1] - a.cpu[1]
    busy = 100 * (total - idle) / total if total else 0
    progs = {}
    for pid, (ticks, name) in b.procs.items():
        before = a.procs.get(pid, (0, name))[0] if pid in a.procs else 0   # new since a: all of its time counts
        d = ticks - before
        if d > 0:
            progs[name] = progs.get(name, 0) + 100 * d / HZ / dt
    watts = {}
    for k, (e, rng) in b.energy.items():
        if k in a.energy:
            watts[k] = ((e - a.energy[k][0]) % rng) / dt / 1e6
    return busy, progs, watts


class Spread:
    """min / average / max of readings taken during the measurement."""
    def __init__(self):
        self.v = []

    def add(self, x):
        if x is not None:
            self.v.append(x)

    def __str__(self):
        if not self.v:
            return "—"
        return f"{sum(self.v) / len(self.v):.0f} (min {min(self.v):.0f}, max {max(self.v):.0f})"


def report(secs):
    a = Sample()
    t, f, fmax, g = {}, Spread(), Spread(), Spread()
    end = time.monotonic() + secs
    while True:
        for k, v in temps().items():
            t.setdefault(k, Spread()).add(v)
        avg, top = mhz()
        f.add(avg); fmax.add(top); g.add(gpu_mhz())
        if time.monotonic() >= end:
            break
        time.sleep(min(5, max(0.1, end - time.monotonic())))
    b = Sample()
    busy, progs, watts = between(a, b)
    ncpu = os.cpu_count() or 1
    load = open("/proc/loadavg").read().split()[:3]
    print(f"  measured over {b.t - a.t:.0f} s · screen {screen()} · load {' '.join(load)}")
    print(f"  CPU, whole Surface: {busy:.1f} % ({busy * ncpu / 100:.2f} of {ncpu} cores' worth)")
    for name, pct in sorted(progs.items(), key=lambda kv: -kv[1])[:12]:
        if pct >= 0.05:
            print(f"     {pct:6.1f} %  {name}")
    if watts:
        nice = {"package-0": "processor (package)", "core": "  its cores", "uncore": "  its graphics",
                "psys": "whole platform", "dram": "memory"}
        print("  Power: " + " · ".join(f"{nice.get(k, k).strip()} {w:.2f} W" for k, w in sorted(watts.items(),
              key=lambda kv: list(nice).index(kv[0]) if kv[0] in nice else 9)))
    else:
        print("  Power: the processor's meter isn't readable here (run with sudo)")
    for d in glob.glob("/sys/class/power_supply/BAT*"):
        st, cap, pw = read(d + "/status"), read(d + "/capacity"), read(d + "/power_now", int)
        if pw is None:
            cur, vol = read(d + "/current_now", int), read(d + "/voltage_now", int)
            pw = cur * vol / 1e6 if cur is not None and vol is not None else None
        print(f"  Battery: {cap} %, {st}" + (f", {pw / 1e6:.1f} W" if pw else ""))
    print("  Temperatures °C, average (min, max):")
    for k in sorted(t, key=lambda k: (k != "x86_pkg_temp", k)):
        print(f"     {('processor' if k == 'x86_pkg_temp' else k):<18} {t[k]}")
    print(f"  CPU clock MHz: average {f}; fastest core {fmax}")
    print(f"  Graphics clock MHz: {g}")
    print(f"  Memory available: {mem_available_mb()} MB of {os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES') // 2**20} MB")


def track():
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    if not os.path.exists(LOG) or os.path.getsize(LOG) == 0:
        with open(LOG, "w") as f:
            f.write("# time\tload\tcpu%\tpkg W\tplatform W\tCPU °C\thottest °C\tMHz\tGPU MHz\tfree MB\tscreen\ttop programs (% of a core)\n")
    print(f"[room-watch] one line a minute → {LOG}", flush=True)
    a = Sample()
    while True:
        tp, hot, f, g = Spread(), Spread(), Spread(), Spread()
        for _ in range(6):                     # readings every 10 s; the line says the minute's average
            time.sleep(10)
            tt = temps()
            tp.add(tt.get("x86_pkg_temp"))
            hot.add(max(tt.values()) if tt else None)
            f.add(mhz()[0]); g.add(gpu_mhz())
        b = Sample()
        busy, progs, watts = between(a, b)
        a = b
        avg = lambda s, d=0: f"{sum(s.v) / len(s.v):.{d}f}" if s.v else "-"
        top = " ".join(f"{n.replace(' ', '_')}={p:.1f}" for n, p in sorted(progs.items(), key=lambda kv: -kv[1])[:6]
                       if p >= 0.1)
        line = "\t".join([time.strftime("%Y-%m-%d %H:%M"), open("/proc/loadavg").read().split()[0], f"{busy:.1f}",
                          f"{watts['package-0']:.2f}" if "package-0" in watts else "-",
                          f"{watts['psys']:.2f}" if "psys" in watts else "-",
                          avg(tp), f"{max(hot.v):.0f}" if hot.v else "-", avg(f), avg(g),
                          str(mem_available_mb()), screen().split(",")[0], top])
        with open(LOG, "a") as fh:
            fh.write(line + "\n")
        if os.path.getsize(LOG) > 4 << 20:            # trim to the last 14 days, now and then
            lines = open(LOG).readlines()
            if len(lines) > KEEP + 600:
                open(LOG, "w").writelines(lines[:1] + lines[-KEEP:])


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--report":
        report(int(sys.argv[2]) if len(sys.argv) > 2 else 60)
    else:
        track()
