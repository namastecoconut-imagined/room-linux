"""The Surface's own speakers — where Room's voice always plays.

Room only ever moves *music* to a Bluetooth speaker (room/output.py). The assistant's voice played on "the default
speaker", which was the Surface — until the sound system made a newly connected Bluetooth speaker the default (18 Nov)
and the voice went with it. So the voice, its chime and its loudness while it talks are tied to the Surface's
speakers by name now (player.py, duck.py), whatever the default is.
"""
import json
import os
import subprocess


def _dump():
    try:
        return json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
    except Exception:
        return []


def surface(nodes=None) -> tuple[int, str] | None:
    """(PipeWire id, node name) of the Surface's own speakers, or None (then: the default speaker, as before)."""
    best = None
    for n in nodes if nodes is not None else _dump():
        p = (n.get("info") or {}).get("props") or {}
        if n.get("type") != "PipeWire:Interface:Node" or p.get("media.class") != "Audio/Sink":
            continue
        name = p.get("node.name", "")
        if not name.startswith("alsa_output"):
            continue                                   # (Bluetooth speakers are bluez_output…)
        desc = (p.get("node.description", "") + " " + p.get("device.description", "")).lower()
        score = 2 if "built-in" in desc or "speaker" in desc else 1
        if best is None or score > best[0]:
            best = (score, n["id"], name)
    return (best[1], best[2]) if best else None


def pin(log=print) -> bool:
    """The assistant's own stream (this process) onto the Surface's speakers, if it's playing anywhere else.
    True if it had to be moved."""
    nodes = _dump()
    s = surface(nodes)
    if not s:
        return False
    sid, name = s
    links: dict = {}
    for n in nodes:
        if n.get("type") == "PipeWire:Interface:Link":
            i = n.get("info") or {}
            links.setdefault(i.get("output-node-id"), set()).add(i.get("input-node-id"))
    moved = False
    for n in nodes:
        p = (n.get("info") or {}).get("props") or {}
        if n.get("type") != "PipeWire:Interface:Node" or p.get("media.class") != "Stream/Output/Audio":
            continue
        if str(p.get("application.process.id")) != str(os.getpid()):
            continue
        out = links.get(n["id"], set())
        if out and sid in out:
            continue
        # clear, then set (setting the same target again is no change to PipeWire)
        for args in (["-d", str(n["id"]), "target.object"], [str(n["id"]), "target.object", name]):
            subprocess.run(["pw-metadata", "-n", "default"] + args, timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log(f"[assistant] voice: back onto the Surface's speakers ({name})")
        moved = True
    return moved
