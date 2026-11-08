"""Sample data for ROOM_DEMO=1 — lets the screens be checked anywhere, without bulbs, Spotify or a calendar."""
WEATHER = {"ok": True, "t": 20, "feels": 20, "hum": 78, "d": "Overcast", "hi": 29, "lo": 20, "aqi": 62,
           "days": [{"name": "Today", "d": "Overcast", "hi": 29, "lo": 20, "p": 60}, {"name": "Mon", "d": "Rain", "hi": 27, "lo": 19, "p": 70}, {"name": "Tue", "d": "Partly cloudy", "hi": 28, "lo": 19, "p": 10}],
           "sunrise": "6:12", "sunset": "5:48", "updated": "11:10",
           "hours": [{"h": 11, "t": 20, "p": 0, "d": "Overcast"},
                     {"h": 12, "t": 21, "p": 0, "d": "Overcast"},
                     {"h": 13, "t": 23, "p": 10, "d": "Overcast"},
                     {"h": 14, "t": 25, "p": 10, "d": "Overcast"},
                     {"h": 15, "t": 27, "p": 20, "d": "Overcast"},
                     {"h": 16, "t": 28, "p": 60, "d": "Overcast"},
                     {"h": 17, "t": 29, "p": 40, "d": "Overcast"},
                     {"h": 18, "t": 28, "p": 20, "d": "Overcast"},
                     {"h": 19, "t": 26, "p": 10, "d": "Overcast"},
                     {"h": 20, "t": 24, "p": 0, "d": "Overcast"},
                     {"h": 21, "t": 22, "p": 0, "d": "Overcast"},
                     {"h": 22, "t": 21, "p": 0, "d": "Overcast"}]}
EVENTS = [] if __import__("os").environ.get("ROOM_DEMO_EMPTY") == "1" else [{"when": "10 pm", "title": "Dinner", "extra": "", "today": True},
          {"when": "Tue", "title": "Team standup", "extra": "10:30 am", "today": False},
          {"when": "Wed", "title": "Dentist", "extra": "5 pm", "today": False}]
ROOMS = [
    {"name": "Living room", "lamps": [{"id": "li0", "name": "Floor lamp", "reachable": True, "on": True, "level": 80}, {"id": "li1", "name": "Ceiling", "reachable": True, "on": True, "level": 80}, {"id": "li2", "name": "Reading lamp", "reachable": True, "on": False, "level": 0}], "here": True, "total": 3, "reachable": 3, "on": 3, "level": 80, "kelvin": 2700, "rgb": [], "glow": [255, 190, 122], "sub": "Warm · 2700K"},
    {"name": "Kitchen", "lamps": [{"id": "ki0", "name": "Ceiling", "reachable": True, "on": False, "level": 0}, {"id": "ki1", "name": "Counter", "reachable": True, "on": False, "level": 0}], "here": False, "total": 2, "reachable": 2, "on": 0, "level": 0, "kelvin": 2700, "rgb": [], "glow": [255, 190, 122], "sub": "Off"},
    {"name": "Aviral's bedroom", "lamps": [{"id": "av0", "name": "Bedside", "reachable": True, "on": True, "level": 80}, {"id": "av1", "name": "Ceiling", "reachable": True, "on": True, "level": 80}, {"id": "av2", "name": "Desk", "reachable": True, "on": False, "level": 0}, {"id": "av3", "name": "Strip", "reachable": True, "on": False, "level": 0}, {"id": "av4", "name": "Corner", "reachable": True, "on": False, "level": 0}], "here": False, "total": 5, "reachable": 5, "on": 2, "level": 40, "kelvin": 2200, "rgb": [], "glow": [255, 190, 122], "sub": "Candle · 2200K"},
    {"name": "Arpit's bedroom", "lamps": [{"id": "ar0", "name": "Ceiling", "reachable": True, "on": False, "level": 0}, {"id": "ar1", "name": "Bedside", "reachable": True, "on": False, "level": 0}], "here": False, "total": 2, "reachable": 2, "on": 0, "level": 0, "kelvin": 2700, "rgb": [], "glow": [255, 190, 122], "sub": "Off"},
]
MUSIC = {"enabled": True, "exists": True, "playing": True, "title": "Fidelio", "artist": "ansh", "album": "Fidelio",
         "duration": 201, "position": 84, "at": 0, "device": "Living room speaker", "volume": 62,
         "art": "", "rgb": [201, 185, 163], "rgb2": [44, 40, 34], "error": "", "source": "spotify",
         "context": "Late night", "canVolume": True, "liked": False,
         "nextUp": [{"title": "Lowlight", "artist": "Sundays", "art": "", "uri": ""}, {"title": "Weightless", "artist": "Marconi Union", "art": "", "uri": ""}],
         "recent": [{"title": "Night Owl", "artist": "Galimatias", "art": "", "uri": ""}, {"title": "Nightcall", "artist": "Kavinsky", "art": "", "uri": ""}],
         "playlists": [{"name": "Late night", "uri": "", "art": ""}, {"name": "Focus", "uri": "", "art": ""}, {"name": "Sunday", "uri": "", "art": ""},
                       {"name": "Drive", "uri": "", "art": ""}, {"name": "Liked Songs", "uri": "", "art": ""}, {"name": "Dinner", "uri": "", "art": ""}],
         "devices": [{"id": "a", "name": "Living room speaker", "type": "Speaker", "active": True},
                     {"id": "b", "name": "Aviral's MacBook Air", "type": "Computer", "active": False},
                     {"id": "c", "name": "Aviral's iPhone", "type": "Smartphone", "active": False}]}


def fill_things(t):
    """Sample alarms, a running timer and reminders, so the clock and reminders screens can be checked."""
    import os, time, datetime as dt
    if os.environ.get("ROOM_DEMO_EMPTY") == "1":
        return
    t.alarms = [{"id": "a1", "h": 7, "m": 0, "days": [0, 1, 2, 3, 4], "on": True},
                {"id": "a2", "h": 8, "m": 30, "days": [5, 6], "on": True},
                {"id": "a3", "h": 6, "m": 15, "days": [], "on": False}]
    t.timers = [{"id": "t1", "label": "Pasta", "total": 720.0, "ends": time.time() + 522}]
    today = dt.datetime.now().replace(second=0, microsecond=0)
    at = lambda days, h, m=0: (today + dt.timedelta(days=days)).replace(hour=h, minute=m).timestamp()
    t.reminders = [{"id": "r1", "text": "Water the plants", "due": at(0, 18), "done": False, "fired": True},
                   {"id": "r2", "text": "Call Mom", "due": at(0, 20), "done": False, "fired": True},
                   {"id": "r3", "text": "Order cat food", "due": at(1, 10), "done": False},
                   {"id": "r4", "text": "Pay electricity bill", "due": at(4, 11), "done": False},
                   {"id": "r5", "text": "Renew car insurance", "due": 0, "done": True}]
    t._save = lambda: t.changed.emit()     # sample data isn't written to disk
    if os.environ.get("ROOM_DEMO_ALERT"):
        t.alert = {"kind": os.environ["ROOM_DEMO_ALERT"], "id": "t1", "title": "Time's up" if os.environ["ROOM_DEMO_ALERT"] == "timer" else "7:00 am",
                   "sub": "Pasta" if os.environ["ROOM_DEMO_ALERT"] == "timer" else "Alarm", "at": time.time()}
