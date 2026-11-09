"""Room's ears — the rebuilt listening side. Deliberately plain:

  • The mic is whatever the system's default input is — on the Surface, Aviral's own "Surface Mic (Noise Suppressed)"
    — read as it comes (16 kHz mono). Room does no mic processing of its own: no gain, no filters, no suppression.
  • "Alexa" is spotted on the Surface (openWakeWord), and Room reacts at once — no checking over the internet first.
    While Room is talking it needs a clearer "Alexa" (its own voice is in the mic).
  • What follows streams to Deepgram (nova-3, Indian English) from the moment "Alexa" is heard (with the second before
    it, so a quick "Alexa, lights off" isn't clipped). One stream per request: a pause after "Alexa" or mid-sentence
    ("…tomorrow in") doesn't end it.
  • You've finished when Deepgram says so, or after ~0.8 s without speech (Silero VAD, on the Surface) — whichever
    is first. Nothing said for 5 s (8 s after a question): it closes.

Events out: level · wake · listening · partial · heard · error. Commands in: listen (tap, or follow-up) · cancel · words.
"""
import functools
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time

import numpy as np

# stdout is Room's JSON channel — anything printed there was being thrown away; logs go to the journal via stderr
print = functools.partial(print, file=sys.stderr, flush=True)  # noqa: A001

RATE = 16000
CHUNK = 1280                                 # 80 ms — what openWakeWord wants
WAKE_RE = re.compile(r"\b(?:(?:hey|okay|ok|hi)\s+)?(?:alexa|alexis|alexia|alexi|alex|lexa|elexa|alaxa|alyssa)\b[\s,.!?]*", re.I)
DANGLE = {"something", "me", "in", "on", "at", "to", "for", "of", "the", "a", "an", "and", "or", "but", "with", "from", "my", "is", "set",
          "play", "turn", "what's", "what", "how", "about", "by", "into", "some", "until", "till"}
KEYTERMS = ["Alexa", "turn off the lights", "turn on the lights", "turn off", "turn on", "set a timer", "timer", "minutes", "lights", "bedroom", "living room", "make it cozy", "cozy", "dim",
            "brightness", "percent", "weather", "Spotify", "play", "pause", "chill"]


def after_wake(text: str) -> str:
    """What was said after the last "Alexa" (anything before it is the room, or Room's own voice)."""
    ms = list(WAKE_RE.finditer(text or ""))
    return (text[ms[-1].end():] if ms else text or "").strip()


def unfinished(text: str) -> bool:
    """Only "Alexa" so far, or a sentence stopping on "in", "the", "and"… — wait for the rest."""
    if WAKE_RE.search(text or "") and not after_wake(text):
        return True
    w = re.sub(r"[^a-z' ]", "", (text or "").lower()).split()
    return bool(w) and w[-1] in DANGLE and not (text or "").rstrip().endswith((".", "?", "!"))


