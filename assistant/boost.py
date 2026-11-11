"""A short CPU boost while Room makes speech, then straight back to cool.

The Surface runs Room's cool power profile (scripts/cool.sh: the CPU's energy preference "balance_power", idling at
~1 GHz). Kokoro there made speech no faster than it plays (2.06 s for 2.03 s of speech), so Room was slow to start
talking. With "balance_performance" it took 1.43 s. So the preference is raised only while speech is being made — a
second or two per answer — and put back right after ("race to idle"): fast answers without a hot Surface.

Writing the preference needs permission, given once by scripts/cool.sh (a systemd-tmpfiles rule makes these files
writable by your group). Without it there's simply no boost. A boost can never stick: it ends after 15 s whatever
happens, and the assistant puts the cool setting back when it starts.
"""
import glob
import threading
import time

FILES = "/sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference"


def log(*a):
    print("[assistant]", *a, flush=True)


class Boost:
    FAST, COOL, LIMIT = "balance_performance", "balance_power", 15.0

    def __init__(self, enabled=True):
        self.files = sorted(glob.glob(FILES))
        self.ok = enabled and bool(self.files) and all(self._writable(f) for f in self.files)
        self.n = 0
        self.lock = threading.Lock()
        self.until = 0.0
        if not enabled:
            log("voice: no CPU boost (assistant.cpuBoost is off)")
        elif not self.ok:
            log("voice: no CPU boost while speaking — not permitted yet (run scripts/cool.sh once)")
        else:
            self._write(self.COOL)                  # a boost left on by a crash ends here
            threading.Thread(target=self._guard, daemon=True).start()
            log(f"voice: CPU boost while speech is made ({self.FAST}, back to {self.COOL} after)")

    @staticmethod
    def _writable(f):
        try:
            with open(f, "a"):
                return True
        except OSError:
            return False

    def _write(self, v):
        for f in self.files:
            try:
                with open(f, "w") as fh:
                    fh.write(v)
            except OSError:
                pass

    def on(self):
        if not self.ok:
            return
        with self.lock:
            self.n += 1
            self.until = time.time() + self.LIMIT
            if self.n == 1:
                self._write(self.FAST)

    def off(self):
        if not self.ok:
            return
        with self.lock:
            self.n = max(0, self.n - 1)
            if self.n == 0:
                self._write(self.COOL)

    def _guard(self):
        while True:                                  # never left boosted: 15 s at most, whatever happened
            time.sleep(2)
            with self.lock:
                if self.n and time.time() > self.until:
                    log(f"voice: CPU boost ran {self.LIMIT:g} s — back to cool")
                    self.n = 0
                    self._write(self.COOL)
