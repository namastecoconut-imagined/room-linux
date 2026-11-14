"""Bebo and Evan's action library on the pen puppet (softrig). Every clip is drawn frame by frame at 10 a second;
every clip starts and ends on a state's resting pose at the bottom of a breath, so any clip can follow any other
that ends where it starts.

  python3 tools/cats/lib.py poses out.png      the key poses, both cats, on one sheet (for checking)
(clips.py builds the clips from these poses.)

The cell is 200 × 210 units (y 30 … 240); the ground is y 180 and the cat stands on (100, 180). Drawn 1.6 px a unit.
"""
import sys, os, math, json, subprocess, hashlib, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import softrig as R
from softrig import STAND, SIT, LOAF, CURL, lerp, ease, P

TOP, CW, CH, SCALE = 30, 200, 210, 1.6
PXW, PXH = int(CW * SCALE), int(CH * SCALE)          # 320 × 336
FPS = 10

def norm(F):
    F = R.copy(F)
    F["head"].setdefault("lx", 0.0); F["head"].setdefault("ly", 0.0)
    F.setdefault("puff", 1.0); F.setdefault("sag", 1.5)
    return F
def cp(F): return R.copy(F)
def head(F, **kw):
    G = cp(F); G["head"].update(kw); return G
def headd(F, **kw):          # head changes added to what's there
    G = cp(F)
    for k, v in kw.items(): G["head"][k] += v
    return G
def shift(F, dx=0, dy=0):
    G = cp(F)
    G["body"] = [(x + dx, y + dy) for x, y in G["body"]]
    G["legs"] = [[(x + dx, y + dy) for x, y in leg] for leg in G["legs"]]
    G["tail"] = [(x + dx, y + dy) for x, y in G["tail"]]
    G["head"]["x"] += dx; G["head"]["y"] += dy
    return G
def squeeze(F, k, cx=100):   # seen more from the front: the body narrows about cx
    G = cp(F); f = lambda x: cx + (x - cx) * k
    G["body"] = [(f(x), y) for x, y in G["body"]]
    G["legs"] = [[(f(x), y) for x, y in leg] for leg in G["legs"]]
    G["tail"] = [(f(x), y) for x, y in G["tail"]]
    G["head"]["x"] = f(G["head"]["x"])
    return G
def bump(f, a, b, edge):     # 0 → 1 → 0 across frames a..b, easing over `edge` frames each side
    if f < a or f > b: return 0.0
    return ease(min((f - a + 1) / (edge + 1), (b - f + 1) / (edge + 1), 1.0))

STAND, SIT, LOAF, CURL = map(norm, (STAND, SIT, LOAF, CURL))

# ---------------------------------------------------------------- the new key poses (facing right)
# lying along an edge: belly on the line, front paws and tail hanging over it
DRAPE = norm(dict(
    body=P((130, 180), (138, 170), (128, 152), (104, 143), (78, 143), (60, 148), (48, 163), (54, 180)),
    haunch=0.3,
    head=dict(x=148, y=163, r=22, tilt=12, earL=0, earR=0, eye=0.7, mouth=0.0),
    legs=[P((124, 178), (126, 193), (125, 205)), P((133, 177), (136, 195), (135, 211)),
          P((70, 178), (70, 190), (70, 200)), P((62, 178), (64, 193), (63, 205))],
    legv=[0.9, 1, 0, 1],
    tail=P((52, 176), (47, 190), (48, 204), (45, 217), (49, 227)),
    breath=0.0, squash=1.0))
# peeking up over the bottom edge of the screen: head and paws above the line, the rest below (off screen)
PEEK = norm(dict(
    body=P((112, 240), (118, 214), (88, 184), (78, 200), (72, 218), (70, 232), (72, 240), (90, 240)),
    haunch=0.0,
    head=dict(x=100, y=147, r=24, tilt=0, earL=0, earR=0, eye=1.0, mouth=0.0),
    legs=[P((83, 204), (80, 190), (83, 175)), P((117, 204), (120, 190), (117, 175)),
          P((80, 236), (80, 238), (80, 240)), P((90, 236), (90, 238), (90, 240))],
    legv=[1, 1, 0, 0],
    tail=P((74, 236), (66, 240), (60, 244), (56, 248), (54, 252)),
    breath=0.0, squash=1.0))
