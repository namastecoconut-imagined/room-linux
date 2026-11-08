"""Sample data for ROOM_DEMO=1 — lets the screens be checked anywhere, without bulbs, Spotify or a calendar."""
WEATHER = {"ok": True, "t": 20, "feels": 20, "hum": 78, "d": "Overcast", "hi": 29, "lo": 20, "aqi": 62,
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
    {"name": "Living room", "here": True, "total": 3, "reachable": 3, "on": 3, "level": 80, "kelvin": 2700, "rgb": [], "glow": [255, 190, 122], "sub": "Warm · 2700K"},
    {"name": "Kitchen", "here": False, "total": 2, "reachable": 2, "on": 0, "level": 0, "kelvin": 2700, "rgb": [], "glow": [255, 190, 122], "sub": "Off"},
    {"name": "Aviral's bedroom", "here": False, "total": 5, "reachable": 5, "on": 2, "level": 40, "kelvin": 2200, "rgb": [], "glow": [255, 190, 122], "sub": "Candle · 2200K"},
    {"name": "Arpit's bedroom", "here": False, "total": 2, "reachable": 2, "on": 0, "level": 0, "kelvin": 2700, "rgb": [], "glow": [255, 190, 122], "sub": "Off"},
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
