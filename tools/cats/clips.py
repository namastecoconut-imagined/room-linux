"""Every clip in Bebo and Evan's library, built on lib.py's poses, then drawn, packed into sprite sheets and listed in
catsdata.js for Room.

  python3 tools/cats/clips.py build [bebo|evan] [sheet=stand,sit…]   draw + pack → assets/cats/<who>-<sheet>.png and
                                                                   qml/catsdata.js (every sheet of both cats by default)
  python3 tools/cats/clips.py reel <who> out.mp4 [clip …]           play clips from the packed sheets (checks them)
  python3 tools/cats/clips.py count                                 every clip and its length

Needs (only to draw them, not to run Room): pip install svgpathtools pillow; node with playwright (and its Chromium);
ffmpeg for reel. tools/cats/manifest.json remembers every sheet, so building one sheet keeps the others.

Rules every clip keeps: a loop's frame 0 is its state's resting pose at the bottom of a breath, and a clip from A to B
leaves out both ends (A was just on screen, B's loop starts on B), so clips join without a held or doubled frame.
Moving clips carry how far the cat travels on each frame (dx, in units, forwards), so the paws don't skate.
"""
import sys, os, math, json, hashlib, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(REPO, "assets", "cats"); JS = os.path.join(REPO, "qml", "catsdata.js"); MAN = os.path.join(HERE, "manifest.json")
from lib import *
from lib import lerp, ease
TAU = 2 * math.pi

# ---------------------------------------------------------------- the states and the life in them
STATES = dict(stand=(STAND, 24), sit=(SIT, 24), loaf=(LOAF, 24), curl=(CURL, 34), drape=(DRAPE, 24), peek=(PEEK, 24))

def wave_tail(G, w, lift=0.3, hang=False):
    if hang: G["tail"] = [(x + w * (i / 4), y) for i, (x, y) in enumerate(G["tail"])]
    else: G["tail"] = [(x + w * (i / 4) ** 2, y - abs(w) * lift * (i / 4) ** 2) for i, (x, y) in enumerate(G["tail"])]

def alive(S, F, f, N):
    """breathing, and the tail never quite still"""
    G = cp(F); ph = f / N; s = math.sin(TAU * ph)
    asleep = S == "curl"
    G["breath"] = (0.5 - 0.5 * math.cos(TAU * ph)) * (1.3 if asleep else 1.0)
    if S == "drape":
        wave_tail(G, 3.0 * s, hang=True)
        G["legs"] = [[a, (k[0] + 0.5 * s, k[1]), (p[0] + 1.3 * s, p[1])] if p[1] > 186 else [a, k, p] for a, k, p in G["legs"]]
    elif S == "peek":
        G["head"]["y"] -= 1.3 * G["breath"]
    else:
        wave_tail(G, (1.5 if asleep else 3.5) * s)
    return G

def event(kind, S, G, f):
    """one small thing happening on top of the resting loop"""
    h = G["head"]
    if kind == "blink":
        if f == 10: h["eye"] *= 0.0
        if f == 11: h["eye"] *= 0.45
    elif kind == "ear":
        if 6 <= f <= 8: h["earR"] -= 14 * math.sin(math.pi * (f - 5) / 4); h["earL"] -= 3 * math.sin(math.pi * (f - 5) / 4)
    elif kind == "look":
        b = bump(f, 2, 20, 5)
        if b:
            h["lx"] -= 0.9 * b; h["ly"] -= 0.25 * b; h["tilt"] += 7 * b
            if f == 3 and h["eye"] > 0.5: h["eye"] *= 0.35
    elif kind == "tail":
        b = bump(f, 4, 17, 4)
        if b:
            sw = math.sin(TAU * (f - 4) / 6.5) * b
            if S == "drape": G["tail"] = [(x + 9 * sw * (i / 4), y - 3 * b * (i / 4) ** 2) for i, (x, y) in enumerate(G["tail"])]
            else:
                k = 0.4 if S == "curl" else 1.0
                G["tail"] = [(x + 7 * sw * k * (i / 4) ** 2, y - 9 * b * k * (i / 4) ** 2) for i, (x, y) in enumerate(G["tail"])]
    return G

