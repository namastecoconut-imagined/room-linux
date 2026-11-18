"""Music down the moment "Alexa" is heard, back exactly where it was afterwards — every app playing (AirPlay, the
Surface's Spotify, a browser), never a speaker as a whole and never the assistant's own voice.

Each stream's own level is read first and put back exactly (not "to full"): the Surface's Spotify (Soloist) uses its
stream level as Spotify's volume, so "back to full" blasted it last time.
"""
import json
import os
import subprocess
import threading

LEVEL = 0.15            # music at 15 % of where it was while you talk and Room answers
FLOOR = 0.86            # while Room talks, the speaker is set to this (wpctl's scale) — Settings → More settings → Sound →
                        # Assistant's voice (__main__.floor), up or down from where the music had it: Room's voice shares
                        # the speaker with the music, so a speaker turned down for music left the voice too quiet, and
                        # one turned up for it was too loud at night. Put back exactly after the conversation; the music,
                        # ducked to 15 % of its own level meanwhile, stays quiet under it.


class Duck:
    """down() / up() go to one worker in order (two threads could run up before down and leave music low)."""

    def __init__(self, floor=FLOOR):
        import queue
        self.saved: dict = {}
        self.floor = floor
        self.sink_was = None        # the speaker's level before it was set for the conversation
        self.target = "@DEFAULT_AUDIO_SINK@"   # which speaker that is: the Surface's own (speaker.py), set at down()
        self.q = queue.Queue()
        threading.Thread(target=self._worker, daemon=True).start()

    def down(self):
        self.q.put("down")

    def up(self):
        self.q.put("up")

    def _worker(self):
        while True:
            want = self.q.get()
            try:
                if want == "down" and self.sink_was is None:
                    self.target = self._target()
                    v = self._sink()
                    if v is not None and abs(v - self.floor) > 0.005:
                        self.sink_was = v
                        subprocess.run(["wpctl", "set-volume", self.target, f"{self.floor:.2f}"], timeout=2,
                                       stderr=subprocess.DEVNULL)
                        print(f"[assistant] speaker {v:.2f} → {self.floor:.2f} for the conversation", flush=True)
                if want == "up" and self.sink_was is not None:
                    v = self._sink()
                    if v is not None and abs(v - self.floor) < 0.015:        # not changed meanwhile ("volume 20")
                        subprocess.run(["wpctl", "set-volume", self.target, f"{self.sink_was:.2f}"], timeout=2,
                                       stderr=subprocess.DEVNULL)
                    self.sink_was = None
                if want == "down" and not self.saved:
                    for sid, app, v in self._streams():
                        self.saved[sid] = (app, v)
                        subprocess.run(["wpctl", "set-volume", str(sid), f"{v * LEVEL:.3f}"], timeout=2,
                                       stderr=subprocess.DEVNULL)
                elif want == "up" and self.saved:
                    # put back by stream, and by app for streams that weren't there before: an app that started a new
                    # stream meanwhile (the Surface's Spotify does, per song) got the lowered level from PipeWire's
                    # memory of that app — and stayed quiet ("it went back to a lower volume and stayed there")
                    by_app = {app: v for app, v in self.saved.values()}
                    for sid, app, now in self._streams():
                        v = self.saved[sid][1] if sid in self.saved else by_app.get(app)
                        if v is not None:
                            subprocess.run(["wpctl", "set-volume", str(sid), f"{v:.3f}"], timeout=2,
                                           stderr=subprocess.DEVNULL)
                    self.saved = {}
                elif want == "forget":
                    self.saved = {}
            except Exception as e:
                print("[assistant] duck:", repr(e), flush=True)

    @staticmethod
    def _target():
        """The Surface's own speakers (where Room's voice plays, speaker.py) — the default speaker if not found."""
        from .speaker import surface
        s = surface()
        return str(s[0]) if s else "@DEFAULT_AUDIO_SINK@"

    def _sink(self):
        try:
            out = subprocess.run(["wpctl", "get-volume", self.target], capture_output=True, text=True,
                                 timeout=2).stdout
            return float(out.split()[1])
        except Exception:
            return None

    @staticmethod
    def _streams():
        nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
        out = []
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if n.get("type") != "PipeWire:Interface:Node" or p.get("media.class") != "Stream/Output/Audio":
                continue                    # (the apps themselves are listed too, with the same class — not volumes)
            if str(p.get("application.process.id")) == str(os.getpid()):
                continue                    # the assistant's own voice
            name = (p.get("node.name") or "").lower()
            who = " ".join(str(p.get(k, "")) for k in ("application.name", "node.name")).lower()
            if "room assistant" in who or "room sound" in who or name.startswith(("effect_", "output.", "input.")) \
                    or p.get("node.virtual") or p.get("factory.name") == "filter-chain" or "filter" in name \
                    or "loopback" in name:
                continue
            props = (((n.get("info") or {}).get("params") or {}).get("Props") or [{}])[0] or {}
            vols = props.get("channelVolumes") or [1.0]
            app = p.get("application.name") or p.get("application.process.binary") or name
            out.append((n["id"], app, max(vols) ** (1 / 3)))          # wpctl's scale (cubic)
        return out
