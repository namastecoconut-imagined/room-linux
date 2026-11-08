"""Understands what was said the way the iPhone panel did (Voice/Assistant.swift): the words plus a snapshot of the home
go to Claude, which answers through one tool — say (spoken), reply (on-screen caption), actions, follow_up, for_me and
a card to show beside the answer. The spoken sentence streams in first, so Room starts talking before the actions are
even parsed. Needs "anthropicKey" in config.json; without it (or offline) Room uses its own small rules (intents.py).

Runs on worker threads; every callback is handed back to Qt's main thread by the caller (assistant.py).
"""
import contextlib
import datetime as dt
import http.client
import io
import json
import ssl
import urllib.parse
import os
import re
import threading
import time
import urllib.error
import urllib.request

from .config import STATE_DIR

API = os.environ.get("ROOM_CLAUDE_URL", "https://api.anthropic.com/v1/messages")


class _Pool:
    """Kept-alive HTTPS connections to Claude. From India a new connection (DNS + TLS) costs ~0.5–0.8 s, so one is
    opened while the person is still talking (warm) and reused for the answer."""

    def __init__(self, url):
        u = urllib.parse.urlsplit(url)
        self.host, self.path, self.https = u.hostname, u.path, u.scheme == "https"
        self.port = u.port
        self.free: list = []
        self.lock = threading.Lock()

    def _new(self, timeout):
        cls = http.client.HTTPSConnection if self.https else http.client.HTTPConnection
        return cls(self.host, self.port, timeout=timeout, **({"context": ssl.create_default_context()} if self.https else {}))

    def take(self, timeout):
        with self.lock:
            while self.free:
                c, at = self.free.pop()
                if time.time() - at < 50:
                    c.timeout = timeout
                    if c.sock:
                        c.sock.settimeout(timeout)
                    return c, True
                c.close()
        return self._new(timeout), False

    def give(self, c):
        with self.lock:
            self.free.append((c, time.time()))
            del self.free[:-2]

    def warm(self):
        with self.lock:
            if any(time.time() - at < 40 for _, at in self.free):
                return
        c = self._new(5)
        try:
            c.connect()
            self.give(c)
        except Exception:
            c.close()

    @contextlib.contextmanager
    def post(self, body: dict, key: str, timeout=12):
        data = json.dumps(body).encode()
        hdrs = {"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"}
        for attempt in range(2):
            c, reused = self.take(timeout)
            try:
                c.request("POST", self.path, body=data, headers=hdrs)
                r = c.getresponse()
                break
            except (http.client.RemoteDisconnected, BrokenPipeError, ConnectionResetError, http.client.CannotSendRequest):
                c.close()
                if not reused or attempt:
                    raise
        if r.status != 200:
            err = r.read()
            c.close()
            raise urllib.error.HTTPError(API, r.status, r.reason, r.headers, io.BytesIO(err))
        try:
            yield r
            r.read()                         # drain, so the connection can be reused
            if r.will_close:
                c.close()
            else:
                self.give(c)
        except BaseException:
            c.close()
            raise


POOL = _Pool(API)


def _post(body: dict, key: str, timeout=12):
    return POOL.post(body, key, timeout)


class Memory:
    """Facts they asked it to remember ("remember my sister's birthday is 12 March"), kept on this panel."""

    def __init__(self):
        self.path = STATE_DIR / "assistant-memory.json"
        try:
            self.facts = json.loads(self.path.read_text())
        except Exception:
            self.facts = []

    def add(self, fact):
        f = (fact or "").strip()
        if f and not any(x.lower() == f.lower() for x in self.facts):
            self.facts = (self.facts + [f])[-60:]
            self._save()

    def forget(self, what) -> int:
        words = {w for w in (what or "").lower().split() if len(w) > 2}
        before = len(self.facts)
        self.facts = [f for f in self.facts
                      if not (words and len(words & {w for w in f.lower().split() if len(w) > 2}) / len(words) >= 0.5)]
        if len(self.facts) != before:
            self._save()
        return before - len(self.facts)

    def _save(self):
        try:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(self.facts))
        except Exception:
            pass


