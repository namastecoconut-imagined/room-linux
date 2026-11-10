"""The assistant's end of the line to Room (room/voice.py): a local socket, one JSON object per line. It keeps trying
to connect, so either side can start or restart first. If Room isn't there, the assistant still listens and talks —
it just can't show anything or do anything in the home."""
import itertools
import json
import os
import socket
import threading
import time

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "room-assistant.sock")


class Link:
    def __init__(self, on_command=None):
        self.on_command = on_command          # called with Room's commands: {"t": "listen"} / {"t": "cancel"}
        self.s: socket.socket | None = None
        self.lock = threading.Lock()
        self.ids = itertools.count(1)
        self.waiting: dict[int, list] = {}

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    @property
    def up(self) -> bool:
        return self.s is not None

    def _run(self):
        said = False
        while True:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(SOCK)
            except OSError:
                if not said:
                    print("[assistant] waiting for Room…", flush=True); said = True
                time.sleep(2); continue
            self.s, said = s, False
            print("[assistant] connected to Room", flush=True)
            buf = b""
            try:
                while True:
                    d = s.recv(65536)
                    if not d:
                        break
                    buf += d
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        try:
                            self._got(json.loads(line))
                        except ValueError:
                            pass
            except OSError:
                pass
            self.s = None
            print("[assistant] Room went away — reconnecting", flush=True)
            for w in self.waiting.values():
                w[1].set()
            time.sleep(1)

    def _got(self, m: dict):
        if m.get("t") == "reply" and m.get("id") in self.waiting:
            w = self.waiting[m["id"]]
            w[0] = m.get("data")
            w[1].set()
        elif self.on_command:
            self.on_command(m)

    def send(self, msg: dict):
        s = self.s
        if not s:
            return
        try:
            with self.lock:
                s.sendall((json.dumps(msg) + "\n").encode())
        except OSError:
            pass

    def request(self, msg: dict, timeout=5.0):
        """Send and wait for Room's reply (None if Room isn't there or doesn't answer in time)."""
        if not self.s:
            return None
        i = next(self.ids)
        w = [None, threading.Event()]
        self.waiting[i] = w
        self.send(dict(msg, id=i))
        w[1].wait(timeout)
        self.waiting.pop(i, None)
        return w[0]
