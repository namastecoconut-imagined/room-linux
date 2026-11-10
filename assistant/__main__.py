"""Room's voice assistant — its own program (the room-assistant service), separate from the panel.

  "Alexa" (or a tap on the panel) → music down → your request, recorded until you've finished → Sarvam's words →
  Claude (with the home's current state) → Room carries out the actions → Kokoro speaks the answer → music back up.
  If the answer is a question, it listens again for a few seconds without the wake word.

Everything it does is logged ([assistant] lines: journalctl --user -u room-assistant). Settings in config.json:
"anthropicKey", "sarvamKey" and, optionally, "assistant": {"wakeThreshold": 0.5, "micLevel": 0.65, "voice": "af_heart", "voiceFloor": 0.4}.
"""
import json
import os
import re
import threading
import time

import numpy as np

from .brain import Brain, Computer
from .duck import Duck
from .link import Link
from .listen import VAD, Listener, Mic, Wake, log, sarvam, warm
from .tts import Voice

WAKE_WORDS = re.compile(r"^\s*(?:(?:hey|ok|okay)\s+)?(?:alexa|alexis|alexia|alex|lexa)\b[\s,.!?]*", re.I)
LOCAL = ("look_up", "remember", "forget", "computer")       # done here; everything else is done by Room


def chime(rate=24000, up=True):
    t = np.arange(int(rate * 0.22)) / rate
    f = (660, 990) if up else (660, 440)
    x = np.where(t < 0.09, np.sin(2 * np.pi * f[0] * t), np.sin(2 * np.pi * f[1] * t))
    return (x * np.exp(-t * 9) * 0.25).astype(np.float32), rate


