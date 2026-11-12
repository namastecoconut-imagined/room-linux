"""Where the music plays, and the levels underneath it.

(There's no speaker tuning any more: the Dolby filter cost about half a core, all day — it processed even silence —
and the realtime load it put on PipeWire got it killed. Music mostly goes to the Bluetooth speaker, which has its
own. The Surface's speakers play raw.)

AirPlay always goes to the Bluetooth speaker when one is connected (whatever the default output is), and back to the
Surface's speakers when it isn't ("airplayToBluetooth": false turns that off) — and so do the Surface's own Spotify
speaker and the web browser Room opens (Firefox: a video there plays where the music does, so the volume buttons,
which follow the Bluetooth speaker, work on it). Checked the moment AirPlay starts or changes (Room is told by the
AirPlay reader), every 3 s while the browser is open, and every 20 s otherwise — the PipeWire listing it reads is too
heavy to run every few seconds all day on a battery.

At start (and every few minutes) the levels underneath are put right: the Surface's own speakers at full — PipeWire's
level for the raw speakers and the chip's Speaker control (Master a few dB under full — see levels()); the volume slider works on the output in front of
them (the Surface's speakers, or a Bluetooth speaker), and a lowered level underneath (it sat around 20 %) only made
everything quiet — and any music stream left turned down is put back to full (PipeWire remembers a stream's level per
app, so one left low stays low for good; how loud music is belongs to the phone, Spotify and the speaker).
"""
import json
import subprocess
import threading
import time


class Output:
    def __init__(self, cfg: dict):
        self.airplay_bt = cfg.get("airplayToBluetooth") is not False
        self.moved: dict = {}          # AirPlay stream id → where it was sent
        self.poked = threading.Event()
        self.headroom = abs(float(cfg.get("speakerHeadroomDb", 4)))
        self.on_airplay_audio = None   # called (from this thread) when AirPlay's sound is seen flowing
        self.browser_open = False      # Room's Firefox is open: look every 3 s, so its sound moves over quickly

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
            except Exception as e:
                print(f"[room] output: {e!r}")
            n += 1
            if self.burst > 0:
                self.burst -= 1
                time.sleep(1.5)
            else:
                self.poked.wait(3 if self.browser_open else 20)
            self.poked.clear()

    def airplay(self, nodes):
        """Music (AirPlay, the Surface's own Spotify speaker, Room's Firefox) → the Bluetooth speaker when one's connected.
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
            if n.get("type") != "PipeWire:Interface:Node" or p.get("media.class") != "Stream/Output/Audio":
                continue
            who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name", "application.process.binary")).lower()
            spot = "soloist" in who or "spotify" in who
            fox = "firefox" in who          # the web browser (Settings → Web browser): a video plays where music does
            if "airplay" not in who and "shairport" not in who and not spot and not fox:
                continue                    # (Soloist: the Surface's own Spotify speaker, same rule as AirPlay)
            sid = n["id"]
            if (n.get("info") or {}).get("state") != "running":
                continue                    # paused / idle: nothing to move (it's checked again when it plays)
            if not spot and not fox and self.on_airplay_audio:
                self.on_airplay_audio()     # AirPlay's sound is flowing: it's the music source, whatever metadata says
            if sid not in self.moved and not spot and not fox:
                # a new AirPlay stream starts at full (not Spotify's: its loudness is Spotify's volume): PipeWire may have kept a lower level for this app from an
                # old duck that was never undone (how AirPlay got quiet)
                subprocess.run(["wpctl", "set-volume", str(sid), "1.0"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            name = "Spotify" if spot else "Firefox" if fox else "AirPlay"
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
        """The Surface's speakers never left muted, the chip never above its crackle cap, and (at start) music streams
        that were left turned down back to full. It never RAISES the speakers' volume: with the Dolby filter gone the
        volume slider sets the Surface's speakers directly, and this used to put them back to 100 % every few minutes
        (it was written for when the filter sat in front and carried the volume)."""
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            name = p.get("node.name", "")
            if p.get("media.class") == "Audio/Sink" and name.startswith("alsa_output.pci") and "hdmi" not in name:
                out = subprocess.run(["wpctl", "get-volume", str(n["id"])], capture_output=True, text=True, timeout=3).stdout
                if "MUTED" in out:
                    subprocess.run(["wpctl", "set-mute", str(n["id"]), "0"], timeout=3)
                    print("[room] output: the Surface's speakers were muted — unmuted", flush=True)
            if heal and n.get("type") == "PipeWire:Interface:Node" and p.get("media.class") == "Stream/Output/Audio":
                who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name", "application.process.binary")).lower()
                if "soloist" in who or "spotify" in who or name.startswith(("effect_", "output.", "input.")) \
                        or p.get("node.virtual") or p.get("factory.name") == "filter-chain" or "filter" in name or "loopback" in name:
                    continue        # Spotify's loudness is Spotify's own volume; filters aren't music
                vol = ((n.get("info") or {}).get("params") or {}).get("Props") or [{}]
                v = (vol[0] or {}).get("channelVolumes") or [1.0]
                if min(v) < 0.99:
                    subprocess.run(["wpctl", "set-volume", str(n["id"]), "1.0"], timeout=3)
                    print(f"[room] output: {who.split()[0] if who.split() else n['id']} was turned down — back to full", flush=True)
        # the chip itself: never muted, and Master never above a few dB under full — at the very top, both the music and
        # Room's voice crackled (the speakers themselves: it crackled with any tuning bypassed too). Only ever LOWERED
        # to the cap: the volume slider moves these controls too now. "speakerHeadroomDb" in config.json (0 = no cap)
        for ctl in ("Speaker", "Master"):
            subprocess.run(["amixer", "-q", "-c", "0", "sset", ctl, "unmute"], timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if self.headroom:
            db = master_db()
            if db is not None and db > -self.headroom + 0.01:
                subprocess.run(["amixer", "-q", "-c", "0", "sset", "Master", f"-{self.headroom:g}dB"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(f"[room] output: the chip was at {db:g} dB — down to the crackle cap, -{self.headroom:g} dB", flush=True)


def master_db(text: str = None):
    """The chip's Master level in dB (the first channel amixer reports), or None."""
    import re
    if text is None:
        try:
            text = subprocess.run(["amixer", "-c", "0", "sget", "Master"], capture_output=True, text=True, timeout=3).stdout
        except Exception:
            return None
    m = re.search(r"\[(-?\d+(?:\.\d+)?)dB\]", text or "")
    return float(m.group(1)) if m else None
