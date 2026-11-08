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


def warm_voice():
    """Open the connection to Deepgram's voice while the person is still talking, so the answer's first sound isn't
    held up by a fresh connection (it measured 1.2–3 s to first sound without this)."""
    def go():
        try:
            HTTP.head(DG_SPEAK.rsplit("/v1/", 1)[0] + "/", timeout=4)
        except Exception:
            pass
    if DG_KEY:
        threading.Thread(target=go, daemon=True).start()
CUES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cues")


def emit(**ev):
    sys.stdout.write(json.dumps(ev) + "\n")
    sys.stdout.flush()


def log(*a):
    print("[voice]", *a, file=sys.stderr, flush=True)


class Voicer:
    """Room's voice, shaped for the Surface's small speakers, which can't play bass and are quiet on Linux:
      1. the deep lows (under ~120 Hz) taken out — the speakers can't play them, they only use up headroom,
      2. presence lifted (+4 dB around 2.8 kHz) — where speech is understood, and where small speakers sound loudest,
      3. an even level (every sentence as loud as the last), then a soft limiter (peaks round off, never crackle).
    Streaming, so it works on Aura's chunks as they arrive. 'loudness' in voiceSettings scales the drive."""

    def __init__(self, rate):
        from scipy.signal import butter
        self.hp = butter(2, 120, "highpass", fs=rate, output="sos")
        f0, gain_db, q = 2800.0, 4.0, 0.9                 # RBJ peaking EQ
        A, w0 = 10 ** (gain_db / 40), 2 * np.pi * f0 / rate
        al = np.sin(w0) / (2 * q)
        bb = np.array([1 + al * A, -2 * np.cos(w0), 1 - al * A])
        aa = np.array([1 + al / A, -2 * np.cos(w0), 1 - al / A])
        self.pk = np.concatenate([bb / aa[0], aa / aa[0]])[None, :]
        self.z1 = np.zeros((self.hp.shape[0], 2)); self.z2 = np.zeros((1, 2))
        self.level = 0.0
        self.drive = 1.6 * float(CFG.get("loudness", 1.0))

    def __call__(self, x: np.ndarray) -> np.ndarray:
        from scipy.signal import sosfilt
        if not len(x):
            return x
        y, self.z1 = sosfilt(self.hp, x, zi=self.z1)
        y, self.z2 = sosfilt(self.pk, y, zi=self.z2)
        r = float(np.sqrt(np.mean(y ** 2)))
        if r > 0.004:                                       # speech, not a pause: follow its loudness
            self.level = r if self.level == 0 else self.level + (r - self.level) * (0.5 if r > self.level else 0.1)
        g = float(np.clip(0.2 / max(self.level, 1e-4), 1.0, 8.0))
        d = self.drive
        return np.tanh(y * g * d) / np.tanh(d) * 0.95          # gentle: clean, never clipped


def _sinks():
    """(default sink name, the Surface's speakers — through the Dolby tuning if there is one, it makes them much
    louder — and the default's volume)."""
    nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
    raw, default, tuned = None, None, None
    for n in nodes:
        props = (n.get("info") or {}).get("props") or {}
        name = props.get("node.name", "")
        if props.get("media.class") == "Audio/Sink" and name.startswith("alsa_output.pci") and "hdmi" not in name:
            raw = name
        if props.get("media.class") == "Audio/Sink" and "dolby" in (name + props.get("node.description", "")).lower():
            tuned = name                      # the speaker tuning, which plays on the Surface's speakers
        if n.get("type") == "PipeWire:Interface:Metadata" and (n.get("props") or {}).get("metadata.name") == "default":
            for m in n.get("metadata") or []:
                if m.get("key") == "default.audio.sink" and isinstance(m.get("value"), dict):
                    default = m["value"].get("name")
    out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], capture_output=True, text=True, timeout=2).stdout
    try:
        vol = 0.0 if "MUTED" in out else float(out.split()[1])
    except Exception:
        vol = 1.0
    return default, tuned or raw, vol


def voice_out():
    """Where Room's voice plays: always the Surface's own speakers. When they're the system's output, through the same
    path as everything else (your Dolby tuning — it gives the voice body), at least voiceMinLevel; while music is on
    a Bluetooth speaker, straight to the Surface's speakers at full. "voiceDirect": false: wherever the output is."""
    props = ["-P", "{ application.name = \"Room voice\" state.restore-props = false state.restore-target = false }"]
    try:
        default, raw, vol = _sinks()
    except Exception as e:
        log("voice out:", repr(e))
        return ["--volume", "1.0", *props]
    elsewhere = bool(default) and (default.startswith("bluez") or default.startswith("alsa_output.usb"))
    if elsewhere and raw and CFG.get("voiceDirect") is not False:
        # nothing else plays on the Surface while music is on Bluetooth: its speakers (tuning included) at full
        try:
            for n in json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]"):
                if ((n.get("info") or {}).get("props") or {}).get("node.name") == raw:
                    subprocess.run(["wpctl", "set-volume", str(n["id"]), "1.0"], timeout=2)
                    subprocess.run(["wpctl", "set-mute", str(n["id"]), "0"], timeout=2)
        except Exception:
            pass
        return ["--target", raw, "--volume", f"{min(1.0, float(CFG.get('voiceVolume', 1.0))):.2f}", *props]
    LEVEL.lift()
    return ["--volume", f"{min(1.0, float(CFG.get('voiceVolume', 1.0))):.2f}", *props]