VARIANTS = dict(stand=("blink", "ear", "look", "tail"), sit=("blink", "ear", "look", "tail"), loaf=("blink", "ear", "look", "tail"),
                curl=("ear", "tail"), drape=("blink", "ear", "look", "tail"), peek=("blink", "look"))

# ---------------------------------------------------------------- building blocks
def between(A, B, n, shape=ease, each=None):
    """n in-between frames from A to B, leaving out both ends"""
    out = []
    for j in range(n):
        t = (j + 1) / (n + 1); G = lerp(A, B, shape(t))
        if each: each(G, t)
        out.append(G)
    return out
def upto(A, B, n, shape=ease, each=None):
    """n frames from A to B, ending on B"""
    out = []
    for j in range(n):
        t = (j + 1) / n; G = lerp(A, B, shape(t))
        if each: each(G, t)
        out.append(G)
    return out
def hold(F, n, each=None):
    out = []
    for j in range(n):
        G = cp(F)
        if each: each(G, j)
        out.append(G)
    return out

def walking(phase, amt=1.0, base=STAND, A=10, lift=7, bobA=1.5):
    F = cp(base); a = TAU * phase
    for i, off in enumerate((0.0, 0.5, 0.5, 0.0)):
        anc, knee, paw = F["legs"][i]
        aa = a + TAU * off
        dx = -A * math.cos(aa) * amt; up = max(0, math.sin(aa)) * lift * amt     # swing forward in the air, back on the ground
        F["legs"][i] = [anc, (knee[0] + dx * 0.5, knee[1] - up * 0.6), (paw[0] + dx, paw[1] - up)]
    bob = bobA * math.cos(2 * a) * amt
    F["body"] = [(x, y + bob) for x, y in F["body"]]
    F["head"]["y"] += bob * 0.7
    F["head"]["tilt"] += 2 * math.sin(a) * amt
    F["tail"] = [(x + 3 * math.sin(a + i * 0.6) * amt * i / 4, y) for i, (x, y) in enumerate(F["tail"])]
    return F

def alerted(S, F):
    G = cp(F); h = G["head"]
    h["earL"] += 8; h["earR"] += 8; h["eye"] = 1.2; h["tilt"] = h["tilt"] * 0.3 - 6; h["ly"] = -0.35
    h["y"] -= 3 if S in ("sit", "stand") else 7
    return G
def bobbing(F):
    G = cp(F); h = G["head"]; h["eye"] = 0.8; h["earL"] += 2; h["earR"] += 2
    return G

# ---------------------------------------------------------------- the library
CLIPS = []      # dict(sheet, name, frames=[(F, seed)], loop, a, b, dx)
def seedbase(name): return int(hashlib.md5(name.encode()).hexdigest()[:6], 16) % 50000 * 10
def add(sheet, name, frames, loop=False, a=None, b=None, dx=None, seeds=None, glide=False):
    sb = seedbase(name)
    fr = [(F, seeds[i] if seeds else sb + i) for i, F in enumerate(frames)]
    CLIPS.append(dict(sheet=sheet, name=name, frames=fr, loop=loop, a=a, b=b, dx=dx, g=glide))

