"""Wi-Fi from the panel: the networks around, the one it's on, joining one (with its password, typed on the screen's
keyboard), connecting to a saved one, forgetting one. Talks to NetworkManager with `nmcli` on worker threads (nothing
here blocks the screen); Search rescans for ~12 s and runs while Settings is open.

A new network is saved for everyone on the Surface. If the system won't let Room do that (NetworkManager asks the
desktop for an admin password, and the panel has no desktop), it's saved for this user only instead — that works the
same here, as the panel signs in by itself. A join that fails (a wrong password) doesn't leave a broken entry behind."""
import re
import subprocess
import threading
import time

from PySide6.QtCore import QObject, Signal


def nmcli(*args, timeout=15) -> tuple[int, str]:
    try:
        r = subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except Exception as e:
        return 1, repr(e)


def fields(line: str) -> list[str]:
    """One line of nmcli's terse output (-t -e yes): fields split on ':', with '\\:' and '\\\\' escaped."""
    out, cur, i = [], "", 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur += line[i + 1]; i += 2; continue
        if c == ":":
            out.append(cur); cur = ""
        else:
            cur += c
        i += 1
    out.append(cur)
    return out


def why(out: str) -> str:
    """nmcli's error, said plainly."""
    o = out.lower()
    if "secrets were required" in o or "802-1x" in o or "psk" in o or "(7)" in o:
        return "Couldn't join — wrong password?"
    if "not authorized" in o or "insufficient privileges" in o or "permission" in o:
        return "Room isn't allowed to change the Wi-Fi"
    if "no network with ssid" in o:
        return "Can't see that network right now"
    if "timed out" in o or "timeout" in o:
        return "That took too long — try again"
    last = [ln for ln in out.splitlines() if ln.strip()]
    return (last[-1].replace("Error: ", "") if last else "Something went wrong")[:90]


class Wifi(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.networks: list = []
        self.radio = True
        self.device = ""
        self.searching = False
        self.busy: dict = {}              # ssid → "Joining…" / "Forgetting…"
        self.note = ""
        self._ssid_of: dict = {}          # saved connection uuid → its SSID
        self.ready = False                # looked at least once
        self._lock = threading.Lock()

    def snapshot(self):
        cur = next((n["ssid"] for n in self.networks if n["active"]), "")
        return {"ready": self.ready, "radio": self.radio, "device": self.device, "searching": self.searching,
                "note": self.note, "current": cur,
                "networks": [dict(n, busy=self.busy.get(n["ssid"], "")) for n in self.networks]}

    # ---------------------------------------------------------------- reading
    def refresh(self):
        threading.Thread(target=self._refresh, daemon=True).start()

    def _saved(self) -> dict:
        """SSID → saved connection uuid."""
        code, out = nmcli("-t", "-e", "yes", "-f", "UUID,TYPE", "connection", "show")
        saved = {}
        for line in out.splitlines() if code == 0 else []:
            f = fields(line)
            if len(f) < 2 or f[1] != "802-11-wireless":
                continue
            uuid = f[0]
            if uuid not in self._ssid_of:
                c, ssid = nmcli("-g", "802-11-wireless.ssid", "connection", "show", "uuid", uuid)
                self._ssid_of[uuid] = fields(ssid.strip())[0] if c == 0 else ""     # (-g escapes too)
            if self._ssid_of[uuid]:
                saved[self._ssid_of[uuid]] = uuid
        return saved

    def _refresh(self):
        with self._lock:
            code, out = nmcli("radio", "wifi")
            self.radio = code != 0 or "enabled" in out
            code, out = nmcli("-t", "-e", "yes", "-f", "DEVICE,TYPE", "device")
            self.device = next((f[0] for f in map(fields, out.splitlines()) if len(f) > 1 and f[1] == "wifi"), "") \
                if code == 0 else ""
            saved = self._saved()
            code, out = nmcli("-t", "-e", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
                              "--rescan", "no")
            seen: dict = {}
            for line in out.splitlines() if code == 0 else []:
                f = fields(line)
                if len(f) < 4 or not f[1].strip():
                    continue                                  # hidden networks: nothing anyone could pick
                ssid = f[1]
                sig = int(f[2]) if f[2].isdigit() else 0
                n = seen.get(ssid)
                if n is None:
                    n = seen[ssid] = {"ssid": ssid, "signal": sig, "secure": f[3].strip() not in ("", "--"),
                                      "active": False, "saved": ssid in saved, "uuid": saved.get(ssid, "")}
                n["signal"] = max(n["signal"], sig)
                n["active"] = n["active"] or f[0].strip() == "*"
            nets = sorted(seen.values(), key=lambda n: (not n["active"], not n["saved"], -n["signal"]))
            self.networks = nets
            self.ready = True
        self.changed.emit()

    # ---------------------------------------------------------------- searching
    def search(self):
        if self.searching:
            return
        self.searching = True
        self.note = ""
        self.changed.emit()

        def go():
            if not self.radio:
                nmcli("radio", "wifi", "on")
                time.sleep(2)
            nmcli("device", "wifi", "rescan", timeout=20)
            for _ in range(4):
                self._refresh()
                time.sleep(3)
            self.searching = False
            self._refresh()
        threading.Thread(target=go, daemon=True).start()

    # ---------------------------------------------------------------- doing
    def _do(self, ssid, label, work):
        if ssid in self.busy:
            return
        self.busy[ssid] = label
        self.note = ""
        self.changed.emit()

        def go():
            try:
                self.note = work() or ""
            except Exception as e:
                self.note = f"Something went wrong ({e!r})"[:90]
            self.busy.pop(ssid, None)
            self._refresh()
        threading.Thread(target=go, daemon=True).start()

    def join(self, ssid: str, password: str = ""):
        """A network that isn't saved (with its password if it has one), or a saved one (password ignored)."""
        def work():
            saved = self._saved()
            if ssid in saved:
                code, out = nmcli("connection", "up", "uuid", saved[ssid], timeout=45)
                return "" if code == 0 else why(out)
            before = set(saved.values())
            args = ["device", "wifi", "connect", ssid] + (["password", password] if password else [])
            code, out = nmcli(*args, timeout=45)
            if code != 0 and ("not authorized" in out.lower() or "insufficient" in out.lower()):
                self._tidy(before)
                code, out = nmcli(*args, "private", "yes", timeout=45)      # saved for this user only
            if code != 0:
                self._tidy(before)                     # a wrong password mustn't stay saved
                return why(out)
            return ""
        self._do(ssid, "Joining…", work)

    def _tidy(self, before: set):
        self._ssid_of.clear()
        for uuid in set(self._saved().values()) - before:
            nmcli("connection", "delete", "uuid", uuid)

    def forget(self, ssid: str):
        def work():
            uuid = self._saved().get(ssid)
            if not uuid:
                return ""
            code, out = nmcli("connection", "delete", "uuid", uuid)
            self._ssid_of.pop(uuid, None)
            return "" if code == 0 else why(out)
        self._do(ssid, "Forgetting…", work)