PEEK_LOW = shift(PEEK, dy=92)
# the big stretch: front paws reaching out, rump up
STRETCH = norm(dict(
    body=P((136, 170), (150, 160), (142, 146), (118, 128), (92, 112), (70, 104), (58, 116), (68, 136)),
    haunch=0.0,
    head=dict(x=154, y=150, r=23, tilt=-8, earL=-6, earR=-6, eye=0.0, mouth=0.0),
    legs=[P((138, 166), (154, 176), (168, 180)), P((144, 164), (160, 175), (176, 180)),
          P((70, 132), (67, 156), (68, 180)), P((78, 130), (76, 156), (78, 180))],
    legv=[1, 1, 1, 1],
    tail=P((60, 108), (52, 90), (54, 72), (60, 60), (68, 56)),
    breath=0.0, squash=1.0))
# ready to jump
CROUCH = norm(dict(
    body=P((128, 160), (139, 139), (129, 119), (104, 114), (78, 114), (60, 118), (51, 136), (62, 156)),
    haunch=0.2,
    head=dict(x=143, y=110, r=24, tilt=-4, earL=4, earR=4, eye=1.15, mouth=0.0),
    legs=[P((125, 156), (131, 170), (128, 180)), P((134, 154), (141, 169), (139, 180)),
          P((70, 152), (60, 166), (70, 180)), P((79, 152), (70, 167), (80, 180))],
    legv=[1, 1, 1, 1],
    tail=P((53, 126), (40, 126), (28, 128), (18, 126), (10, 122)),
    breath=0.0, squash=1.0))
# in the air, stretched out
AIR = norm(dict(
    body=P((140, 140), (152, 122), (144, 104), (118, 98), (88, 100), (66, 106), (54, 122), (64, 140)),
    haunch=0.0,
    head=dict(x=152, y=94, r=24, tilt=-8, earL=-8, earR=-8, eye=1.1, mouth=0.0),
    legs=[P((136, 136), (148, 147), (160, 154)), P((144, 134), (157, 143), (170, 148)),
          P((66, 136), (54, 149), (40, 158)), P((74, 136), (62, 151), (48, 162))],
    legv=[1, 1, 1, 1],
    tail=P((55, 112), (42, 108), (30, 108), (20, 110), (12, 114)),
    breath=0.0, squash=1.0))
AIR2 = cp(AIR)
AIR2["legs"] = [[a, (k[0] + 3, k[1] + 3), (p[0] + 4, p[1] + 5)] for a, k, p in AIR["legs"][:2]] + \
               [[a, (k[0] - 2, k[1] + 2), (p[0] - 3, p[1] + 3)] for a, k, p in AIR["legs"][2:]]
AIR2["tail"] = [(x, y + (i / 4) ** 2 * 5) for i, (x, y) in enumerate(AIR["tail"])]
# landing: front paws down, everything gives a little
LAND = cp(CROUCH)
LAND["legs"][0] = P((125, 156), (133, 168), (134, 180)); LAND["legs"][1] = P((134, 154), (143, 167), (146, 180))
LAND["head"].update(eye=1.0, earL=-4, earR=-4, y=114); LAND["squash"] = 0.95
# turning round: seen almost from the front for a moment
TURN = squeeze(head(STAND, x=STAND["head"]["x"], tilt=0), 0.32, cx=98)
TURN["head"]["y"] += 4
# startled: the back arches, legs go straight, the tail puffs up
ARCH = norm(dict(
    body=P((128, 146), (138, 126), (130, 106), (112, 80), (86, 78), (64, 90), (52, 116), (62, 146)),
    haunch=0.0,
    head=dict(x=141, y=106, r=23, tilt=10, earL=-14, earR=-14, eye=1.25, mouth=0.35),
    legs=[P((124, 142), (126, 162), (127, 180)), P((132, 140), (136, 160), (138, 180)),
          P((66, 142), (64, 162), (66, 180)), P((74, 142), (73, 162), (76, 180))],
    legv=[1, 1, 1, 1],
    tail=P((56, 104), (52, 86), (52, 68), (54, 52), (58, 40)),
    breath=0.0, squash=1.0, puff=2.1))
