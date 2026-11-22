"""Room maps: each room drawn once ahead of time (never on the Surface), for the Room screen (RoomMap.qml).

  python3 tools/rooms/bake.py            every room (each <name>.js here but draw.js)
  python3 tools/rooms/bake.py aviral     just one

Each room's drawing is drawn by Chromium from its file (the pen helpers in draw.js) and saved as:

  assets/rooms/<room>/lines.png     the room's lines, nothing filled (it sits on Room's background), at 4 px a stage
                                    unit — sharp at 2.3× zoomed in on the Surface (2 px a unit)
  assets/rooms/<room>/shade<n>.png  lamp n's shade, filled white, alone (hidden where something's in front of it):
                                    Room tints it the lamp's colour while it's on
  assets/rooms/glow.png             one soft light, white, tinted and sized per lamp
and qml/roomsdata.js: where each picture goes on the stage, and each lamp (its number, name, the words that find its
bulb in config.json, where it is).
"""
import json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "rooms")
W, H, PX = 1368, 912, 4

PAGE = """<!doctype html><html><head><style>html,body{margin:0;background:transparent;overflow:hidden}</style></head><body>
<svg id="art" xmlns="http://www.w3.org/2000/svg" width="1368" height="912" viewBox="0 0 1368 912"></svg>
<script>%s</script><script>%s</script></body></html>"""


def crop(a, pad=6):
    ys, xs = np.nonzero(a[..., 3] > 2)
    if not len(xs):
        return None
    x0, x1 = max(0, xs.min() - pad), min(a.shape[1], xs.max() + 1 + pad)
    y0, y1 = max(0, ys.min() - pad), min(a.shape[0], ys.max() + 1 + pad)
    # whole stage units, so the picture lands on the stage exactly
    x0, y0 = x0 // PX * PX, y0 // PX * PX
    x1, y1 = -(-x1 // PX) * PX, -(-y1 // PX) * PX
    return x0, y0, x1, y1


def bake(page, name):
    draw = open(os.path.join(HERE, "draw.js"), encoding="utf-8").read()
    room = open(os.path.join(HERE, name + ".js"), encoding="utf-8").read()
    page.set_content(PAGE % (draw, room))
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, ".shot.png")

    def shot(mode, n=0):
        page.evaluate("(a) => { document.getElementById('art').innerHTML = render(a[0], a[1]) }", [mode, n])
        page.screenshot(path=tmp, omit_background=True)
        return np.asarray(Image.open(tmp).convert("RGBA"))

    lines = shot("lines")
    x0, y0, x1, y1 = crop(lines)
    Image.fromarray(lines[y0:y1, x0:x1]).save(os.path.join(out, "lines.png"), optimize=True)
    man = {"lines": {"x": x0 / PX, "y": y0 / PX, "w": (x1 - x0) / PX, "h": (y1 - y0) / PX}, "lamps": []}
    for l in page.evaluate("() => L.map(l => ({ n: l.n, name: l.name, match: l.match, at: P(...l.at) }))"):
        s = shot("shade", l["n"])
        c = crop(s, 2)
        lamp = {"n": l["n"], "name": l["name"], "match": l["match"], "x": round(l["at"][0], 1), "y": round(l["at"][1], 1)}
        if c:
            a0, b0, a1, b1 = c
            Image.fromarray(s[b0:b1, a0:a1]).save(os.path.join(out, f"shade{l['n']}.png"), optimize=True)
            lamp["shade"] = {"x": a0 / PX, "y": b0 / PX, "w": (a1 - a0) / PX, "h": (b1 - b0) / PX}
        man["lamps"].append(lamp)
    os.remove(tmp)
    print(f"{name}: {x1 - x0} × {y1 - y0} px, {len(man['lamps'])} lamps")
    return man


def glow():
    n = 256
    y, x = np.mgrid[0:n, 0:n] - (n - 1) / 2
    r = np.sqrt(x * x + y * y) / (n / 2)
    a = np.clip(1 - r, 0, 1) ** 2.2                    # soft, mostly near the middle
    img = np.zeros((n, n, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = np.round(a * 255).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(OUT, "glow.png"), optimize=True)


def main():
    from playwright.sync_api import sync_playwright
    names = sys.argv[1:] or sorted(f[:-3] for f in os.listdir(HERE) if f.endswith(".js") and f != "draw.js")
    os.makedirs(OUT, exist_ok=True)
    data = {}
    df = os.path.join(ROOT, "qml", "roomsdata.js")
    if os.path.exists(df):                              # (rooms not baked this time keep what they had)
        txt = open(df, encoding="utf-8").read()
        data = json.loads(txt[txt.index("var maps = ") + 11:txt.rindex(";")])
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={"width": W, "height": H}, device_scale_factor=PX)
        for n in names:
            data[n] = bake(page, n)
        b.close()
    glow()
    with open(df, "w", encoding="utf-8") as f:
        f.write("// The Room screen's room drawings (made by tools/rooms/bake.py from tools/rooms/*.js; don't edit by hand).\n"
                "// Keyed by the room's name, lower case, spaces removed.\n.pragma library\n")
        f.write("var maps = " + json.dumps(data, separators=(",", ":")) + ";\n")


if __name__ == "__main__":
    main()