class Stream:
    """One request, live to Deepgram. on_text(text, self) while talking; on_end(text, self) once."""

    def __init__(self, cfg, words, on_text, on_end, spare=None):
        self.cfg, self.on_text, self.on_end = cfg, on_text, on_end
        self.q: queue.Queue = queue.Queue()
        self.finals: list[str] = []
        self.interim = ""
        self.last_guess = ""
        self.ended = False
        self.closing = False
        self.failed = False
        self.url = Stream.url(cfg, words)
        self.spare = spare
        self.t0 = time.time()
        self.first_at = 0.0                 # Deepgram's first words back
        self.guesses: list[str] = []        # what it thought along the way (the final can be worse: "please drink chill")
        threading.Thread(target=self._run, daemon=True).start()

    @staticmethod
    def url(cfg, words):
        from urllib.parse import urlencode
        p = [("model", cfg.get("deepgramModel", "nova-3")), ("language", cfg.get("language", "en-IN")),
             ("encoding", "linear16"), ("sample_rate", str(RATE)), ("channels", "1"), ("interim_results", "true"),
             ("endpointing", str(cfg.get("endpointMs", 800))), ("utterance_end_ms", "1000"), ("vad_events", "true")]
        p += [("keyterm", w) for w in (KEYTERMS + list(words))[:50]]
        return cfg.get("deepgramListenURL", "wss://api.deepgram.com/v1/listen") + "?" + urlencode(p)

    def push(self, pcm):
        if not self.ended:
            self.q.put(pcm.tobytes())

    def finish(self):
        """Ask Deepgram for its final words now."""
        if not self.closing:
            self.closing = True
            self.q.put(None)

    def text(self):
        return " ".join([*self.finals, self.interim]).strip()

    def _end(self):
        if not self.ended:
            self.ended = True
            self.on_end(self.text() or self.last_guess, self)

    def _run(self):
        from websockets.sync.client import connect
        t0 = time.time()
        try:
            if self.spare:
                ctx, ws = self.spare
            else:
                ctx = connect(self.url, additional_headers={"Authorization": f"Token {self.cfg['deepgramKey']}"},
                              open_timeout=4, max_size=None)
                ws = ctx.__enter__()
        except Exception as e:
            print("[voice] deepgram connect:", repr(e), flush=True)
            self.failed = True
            self._end()
            return

        self.opened = time.time() - t0

        def sender():
            try:
                while not self.ended:
                    try:
                        b = self.q.get(timeout=2)
                    except queue.Empty:
                        ws.send(json.dumps({"type": "KeepAlive"})); continue
                    if b is None:
                        ws.send(json.dumps({"type": "Finalize"}))
                        time.sleep(1.5)
                        break
                    ws.send(b)
                ws.send(json.dumps({"type": "CloseStream"}))
            except Exception:
                pass
        threading.Thread(target=sender, daemon=True).start()
        try:
            for msg in ws:
                if isinstance(msg, bytes):
                    continue
                m = json.loads(msg)
                if m.get("type") == "Results":
                    t = (((m.get("channel") or {}).get("alternatives") or [{}])[0].get("transcript") or "").strip()
                    if m.get("is_final"):
                        if t:
                            self.finals.append(t)
                        self.interim = ""
                    else:
                        self.interim = t
                        if t:
                            self.last_guess = " ".join([*self.finals, t])
                            self.guesses.append(self.last_guess)
                    if t and not self.first_at:
                        self.first_at = time.time()
                    if self.text():
                        self.on_text(self.text(), self)
                    if m.get("from_finalize") and self.finals:
                        break
                    if m.get("speech_final") and self.finals and not unfinished(self.text()):
                        break
                elif m.get("type") == "UtteranceEnd" and self.finals and not unfinished(self.text()):
                    break
        except Exception as e:
            if not self.ended:
                print("[voice] deepgram:", repr(e), flush=True)
        print(f"[voice] heard {self.text()!r} · {'spare' if self.spare else 'new'} connection {self.opened:.2f} s · "
              f"first words {self.first_at - self.t0 if self.first_at else 0:.1f} s · done {time.time() - self.t0:.1f} s")
        self._end()
        try:
            ws.send(json.dumps({"type": "CloseStream"}))
            ctx.__exit__(None, None, None)
        except Exception:
            pass


