"""Echo cancelling for Room's ears: the mic with what the room is playing taken back out, so "Alexa" is heard over
music and over Room's own voice.

PipeWire's echo canceller (WebRTC), run as its own small PipeWire process (nothing in the system's setup changes):
  • in: the Surface's own mic, raw — echo cancelling has to come *before* any noise suppression (a noise-suppressed
    mic has already been bent out of shape, and the canceller can't match it to what's playing any more); WebRTC's
    own, gentler noise suppression runs after the cancelling instead
  • reference: what's playing on the speaker music actually goes to — the Bluetooth speaker when one's connected,
    otherwise the Surface's speakers — taken from that speaker's monitor, so nothing has to be re-routed
  • out: "room_aec_source", which only Room listens to
It follows a speaker connecting or disconnecting (it restarts on the new one), and stops when Room's voice stops.
"echoCancel": false in config.json turns it off (Room then listens to the system's default mic, as before).
"""
import json
import os
import subprocess
import threading
import time

SOURCE = "room_aec_source"


def _dump():
    try:
        return json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout or "[]")
    except Exception:
        return []


def _props(n):
    return (n.get("info") or {}).get("props") or {}


def _defaults(nodes):
    out = {}
    for n in nodes:
        if n.get("type") == "PipeWire:Interface:Metadata" and (n.get("props") or {}).get("metadata.name") == "default":
            for m in n.get("metadata") or []:
                v = m.get("value")
                if m.get("key") in ("default.audio.sink", "default.audio.source") and isinstance(v, dict):
                    out[m["key"]] = v.get("name")
    return out


def exists(name, nodes=None):
    return any(_props(n).get("node.name") == name for n in (nodes if nodes is not None else _dump()))


def pick(cfg, nodes):
    """(mic, reference speaker) for the canceller."""
    mic = cfg.get("aecMic")
    if not mic:
        mics = [_props(n).get("node.name", "") for n in nodes if _props(n).get("media.class") == "Audio/Source"]
        mic = next((m for m in mics if m.startswith("alsa_input")), None) or _defaults(nodes).get("default.audio.source")
    bt = next((_props(n)["node.name"] for n in nodes if _props(n).get("media.class") == "Audio/Sink"
               and _props(n).get("node.name", "").startswith("bluez_output")), None)
    ref = cfg.get("aecSpeaker") or bt or _defaults(nodes).get("default.audio.sink")
    return mic, ref


CONF = """# written by Room (voice/aec.py) — run as its own process; delete freely
context.properties = { log.level = 2 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt args = { nice.level = -11 } flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-echo-cancel
      args = {
        library.name = aec/libspa-aec-webrtc
        monitor.mode = true
        audio.rate = 48000
        audio.channels = 1
        audio.position = [ MONO ]
        aec.args = {
            webrtc.extended_filter = true
            webrtc.delay_agnostic = true
            webrtc.high_pass_filter = true
            webrtc.noise_suppression = true
            webrtc.gain_control = false
            webrtc.voice_detection = false
        }
        capture.props = { node.name = "room_aec_capture" node.description = "Room echo canceller (mic in)"
                          target.object = "%MIC%" }
        source.props = { node.name = "room_aec_source" node.description = "Room mic (its own sound taken out)"
                         priority.session = 0 priority.driver = 0 }
        sink.props = { node.name = "room_aec_reference" node.description = "Room echo canceller (what's playing)"
                       target.object = "%REF%" }
        playback.props = { node.name = "room_aec_playback" }
      }
    }
]
"""


class EchoCancel:
    def __init__(self, cfg, data, log):
        self.cfg, self.data, self.log = cfg, data, log
        self.conf = os.path.join(data, "echo-cancel.conf")
        self.proc = None
        self.now = (None, None)
        self.failed = 0

    def start(self):
        if self.cfg.get("echoCancel") is False or not subprocess.run(["which", "pipewire"], capture_output=True).stdout:
            self.log("echo cancelling off — listening to the default mic")
            return False
        subprocess.run(["pkill", "-f", "pipewire -c " + self.conf], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        threading.Thread(target=self._watch, daemon=True).start()
        return True

    def _run(self, mic, ref):
        os.makedirs(self.data, exist_ok=True)
        with open(self.conf, "w") as f:
            f.write(CONF.replace("%MIC%", mic).replace("%REF%", ref))

        def die_with_me():
            try:
                import ctypes, signal
                ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)      # goes when Room's voice goes
            except Exception:
                pass
        self.proc = subprocess.Popen(["pipewire", "-c", self.conf], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                     preexec_fn=die_with_me)
        self.started = time.time()
        self.log(f"echo cancelling: mic {mic} · taking out what plays on {ref}")

    def _watch(self):
        while True:
            try:
                nodes = _dump()
                want = pick(self.cfg, nodes)
                alive = self.proc is not None and self.proc.poll() is None
                if self.proc is not None and not alive:
                    err = (self.proc.stderr.read() or b"").decode(errors="replace")[-300:]
                    self.log("echo canceller stopped:", err.strip() or f"exit {self.proc.returncode}")
                    self.failed += 1 if time.time() - self.started < 20 else 0
                    self.proc = None
                    if self.failed >= 3:
                        self.log("echo canceller keeps failing here — listening to the default mic")
                        return
                if all(want) and (self.proc is None or want != self.now):
                    if self.proc is not None:
                        self.proc.terminate()
                        try:
                            self.proc.wait(3)
                        except Exception:
                            self.proc.kill()
                    self.now = want
                    self._run(*want)
                # Room's mic is only for Room: if the system ever falls back to it as everyone's default, put it back
                d = _defaults(nodes).get("default.audio.source")
                if d == SOURCE and want[0]:
                    nid = next((str(n["id"]) for n in nodes if _props(n).get("node.name") == "surface_mic_ns"), None) \
                        or next((str(n["id"]) for n in nodes if _props(n).get("node.name") == want[0]), None)
                    if nid:
                        subprocess.run(["wpctl", "set-default", nid], timeout=3)
            except Exception as e:
                self.log("echo canceller:", repr(e))
            time.sleep(10)
