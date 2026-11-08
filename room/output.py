"""Keeps sound going through the speaker tuning. Your Dolby filter (the Windows tuning rebuilt for Linux) is a sink of
its own; when a Bluetooth speaker disconnects, PipeWire falls back to the raw "Built-in Audio" sink instead, so
everything — Room's voice included — plays untuned and much quieter. Every 10 s: if the default output is the
Surface's raw speakers and a tuned sink exists (its name contains "preferSink" from config.json, "Dolby" by default),
the tuned one becomes the default again. A Bluetooth speaker or anything else you pick is left alone.
"""
import json
import subprocess
import threading
import time


class Output:
    def __init__(self, cfg: dict):
        self.want = (cfg.get("preferSink") or "Dolby").lower()
        self.off = cfg.get("preferSink") is False

    def start(self):
        if not self.off:
            threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            try:
                self.check()
            except Exception as e:
                print(f"[room] output: {e!r}")
            time.sleep(10)

    def check(self):
        nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
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