def partial_string(key, s):
    """The value of a string key as far as it has arrived in streaming JSON (no closing quote needed)."""
    m = re.search(r'"' + key + r'"\s*:\s*"', s)
    if not m:
        return None
    out, i, esc = [], m.end(), False
    while i < len(s):
        c = s[i]
        if esc:
            esc = False
            if c in "nt":
                out.append(" ")
            elif c == "u":
                h = s[i + 1:i + 5]
                if len(h) < 4:
                    break
                try:
                    out.append(chr(int(h, 16)))
                except ValueError:
                    pass
                i += 4
            else:
                out.append(c)
        elif c == "\\":
            esc = True
        elif c == '"':
            return "".join(out), True
        else:
            out.append(c)
        i += 1
    return "".join(out), False


class Brain:
    def __init__(self, key: str, model: str | None, place="Bangalore", room="living room"):
        self.key = key.strip()
        self.model = model or "claude-haiku-5-5"
        self.place, self.room = place, room
        self.history: list[dict] = []           # {said, spoken, did, at, interrupted}
        self.memory = Memory()
        self.last_error = ""

    def remember(self, said, spoken, did=""):
        self.history = (self.history + [{"said": said, "spoken": spoken, "did": did, "at": time.time(), "interrupted": False}])[-12:]

    def mark_interrupted(self):
        if self.history:
            self.history[-1]["interrupted"] = True

    def warm(self):
        """Open the connection early (DNS + TLS) while the person is still talking."""
        threading.Thread(target=POOL.warm, daemon=True).start()

    # ---------------------------------------------------------------- the prompt (the phone's, for the living room)
    def system(self, has_computer: bool) -> str:
        facts = "\n".join("  • " + f for f in self.memory.facts) or "(nothing remembered yet)"
        computer = """
Their computer (only if snapshot.computer is set):
- kind "computer" with command "sleep", "lock", "screen_off", "shutdown" or "restart". "Turn off my laptop/Mac/computer" \
means shutdown; "put it to sleep" = sleep.
- Shutdown and restart need a yes first: if they haven't just confirmed, no action — ask "Shut down your Mac now? \
Anything unsaved might ask to be saved." with follow_up true, and do it when they say yes. Sleep, lock and screen off: just do it.
- It can't turn the computer on.
""" if has_computer else ""
        return f"""You are the voice assistant on a panel in the user's {self.room} in {self.place}, India — like Alexa \
or Google Assistant, but warmer and smarter. You control their lights and Spotify, and you can also just talk: \
answer questions, explain things, help them think, chat. They speak; speech recognition turns it into text, which \
sometimes mishears (Indian-English accents; names and places get mangled most): read odd words as a mishearing and \
answer the sensible question — never ask about a strange word that's obviously a mishearing. Go by the sound: \
"standard time of five minutes" is "set a timer for five minutes"; "make a posing" / "make it cosy" / "make \
it cause he" is "make it cozy" (a lighting scene); "turn off/on" can come out as "no off", "done off", "turn of"; "set a time" is "set a timer". "alarm" can come out as "a lot" or "llama". When a \
sound-alike reading is a clear command, just do it — don't ask. \
Work out what they mean and call control_home exactly once.

Talking:
- "say" is spoken aloud by a text-to-speech voice. Sound like a friendly, sharp person — natural, contractions, no \
lists, no markdown, no symbols, no emoji. Numbers as people say them.
- Home commands: one short sentence ("Done, the living room's cosy."). Don't narrate obvious things. say is never \
empty when you act — for music it's a few words before it starts ("Putting on something chill.").
- Questions and chat: answer properly but briefly — usually one to three sentences; up to five if they ask you to \
explain something. Lead with the answer.
- Use the snapshot for time, date, weather here, air quality, calendar and what's playing. For live facts (news, \
scores, prices today, weather elsewhere) use look_up — don't say you can't know.

Conversation:
- After you speak, the panel keeps listening for about 8 seconds without the wake word, so they can just carry on.
- follow_up: true by default — they might well add something. False only when the exchange is clearly over: they \
said thanks / that's all / goodnight, or said bye.
- The earlier messages are this conversation. Resolve references from them: "it", "that one", "the other one", \
"do the same for the floor lamp", "and tomorrow?", "why?", "a bit more". Never ask for something they already told you.
- Don't greet again mid-conversation and don't repeat what you just said. Vary your wording.
- If an earlier answer of yours was cut off (marked interrupted), they may not have heard the end.
- for_me: in a follow-up turn (marked as one), the mic may pick up talk that isn't for you — them talking to someone \
else, a call, the TV, singing along. If it isn't addressed to you, set for_me false, say "", reply "", no actions. \
Otherwise true. In a turn that started with the wake word it's always true.
- Ask at most one short question at a time, and only when you really need the answer.
{computer}
Memory:
- "Remember that …" → kind "remember" with label = the fact, short and in third person; confirm briefly. \
"Forget that …" → kind "forget" with label = what to forget.
- What you remember about them is listed below; use it naturally when relevant, never recite it unprompted.
{facts}

Everyday things:
- Weather: use snapshot.weather (now, next hours, next days, sunrise/sunset).
- Anything you'd need to look up — weather anywhere other than here, news, scores, prices, opening hours, recent \
events, facts you aren't sure of: kind "look_up" with question = a complete, self-contained question (fix any \
mishearing, add the place and day). say "Let me check." (or similar, a few words), reply "", card "none". The panel \
searches the web and reads the answer out. Advice, opinions and general knowledge you answer yourself, briefly.
- Reminders (kept on this panel): "remind me to call Mom at 6", "in 20 minutes remind me to check the oven", \
"remind me tomorrow morning to…" → kind "set_reminder" with label = the thing, short and in their words, at = local \
time "YYYY-MM-DD HH:MM" worked out from snapshot.now. Vague times: "morning" 9:00, "afternoon" 14:00, "evening" \
18:00, "tonight" 20:00; if there's no time at all and it isn't obvious, ask when. Confirm briefly. "What are my \
reminders?" → read snapshot.reminders. "Cancel the oven one" → "cancel_reminder" with reminder_id. When \
snapshot.reminder_showing is set and they say "done", "ok", "got it" → "reminder_done".
- Timers: kind "timer" with seconds and a short label ("pasta", "tea"). Anything they want to be reminded of is a \
reminder, not a timer. "Cancel the pasta timer" → kind "cancel_timer" with label (no label = all). "How long's \
left?" → read snapshot.timers.
- Alarms: kind "set_alarm" with time "HH:MM" (24-hour), days (["mon","tue",…]; empty = once; "weekdays" = mon–fri, \
"every day" = all seven). "Wake me up at 7" = set_alarm 07:00. "Turn off my 7am alarm" → "alarm_off" with alarm_id; \
"delete" → "delete_alarm". "What alarms do I have?" → read snapshot.alarms. Confirm the time out loud.
- Sleep timer: "stop the music in 30 minutes" → kind "sleep_timer" with seconds.
- card: pick the visual shown beside your answer — "weather" (current conditions, today), "forecast" (tomorrow / \
next days / rain later / sunrise), "air" (air quality), "timer" (set or asked about a timer), "music" (what's \
playing, or after changing music), "schedule" (calendar), "alarm" (set or asked about alarms), or "none".

Home rules:
- Use light ids from the home snapshot only. "the lights" / "lights" with no room means the room the panel is in ("here").
- A room name means every light in it.
- Relative requests use current state: "brighter" ≈ +25 points, "dimmer" ≈ −25, "a bit" ≈ ±10, clamp 1–100. \
"warmer" ≈ −800 K, "cooler" ≈ +800 K, clamp 2200–6500.
- Moods: cosy/relax ≈ 2400 K at 35 %, reading/focus ≈ 4200 K at 90 %, movie ≈ 20 %, night light ≈ 5 % at 2200 K, \
"too bright in here" = dim the lit lights.
- Colour names → rgb, e.g. red [255,0,0], orange [255,110,0], warm yellow [255,190,60], green [0,255,60], \
blue [0,70,255], purple [150,0,255], pink [255,40,140], teal [0,200,180].
- Change only what they asked for: "warm" / "cooler" = kelvin only, "dim" / "50 percent" = brightness only. Moods set both.
- Setting brightness, warmth or colour on a light that is off also turns it on.
- Music is Spotify (or AirPlay from their phone — then music and volume actions control that). To play something \
specific, use kind "play" with a search query and search_type. If they name a speaker, pass it inside that play \
action (closest name from the speaker list).
- "my_playlists" are their own Spotify playlists: if they ask for one, use kind "play" with its uri. Otherwise search.
- "goodnight" = all lights off and pause music. "turn everything off" = all lights off.
- Questions ("what's next", "is the floor lamp on", "what's playing") → no actions; answer.
- If it's unclear, no actions — ask a short clarifying question and set follow_up true.
- reply: a short on-screen caption, lowercase, under 9 words, no full stop. For commands what you did ("living room \
· 30% · warm"); for answers the gist ("23° and cloudy · rain after 4").
- say: the spoken version (see Talking)."""

    ACTION = {
        "type": "object",
        "properties": {
            "kind": {"type": "string", "enum": ["lights", "music", "volume", "speaker", "play", "timer", "cancel_timer",
                                                "set_alarm", "alarm_off", "delete_alarm", "sleep_timer", "remember",
                                                "forget", "computer", "look_up", "set_reminder", "cancel_reminder",
                                                "reminder_done"]},
            "reminder_id": {"type": "string"}, "at": {"type": "string"},
            "time": {"type": "string"},
            "days": {"type": "array", "items": {"type": "string", "enum": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]}},
            "alarm_id": {"type": "string"},
            "seconds": {"type": "integer", "minimum": 1},
            "label": {"type": "string"},
            "light_ids": {"type": "array", "items": {"type": "string"}},
            "on": {"type": "boolean"},
            "brightness": {"type": "integer", "minimum": 1, "maximum": 100},
            "kelvin": {"type": "integer", "minimum": 2200, "maximum": 6500},
            "rgb": {"type": "array", "items": {"type": "integer"}, "minItems": 3, "maxItems": 3},
            "command": {"type": "string", "enum": ["play", "pause", "next", "previous", "sleep", "lock", "screen_off", "shutdown", "restart"]},
            "level": {"type": "integer", "minimum": 0, "maximum": 100},
            "change": {"type": "integer"},
            "speaker": {"type": "string"}, "query": {"type": "string"},
            "search_type": {"type": "string", "enum": ["track", "artist", "album", "playlist"]},
            "uri": {"type": "string"}, "question": {"type": "string"},
        },
        "required": ["kind"],
    }

    def interpret(self, text, snapshot: dict, follow_up: bool, has_computer: bool, on_say, on_done, alt=""):
        """Streams Claude's answer. on_say(sentence) as soon as the spoken line is complete; on_done(outcome or None)."""
        threading.Thread(target=self._interpret, args=(text, snapshot, follow_up, has_computer, on_say, on_done, alt), daemon=True).start()

    def _interpret(self, text, snapshot, follow_up, has_computer, on_say, on_done, alt=""):
        recent, last = [], time.time()
        for t in reversed(self.history):
            if last - t["at"] > 600:
                break
            recent.insert(0, t); last = t["at"]
        messages = []
        for t in recent:
            messages.append({"role": "user", "content": t["said"]})
            a = t["spoken"] or "(said nothing)"
            if t["did"] and t["did"].lower() != t["spoken"].lower():
                a += f"  [did: {t['did']}]"
            if t["interrupted"]:
                a += "  [they cut this answer off]"
            messages.append({"role": "assistant", "content": a})
        messages.append({"role": "user", "content": "Home snapshot right now:\n" + json.dumps(snapshot) + "\n\n" +
                         ("(Follow-up turn — no wake word, the mic was just left open.) " if follow_up else "") +
                         f"They said: “{text}”" +
                         (f" (the recogniser's earlier guess was “{alt}” — go by whichever makes more sense)" if alt else "")})
        # "say" first in the schema, so it streams in (and can be spoken) before the actions
        schema = {"type": "object", "properties": {
            "say": {"type": "string"}, "reply": {"type": "string"},
            "actions": {"type": "array", "items": self.ACTION},
            "follow_up": {"type": "boolean"}, "for_me": {"type": "boolean"},
            "card": {"type": "string", "enum": ["none", "weather", "forecast", "air", "timer", "music", "schedule", "alarm"]}},
            "required": ["say", "reply", "actions", "follow_up", "for_me", "card"]}
        body = {"model": self.model, "max_tokens": 500, "stream": True,
                "system": [{"type": "text", "text": self.system(has_computer), "cache_control": {"type": "ephemeral"}}],
                "tools": [{"name": "control_home", "input_schema": schema,
                           "description": "Carry out the request. Write say first, then reply, then actions, follow_up, for_me, card."}],
                "tool_choice": {"type": "tool", "name": "control_home"}, "messages": messages}
        t0 = time.time()
        js, said = "", False
        try:
            with _post(body, self.key) as r:
                for raw in r:
                    line = raw.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    try:
                        ev = json.loads(line[5:].strip())
                    except ValueError:
                        continue
                    if ev.get("type") == "content_block_delta" and (ev.get("delta") or {}).get("type") == "input_json_delta":
                        js += ev["delta"].get("partial_json", "")
                        if not said:
                            p = partial_string("say", js)
                            if p and p[1]:
                                said = True
                                print(f"[room] claude: spoken line ready in {int((time.time() - t0) * 1000)} ms")
                                on_say(p[0])
                    elif ev.get("type") == "message_stop":
                        break
            out = json.loads(js) if js else None
        except urllib.error.HTTPError as e:
            self.last_error = "anthropic key was rejected" if e.code == 401 else f"assistant error {e.code}"
            print(f"[room] claude: {e.code} {e.read()[:300]!r}")
            out = None
        except Exception as e:
            self.last_error = "no internet" if isinstance(e, (urllib.error.URLError, TimeoutError, OSError)) else repr(e)
            print(f"[room] claude: {e!r}")
            out = None
        print(f"[room] claude {int((time.time() - t0) * 1000)} ms for {text!r}" + (f" (or {alt!r})" if alt else ""))
        if out:
            print(f"[room] claude said {out.get('say', '')!r} · did {[a.get('kind') for a in out.get('actions') or []]}")
        on_done(out)

    def look_up(self, question, done):
        """A question that needs the web (Claude's web search), answered for speaking. done(answer or None)."""
        def go():
            body = {"model": self.model, "max_tokens": 1024,
                    "system": (f"You are the voice of a smart speaker in {self.place}, India, talking to its owner. It is "
                               f"{dt.datetime.now():%A %-d %B %Y, %-I:%M %p} there. Search the web if you need current facts, then "
                               "reply the way a sharp friend would out loud: one or two short sentences, under 35 words, the answer "
                               "first. Never mention searching, results, pages, sources or websites. If a word looks wrong, silently "
                               "answer what they obviously meant. Plain words, numbers as people say them, Celsius and kilometres, "
                               "rupees for prices unless asked otherwise. No lists, no markdown, no caveats."),
                    "messages": [{"role": "user", "content": question}],
                    "tools": [{"type": "web_search_20250305", "name": "web_search", "max_uses": 1}]}
            ans = None
            try:
                with _post(body, self.key, timeout=25) as r:
                    o = json.loads(r.read())
                blocks = []
                for c in o.get("content", []):
                    if c.get("type") == "text":
                        blocks.append(c.get("text", ""))
                    elif "tool" in (c.get("type") or ""):
                        blocks = []
                a = re.sub(r"\s+", " ", "".join(blocks)).strip()
                a = re.sub(r"\[[0-9, ]+\]", "", a)
                sentences = re.findall(r"[^.!?]+[.!?]?", a)
                ans = " ".join(s.strip() for s in sentences[:2]).strip() or None
            except Exception as e:
                print(f"[room] look-up: {e!r}")
            done(ans)
        threading.Thread(target=go, daemon=True).start()


class Computer:
    """The 'Room remote' helper on the Mac (sleep, lock, screen off, shut down, restart) — the same as the phone's."""
    ACTIONS = {"sleep", "lock", "screen_off", "shutdown", "restart"}

    def __init__(self, c: dict | None):
        c = c or {}
        self.ok = bool(c.get("host") and c.get("token"))
        self.name = c.get("name") or "my computer"
        self.urls = [f"http://{c.get('host')}:{c.get('port', 8765)}"] + ([f"http://{c['ip']}:{c.get('port', 8765)}"] if c.get("ip") else [])
        self.token = c.get("token", "")

    def send(self, action, done):
        def go():
            why = "can't " + action
            if action in self.ACTIONS:
                for u in self.urls:
                    try:
                        req = urllib.request.Request(f"{u}/{action}", method="POST", headers={"X-Room-Token": self.token})
                        urllib.request.urlopen(req, timeout=5)
                        why = None; break
                    except urllib.error.HTTPError as e:
                        why = "the key didn't match" if e.code == 401 else f"error {e.code}"; break
                    except Exception:
                        why = "couldn't reach it — is it awake and on the same Wi-Fi?"
            done(why)
        threading.Thread(target=go, daemon=True).start()