# washing: lick the paw, wipe it over the face
LICK = head(SIT, x=113, y=94, tilt=-10, eye=0.0, mouth=0.35)
LICK["legs"][1] = P((119, 136), (132, 128), (123, 111))
WIPE = head(SIT, x=117, y=92, tilt=16, eye=0.0, earR=-12, mouth=0.0)
WIPE["legs"][1] = P((119, 136), (136, 110), (122, 80))
# kneading in a loaf: front paws out, eyes half shut
KNEAD = cp(LOAF)
KNEAD["legs"][0] = P((130, 168), (136, 174), (140, 180)); KNEAD["legs"][1] = P((138, 168), (144, 174), (149, 180))
KNEAD["head"].update(eye=0.3)
# a swat from lying on an edge (the near paw hooks out) and from sitting (a paw up, then down)
SWAT_D0 = head(DRAPE, ly=0.8, eye=1.1, earL=4, earR=4, tilt=6)
SWAT_D1 = cp(SWAT_D0); SWAT_D1["legs"][1] = P((133, 177), (141, 190), (131, 200))
SWAT_D2 = cp(SWAT_D0); SWAT_D2["legs"][1] = P((133, 177), (150, 188), (163, 196))
SWAT_S1 = head(SIT, eye=1.15, earL=5, earR=5, tilt=-6, ly=0.3)
SWAT_S1["legs"][1] = P((119, 136), (133, 128), (144, 120))
SWAT_S2 = head(SIT, eye=1.1, earL=5, earR=5, tilt=4, ly=0.8)
SWAT_S2["legs"][1] = P((119, 136), (136, 150), (148, 172))
# the yawn (as in the take)
LEAN = headd(SIT, tilt=8, x=3, y=2); LEAN["head"]["eye"] = 0.6
YAWN = head(SIT, tilt=-24, mouth=1.0, eye=0.0, earL=-14, earR=-14, y=SIT["head"]["y"] - 3)

# ---------------------------------------------------------------- running: a gallop in four beats, and a skid to a stop
G_EXT = norm(dict(        # all four legs stretched out, in the air
    body=P((142, 150), (154, 134), (146, 116), (118, 110), (88, 112), (64, 118), (52, 134), (62, 150)), haunch=0.0,
    head=dict(x=154, y=108, r=23, tilt=-6, earL=-10, earR=-10, eye=1.1, mouth=0.0),
    legs=[P((138, 146), (152, 157), (166, 164)), P((146, 144), (160, 151), (175, 156)),
          P((64, 146), (50, 157), (36, 164)), P((72, 146), (58, 159), (44, 168))],
    legv=[1, 1, 1, 1], tail=P((54, 124), (40, 120), (28, 118), (18, 116), (10, 114)), breath=0.0, squash=1.0))
G_FRONT = norm(dict(      # front paws come down, back legs swing under
    body=P((138, 160), (150, 144), (142, 126), (116, 116), (88, 114), (64, 118), (52, 134), (62, 152)), haunch=0.0,
    head=dict(x=150, y=120, r=23, tilt=-2, earL=-10, earR=-10, eye=1.1, mouth=0.0),
    legs=[P((134, 156), (140, 168), (142, 180)), P((142, 154), (150, 167), (154, 180)),
          P((66, 148), (68, 160), (80, 168)), P((74, 148), (78, 160), (90, 166))],
    legv=[1, 1, 1, 1], tail=P((54, 126), (42, 126), (30, 128), (20, 126), (12, 122)), breath=0.0, squash=1.0))
G_GATHER = norm(dict(     # bunched up, back curved, back paws land under the chest
    body=P((128, 156), (138, 136), (130, 116), (108, 104), (84, 104), (64, 112), (54, 130), (64, 152)), haunch=0.2,
    head=dict(x=140, y=112, r=23, tilt=4, earL=-8, earR=-8, eye=1.1, mouth=0.0),
    legs=[P((124, 152), (118, 166), (112, 178)), P((132, 150), (126, 165), (120, 176)),
          P((68, 148), (82, 163), (96, 178)), P((76, 148), (90, 164), (104, 180))],
    legv=[1, 1, 1, 1], tail=P((56, 120), (44, 112), (34, 110), (24, 112), (16, 116)), breath=0.0, squash=1.0))
