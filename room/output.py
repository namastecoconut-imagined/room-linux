"""Keeps sound going through the speaker tuning. Your Dolby filter (the Windows tuning rebuilt for Linux) is a sink of
its own; when a Bluetooth speaker disconnects, PipeWire falls back to the raw "Built-in Audio" sink instead, so
everything — Room's voice included — plays untuned and much quieter. Every 10 s: if the default output is the
Surface's raw speakers and a tuned sink exists (its name contains "preferSink" from config.json, "Dolby" by default),
the tuned one becomes the default again. A Bluetooth speaker or anything else you pick is left alone.

AirPlay always goes to the Bluetooth speaker when one is connected (whatever the default output is), and back to the
Surface's speakers when it isn't ("airplayToBluetooth": false turns that off). Checked the moment AirPlay starts or
changes (Room is told by the AirPlay reader), and every 20 s otherwise — the PipeWire listing it reads is too heavy to
run every few seconds on a battery.
"""
import json
import subprocess
import threading
import time


class Output:
    def __init__(self, cfg: dict):
        self.want = (cfg.get("preferSink") or "Dolby").lower()
        self.off = cfg.get("preferSink") is False
        self.airplay_bt = cfg.get("airplayToBluetooth") is not False
        self.moved: dict = {}          # AirPlay stream id → where it was sent
        self.poked = threading.Event()

    def poke(self):
        """Something changed (AirPlay started, a speaker came or went): look now, and again over the next few seconds
        while the new stream settles."""
        self.burst = 4
        self.poked.set()

    def start(self):
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        n = 0
        self.burst = 0
        while True:
            try:
                nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
                if self.airplay_bt:
                    self.airplay(nodes)
                if not self.off:
                    self.check(nodes)
            except Exception as e:
                print(f"[room] output: {e!r}")
            n += 1
            if self.burst > 0:
                self.burst -= 1
                time.sleep(1.5)
            else:
                self.poked.wait(20)
            self.poked.clear()

    def airplay(self, nodes):
        bt = next(((n.get("info") or {}).get("props", {}).get("node.name") for n in nodes
                   if ((n.get("info") or {}).get("props") or {}).get("media.class") == "Audio/Sink"
                   and ((n.get("info") or {}).get("props") or {}).get("node.name", "").startswith("bluez_output")), None)
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if p.get("media.class") != "Stream/Output/Audio":
                continue
            who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name", "application.process.binary")).lower()
            spot = "soloist" in who or "spotify" in who or "uxplay" in who   # (UxPlay: AirPlay video)
            if "airplay" not in who and "shairport" not in who and not spot:
                continue                    # (Soloist: the Surface's own Spotify speaker, same rule as AirPlay)
            sid = n["id"]
            if self.moved.get(sid) == (bt or ""):
                continue
            if sid not in self.moved:
                # a new music stream starts at full: PipeWire may have kept a lower level for this app from an
                # old duck that was never undone (how AirPlay got quiet)
                subprocess.run(["wpctl", "set-volume", str(sid), "1.0"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if bt:
                subprocess.run(["pw-metadata", "-n", "default", str(sid), "target.object", bt], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(f"[room] output: {'Spotify/video' if spot else 'AirPlay'} → {bt}", flush=True)
            else:
                subprocess.run(["pw-metadata", "-n", "default", "-d", str(sid), "target.object"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print("[room] output: music → the system's output (no Bluetooth speaker)", flush=True)
            self.moved[sid] = bt or ""
        live = {n["id"] for n in nodes}
        self.moved = {k: v for k, v in self.moved.items() if k in live}

    def check(self, nodes):
        sinks, default = {}, None
        for n in nodes:
            props = (n.get("info") or {}).get("props") or {}
            if props.get("media.class") == "Audio/Sink":
                sinks[props.get("node.name", "")] = (n["id"], (props.get("node.description") or "").lower())
            if n.get("type") == "PipeWire:Interface:Metadata" and (n.get("props") or {}).get("metadata.name") == "default":
                for m in n.get("metadata") or []:
                    if m.get("key") == "default.audio.sink":
                        v = m.get("value")
                        default = (v or {}).get("name") if isinstance(v, dict) else None
        tuned = next((name for name, (_, desc) in sinks.items() if self.want in desc or self.want in name.lower()), None)
        if not tuned or not default or default == tuned:
            return
        raw = default.startswith("alsa_output.pci") and "hdmi" not in default
        if raw:
            subprocess.run(["wpctl", "set-default", str(sinks[tuned][0])], timeout=5)
            print(f"[room] output: back to the tuned speakers ({tuned}) — the default had fallen back to {default}", flush=True)