def library():
    CLIPS.clear()
    home = dict(stand="stand", sit="sit", loaf="loaf", curl="curl", drape="drape", peek="peek")
    # resting loops and their variants (the same drawings except where something happens, so they share frames)
    for S, (F, N) in STATES.items():
        seeds = [seedbase(S) + i for i in range(N)]
        add(home[S], S, [alive(S, F, f, N) for f in range(N)], loop=True, a=S, b=S, seeds=seeds)
        for v in VARIANTS[S]:
            add(home[S], f"{S}.{v}", [event(v, S, alive(S, F, f, N), f) for f in range(N)], a=S, b=S, seeds=seeds)

    # from one state to another
    def sq_end(G, t): G["squash"] = 1 - 0.03 * math.sin(math.pi * min(1, max(0, (t - 0.5) / 0.5)))
    add("stand", "stand>sit", between(STAND, SIT, 12, each=sq_end), a="stand", b="sit")
    add("sit", "sit>stand", between(SIT, STAND, 10), a="sit", b="stand")
    add("sit", "sit>loaf", between(SIT, LOAF, 14), a="sit", b="loaf")
    add("loaf", "loaf>sit", between(LOAF, SIT, 12), a="loaf", b="sit")
    def eyes_shut(G, t): G["head"]["eye"] = max(0.0, 1 - ease(t * 1.6))
    add("loaf", "loaf>curl", between(LOAF, CURL, 15, each=eyes_shut), a="loaf", b="curl")
    def eyes_open(G, t): G["head"]["eye"] = ease((t - 0.35) / 0.65)
    add("curl", "curl>loaf", between(CURL, LOAF, 14, each=eyes_open), a="curl", b="loaf")
    add("loaf", "loaf>drape", between(LOAF, DRAPE, 12), a="loaf", b="drape")
    add("drape", "drape>loaf", between(DRAPE, LOAF, 12), a="drape", b="loaf")
    add("peek", "peek.up", between(PEEK_LOW, PEEK, 10, shape=lambda t: 1 - (1 - t) ** 3), a="none", b="peek")
    add("peek", "peek.down", between(PEEK, PEEK_LOW, 8, shape=lambda t: t ** 2.2), a="peek", b="none")

    # walking (8 drawings a step cycle, 50 units a second), trotting (6, 93 u/s), pushing something (10, 24 u/s)
    amts = (0.2, 0.45, 0.7, 0.9)
    add("stand", "walk.in", [walking(0.5 + i / 8, a) for i, a in enumerate(amts)], a="stand", b="walk", dx=[5 * a for a in amts])
    add("stand", "walk", [walking(i / 8) for i in range(8)], loop=True, a="walk", b="walk", dx=[5.0] * 8)
    add("stand", "walk.out", [walking(i / 8, a) for i, a in enumerate(amts[::-1])], a="walk", b="stand", dx=[5 * a for a in amts[::-1]])
    ta = (0.3, 0.65, 0.9)
    trot = lambda ph, amt: walking(ph, amt, A=14, lift=10, bobA=2.5)
    add("move", "trot.in", [trot(0.5 + i / 6, a) for i, a in enumerate(ta)], a="stand", b="trot", dx=[9.33 * a for a in ta], glide=True)
    add("move", "trot", [trot(i / 6, 1) for i in range(6)], loop=True, a="trot", b="trot", dx=[9.33] * 6, glide=True)
    add("move", "trot.out", [trot(i / 6, a) for i, a in enumerate(ta[::-1])], a="trot", b="stand", dx=[9.33 * a for a in ta[::-1]], glide=True)
    # pushing the seek bar's playhead along: leaning in, paws working, hardly moving (the playhead sets the pace)
    def shoving(f):
        G = walking(f / 8, 1, base=SHOVE, A=3, lift=3, bobA=0.6)
        G["head"]["tilt"] += 3 * math.sin(TAU * f / 8); G["breath"] = 0.5 - 0.5 * math.cos(TAU * f / 8)
        return G
    add("move", "push.in", between(STAND, SHOVE, 3), a="stand", b="push")
    add("move", "push", [shoving(f) for f in range(8)], loop=True, a="push", b="push")
    add("move", "push.out", between(SHOVE, STAND, 3), a="push", b="stand")

    # running: a gallop, 6 drawings a stride at 300 units a second (it glides between drawings), and a skid to a stop
    beats = [G_EXT, G_FRONT, G_GATHER, G_PUSH]
    def gallop(ph):
        x = (ph % 1) * 4; i = int(x); return lerp(beats[i], beats[(i + 1) % 4], x - i)
    add("run", "run.in", [lerp(STAND, CROUCH, 0.7), lerp(CROUCH, G_PUSH, 0.6), G_PUSH], a="stand", b="run", dx=[0, 10, 22], glide=True)
    add("run", "run", [gallop(i / 6) for i in range(6)], loop=True, a="run", b="run", dx=[30] * 6, glide=True)
    add("run", "run.out", [G_EXT, G_FRONT, SKID, lerp(SKID, STAND, 0.45)], a="run", b="stand", dx=[26, 20, 11, 4], glide=True)
    add("run", "run.turn", [SKID, lerp(SKID, TURN, 0.6), TURN], a="run", b="turned", dx=[14, 6, 0], glide=True)

    # turning round: there and (mirrored) back
    turn = upto(STAND, TURN, 4)
    add("stand", "turn", turn, a="stand", b="turned")
    add("stand", "turn.back", turn[:-1][::-1], a="turned", b="stand")

    # a leap: crouch (a little wiggle), take off, fly (as long as the jump takes), land
    def wiggle(G, j): G["body"] = [(x + (1.5 * math.sin(j * 2.5) if i >= 5 else 0), y) for i, (x, y) in enumerate(G["body"])]; wave_tail(G, 3 * math.sin(j * 2.5))
    add("stand", "crouch", upto(STAND, CROUCH, 5) + hold(CROUCH, 3, wiggle), a="stand", b="crouched")
    add("stand", "takeoff", [lerp(CROUCH, AIR, 0.55), lerp(CROUCH, AIR, 0.9)], a="crouched", b="air")
    add("stand", "air", [AIR, lerp(AIR, AIR2, 0.5), AIR2, lerp(AIR, AIR2, 0.5)], loop=True, a="air", b="air")
    add("stand", "land", [lerp(AIR, LAND, 0.5), LAND] + between(LAND, STAND, 5), a="air", b="stand")

    # stand: the big stretch; a fright
    def st_hold(G, j):
        b = math.sin(math.pi * (j + 0.5) / 8)
        G["legs"][0][2] = (G["legs"][0][2][0] + 2 * b, 180); G["legs"][1][2] = (G["legs"][1][2][0] + 2 * b, 180)
        G["head"]["mouth"] = 0.55 * b; G["head"]["tilt"] -= 6 * b
        wave_tail(G, 4 * math.sin(TAU * j / 8))
    add("move", "stand.stretch", upto(STAND, STRETCH, 8) + hold(STRETCH, 8, st_hold) + between(STRETCH, STAND, 7), a="stand", b="stand")
    up = shift(ARCH, dy=-14)
    def fast_breath(G, j): G["breath"] = 0.5 - 0.5 * math.cos(TAU * j / 2)
    startle = upto(STAND, lerp(STAND, CROUCH, 0.6), 2) + upto(lerp(STAND, CROUCH, 0.6), up, 2) + hold(up, 2) + upto(up, ARCH, 2) \
        + hold(ARCH, 4, fast_breath) + between(ARCH, STAND, 6)
    add("move", "stand.startle", startle, a="stand", b="stand")

    # sit: a yawn, a wash, a swat
    def flutter(G, j): G["head"]["mouth"] = 1 - 0.08 * math.sin(j * 1.2)
    SIT3 = head(SIT, eye=0.3)
    yawn = upto(SIT, LEAN, 4) + upto(LEAN, YAWN, 7) + hold(YAWN, 4, flutter) + upto(YAWN, SIT3, 6) + \
        [head(SIT, eye=0.3 + 0.7 * ease((j + 1) / 5)) for j in range(4)]
    add("sitdo", "sit.yawn", yawn, a="sit", b="sit")
    def licking(G, j):
        s = math.sin(TAU * j / 4); G["head"]["y"] += 1.5 * s; G["head"]["tilt"] += 3 * s
        a, k, p = G["legs"][1]; G["legs"][1] = [a, k, (p[0], p[1] + 2 * s)]; G["head"]["mouth"] = 0.25 + 0.12 * s
    wash = upto(SIT, LICK, 5) + hold(LICK, 8, licking) + upto(LICK, WIPE, 4) + upto(WIPE, LICK, 4) + upto(LICK, WIPE, 4) \
        + upto(WIPE, LICK, 4) + hold(LICK, 4, licking) + between(LICK, SIT, 6)
    add("sitdo", "sit.wash", wash, a="sit", b="sit")
    swat_s = upto(SIT, SWAT_S1, 3) + hold(SWAT_S1, 1) + upto(SWAT_S1, SWAT_S2, 2) + hold(SWAT_S2, 1) + upto(SWAT_S2, SWAT_S1, 2) \
        + between(SWAT_S1, SIT, 3)
    add("sitdo", "sit.swat", swat_s, a="sit", b="sit")

    # loaf: kneading
    add("loafdo", "loaf.knead.in", between(LOAF, KNEAD, 4), a="loaf", b="knead")
    def kneading(f):
        G = cp(KNEAD); s = math.sin(TAU * f / 12); s0, s1 = max(0, s), max(0, -s)
        for i, sv in ((0, s0), (1, s1)):
            a, k, p = G["legs"][i]; G["legs"][i] = [a, (k[0] + 1.5 * sv, k[1] - 5 * sv), (p[0] + 2 * sv, p[1] - 7 * sv)]
        G["head"]["y"] += 1.5 * (s0 + s1); G["head"]["tilt"] += 3 * (s0 - s1)
        G["breath"] = (0.5 - 0.5 * math.cos(TAU * f / 12)) * 0.6
        wave_tail(G, 2.5 * math.sin(TAU * f / 12))
        return G
    add("loafdo", "loaf.knead", [kneading(f) for f in range(12)], loop=True, a="knead", b="knead")
    add("loafdo", "loaf.knead.out", between(KNEAD, LOAF, 4), a="knead", b="loaf")
    def wriggle(G, j):
        s_ = math.sin(TAU * j / 7)
        G["head"]["tilt"] += 10 * s_
        G["legs"] = [[an, (k[0] + 2 * s_ * (1 if i % 2 else -1), k[1]), (p[0] + 4 * s_ * (1 if i % 2 else -1), p[1] + 2 * math.cos(TAU * j / 7 + i))]
                     for i, (an, k, p) in enumerate(G["legs"])]
        G["body"] = [(x + 1.5 * s_, y) for x, y in G["body"]]
        wave_tail(G, 5 * s_)
    # (the back and the belly swap places, so the drawing goes straight from the round bundle to on its back)
    roll = upto(LOAF, SIDE, 7) + upto(SIDE, ROLLM, 3) + hold(ROLLM, 1) + hold(BELLY, 14, wriggle) \
        + hold(ROLLM, 2) + upto(ROLLM, SIDE, 3) + between(SIDE, LOAF, 7)
    add("loafdo", "loaf.roll", roll, a="loaf", b="loaf")

    # drape: a swat over the edge
    swat_d = upto(DRAPE, SWAT_D0, 2) + upto(SWAT_D0, SWAT_D1, 2) + upto(SWAT_D1, SWAT_D2, 1) + hold(SWAT_D2, 1) + upto(SWAT_D2, SWAT_D1, 1) \
        + upto(SWAT_D1, SWAT_D2, 1) + upto(SWAT_D2, SWAT_D0, 2) + between(SWAT_D0, DRAPE, 3)
    add("drapedo", "drape.swat", swat_d, a="drape", b="drape")

    # hearing "Alexa" (ears up, eyes wide, a curious head tilt) and music (eyes shut, nodding along at 120 a minute)
    for S, sheet in (("sit", "sitfeel"), ("loaf", "loafdo"), ("drape", "drapedo")):
        F = STATES[S][0]; AL = alerted(S, F)
        add(sheet, f"{S}.alert.in", between(F, AL, 5), a=S, b=f"{S}.alert")
        def listening(f, AL=AL):
            G = cp(AL); ph = f / 16
            G["head"]["tilt"] += 14 * (0.5 - 0.5 * math.cos(TAU * ph))
            if 10 <= f <= 12: G["head"]["earL"] -= 10 * math.sin(math.pi * (f - 9) / 4)
            if f == 6: G["head"]["eye"] = 0.0
            G["breath"] = (0.5 - 0.5 * math.cos(TAU * ph)) * 0.8
            wave_tail(G, 2.5 * math.sin(TAU * ph), hang=S == "drape")
            return G
        add(sheet, f"{S}.alert", [listening(f) for f in range(16)], loop=True, a=f"{S}.alert", b=f"{S}.alert")
        add(sheet, f"{S}.alert.out", between(AL, F, 5), a=f"{S}.alert", b=S)
        BO = bobbing(F)
        add(sheet, f"{S}.bob.in", between(F, BO, 3), a=S, b=f"{S}.bob")
        def nodding(f, BO=BO):
            G = cp(BO); s = math.sin(TAU * f / 10)
            G["head"]["tilt"] += 7 * s; G["head"]["y"] += 2.2 * abs(s)
            wave_tail(G, 5 * s, hang=S == "drape")
            return G
        add(sheet, f"{S}.bob", [nodding(f) for f in range(10)], loop=True, a=f"{S}.bob", b=f"{S}.bob")
        add(sheet, f"{S}.bob.out", between(BO, F, 3), a=f"{S}.bob", b=S)
    return CLIPS