G_PUSH = norm(dict(       # back legs push off, front legs reach
    body=P((136, 148), (148, 130), (140, 112), (114, 104), (86, 106), (62, 114), (50, 132), (60, 152)), haunch=0.0,
    head=dict(x=150, y=104, r=23, tilt=-6, earL=-10, earR=-10, eye=1.1, mouth=0.0),
    legs=[P((132, 144), (146, 148), (158, 154)), P((140, 142), (156, 144), (168, 148)),
          P((62, 150), (56, 166), (48, 180)), P((70, 150), (66, 166), (60, 180))],
    legv=[1, 1, 1, 1], tail=P((52, 128), (38, 126), (26, 126), (16, 124), (8, 122)), breath=0.0, squash=1.0))
SKID = norm(dict(         # front paws braced, leaning back, ears back
    body=P((130, 158), (142, 140), (136, 120), (112, 116), (86, 120), (64, 128), (52, 146), (60, 164)), haunch=0.4,
    head=dict(x=146, y=112, r=23, tilt=-10, earL=-8, earR=-8, eye=1.15, mouth=0.0),
    legs=[P((128, 154), (140, 166), (152, 180)), P((136, 152), (149, 165), (162, 180)),
          P((64, 160), (70, 170), (80, 180)), P((72, 160), (78, 170), (88, 180))],
    legv=[1, 1, 1, 1], tail=P((54, 140), (42, 136), (32, 128), (26, 118), (24, 108)), breath=0.0, squash=1.0))
# rolling over: onto its side, then its back with its paws in the air
SIDE = norm(dict(
    body=P((136, 180), (146, 172), (138, 160), (112, 150), (84, 150), (62, 154), (50, 166), (58, 180)), haunch=0.3,
    head=dict(x=154, y=163, r=23, tilt=32, earL=-4, earR=-4, eye=0.6, mouth=0.0),
    legs=[P((132, 175), (148, 177), (162, 176)), P((138, 173), (154, 173), (168, 171)),
          P((66, 175), (80, 178), (94, 178)), P((74, 174), (88, 176), (102, 175))],
    legv=[1, 1, 0.7, 1], tail=P((52, 174), (38, 178), (26, 178), (16, 174), (10, 168)), breath=0.0, squash=1.0))
BELLY = norm(dict(
    body=P((128, 148), (142, 156), (138, 172), (110, 180), (82, 180), (62, 176), (50, 162), (60, 148)), haunch=0.0,
    head=dict(x=150, y=150, r=22, tilt=165, earL=0, earR=0, eye=0.35, mouth=0.0),
    legs=[P((124, 152), (124, 136), (132, 128)), P((132, 154), (136, 140), (145, 134)),
          P((70, 152), (66, 136), (74, 127)), P((78, 152), (77, 137), (86, 130))],
    legv=[1, 1, 1, 1], tail=P((52, 170), (38, 176), (26, 178), (16, 176), (8, 170)), breath=0.0, squash=1.0, sag=-12.0))
ROLLM = norm(dict(        # halfway over: a round bundle, legs to the side and up
    body=P((124, 170), (140, 160), (138, 146), (116, 136), (88, 136), (66, 142), (54, 158), (66, 176)), haunch=0.2,
    head=dict(x=150, y=156, r=22, tilt=95, earL=-4, earR=-4, eye=0.4, mouth=0.0),
    legs=[P((126, 162), (138, 152), (150, 146)), P((132, 160), (146, 152), (158, 148)),
          P((72, 166), (84, 154), (96, 146)), P((80, 164), (92, 152), (104, 146))],
    legv=[1, 1, 1, 1], tail=P((56, 172), (42, 178), (30, 180), (20, 178), (12, 172)), breath=0.0, squash=1.0))
