"""What was said → what to do. Plain rules, no cloud: the same kind of preset commands the iPhone panel answered.

parse(text, rooms, playlists) → {"do": <action>, ...}. Nothing here touches lights or music; assistant.py acts on it.
"""
import re

ONES = {"zero": 0, "oh": 0, "one": 1, "a": 1, "an": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19}
TENS = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}

COLOURS = {"red": (255, 60, 40), "orange": (255, 140, 30), "yellow": (255, 210, 60), "green": (60, 210, 120),
           "blue": (40, 120, 255), "purple": (140, 80, 255), "violet": (140, 80, 255), "pink": (255, 70, 160),
           "teal": (40, 200, 190), "cyan": (40, 200, 230), "white": None}
WARMTH = {"candle": 2200, "warm": 2700, "warm white": 2700, "neutral": 4000, "cool": 5000, "cool white": 5000,
          "daylight": 6500, "bright white": 6500}
SCENES = {"movie": "Movie", "film": "Movie", "evening": "Evening", "night": "Night", "relax": "Relax", "relaxing": "Relax",
          "read": "Read", "reading": "Read", "cozy": "Relax", "cosy": "Relax"}

# What the recogniser writes when it mishears a command, → what was said. Only whole, well-known command shapes, so a
# real sentence is never "corrected" (Alexa does the same: a reading that's a valid command beats one that isn't).
SOUNDALIKES = [
    (r"^(?:no|now|know|done|don|torn|tone|ton|tun|tan|then|turned|tune|tum|tom|town)\s+(off|on)\b", r"turn \1"),
    (r"^(?:switch|turn)\s+of\b", "turn off"),
    (r"\blights? of$", "lights off"),
    (r"^(?:set|said|sit|sat)\s+(?:a\s+)?(?:time|timer|tie|type)\s+(?:of|for|off|to)\s+", "set a timer for "),
    (r"^standard time of\s+", "set a timer for "),
    (r"^(?:set a|start a)\s+time\b", "set a timer"),
    (r"^make (?:a posing|a cozy|a cosy|it cosy|it cause he|it cosie|it causey|it cozie|a cozie|it kozy)$", "make it cozy"),
    (r"^(?:please|plays|place|played|flay|blaze|plea)\s+(?:drink|thing|sting|some thing|something|some)\b", "play something"),
    (r"^(?:say|stay|play)\s+something\s+(\w+)\s+on\s+spot(?:ify)?$", r"play something \1"),
    (r"\bon spot$", "on spotify"),
    (r"^(?:paws|pours|pores|pass)$", "pause"),
    (r"^(?:next song|skip it|skip this)$", "next"),
]


def soundalike(t: str) -> str:
    for pat, to in SOUNDALIKES:
        t = re.sub(pat, to, t)
    return t


def words_to_numbers(t: str) -> str:
    """'twenty five minutes' → '25 minutes', 'half an hour' → '30 minutes', 'a minute' → '1 minute'."""
    t = re.sub(r"\bhalf an hour\b", "30 minutes", t)
    t = re.sub(r"\ban hour and a half\b", "90 minutes", t)
    t = re.sub(r"\bquarter of an hour\b", "15 minutes", t)
    toks, out, i = t.split(), [], 0
    while i < len(toks):
        w = toks[i]
        if w in TENS:
            n = TENS[w]
            if i + 1 < len(toks) and toks[i + 1] in ONES and ONES[toks[i + 1]] < 10 and toks[i + 1] not in ("a", "an", "oh"):
                n += ONES[toks[i + 1]]; i += 1
            out.append(str(n))
        elif w in ONES and w not in ("a", "an", "oh"):
            out.append(str(ONES[w]))
        elif w in ("a", "an") and i + 1 < len(toks) and re.match(r"(second|minute|hour|day)s?$", toks[i + 1]):
            out.append("1")
        elif w == "hundred" and out and out[-1].isdigit():
            out[-1] = str(int(out[-1]) * 100)
        else:
            out.append(w)
        i += 1
    return " ".join(out)


