"""Room's voice and ears — a separate process, so a sound problem can never take the panel down.

Started by Room (room/assistant.py) with its own Python (voice/.venv). Talks over stdin/stdout, one JSON object a line.
  out → ready · level · wake · listening · partial · heard · speaking · spoken · error
  in  ← say {text} · chime {name} · listen {follow} · cancel · words {words}
Listening is in ears.py; "listen": false in voiceSettings turns it off (speaking still works).

Speaking: Deepgram's Aura voice, streamed straight to the speaker; Kokoro (af_heart) when there's no key or no internet.
"""
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

import numpy as np
import requests

DATA = os.path.expanduser(os.environ.get("ROOM_VOICE_DATA", "~/.local/share/room/voice"))
CFG = json.loads(os.environ.get("ROOM_VOICE_CFG", "{}"))
VOICE = CFG.get("voice", "af_heart")                    # Kokoro (offline) voice
DG_KEY = CFG.get("deepgramKey") or ""
DG_VOICE = CFG.get("auraVoice", "aura-2-thalia-en")
DG_SPEAK = CFG.get("deepgramSpeakURL", "https://api.deepgram.com/v1/speak")
HTTP = requests.Session()                      # kept alive: from India a fresh TLS handshake costs ~0.5 s per answer
CUES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cues")


def emit(**ev):
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


def log(*a):
    print("[voice]", *a, file=sys.stderr, flush=True)


def louder(x: np.ndarray) -> np.ndarray:
    """Room's voice, made louder for the Surface's small speakers: gain (×2.5 by default, 'loudness' scales it) with a
    soft limiter, so peaks round off instead of crackling. Float in, float out (−1…1)."""
    g = 3.5 * float(CFG.get("loudness", 1.0))
    return np.tanh(x * g) / np.tanh(g) if g > 1 else x * g


def _sinks():
    """(default sink name, the Surface's own speaker sink name, the default's volume)."""
    nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
    raw, default = None, None
    for n in nodes:
        props = (n.get("info") or {}).get("props") or {}
        name = props.get("node.name", "")
        if props.get("media.class") == "Audio/Sink" and name.startswith("alsa_output.pci") and "hdmi" not in name:
            raw = name
        if n.get("type") == "PipeWire:Interface:Metadata" and (n.get("props") or {}).get("metadata.name") == "default":
            for m in n.get("metadata") or []:
                if m.get("key") == "default.audio.sink" and isinstance(m.get("value"), dict):
                    default = m["value"].get("name")
    out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True, timeout=2).stdout
    try:
        vol = 0.0 if "MUTED" in out else float(out.split()[1])
    except Exception:
        vol = 1.0
    return default, raw, vol


def voice_out():
    """Where Room's voice plays, and how loud. On the Surface's own speakers it goes straight to the speakers — not
    through the speaker tuning, which is made for music (it boosts the bass and turns everything down to make room for
    it, so speech came out quiet) — at the volume slider's level, but never below voiceMinLevel (75 %). On a Bluetooth
    speaker or anything else you've picked, it simply plays there. "voiceDirect": false sends it through the tuning."""
    props = ["-P", "{ application.name = \"Room voice\" }"]
    floor = float(CFG.get("voiceMinLevel", 0.75))
    try:
        default, raw, vol = _sinks()
    except Exception as e:
        log("voice out:", repr(e))
        return ["--volume", "1.0", *props]
    on_surface = default is None or default == raw or not (default.startswith("bluez") or default.startswith("alsa_output.usb"))
    if CFG.get("voiceDirect") is not False and on_surface and raw:
        v = max(vol, floor) * float(CFG.get("voiceVolume", 1.0))
        return ["--target", raw, "--volume", f"{min(1.0, v):.2f}", *props]
    LEVEL.lift()
    return ["--volume", str(float(CFG.get("voiceVolume", 1.0))), *props]


class Level:
    """Room's voice never comes out quieter than voiceMinLevel (75 % by default) of the speakers, whatever the volume
    slider is at — like a smart speaker, whose voice has a floor of its own. While Room talks, the output is lifted to
    that level if it's below it, and put back to where it was a moment after (unless it was changed meanwhile)."""

    def __init__(self):
        self.floor = float(CFG.get("voiceMinLevel", 0.75))
        self.saved = None            # (volume before, volume set)
        self.timer = None
        self.lock = threading.Lock()

    @staticmethod
    def _get():
        out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True, timeout=2).stdout
        return float(out.split()[1]), "MUTED" in out

    def lift(self):
        if self.floor <= 0:
            return
        with self.lock:
            if self.timer:
                self.timer.cancel(); self.timer = None
            if self.saved:
                return                   # still lifted from the sentence before
            try:
                v, muted = self._get()
                if v < self.floor or muted:
                    subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{self.floor:.2f}"], timeout=2)
                    subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"], timeout=2)
                    self.saved = (v, self.floor, muted)
            except Exception as e:
                log("level:", repr(e))

    def release(self, after=1.2):
        with self.lock:
            if self.timer:
                self.timer.cancel()
            self.timer = threading.Timer(after, self._put_back)
            self.timer.daemon = True
            self.timer.start()

    def _put_back(self):
        with self.lock:
            self.timer = None
            if not self.saved:
                return
            before, mine, muted = self.saved
            self.saved = None
            try:
                v, _ = self._get()
                if abs(v - mine) < 0.02:     # nobody touched the slider while Room talked
                    subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{before:.2f}"], timeout=2)
                    if muted:
                        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"], timeout=2)
            except Exception as e:
                log("level:", repr(e))


LEVEL = Level()


