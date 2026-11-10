"""Keeps sound going through the speaker tuning. Your Dolby filter (the Windows tuning rebuilt for Linux) is a sink of
its own; when a Bluetooth speaker disconnects, PipeWire falls back to the raw "Built-in Audio" sink instead, so
everything plays untuned and much quieter. Every 10 s: if the default output is the
Surface's raw speakers and a tuned sink exists (its name contains "preferSink" from config.json, "Dolby" by default),
the tuned one becomes the default again. A Bluetooth speaker or anything else you pick is left alone.

AirPlay always goes to the Bluetooth speaker when one is connected (whatever the default output is), and back to the
Surface's speakers when it isn't ("airplayToBluetooth": false turns that off). Checked the moment AirPlay starts or
changes (Room is told by the AirPlay reader), and every 20 s otherwise — the PipeWire listing it reads is too heavy to
run every few seconds on a battery.

At start (and every few minutes) the levels underneath are put right: the Surface's own speakers at full — PipeWire's
level for the raw speakers and the chip's Master/Speaker controls; the volume slider works on the output in front of
them (the Dolby tuning, or a Bluetooth speaker), and a lowered level underneath (it sat around 20 %) only made
everything quiet — and any music stream left turned down is put back to full (PipeWire remembers a stream's level per
app, so one left low stays low for good; how loud music is belongs to the phone, Spotify and the speaker).
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
                if n % 15 == 0:                 # at start, then every ~5 minutes
                    self.levels(nodes, heal=(n == 0))
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
        """Music (AirPlay, and the Surface's own Spotify speaker) → the Bluetooth speaker when one's connected.
        Checked against where each stream is *actually* playing (PipeWire's links), not against what was set last:
        a speaker that drops and reconnects, or a stream PipeWire moved back to the Surface, used to stay on the
        Surface's speakers for good because Room thought it had already sent it over."""
        bt, bt_id = None, None
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if p.get("media.class") == "Audio/Sink" and p.get("node.name", "").startswith("bluez_output"):
                bt, bt_id = p["node.name"], n["id"]
                break
        # where each stream's sound goes now: output node → the nodes it's linked into
        links: dict = {}
        for n in nodes:
            if n.get("type") == "PipeWire:Interface:Link":
                i = n.get("info") or {}
                links.setdefault(i.get("output-node-id"), set()).add(i.get("input-node-id"))
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if p.get("media.class") != "Stream/Output/Audio":
                continue
            who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name", "application.process.binary")).lower()
            spot = "soloist" in who or "spotify" in who
            if "airplay" not in who and "shairport" not in who and not spot:
                continue                    # (Soloist: the Surface's own Spotify speaker, same rule as AirPlay)
            sid = n["id"]
            if (n.get("info") or {}).get("state") != "running":
                continue                    # paused / idle: nothing to move (it's checked again when it plays)
            if sid not in self.moved and not spot:
                # a new AirPlay stream starts at full (not Spotify's: its loudness is Spotify's volume): PipeWire may have kept a lower level for this app from an
                # old duck that was never undone (how AirPlay got quiet)
                subprocess.run(["wpctl", "set-volume", str(sid), "1.0"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            name = "Spotify" if spot else "AirPlay"
            if bt:
                if bt_id in links.get(sid, set()):
                    self.moved[sid] = bt
                    continue                # already on the speaker
                # clear, then set: setting the same target again is no change to PipeWire, so it wouldn't move
                subprocess.run(["pw-metadata", "-n", "default", "-d", str(sid), "target.object"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["pw-metadata", "-n", "default", str(sid), "target.object", bt], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(f"[room] output: {name} → {bt}", flush=True)
                self.moved[sid] = bt
                self.burst = max(self.burst, 2)      # look again shortly: did it go?
            elif self.moved.get(sid) != "":
                subprocess.run(["pw-metadata", "-n", "default", "-d", str(sid), "target.object"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(f"[room] output: {name} → the Surface (no Bluetooth speaker)", flush=True)
                self.moved[sid] = ""
        live = {n["id"] for n in nodes}
        self.moved = {k: v for k, v in self.moved.items() if k in live}

    def levels(self, nodes, heal=False):
        """The Surface's raw speakers at full, and (at start) music streams that were left turned down back to full."""
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            name = p.get("node.name", "")
            if p.get("media.class") == "Audio/Sink" and name.startswith("alsa_output.pci") and "hdmi" not in name:
                out = subprocess.run(["wpctl", "get-volume", str(n["id"])], capture_output=True, text=True, timeout=3).stdout
                if "1.00" not in out or "MUTED" in out:
                    subprocess.run(["wpctl", "set-volume", str(n["id"]), "1.0"], timeout=3)
                    subprocess.run(["wpctl", "set-mute", str(n["id"]), "0"], timeout=3)
                    print(f"[room] output: the Surface's speakers were at {out.strip()} — set to full", flush=True)
            if heal and p.get("media.class") == "Stream/Output/Audio":
                who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name", "application.process.binary")).lower()
                if "soloist" in who or "spotify" in who or name.startswith(("effect_", "output.", "input.")) \
                        or p.get("node.virtual") or p.get("factory.name") == "filter-chain" or "filter" in name or "loopback" in name:
                    continue        # Spotify's loudness is Spotify's own volume; filters aren't music
                vol = ((n.get("info") or {}).get("params") or {}).get("Props") or [{}]
                v = (vol[0] or {}).get("channelVolumes") or [1.0]
                if min(v) < 0.99:
                    subprocess.run(["wpctl", "set-volume", str(n["id"]), "1.0"], timeout=3)
                    print(f"[room] output: {who.split()[0] if who.split() else n['id']} was turned down — back to full", flush=True)
        for c in ("Master", "Speaker"):
            subprocess.run(["amixer", "-q", "-c", "0", "sset", c, "100%", "unmute"], timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

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