class SarvamStream:
    """One request, live to Sarvam (saaras, trained on Indian speech — Indian English included) over its realtime
    websocket: audio as base64 JSON, partial words as they come, the final words after a flush. Same shape as
    Stream, so the rest of the listening works the same. If Sarvam can't be reached, `fallback` is set and the audio
    so far is kept, so Ears can carry on with Deepgram without losing what was said."""

    URL = "wss://api.sarvam.ai/speech-to-text-realtime/ws"

    def __init__(self, cfg, words, on_text, on_end):
        self.cfg, self.on_text, self.on_end = cfg, on_text, on_end
        self.q: queue.Queue = queue.Queue()
        self.finals: dict = {}              # utterance → its final words
        self.parts: dict = {}               # utterance → words so far
        self.last_guess = ""
        self.ended = self.closing = self.failed = self.fallback = False
        self.t0 = time.time()
        self.first_at = 0.0
        self.opened = 0.0
        self.guesses: list[str] = []
        self.audio: list[bytes] = []        # everything sent, in case Deepgram has to take over
        self.lock = threading.Lock()
        self.got_final = threading.Event()
        terms = (KEYTERMS + list(words))[:50]
        from urllib.parse import urlencode
        self.url = self.URL + "?" + urlencode({
            "language_code": cfg.get("sarvamLanguage", "en-IN"),
            "model": cfg.get("sarvamModel", "saaras:v4"),
            "stream_type": cfg.get("sarvamStream", "balanced"),
            "endpointing": "manual",        # Room decides when you've finished (as with Deepgram)
            "encoding": "linear16", "sample_rate": str(RATE),
            "keyterms": json.dumps([t[:64] for t in terms]),
            "prompt": "Voice commands to a smart-home panel in Bangalore, India: lights, scenes, timers, alarms, "
                      "reminders, Spotify music, weather, questions.",
        })
        threading.Thread(target=self._run, daemon=True).start()

    def push(self, pcm):
        if not self.ended:
            b = pcm.tobytes()
            self.audio.append(b)
            self.q.put(b)

    def finish(self):
        if not self.closing:
            self.closing = True
            self.q.put(None)

    def text(self):
        idx = sorted(set(self.finals) | set(self.parts))
        return " ".join(self.finals.get(i) or self.parts.get(i, "") for i in idx).strip()

    def _end(self):
        with self.lock:
            if self.ended or self.fallback:     # Deepgram is taking over this one
                return
            self.ended = True
        self.on_end(self.text() or self.last_guess, self)

    def _run(self):
        import base64
        from websockets.sync.client import connect
        try:
            ctx = connect(self.url, additional_headers={"Api-Subscription-Key": self.cfg["sarvamKey"]},
                          open_timeout=4, max_size=None)
            ws = ctx.__enter__()
        except Exception as e:
            print("[voice] sarvam connect:", repr(e), "— using Deepgram")
            self.fallback = True
            return
        self.opened = time.time() - self.t0

        def sender():
            try:
                while not self.ended:
                    try:
                        b = self.q.get(timeout=5)
                    except queue.Empty:
                        ws.send(json.dumps({"event": "ping"})); continue
                    if b is None:
                        ws.send(json.dumps({"event": "flush"}))
                        # the final words normally come back in a fraction of a second; don't wait forever
                        if not self.got_final.wait(2.5):
                            print("[voice] sarvam: no final words after 2.5 s — going with what came")
                        self._end()
                        break
                    ws.send(json.dumps({"event": "audio_input", "audio": base64.b64encode(b).decode()}))
                ws.send(json.dumps({"event": "end"}))
            except Exception:
                self._end()
        threading.Thread(target=sender, daemon=True).start()
        try:
            for msg in ws:
                if isinstance(msg, bytes):
                    continue
                m = json.loads(msg)
                ev = m.get("event")
                if ev in ("transcript.partial", "transcript.final"):
                    i, t = m.get("utterance_idx", 0), (m.get("text") or "").strip()
                    (self.finals if ev == "transcript.final" else self.parts)[i] = t
                    if t and not self.first_at:
                        self.first_at = time.time()
                    if ev == "transcript.partial" and t:
                        self.last_guess = self.text()
                        self.guesses.append(self.last_guess)
                    if self.text():
                        self.on_text(self.text(), self)
                    if ev == "transcript.final" and self.closing:
                        self.got_final.set()
                elif ev == "error":
                    print(f"[voice] sarvam: {m.get('code')} {m.get('message')}")
                    if m.get("is_fatal"):
                        if not self.text() and not self.closing:
                            self.fallback = True        # turned down (no access, quota…): Deepgram takes over
                            return
                        break
        except Exception as e:
            if not self.ended:
                print("[voice] sarvam:", repr(e))
        print(f"[voice] heard {self.text()!r} · sarvam · connect {self.opened:.2f} s · "
              f"first words {self.first_at - self.t0 if self.first_at else 0:.1f} s · done {time.time() - self.t0:.1f} s")
        self._end()
        try:
            ctx.__exit__(None, None, None)
        except Exception:
            pass