# ---------------------------------------------------------------- drawing, packing, the manifest
def build(whos, only=None):
    outdir = ASSETS
    from PIL import Image
    from multiprocessing import Pool
    os.makedirs(outdir, exist_ok=True)
    library()
    manifest_path = MAN
    man = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {"sheets": {}, "clips": {}}
    for who in whos:
        man["clips"].setdefault(who, {})
        for sheet in dict.fromkeys(c["sheet"] for c in CLIPS):
            if only and sheet not in only: continue
            clips = [c for c in CLIPS if c["sheet"] == sheet]
            jobs = [(F, who, seed) for c in clips for F, seed in c["frames"]]
            with Pool(2) as pool: svgs = pool.starmap(svg, jobs)
            uniq, index, k = [], {}, 0
            idx = []
            for s in svgs:
                h = hashlib.md5(s.encode()).hexdigest()
                if h not in index: index[h] = len(uniq); uniq.append(s)
                idx.append(index[h])
            tmp = tempfile.mkdtemp(prefix="cats-"); cells = render(uniq, tmp)
            rects, ims = pack(cells)
            name = f"{who}-{sheet}"
            W = max(r[0] + r[2] for r in rects); H = max(r[1] + r[3] for r in rects)
            out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            for (x, y, w, h, ox, oy), im in zip(rects, ims): out.paste(im, (x, y))
            out.quantize(256, method=Image.Quantize.FASTOCTREE).save(os.path.join(outdir, name + ".png"), optimize=True)   # (looks the same, ~4× smaller)
            shutil.rmtree(tmp, ignore_errors=True)
            man["sheets"][name] = dict(size=[W, H], frames=rects)
            for c in clips:
                n = len(c["frames"]); fi = idx[k:k + n]; k += n
                man["clips"][who][c["name"]] = dict(s=name, f=fi, loop=c["loop"], a=c["a"], b=c["b"], dx=c["dx"], g=c["g"])
            print(f"{name}: {len(svgs)} frames, {len(uniq)} drawn, sheet {W}×{H}, {os.path.getsize(os.path.join(outdir, name + '.png')) // 1024} KB", flush=True)
    json.dump(man, open(manifest_path, "w"), separators=(",", ":"))
    write_js(man, JS)