class Assistant:
    def __init__(self, cfg: dict):
        a = cfg.get("assistant") or {}
        self.cfg = cfg
        self.sarvam_key = cfg.get("sarvamKey") or (cfg.get("voiceSettings") or {}).get("sarvamKey")
        key = (cfg.get("anthropicKey") or "").strip()
        self.brain = Brain(key, cfg.get("anthropicModel"), room="living room") if key else None
        self.computer = Computer(cfg.get("computer"))
        self.link = Link(on_command=self.command)
        self.mic = Mic(float(a.get("micLevel", 0.65)))
        self.ears = Listener(self.mic, Wake(a.get("wakeThreshold")), VAD())
        self.voice = Voice(voice=a.get("voice", "af_heart"))
        self.duck = Duck(float(a.get("voiceFloor", 0.40)))
        self.ears.on_level = lambda v: self.link.send({"t": "level", "v": round(v, 3)})
        self.cancelled = False
        if not self.sarvam_key:
            log("no sarvamKey in config.json — it can't understand speech")
        if not self.brain:
            log("no anthropicKey in config.json — it can't answer")

    # ---------------------------------------------------------------- what Room asks
    def command(self, m: dict):
        if m.get("t") == "listen":
            self.ears.tap.set()
        elif m.get("t") == "cancel":
            self.cancelled = True
            self.ears.abort.set()
            self.voice.stop()

    def state(self, **kw):
        self.link.send(dict({"t": "state"}, **kw))

    # ---------------------------------------------------------------- the loop
    def run(self):
        self.link.start()
        self.mic.start()
        log("ready — say \"Alexa\"")
        while True:
            score = self.ears.wait_wake()
            log(f"Alexa ({score:.2f})" if score >= 0 else "tap — listening")
            try:
                self.conversation()
            except Exception as e:
                log("turn failed:", repr(e))
                self.voice.stop()
                self.state(state="idle", stage="idle")
                self.duck.up()

    def conversation(self):
        follow, turns = False, 0
        self.cancelled = False
        self.duck.down()
        while True:
            more = self.turn(follow)
            turns += 1
            if not more or self.cancelled or turns >= 4:
                break
            follow = True
        self.duck.up()

    def turn(self, follow: bool) -> bool:
        """One request and its answer. True if it should listen again (it asked a question)."""
        warm()
        if self.brain:
            self.brain.warm()
        self.state(state="listening", stage="follow" if follow else "wake", heard="", reply="", line="", card="")
        if not follow:
            self.voice.player.begin(); self.voice.player.feed(*chime()); self.voice.player.end()
        t0 = time.time()
        audio, info = self.ears.record(onset=6.0 if follow else Listener.ONSET, fresh=follow)
        if self.cancelled:
            self.state(state="idle", stage="idle"); return False
        if audio is None:
            self.state(state="idle", stage="idle" if follow else "miss")
            return False
        self.state(state="thinking", stage="think")
        try:
            text = sarvam(audio, self.sarvam_key) if self.sarvam_key else ""
        except Exception as e:
            log("words:", e)
            self.answer("Sorry, I can't reach the internet right now.")
            return False
        text = WAKE_WORDS.sub("", text).strip()
        heard_at = time.time()
        log(f"heard {text!r} · {info.get('spoke', 0):.1f} s of speech · words {heard_at - t0 - info.get('took', 0):.2f} s after you stopped")
        if not text:
            self.state(state="idle", stage="idle" if follow else "miss")
            return False
        self.state(state="thinking", stage="think", heard=text)
        if not self.brain:
            self.answer("I can hear you, but I'm not connected to my brain yet."); return False
        snap = self.link.request({"t": "snapshot"}, 3) or {}

        early = {"said": ""}

        def on_say(sentence):
            if sentence and not self.cancelled:
                early["said"] = sentence
                self.state(state="speaking", stage="done", heard=text, reply=sentence)
                self.voice.say(sentence)
        got = threading.Event()
        res = {}
        self.brain.interpret(text, snap, follow, self.computer.ok, on_say, lambda out: (res.update(out=out), got.set()))
        got.wait(20)
        out = res.get("out")
        log(f"Claude: {time.time() - heard_at:.2f} s")
        if self.cancelled:
            return False
        if not out:
            self.answer("Sorry, I couldn't reach my brain just now — try again in a moment."); return False
        if follow and out.get("for_me") is False:
            self.voice.stop(); self.state(state="idle", stage="idle"); return False

        actions = out.get("actions") or []
        here = [a for a in actions if a.get("kind") not in LOCAL]
        summary = []
        if here:
            if any(a.get("kind") == "volume" for a in here):
                self.duck.up()          # music back first, so the new volume isn't undone when the duck lifts
            s = self.link.request({"t": "run", "actions": here}, 15)
            summary.append(s if s is not None else "couldn't reach the panel")
        looked = None
        for a in actions:
            k = a.get("kind")
            if k == "remember" and a.get("label"):
                self.brain.memory.add(a["label"]); summary.append("noted")
            elif k == "forget" and a.get("label"):
                summary.append("forgotten" if self.brain.memory.forget(a["label"]) else "nothing to forget")
            elif k == "look_up" and a.get("question"):
                ev, box = threading.Event(), {}
                self.brain.look_up(a["question"], lambda x: (box.update(a=x), ev.set()))
                ev.wait(25)
                looked = box.get("a") or "Sorry, I couldn't look that up just now."
            elif k == "computer":
                ev, box = threading.Event(), {}
                self.computer.send(a.get("command", ""), lambda why: (box.update(w=why), ev.set()))
                ev.wait(8)
                summary.append(f"couldn't reach the computer — {box.get('w')}" if box.get("w") else f"computer {a.get('command')}")
        did = " · ".join(x for x in summary if x)
        failed = "couldn't" in did
        line = looked or ((out.get("reply") or "") if out.get("reply") and not failed else did)
        spoken = looked or ((out.get("say") or "") if out.get("say") and not failed else did)
        self.brain.remember(text, spoken, did=did)
        card = out.get("card") if out.get("card") not in (None, "none") else ""
        if spoken and spoken.strip() != early["said"].strip():
            while self.voice.busy and not self.cancelled:       # let the first line finish
                time.sleep(0.05)
            self.voice.say(spoken)
        self.state(state="speaking" if spoken else "idle", stage="done", heard=text, reply=spoken or line,
                   line=line.lower() if line else "", card=card)
        time.sleep(0.2)
        while self.voice.busy and not self.cancelled:
            time.sleep(0.05)
        asked = spoken.strip().endswith("?")
        again = bool(out.get("follow_up", True)) and asked and not self.cancelled
        if not again:
            self.state(state="idle", stage="done", heard=text, reply=spoken or line, line=line.lower() if line else "", card=card)
        return again

    def answer(self, words: str):
        """Something went wrong (no internet, no brain): said, and shown in the error colours (stage "error")."""
        self.state(state="speaking", stage="error", reply=words)
        self.voice.say(words)
        time.sleep(0.2)
        while self.voice.busy:
            time.sleep(0.05)
        self.state(state="idle", stage="error", reply=words)


def main():
    cfg = json.load(open(os.path.expanduser("~/.config/room/config.json")))
    if (cfg.get("assistant") or {}).get("enabled") is False:
        log("turned off in config.json (assistant.enabled) — not starting"); time.sleep(3600); return
    Assistant(cfg).run()


if __name__ == "__main__":
    main()