class Spare:
    """One Deepgram connection kept open and ready (KeepAlive, no audio — nothing to pay for): from India, opening one
    costs ~0.5–0.9 s, which would otherwise come straight after "Alexa"."""

    def __init__(self, cfg):
        self.cfg, self.words = cfg, []
        self.lock = threading.Lock()
        self.spare = None                  # (ctx, ws, url, opened)
        self.need = threading.Event()
        threading.Thread(target=self._keep, daemon=True).start()

    def take(self):
        with self.lock:
            sp, self.spare = self.spare, None
        self.need.set()
        if sp and sp[2] == Stream.url(self.cfg, self.words) and time.time() - sp[3] < 400:
            return sp[0], sp[1]
        if sp:
            Spare._close(sp)
        return None

    @staticmethod
    def _close(sp):
        try:
            sp[1].send(json.dumps({"type": "CloseStream"})); sp[0].__exit__(None, None, None)
        except Exception:
            pass

    def _keep(self):
        from websockets.sync.client import connect
        while True:
            with self.lock:
                sp = self.spare
            try:
                url = Stream.url(self.cfg, self.words)
                if sp is None or time.time() - sp[3] > 380 or sp[2] != url:
                    ctx = connect(url, additional_headers={"Authorization": f"Token {self.cfg['deepgramKey']}"},
                                  open_timeout=5, max_size=None)
                    new = (ctx, ctx.__enter__(), url, time.time())
                    with self.lock:
                        old, self.spare = self.spare, new
                    if old:
                        Spare._close(old)
                else:
                    sp[1].send(json.dumps({"type": "KeepAlive"}))
            except Exception as e:
                print("[voice] deepgram spare:", repr(e), flush=True)
                with self.lock:
                    self.spare = None
                time.sleep(2)
            self.need.wait(3)
            self.need.clear()