def pack(cells, width=2048, pad=2):
    """trim each drawing to what's drawn, then shelf-pack: (x, y, w, h, ox, oy) in px, ox/oy = where it sits in the cell"""
    from PIL import Image
    ims, boxes = [], []
    for p in cells:
        im = Image.open(p); bb = im.getchannel("A").getbbox() or (0, 0, 1, 1)
        x0, y0, x1, y1 = max(0, bb[0] - 1), max(0, bb[1] - 1), min(PXW, bb[2] + 1), min(PXH, bb[3] + 1)
        ims.append(im.crop((x0, y0, x1, y1))); boxes.append((x0, y0, x1 - x0, y1 - y0))
    rects, x, y, row = [], pad, pad, 0
    for (ox, oy, w, h) in boxes:
        if x + w + pad > width: x = pad; y += row + pad; row = 0
        rects.append((x, y, w, h, ox, oy)); x += w + pad; row = max(row, h)
    return rects, ims

def write_js(man, path):
    lines = ["// Bebo and Evan's clips (made by tools/cats/clips.py; don't edit by hand).",
             "// A frame is [x, y, w, h, ox, oy] in its sheet's pixels: where it is in the sheet, and where that sits in the",
             f"// cat's {CW} × {CH} cell (drawn {SCALE} px a unit; the cell's top is y {TOP}; the cat stands on (100, 180)).",
             "// A clip: s sheet, f frames, loop, a → b the state it starts and ends in, dx how far it moves on each frame (units).",
             ".pragma library", f"var unit = {SCALE}", f"var top = {TOP}", f"var cellW = {CW}", f"var cellH = {CH}"]
    lines.append("var sheets = " + json.dumps({k: v["size"] for k, v in man["sheets"].items()}, separators=(",", ":")))
    lines.append("var frames = " + json.dumps({k: v["frames"] for k, v in man["sheets"].items()}, separators=(",", ":")))
    clips = {who: {n: {k: v for k, v in c.items() if v not in (None, False)} for n, c in cs.items()} for who, cs in man["clips"].items()}
    for who in clips:
        for c in clips[who].values():
            if "dx" in c: c["dx"] = [round(d, 2) for d in c["dx"]]
    lines.append("var clips = " + json.dumps(clips, separators=(",", ":")))
    open(path, "w").write("\n".join(lines) + "\n")