class Speaker:
    """Deepgram Aura, streamed into pw-play; Kokoro sentence by sentence when that isn't possible. stop() cuts it off."""

    def __init__(self):
        self.k = None
        self.lang = "en-gb" if VOICE.startswith("b") else "en-us"
        self.proc = None
        self.gen = 0
        self.busy = False
        self.lock = threading.Lock()

    def _kokoro(self):
        if self.k is None:
            from kokoro_onnx import Kokoro
            self.k = Kokoro(os.path.join(DATA, "kokoro.onnx"), os.path.join(DATA, "voices.bin"))
        return self.k

    def say(self, text, done):
        self.stop()
        self.gen += 1
        g = self.gen
        threading.Thread(target=self._say, args=(text, g, done), daemon=True).start()

    def _say(self, text, g, done):
        try:
            if DG_KEY and self._deepgram(text, g):
                self.busy = False
                if g == self.gen:
                    done()
                return
            self._run(text, g, done)
        finally:
            LEVEL.release()

    def _deepgram(self, text, g) -> bool:
        """Aura, streamed: playback starts with the first bytes. False if it couldn't be reached (→ Kokoro)."""
        self.busy = True
        try:
            t0 = time.time()
            for attempt in (0, 1):
                try:
                    r = HTTP.post(DG_SPEAK,
                                  params={"model": DG_VOICE, "encoding": "linear16", "sample_rate": 24000, "container": "none"},
                                  headers={"Authorization": f"Token {DG_KEY}", "Content-Type": "application/json"},
                                  json={"text": text}, stream=True, timeout=(3, 15))
                    break
                except requests.ConnectionError:
                    # the kept-alive connection had gone stale (Deepgram closes idle ones): once more on a fresh one.
                    # Without this Room fell back to the offline voice, which is quieter — "the voice went low again"
                    if attempt:
                        raise
                    HTTP.close()
            if r.status_code != 200:
                log(f"aura: {r.status_code} {r.text[:200]}")
                return False
        except Exception as e:
            log("aura:", repr(e))
            return False
        with self.lock:
            if g != self.gen:
                return True
            self.proc = subprocess.Popen(["pw-play", *voice_out(), "--raw", "--rate", "24000", "--channels", "1", "--format", "s16", "-"],
                                         stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        first = True
        odd = b""
        try:
            for chunk in r.iter_content(chunk_size=4800):
                if g != self.gen:
                    break
                if chunk:
                    if first:
                        emit(ev="speaking"); first = False
                        log(f"aura: first sound in {time.time() - t0:.2f} s")
                    chunk = odd + chunk
                    cut = len(chunk) // 2 * 2
                    chunk, odd = chunk[:cut], chunk[cut:]
                    x = np.frombuffer(chunk, dtype="<i2").astype(np.float32) / 32768
                    self.proc.stdin.write((louder(x) * 32000).astype("<i2").tobytes())
        except Exception as e:
            if g == self.gen:
                log("aura play:", repr(e))
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        self.proc.wait()
        return True

    def _run(self, text, g, done):
        import soundfile as sf
        self.busy = True
        parts = [p.strip() for p in re.split(r"(?<=[.!?])\s+", text) if p.strip()]
        q: queue.Queue = queue.Queue(maxsize=2)

        def synth():
            for p in parts:
                if g != self.gen:
                    break
                try:
                    a, sr = self._kokoro().create(p, voice=VOICE, speed=float(CFG.get("speed", 1.05)), lang=self.lang)
                    f = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
                    # Kokoro comes out quiet: every sentence to the same loudness (by its average, not its peak, so a
                    # short "Okay." isn't louder than a long answer)
                    rms = float(np.sqrt(np.mean(a ** 2))) if len(a) else 0.0
                    if rms > 0:
                        a = louder(np.clip(a * (0.16 / rms), -1, 1))
                    sf.write(f.name, a, sr); q.put(f.name)
                except Exception as e:
                    log("tts:", e)
            q.put(None)

        threading.Thread(target=synth, daemon=True).start()
        first = True
        while True:
            f = q.get()
            if f is None or g != self.gen:
                if f:
                    os.unlink(f)
                break
            if first:
                emit(ev="speaking"); first = False
            with self.lock:
                self.proc = subprocess.Popen(["pw-play", *voice_out(), f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.proc.wait()
            os.unlink(f)
        self.busy = False
        if g == self.gen:
            done()

    def stop(self):
        self.gen += 1
        with self.lock:
            if self.proc and self.proc.poll() is None:
                self.proc.kill()



def chime(name):
    f = os.path.join(CUES, f"{name}.wav")
    if os.path.exists(f):
        subprocess.Popen(["pw-play", "--volume", "0.9", f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    if not shutil.which("pw-play"):
        emit(ev="error", msg="pw-play is missing (pipewire-utils)")
        return
    speaker = Speaker()
    ears = None
    if CFG.get("listen") is not False:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from ears import Ears
            ears = Ears(CFG, speaker, emit, chime)
            threading.Thread(target=ears.run, daemon=True).start()
        except Exception as e:
            log("listening couldn't start:", repr(e))
            emit(ev="error", msg=f"Listening couldn't start: {e}")
    emit(ev="ready")
    for line in sys.stdin:
        try:
            c = json.loads(line)
        except ValueError:
            continue
        cmd = c.get("cmd")
        try:
            if cmd == "say":
                speaker.say(c.get("text", ""), lambda: emit(ev="spoken"))
            elif cmd == "chime":
                chime(c.get("name", ""))
            elif cmd == "cancel":
                speaker.stop()
                if ears:
                    ears.cancel()
            elif cmd == "listen" and ears:
                ears.begin(follow=bool(c.get("follow")))
            elif cmd == "words" and ears:
                ears.words = [w for w in c.get("words", []) if isinstance(w, str)][:40]
        except Exception as e:
            log("cmd:", repr(e))
    # Room went away


if __name__ == "__main__":
    main()