def surface_target():
    """The Surface's own speakers (for chimes), or [] for the system's output."""
    try:
        raw = _sinks()[1]
        return ["--target", raw] if CFG.get("voiceDirect") is not False and raw else []
    except Exception:
        return []


def speakers_full():
    """The Surface's speakers themselves at full — PipeWire's level for them and the chip's own Master/Speaker
    controls. The volume slider works on the output in front of them (the speaker tuning, or a Bluetooth speaker), so
    a lowered level here (it sat around 20 %) only made Room's voice quiet, and turning the voice up then just
    distorted it. Checked before every answer (PipeWire can put a remembered level back when outputs change)."""
    try:
        for n in json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]"):
            props = (n.get("info") or {}).get("props") or {}
            name = props.get("node.name", "")
            if props.get("media.class") == "Audio/Sink" and name.startswith("alsa_output.pci") and "hdmi" not in name:
                out = subprocess.run(["wpctl", "get-volume", str(n["id"])], capture_output=True, text=True, timeout=2).stdout
                if "1.00" not in out or "MUTED" in out:
                    subprocess.run(["wpctl", "set-volume", str(n["id"]), "1.0"], timeout=2)
                    subprocess.run(["wpctl", "set-mute", str(n["id"]), "0"], timeout=2)
                    log(f"the Surface's speakers were at {out.strip()} — set to full")
        for c in ("Master", "Speaker"):
            subprocess.run(["amixer", "-q", "-c", "0", "sset", c, "100%", "unmute"], timeout=2,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        log("speakers:", repr(e))


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
        speakers_full()
        try:
            if DG_KEY and self._deepgram(text, g):
                self.busy = False
                if g == self.gen:
                    done()
                return
            self._run(text, g, done)
        finally:
            LEVEL.release()

    @staticmethod
    def _aura(session, text, out: queue.Queue, tag):
        """One request for the voice; puts (tag, response, first bytes) — or (tag, None, error) — on out."""
        try:
            r = session.post(DG_SPEAK,
                             params={"model": DG_VOICE, "encoding": "linear16", "sample_rate": 24000, "container": "none"},
                             headers={"Authorization": f"Token {DG_KEY}", "Content-Type": "application/json"},
                             json={"text": text}, stream=True, timeout=(3, 15))
            if r.status_code != 200:
                out.put((tag, None, f"{r.status_code} {r.text[:200]}")); return
            it = r.iter_content(chunk_size=4800)
            first = next(it, b"")
            out.put((tag, (r, it), first))
        except Exception as e:
            out.put((tag, None, repr(e)))

    def _deepgram(self, text, g) -> bool:
        """Aura, streamed: playback starts with the first bytes. False if it couldn't be reached (→ Kokoro).
        Deepgram's first sound is usually ~0.7 s but now and then 2–2.5 s: if nothing has come back after 1.1 s, a
        second request goes out on a fresh connection and whichever answers first is played."""
        self.busy = True
        t0 = time.time()
        out: queue.Queue = queue.Queue()
        threading.Thread(target=Speaker._aura, args=(HTTP, text, out, "kept"), daemon=True).start()
        sent, errors, got = 1, [], None
        while got is None and len(errors) < sent:
            try:
                tag, res, first = out.get(timeout=1.1 if sent == 1 else 15)
            except queue.Empty:
                if sent == 1:
                    sent = 2
                    threading.Thread(target=Speaker._aura, args=(requests.Session(), text, out, "second"), daemon=True).start()
                    continue
                break
            if res is None:
                errors.append(first)
                if tag == "kept":
                    HTTP.close()            # gone stale (Deepgram closes idle ones): the next answer opens a fresh one
                    if sent == 1:           # once more straight away, on a fresh connection
                        sent = 2
                        threading.Thread(target=Speaker._aura, args=(requests.Session(), text, out, "second"), daemon=True).start()
                continue
            got = (tag, res, first)
        if got is None:
            log("aura:", "; ".join(errors) or "no answer")
            return False
        tag, (r, chunks), head = got
        if sent == 2:
            log(f"aura: the {tag} request answered first")
            def drop():                     # the slower one, when it comes
                try:
                    _, res2, _ = out.get(timeout=20)
                    if res2:
                        res2[0].close()
                except Exception:
                    pass
            threading.Thread(target=drop, daemon=True).start()
        with self.lock:
            if g != self.gen:
                log(f"aura: dropped — something new started {time.time() - t0:.1f} s in")
                r.close()
                return True
            self.proc = subprocess.Popen(["pw-play", *voice_out(), "--raw", "--rate", "24000", "--channels", "1", "--format", "s16", "-"],
                                         stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        first = True
        odd = b""
        shape = Voicer(24000)
        try:
            import itertools
            for chunk in itertools.chain([head], chunks):
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
                    out = (shape(x) * 32000).astype("<i2").tobytes()
                    self.proc.stdin.write(out)
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
                    a = Voicer(sr)(np.asarray(a, dtype=np.float64))
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
        subprocess.Popen(["pw-play", *surface_target(), "--volume", "0.9", f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    if not shutil.which("pw-play"):
        emit(ev="error", msg="pw-play is missing (pipewire-utils)")
        return
    speaker = Speaker()
    speakers_full()
    try:
        Voicer(24000)(np.zeros(2400, dtype=np.float32))     # its first use costs ~0.7 s (scipy loading): pay it now
    except Exception:
        pass
    ears = None
    if CFG.get("listen") is not False:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from ears import Ears
            ears = Ears(CFG, speaker, emit, chime)
            ears.on_begin = warm_voice
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