class Ears:
    def __init__(self, cfg, speaker, emit, chime):
        from openwakeword.model import Model
        from openwakeword.vad import VAD
        self.cfg, self.speaker, self.emit, self.chime = cfg, speaker, emit, chime
        d = os.path.join(os.path.expanduser(os.environ.get("ROOM_VOICE_DATA", "~/.local/share/room/voice")), "oww")
        self.wake = Model(wakeword_models=[os.path.join(d, "alexa_v0.1.onnx")], inference_framework="onnx",
                          melspec_model_path=os.path.join(d, "melspectrogram.onnx"),
                          embedding_model_path=os.path.join(d, "embedding_model.onnx"))
        self.vad = VAD(model_path=os.path.join(d, "silero_vad.onnx"))
        self.threshold = float(cfg.get("wakeThreshold", 0.4))
        self.words: list[str] = []
        self.spare = Spare(cfg) if cfg.get("deepgramKey") else None
        self.stream: Stream | None = None
        self.state = "idle"                 # idle · listening
        self.ring: list[np.ndarray] = []    # the last ~1 s (so "Alexa, lights off" in one breath isn't clipped)
        self.clock = 0.0
        self.last_wake = -9.0
        self.started = 0.0
        self.spoke_at = 0.0
        self.wait = 5.0
        self.mine_first = False             # Room was talking when it woke: its own words come before "Alexa"
        self.best = 0.0
        self.best_at = 0.0
        self.on_begin = None
        self.last_text, self.text_at = "", 0.0
        self.voice_at = self.closed_at = 0.0

    # ---------------------------------------------------------------- the mic
    def run(self):
        cmd = ["pw-record", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16", "--latency", "40ms", "-"]
        if self.cfg.get("mic"):
            cmd[1:1] = ["--target", self.cfg["mic"]]
        while True:
            rec = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            q: queue.Queue = queue.Queue()

            def reader(p=rec):
                n = CHUNK * 2
                while True:
                    b = p.stdout.read(n)
                    if not b or len(b) < n:
                        q.put(None); return
                    q.put(np.frombuffer(b, "<i2").copy())
            threading.Thread(target=reader, daemon=True).start()
            print("[voice] listening to", self.cfg.get("mic") or "the default mic", flush=True)
            while True:
                pcm = q.get()
                if pcm is None:
                    break
                if q.qsize() > 4 and self.state == "idle":
                    # fallen behind (the Surface was busy): skip to now, so "Alexa" is heard now, not seconds late
                    while q.qsize() > 1:
                        x = q.get()
                        if x is None:
                            q.put(None); break
                    self.wake.reset()
                try:
                    self.feed(pcm)
                except Exception as e:
                    print("[voice] feed:", repr(e), flush=True)
            print("[voice] mic stopped — reopening in 2 s", flush=True)
            time.sleep(2)

    def feed(self, pcm):
        self.clock += len(pcm) / RATE
        now = self.clock
        x = pcm.astype(np.float32) / 32768
        rms = float(np.sqrt(np.mean(x ** 2)))
        self.level_n = getattr(self, "level_n", 0) + 1
        if self.level_n % 4 == 0:                    # ~3 a second is enough for the screen's ripple and glow
            self.emit(ev="level", v=round(rms, 5))
        self.ring = (self.ring + [pcm])[-12:]
        # a silent room can't be saying "Alexa": the wake model (the biggest steady CPU cost) rests until there's
        # sound above the room's own quiet, then catches up on the last moments first, so nothing is missed
        fl = getattr(self, "floor", rms)
        self.floor = fl + (rms - fl) * (0.3 if rms < fl else 0.002)
        if rms > max(self.floor * 2.5, 0.002):
            self.loud_at = now
        if self.state != "listening" and not self.speaker.busy and now - getattr(self, "loud_at", -9) > 1.5:
            self.resting = getattr(self, "resting", 0) + 1
            return
        if getattr(self, "resting", 0):
            for c in self.ring[-1 - min(self.resting, 5):-1]:
                self.wake.predict(c)
            self.resting = 0
        score = max(self.wake.predict(pcm).values() or [0])
        if score > self.best:
            self.best = score
        if now - self.best_at > 60:
            if self.best > 0.1:
                print(f"[voice] best 'Alexa' score in the last minute: {self.best:.2f}", flush=True)
            self.best, self.best_at = 0.0, now
        need = max(self.threshold, 0.6) if self.speaker.busy else self.threshold
        if score >= need and now - self.last_wake > 1.5 and not (self.speaker.busy and self.cfg.get("bargeIn") is False):
            self.last_wake = now
            talking = self.speaker.busy
            self.wake.reset()
            print(f"[voice] Alexa ({score:.2f}{', over Room’s own voice' if talking else ''})", flush=True)
            self.emit(ev="wake")
            self.begin(preroll=True, mine_first=talking)
            return
        if self.state != "listening":
            return
        s = self.stream
        if s and getattr(s, "fallback", False) and not s.ended and not self.cfg.get("deepgramKey"):
            s.fallback = False
            s._end()                        # no Deepgram to fall back to: end with nothing heard
        if s and getattr(s, "fallback", False) and not s.ended:
            # Sarvam couldn't be reached or turned us down: Deepgram for a while, with everything said so far
            self.sarvam_off_until = time.time() + 300
            s.ended = True
            d = Stream(self.cfg, self.words, self._text, self._end, self.spare.take() if self.spare else None)
            for b in s.audio:
                d.q.put(b)
            if s.closing:
                d.finish()
            self.stream = s = d
        if s:
            s.push(pcm)
            if float(self.vad.predict(pcm, frame_size=480)) > 0.4:
                if not self.voice_at:
                    self.voice_at = now
                self.spoke_at = now
            said = s.text()
            quiet = now - self.spoke_at
            # finished: ~1.1 s without speech AND no new words for 0.8 s (a short pause — "set a timer… for five
            # minutes", "play something… chill" — was ending requests early)
            still = time.time() - self.text_at
            if said and not s.closing and now - self.started > 1.0 and still > 0.8 and (
                    (quiet > float(self.cfg.get("endQuiet", 0.8)) and not unfinished(said)) or quiet > 2.5):
                s.finish()
            # nothing said: close after `wait` — but not while someone is talking and the words just haven't come
            # back yet ("set a timer…" was cut to "set a" when the first words took 5 s to arrive)
            if not s.closing and ((not said and now - self.started > self.wait and quiet > 1.0)
                                  or now - self.started > 15):
                s.finish()
            if s.closing and not self.closed_at:
                self.closed_at = now
                print(f"[voice] request: speech from {self.voice_at - self.started if self.voice_at else -1:.1f} s, "
                      f"last speech {self.spoke_at - self.started:.1f} s, closed {now - self.started:.1f} s "
                      f"(quiet {quiet:.1f} s)")

    # ---------------------------------------------------------------- a request
    def begin(self, preroll=False, follow=False, mine_first=False):
        self.speaker.stop()
        if self.on_begin:
            self.on_begin()                 # warm the voice's connection while they talk
        if not follow:
            self.chime("listen")
        if self.stream and not self.stream.ended:
            self.stream.ended = True        # the old one is dropped (its late words can't end the new one)
        self.state = "listening"
        self.started = self.spoke_at = self.clock
        self.voice_at = self.closed_at = 0.0
        self.wait = 8.0 if follow else 6.0
        self.mine_first = mine_first
        self.vad.reset_states()
        use_sarvam = bool(self.cfg.get("sarvamKey")) and self.cfg.get("stt", "sarvam") == "sarvam" \
            and time.time() > getattr(self, "sarvam_off_until", 0)
        if not use_sarvam and not self.cfg.get("deepgramKey"):
            self.emit(ev="error", msg="No speech key in config.json (sarvamKey or deepgramKey) — Room can't understand speech")
            self.state = "idle"
            return
        if self.spare:
            self.spare.words = self.words
        if use_sarvam:
            s = SarvamStream(self.cfg, self.words, self._text, self._end)
        else:
            s = Stream(self.cfg, self.words, self._text, self._end, self.spare.take() if self.spare else None)
        self.stream = s
        if preroll:
            for c in self.ring:
                s.push(c)
        self.emit(ev="listening", follow=follow)

    def _text(self, text, s):
        if s is not self.stream:
            return
        t = after_wake(text)
        if text != self.last_text:
            self.last_text, self.text_at = text, time.time()
        if self.mine_first and not WAKE_RE.search(text):
            return                          # still only Room's own voice before "Alexa"
        if t:
            self.emit(ev="partial", text=t)

    def _end(self, text, s):
        if s is not self.stream:
            return                          # an older stream finishing late
        self.stream = None
        self.state = "idle"
        if s.failed:
            self.emit(ev="error", msg="Couldn't reach the speech service — check the internet")
            self.emit(ev="heard", text="")
            return
        if self.mine_first and not WAKE_RE.search(text or ""):
            text = ""
        said = after_wake(text)
        # the best other reading along the way, if the final one changed it ("play something chill on spot" →
        # "please drink chill on spotify"): Claude gets both
        alt = ""
        for g in reversed(s.guesses):
            g = after_wake(g)
            if len(g.split()) >= max(2, len(said.split()) - 2) and g.lower().rstrip(".?!") != said.lower().rstrip(".?!") \
                    and not said.lower().startswith(g.lower().rstrip(".?!")):     # just the start of the same thing
                alt = g; break
        self.emit(ev="heard", text=said, alt=alt)

    def cancel(self):
        if self.stream:
            s, self.stream = self.stream, None
            s.ended = True
        self.state = "idle"