def clean(text: str) -> str:
    t = text.lower()
    t = re.sub(r"[^\w\s:%'.-]", " ", t)
    t = re.sub(r"^\s*(hey\s+|ok(ay)?\s+)?alexa[\s,]*", "", t)
    t = soundalike(re.sub(r"\s+", " ", t).strip(" ."))         # before "please" goes: "please drink chill" is "play something chill"
    t = re.sub(r"\b(please|could you|can you|would you|kindly|just)\b", " ", t)
    t = t.replace("%", " percent").replace("o'clock", "").replace("p.m.", "pm").replace("a.m.", "am")
    t = re.sub(r"(\d)\.(?=\s|$)", r"\1", t)
    t = re.sub(r"\s+", " ", t).strip(" .")
    return words_to_numbers(soundalike(t))


def duration(t: str) -> int | None:
    """Seconds in '10 minutes', '1 hour 20 minutes', '90 seconds', '2 and a half minutes'."""
    total, found = 0, False
    for n, unit in re.findall(r"(\d+(?:\.\d+)?)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b", t):
        n = float(n); found = True
        total += n * (3600 if unit.startswith("h") else 60 if unit.startswith("m") else 1)
    if re.search(r"\band a half (minute|hour)", t):
        m = re.search(r"and a half (minute|hour)", t)
        total += 30 if m.group(1) == "minute" else 1800
        found = True
    return int(total) if found and total > 0 else None


def clock_time(t: str):
    """(hour24, minute) from '7', '7 am', '7:30 pm', '730', 'half past 6', 'quarter to 8', 'noon', 'midnight'."""
    if re.search(r"\bnoon\b|\bmidday\b", t):
        return 12, 0
    if re.search(r"\bmidnight\b", t):
        return 0, 0
    m = re.search(r"\b(half|quarter) past (\d{1,2})\b", t)
    if m:
        return _ampm(int(m.group(2)), 30 if m.group(1) == "half" else 15, t)
    m = re.search(r"\bquarter to (\d{1,2})\b", t)
    if m:
        return _ampm((int(m.group(1)) - 1) % 12 or 12, 45, t)
    m = re.search(r"\b(\d{1,2})(?::(\d{2})|\s([0-5]\d)(?=\s|$))?\s*(am|pm|in the morning|in the evening|at night|tonight)?\b", t)
    if not m:
        return None
    h = int(m.group(1)); mi = int(m.group(2) or m.group(3) or 0)
    if h > 23 or mi > 59:
        return None
    return _ampm(h, mi, t, m.group(4))


def _ampm(h, mi, t, suffix=None):
    s = suffix or ""
    if not s:
        if re.search(r"\b(pm|evening|tonight|at night)\b", t):
            s = "pm"
        elif re.search(r"\b(am|morning)\b", t):
            s = "am"
    if s in ("pm", "in the evening", "at night", "tonight") and h < 12:
        h += 12
    elif s in ("am", "in the morning") and h == 12:
        h = 0
    return h, mi


def match_room(t: str, rooms: list[str]):
    """The room named in t ('living room', 'my bedroom' → "Aviral's bedroom" when it's the only bedroom-ish)."""
    best = None
    for r in rooms:
        rl = r.lower()
        names = {rl, rl.replace("'s", ""), rl.replace("'s", "s")}
        for n in names:
            if re.search(r"\b" + re.escape(n) + r"\b", t):
                if not best or len(n) > len(best[1]):
                    best = (r, n)
    if best:
        return best[0]
    # a last word match ('kitchen', 'bedroom') when it's unambiguous
    for key in ("kitchen", "bedroom", "living", "lounge", "hall", "bathroom", "study", "office", "dining"):
        if re.search(r"\b" + key, t):
            hits = [r for r in rooms if key in r.lower() or (key == "lounge" and "living" in r.lower())]
            if len(hits) == 1:
                return hits[0]
    return None


def percent(t: str):
    m = re.search(r"\b(\d{1,3})\s*(percent|per cent)?\b", t)
    if m and (m.group(2) or re.search(r"\b(to|at)\s+\d{1,3}\b", t)):
        return max(1, min(100, int(m.group(1))))
    if re.search(r"\b(full|max|maximum|100)\b", t):
        return 100
    if re.search(r"\bhalf\b", t):
        return 50
    return None