# pushing something along (the seek bar's playhead): leaning in, head down, paws working
SHOVE = cp(STAND)
SHOVE["head"].update(x=STAND["head"]["x"] + 12, y=STAND["head"]["y"] + 27, tilt=-18, eye=1.1, earL=-6, earR=-6)
SHOVE["body"] = [(x + (3 if i in (0, 1, 2) else 0), y + (7 if i in (1, 2) else 3 if i in (0, 3) else 0)) for i, (x, y) in enumerate(STAND["body"])]
SHOVE["legs"][0] = P((128, 148), (134, 165), (140, 180)); SHOVE["legs"][1] = P((137, 146), (144, 163), (150, 180))
SHOVE["legs"][2] = P((70, 146), (62, 162), (60, 180)); SHOVE["legs"][3] = P((79, 146), (72, 163), (70, 180))

# ---------------------------------------------------------------- playing together, and flopping out
# reared up on the back legs, front paws up (a play-fight), and the two swats from there, ears back
REAR = norm(dict(
    body=P((112, 150), (124, 118), (116, 94), (100, 92), (86, 106), (76, 130), (70, 160), (84, 180)),
    haunch=1.0,
    head=dict(x=120, y=70, r=25, tilt=-4, earL=3, earR=3, eye=1.15, mouth=0.0),
    legs=[P((112, 116), (126, 110), (130, 96)), P((120, 114), (136, 108), (142, 94)),
          P((92, 162), (98, 171), (104, 180)), P((96, 162), (101, 171), (107, 180))],
    legv=[1, 1, 0.6, 0.3],
    tail=P((72, 170), (58, 180), (44, 180), (34, 172), (34, 160)),
    breath=0.0, squash=1.0))
BAT1 = head(REAR, tilt=8, earL=-12, earR=-12, eye=1.2, mouth=0.3, x=123, y=73)
BAT1["legs"][1] = P((120, 114), (140, 112), (154, 122)); BAT1["legs"][0] = P((112, 116), (122, 100), (128, 86))
BAT2 = head(REAR, tilt=-8, earL=-12, earR=-12, eye=1.2, mouth=0.3, x=121, y=71)
BAT2["legs"][0] = P((112, 116), (134, 118), (150, 128)); BAT2["legs"][1] = P((120, 114), (128, 98), (134, 84))
# stalking: flat to the ground, eyes wide, ears forward, rump up a touch (it wiggles before the pounce)
STALK = norm(dict(
    body=P((132, 176), (144, 160), (136, 144), (112, 138), (86, 136), (64, 136), (52, 152), (62, 172)),
    haunch=0.3,
    head=dict(x=152, y=148, r=24, tilt=-4, earL=6, earR=6, eye=1.25, mouth=0.0),
    legs=[P((130, 172), (140, 168), (146, 180)), P((138, 170), (150, 168), (156, 180)),
          P((66, 164), (58, 170), (66, 180)), P((74, 164), (66, 172), (76, 180))],
    legv=[1, 1, 1, 1],
    tail=P((54, 146), (42, 152), (30, 158), (20, 160), (11, 156)),
    breath=0.0, squash=1.0))
# a nose boop: neck stretched out, eyes soft
BOOP = head(STAND, x=158, y=103, tilt=-8, eye=0.35, earL=3, earR=3)
BOOP["body"][1] = (143, 130); BOOP["body"][2] = (136, 110)
# grooming the other one (licking its head), and being groomed (eyes shut, leaning in)
GROOM = head(SIT, x=136, y=90, tilt=-16, eye=0.0, mouth=0.35, earL=-3, earR=-3)
GROOM["body"][1] = (130, 140); GROOM["body"][2] = (124, 110)
PURR = head(SIT, x=112, y=93, tilt=14, eye=0.0, earL=-5, earR=-5)
# lying flat out on its side, and stretched out long that way
SIDE_S = cp(SIDE)
SIDE_S["legs"] = [P((132, 175), (152, 176), (172, 172)), P((138, 173), (160, 170), (180, 164)),
                  P((66, 175), (52, 178), (38, 176)), P((74, 174), (60, 177), (46, 172))]
SIDE_S["head"].update(tilt=44, eye=0.0, mouth=0.55, x=158, y=164)
SIDE_S["tail"] = [(x - 6 * i / 4, y + 2 * i / 4) for i, (x, y) in enumerate(SIDE["tail"])]