def reel(who, out, names=None):
    assets = ASSETS
    """play clips from the packed sheets on Room's dark ground (checks the packing and the joins)"""
    from PIL import Image, ImageDraw
    man = json.load(open(MAN))
    clips = man["clips"][who]; names = names or list(clips)
    sheets = {}
    tmp = tempfile.mkdtemp(prefix="cats-reel-")
    n = 0; Wc, Hc = PXW + 160, PXH + 40
    for name in names:
        c = clips[name]; sh = sheets.get(c["s"]) or sheets.setdefault(c["s"], Image.open(os.path.join(assets, c["s"] + ".png")).convert("RGBA"))
        rects = man["sheets"][c["s"]]["frames"]; x = 0.0
        for rep in range(2 if c["loop"] else 1):
            for j, fi in enumerate(c["f"]):
                fx, fy, w, h, ox, oy = rects[fi]
                bg = Image.new("RGBA", (Wc, Hc), (38, 20, 13, 255)); d = ImageDraw.Draw(bg)
                gy = int((180 - TOP) * SCALE) + 20
                d.line([(0, gy), (Wc, gy)], fill=(255, 255, 255, 60))
                if c.get("dx"): x = (x + c["dx"][j] * SCALE) % 120
                bg.alpha_composite(sh.crop((fx, fy, fx + w, fy + h)), (int(80 + ox + x - 60), 20 + oy))
                d.text((8, 4), f"{who}  {name}  {j + 1}/{len(c['f'])}", fill=(255, 255, 255, 160))
                bg.convert("RGB").save(f"{tmp}/r{n:05d}.png"); n += 1
    import subprocess
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "10", "-i", f"{tmp}/r%05d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", out], check=True)
    shutil.rmtree(tmp)
    print(out, n, "frames")

if __name__ == "__main__":
    if sys.argv[1] == "build":     # build [who …] [sheet=a,b]
        rest = [a for a in sys.argv[2:] if not a.startswith("sheet=")]; sh = [a[6:].split(",") for a in sys.argv[2:] if a.startswith("sheet=")]
        build(rest or ["bebo", "evan"], sh[0] if sh else None)
    elif sys.argv[1] == "reel": reel(sys.argv[2], sys.argv[3], sys.argv[4:] or None)
    elif sys.argv[1] == "count":
        library(); tot = 0
        for c in CLIPS: tot += len(c["frames"]); print(f'{c["sheet"]:8} {c["name"]:18} {len(c["frames"]):3}')
        print("frames a cat (before sharing):", tot)