def parse(text: str, rooms: list[str] | None = None, playlists: list[str] | None = None) -> dict:
    rooms = rooms or []
    playlists = playlists or []
    t = clean(text)
    if not t:
        return {"do": "nothing"}
    if re.fullmatch(r"(stop|cancel|never ?mind|nothing|forget it|shut up|quiet|that's all|thanks?|thank you|no thanks?)( alexa)?", t):
        return {"do": "dismiss", "thanks": "thank" in t}

    # ---------------------------------------------------------------- timers
    if re.search(r"\btimer\b", t) or re.match(r"(start|set) (a )?\d", t):
        if re.search(r"\b(cancel|stop|delete|remove|kill|end)\b", t):
            return {"do": "timer_cancel"}
        if re.search(r"\b(how (long|much)|time left|remaining|left on)\b", t):
            return {"do": "timer_left"}
        if re.search(r"\b(pause|hold)\b", t):
            return {"do": "timer_pause"}
        if re.search(r"\b(resume|continue|unpause)\b", t):
            return {"do": "timer_resume"}
        d = duration(t)
        if re.search(r"\badd\b|\bmore\b|\bextra\b", t) and d:
            return {"do": "timer_add", "sec": d}
        if d:
            m = re.search(r"\b(?:called|named|for the|for my|labell?ed)\s+([a-z][a-z ]{1,24}?)(?:\s+(?:for|timer)\b|$)", t)
            label = m.group(1).strip() if m and not re.search(r"\d", m.group(1)) else ""
            if not label:
                m = re.search(r"\b([a-z]+) timer\b", t)
                label = m.group(1) if m and m.group(1) not in ("a", "the", "my", "minute", "minutes", "hour", "second", "kitchen") else ""
            return {"do": "timer_start", "sec": d, "label": label.title() if label else ""}
        return {"do": "ask", "what": "timer_length"}

    # ---------------------------------------------------------------- alarms
    if re.search(r"\balarms?\b|\bwake me( up)?\b", t):
        if re.search(r"\b(cancel|delete|remove|turn off|switch off|disable|stop)\b", t):
            return {"do": "alarm_off", "at": clock_time(t), "all": bool(re.search(r"\ball\b", t))}
        if re.search(r"\b(what time|when|what's|what is|do i have|is my|list|which)\b", t) and not re.search(r"\b(set|make|create|add)\b", t):
            return {"do": "alarm_query"}
        at = clock_time(t)
        if not at:
            d = duration(t)
            if d and re.search(r"\bin\b", t):
                return {"do": "alarm_set", "in": d}
            return {"do": "ask", "what": "alarm_time"}
        days = []
        if re.search(r"\bweekdays?\b|\bevery weekday\b|\bworkdays?\b", t):
            days = [0, 1, 2, 3, 4]
        elif re.search(r"\bweekends?\b", t):
            days = [5, 6]
        elif re.search(r"\bevery ?day\b|\bdaily\b", t):
            days = list(range(7))
        return {"do": "alarm_set", "h": at[0], "m": at[1], "days": days}

    # ---------------------------------------------------------------- reminders
    if re.search(r"\bremind me\b|\breminders?\b|\bdon't let me forget\b", t):
        if re.search(r"\b(what|which|list|any|read|do i have)\b", t) and not re.search(r"\bremind me to\b", t):
            return {"do": "reminder_list"}
        m = re.search(r"(?:remind me (?:to|that|about)?|reminder (?:to|for)?|don't let me forget (?:to)?)\s*(.+)", t)
        what = m.group(1) if m else ""
        due_in = None; at = None; day = 0
        mi = re.search(r"\bin (\d+(?:\.\d+)? (?:hours?|minutes?|seconds?)(?: (?:and )?\d+ (?:minutes?|seconds?))?)\b", what)
        if mi:
            due_in = duration(mi.group(1)); what = what.replace(mi.group(0), " ")
        if re.search(r"\btomorrow\b", what):
            day = 1; what = re.sub(r"\btomorrow\b", " ", what)
        mt = re.search(r"\b(?:at|by|around)\s+(\d{1,2}(?::\d{2}|\s\d{2})?\s*(?:am|pm)?|noon|midnight|half past \d{1,2}|quarter (?:past|to) \d{1,2})\b(?:\s*(?:in the )?(morning|evening|tonight|night|afternoon))?", what)
        if mt:
            at = clock_time(mt.group(0)); what = what.replace(mt.group(0), " ")
        for w in ("this evening", "tonight", "this afternoon", "in the morning", "this morning"):
            if w in what:
                if not at:
                    at = {"this evening": (18, 0), "tonight": (20, 0), "this afternoon": (15, 0), "in the morning": (9, 0), "this morning": (9, 0)}[w]
                    if w == "in the morning" and not day:
                        day = 1
                what = what.replace(w, " ")
        if day and not at:
            at = (9, 0)
        what = re.sub(r"\s+", " ", what).strip(" .,")
        what = re.sub(r"^(to|that|about)\s+", "", what)
        if not what:
            return {"do": "ask", "what": "reminder_text"}
        return {"do": "reminder_add", "text": what[0].upper() + what[1:], "in": due_in, "at": at, "day": day}

    # ---------------------------------------------------------------- weather
    if re.search(r"\b(weather|temperature|how (hot|cold|warm)|rain|raining|umbrella|forecast|sunny|humid|outside)\b", t):
        when = "tomorrow" if "tomorrow" in t else "today"
        if re.search(r"\b(rain|raining|umbrella|wet|shower)\b", t):
            return {"do": "weather_rain", "when": when}
        return {"do": "weather", "when": when}

    # ---------------------------------------------------------------- time, date, calendar
    if re.search(r"\bwhat('s| is)? the time\b|\bwhat time is it\b|\btime is it\b|^time$", t):
        return {"do": "time"}
    if re.search(r"\b(what('s| is)? (the )?date|what day is it|which day is it|today's date)\b", t):
        return {"do": "date"}
    if re.search(r"\b(calendar|schedule|what's next|what is next|what's on|what do i have|meetings?|agenda|plans)\b", t):
        return {"do": "calendar", "when": "tomorrow" if "tomorrow" in t else "next"}

    # ---------------------------------------------------------------- music
    if re.search(r"\b(volume|louder|quieter|softer|turn it (up|down)|turn up the|turn down the)\b", t) and not match_room(t, rooms):
        n = percent(t) or (int(m.group(1)) if (m := re.search(r"\bvolume (?:to )?(\d{1,3})\b", t)) else None)
        if n is not None:
            return {"do": "volume", "to": n}
        if re.search(r"\b(up|louder|increase|raise)\b", t):
            return {"do": "volume", "by": 15}
        if re.search(r"\b(down|quieter|softer|lower|decrease)\b", t):
            return {"do": "volume", "by": -15}
    if re.fullmatch(r"(pause|stop)( the)?( music| song| playback| it)?", t) or re.search(r"\bpause\b", t):
        return {"do": "pause"}
    if re.fullmatch(r"(resume|continue|play|unpause)( the)?( music| song| playback| it)?", t):
        return {"do": "resume"}
    if re.search(r"\b(next|skip)( song| track| one)?\b", t) and not re.search(r"\b(what's next|what is next|next meeting|next event)\b", t):
        return {"do": "next"}
    if re.search(r"\b(previous|last|go back|back)( song| track| one)?\b", t) and re.search(r"\b(song|track|previous|play)\b", t):
        return {"do": "previous"}
    if re.search(r"\b(what('s| is) (this|playing)|what song|who (is this|sings)|what's this song)\b", t):
        return {"do": "now_playing"}
    if re.search(r"\b(like|love|save|heart) (this|the) (song|track)\b", t):
        return {"do": "like"}
    m = re.match(r"(?:play|put on|start)\s+(?:my |the |some )?(.+?)(?:\s+(?:playlist|on spotify))?$", t)
    if m:
        q = m.group(1).strip()
        best = _best_playlist(q, playlists)
        # a mood, not a name: "something chill", "some jazz", "relaxing music" → a playlist search for it
        mm = re.fullmatch(r"(?:something|some|a bit of|anything)\s+(.+?)|(.+?)\s+(?:music|songs|vibes|tunes)", q)
        mood = (mm.group(1) or mm.group(2)).strip() if mm else ""
        if not mood and re.match(r"(?:play|put on|start)\s+some\s+\w", t):
            mood = q                        # "play some jazz"
        mood = re.sub(r"^(?:something|some|a little|nice|good)\s+", "", mood)
        mood = mood if mood and len(mood.split()) <= 3 else ""
        phrase = ("something " + mood) if q.startswith("something") else ("some " + q) if mood else ""
        return {"do": "play", "query": q, "playlist": best, "mood": mood, "phrase": phrase}

    if re.search(r"\bspotify\b", t):
        return {"do": "unknown", "text": t}        # something about music that isn't a plain command: Claude

    # ---------------------------------------------------------------- lights
    lightish = re.search(r"\b(cozy|cosy|lights?|lamps?|bulbs?|brightness|bright|dim|dimmer|brighter|warmer|cooler|colder|on|off|percent|colou?r|"
                         + "|".join(COLOURS) + "|" + "|".join(WARMTH) + r"|mode|scene)\b", t)
    room = match_room(t, rooms)
    if lightish or room:
        for w, scene in SCENES.items():
            if re.search(r"\b" + w + r"( mode| time| scene| lights?)?\b", t) and re.search(r"\b(mode|scene|time|lights?|set|make|turn|switch|it's|its|going to)\b", t):
                return {"do": "scene", "scene": scene, "room": room}
        everything = bool(re.search(r"\b(all|every|everything|whole house|house|all the)\b", t)) and not room
        target = None if everything else room
        if re.search(r"\b(turn|switch|shut|put)\b.*\boff\b|\boff\b.*\blights?\b|\blights? off\b|^off$|\bkill the lights\b", t):
            return {"do": "lights", "room": target, "all": everything, "on": False}
        p = percent(t)
        if p is not None and re.search(r"\b(to|at|set|percent|brightness|dim|make)\b", t):
            return {"do": "lights", "room": target, "all": everything, "level": p}
        for w, rgb in COLOURS.items():
            if re.search(r"\b" + w + r"\b", t):
                if rgb is None:
                    return {"do": "lights", "room": target, "all": everything, "kelvin": 4000}
                return {"do": "lights", "room": target, "all": everything, "rgb": list(rgb)}
        for w in sorted(WARMTH, key=len, reverse=True):
            if re.search(r"\b" + w + r"\b", t):
                return {"do": "lights", "room": target, "all": everything, "kelvin": WARMTH[w]}
        if re.search(r"\bwarmer\b", t):
            return {"do": "lights", "room": target, "all": everything, "warmer": True}
        if re.search(r"\b(cooler|colder|whiter)\b", t):
            return {"do": "lights", "room": target, "all": everything, "cooler": True}
        if re.search(r"\b(dim|dimmer|darker|lower|down)\b", t):
            return {"do": "lights", "room": target, "all": everything, "step": -25}
        if re.search(r"\b(brighter|brighten|up|more light|bright)\b", t):
            return {"do": "lights", "room": target, "all": everything, "step": 25}
        if re.search(r"\b(turn|switch|put)\b.*\bon\b|\bon\b|\blights? on\b", t):
            return {"do": "lights", "room": target, "all": everything, "on": True}
        if re.search(r"\b(are|is) .*\b(on|off)\b|\bwhich lights\b", t):
            return {"do": "lights_query", "room": target}

    if re.search(r"\b(hello|hi|hey|good (morning|evening|night|afternoon))\b", t):
        return {"do": "greet"}
    return {"do": "unknown", "text": t}


def _best_playlist(q: str, playlists: list[str]):
    q = q.lower().strip()
    if not playlists:
        return None
    if re.search(r"\b(liked|favou?rites?|my songs|saved)\b", q):
        for p in playlists:
            if "liked" in p.lower():
                return p
    qs = set(re.findall(r"\w+", q)) - {"music", "songs", "playlist", "some", "my", "the"}
    best, score = None, 0.0
    for p in playlists:
        ps = set(re.findall(r"\w+", p.lower()))
        if p.lower() == q:
            return p
        if not ps:
            continue
        s = len(qs & ps) / max(len(ps), 1)
        if s > score:
            best, score = p, s
    return best if score >= 0.5 else None