KEYS = dict(stand=STAND, sit=SIT, loaf=LOAF, curl=CURL, drape=DRAPE, peek=PEEK, stretch=STRETCH, crouch=CROUCH,
            air=AIR, land=LAND, turn=TURN, arch=ARCH, lick=LICK, wipe=WIPE, knead=KNEAD, swat_drape=SWAT_D2,
            swat_sit=SWAT_S1, yawn=YAWN, g_ext=G_EXT, g_front=G_FRONT, g_gather=G_GATHER, g_push=G_PUSH, skid=SKID,
            side=SIDE, belly=BELLY, rollm=ROLLM, shove=SHOVE,
            rear=REAR, bat1=BAT1, bat2=BAT2, stalk=STALK, boop=BOOP, groom=GROOM, purr=PURR, side_s=SIDE_S)

def svg(F, who, seed, scale=SCALE):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {TOP} {CW} {CH}" width="{int(CW * scale)}" height="{int(CH * scale)}">'
            f'{R.DEFS}{R.frame(F, who, seed)}</svg>')

def render(svgs, outdir, prefix="c", scale=SCALE):
    """draw many cells at once: a page of 8 × 8 cells, one screenshot, cut up. Returns the PNG paths."""
    PXW, PXH = int(CW * scale), int(CH * scale)
    os.makedirs(outdir, exist_ok=True)
    outdir = os.path.abspath(outdir); job = os.path.join(outdir, "_job.json")
    json.dump({"svgs": svgs, "w": PXW, "h": PXH, "out": outdir, "prefix": prefix}, open(job, "w"))
    subprocess.run(["node", "-e", r"""
const { chromium } = require('playwright'); const J = require(process.argv[1]);
(async () => { const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: J.w * 8, height: J.h * 8 } });
  for (let s = 0; s < J.svgs.length; s += 64) {
    const part = J.svgs.slice(s, s + 64);
    const html = part.map((v, i) => `<div style="position:absolute;left:${(i % 8) * J.w}px;top:${Math.floor(i / 8) * J.h}px;width:${J.w}px;height:${J.h}px">${v}</div>`).join('');
    await p.setContent(`<html><body style="margin:0;background:transparent">${html}</body></html>`);
    await p.screenshot({ path: `${J.out}/_page${s / 64}.png`, omitBackground: true, clip: { x: 0, y: 0, width: J.w * 8, height: J.h * 8 } });
  }
  await b.close(); })();""", job], check=True)
    from PIL import Image
    paths = []
    for s in range(0, len(svgs), 64):
        page = Image.open(f"{outdir}/_page{s // 64}.png")
        for i in range(min(64, len(svgs) - s)):
            c, r = i % 8, i // 8
            p = f"{outdir}/{prefix}{s + i:04d}.png"
            page.crop((c * PXW, r * PXH, (c + 1) * PXW, (r + 1) * PXH)).save(p); paths.append(p)
        os.remove(f"{outdir}/_page{s // 64}.png")
    os.remove(job)
    return paths

if __name__ == "__main__" and sys.argv[1] == "poses":
    from PIL import Image, ImageDraw
    names = sys.argv[3].split(",") if len(sys.argv) > 3 else list(KEYS)
    svgs = [svg(KEYS[n], who, 1) for who in ("bebo", "evan") for n in names]
    tmp = tempfile.mkdtemp(prefix="cats-"); paths = render(svgs, tmp)
    cols = 6; rows = math.ceil(len(paths) / cols)
    sheet = Image.new("RGBA", (cols * PXW, rows * (PXH + 22)), (40, 22, 14, 255)); d = ImageDraw.Draw(sheet)
    for i, p in enumerate(paths):
        c, r = i % cols, i // cols; x, y = c * PXW, r * (PXH + 22)
        d.line([(x + 10, y + int((180 - TOP) * SCALE)), (x + PXW - 10, y + int((180 - TOP) * SCALE))], fill=(255, 255, 255, 70), width=1)
        im = Image.open(p); sheet.alpha_composite(im, (x, y))
        d.text((x + 10, y + PXH + 4), ("bebo " if i < len(names) else "evan ") + names[i % len(names)], fill=(255, 255, 255, 180))
    sheet.convert("RGB").save(sys.argv[2]); print(sys.argv[2])
