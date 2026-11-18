// Room standby scenes: the drawings. Each stroke carries its place in the build (data-t0, data-dur, in build units).

const INK = '#f4eee6', GINGER = '#d9853b', TAG = '#f5b942', WARM = '#ffcf9c', SAGE = '#b9c28a';
let D = 0;
function P(d, t = .7, cls = '', extra = '') { const s = `<path d="${d}" pathLength="1" class="d ${cls}" style="--d:${D.toFixed(2)};--t:${t}" data-t0="${D.toFixed(2)}" data-dur="${t}" ${extra}/>`; D += t * .42; return s; }
function Pa(d, delay, t = .4, cls = '', extra = '') { return `<path d="${d}" pathLength="1" class="d ${cls}" style="--d:${delay.toFixed(2)};--t:${t}" data-t0="${delay.toFixed(2)}" data-dur="${t}" ${extra}/>`; }
function F(d, fill, o = 1, extra = '', delay) { return `<path d="${d}" class="f" fill="${fill}" style="--d:${((delay === undefined ? D : delay) + .1).toFixed(2)};--o:${o}" ${extra}/>`; }
function G(cls, origin, inner, style = '') { return `<g class="${cls}" style="${origin ? 'transform-origin:' + origin + ';' : ''}${style}">${inner}</g>`; }
function plank(x0, x1, y, th = 12, t = .8) { return P(`M${x0},${y} H${x1} V${y + th} H${x0} Z`, t); }
function bracket(x, y, flip) { const s = flip ? -1 : 1; return P(`M${x},${y} v34 l${34 * s},-34`, .35); }
function star(x, y, r = 5, delay) { const d = `M${x - r},${y} h${2 * r} M${x},${y - r} v${2 * r}`; return G('tw', '', delay === undefined ? P(d, .25, 'thin') : Pa(d, delay, .25, 'thin'), `animation-delay:-${((x * 7 + y * 3) % 30) / 10}s`); }
function moon(x, y, r) { const d = `M${x},${y - r} a${r},${r} 0 1 0 ${r * .9},${r * 1.55} a${r * .8},${r * .8} 0 1 1 ${-r * .9},${-r * 1.55} Z`; return F(d, WARM, .22) + P(d, .9); }
function sun(x, y, r) { const c = `M${x},${y - r} a${r},${r} 0 1 0 .1,0 Z`; let rays = ''; for (let i = 0; i < 12; i++) { const a = i * Math.PI / 6, co = Math.cos(a), si = Math.sin(a); rays += P(`M${(x + co * (r + 16)).toFixed(1)},${(y + si * (r + 16)).toFixed(1)} L${(x + co * (r + 38)).toFixed(1)},${(y + si * (r + 38)).toFixed(1)}`, .2, 'thin'); D -= .05; }
  return F(c, WARM, .2) + P(c, .8) + G('spin', `${x}px ${y}px`, rays); }
function glowdot(x, y, i) { return G('tw', '', `<circle cx="${x}" cy="${y}" r="3.5" fill="${TAG}" class="f" style="--d:${(D + i * .1).toFixed(2)};--o:.9"/>`, `animation-duration:${2 + (i % 3)}s;animation-delay:-${i * .7}s`); }
function cloud(x, y, k = 1, dly = 0) { return G('cloud', '', P(`M${x},${y} a${22 * k},${22 * k} 0 0 1 ${40 * k},${-14 * k} a${30 * k},${30 * k} 0 0 1 ${56 * k},0 a${22 * k},${22 * k} 0 0 1 ${36 * k},${14 * k} Z`, .8, 'thin'), `animation-delay:-${dly}s`); }
function pot(x, y, sw = true) { const leaves = P(`M${x + 22},${y - 34} c-4,-30 -22,-44 -34,-46 M${x + 22},${y - 34} c0,-36 8,-56 18,-66 M${x + 22},${y - 34} c6,-26 24,-36 38,-36`, .7, 'thin');
  return P(`M${x},${y} l5,-34 h34 l5,34`, .4) + (sw ? G('sway2', `${x + 22}px ${y - 34}px`, leaves) : leaves); }
function leaf(x, y, a, delay, k = 1) { const d = 'M0,0 c8,-10 22,-10 30,0 c-8,10 -22,10 -30,0 Z', tr = `transform="translate(${x},${y}) rotate(${a}) scale(${k})"`; return F(d, SAGE, .3, tr, delay) + Pa(d, delay, .35, 'thin', tr); }
function rnd(seed) { let a = seed; return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function fly(path, dur, begin = 0) { return `<g class="f" style="--d:${(D + .3).toFixed(2)};--o:.9"><g><animateMotion dur="${dur}s" begin="${begin}s" repeatCount="indefinite" rotate="0" path="${path}"/><path d="M0,0 l-9,-9 v15 Z M0,0 l9,-9 v15 Z" fill="${TAG}" fill-opacity=".85"><animateTransform attributeName="transform" type="scale" values="1 1;.25 1;1 1" dur=".5s" repeatCount="indefinite"/></path></g></g>`; }

const SCENES = [
{ id: 'roofs', name: 'Rooftops', time: { x: 56, y: 48, size: 190, cols: 1 },
  n1: 'Top left, in the sky, as before.',
  n2: 'One column straight down under the time, timer first. With all five it runs most of the way down the left edge; with fewer it simply ends higher and more sky shows.',
  n3: 'The two buildings on the left are now low stubs so the column has clear sky behind it. The skyline starts climbing from a quarter of the way across.',
  spots: [{ id: 'roofC', x0: 350, x1: 430, y: 540 }, { id: 'stairtop', x0: 446, x1: 514, y: 488 }, { id: 'roofD', x0: 572, x1: 808, y: 600 }, { id: 'tank', x0: 850, x1: 930, y: 328 }, { id: 'roofG', x0: 1240, x1: 1296, y: 380 }],
  sleep: [{ who: 'bebo', mode: 'curl', x: 890, y: 328, mirror: true }, { who: 'evan', mode: 'curl', x: 700, y: 600 }],
  cats: [{ who: 'bebo', mode: 'sit', x: 890, y: 328, mirror: true }, { who: 'evan', mode: 'walk', x0: 610, x1: 770, y: 600 }],
  draw(sky) { let s = '', r = rnd(11);
    const B = [[-10, 150, 846], [150, 340, 818], [340, 560, 540], [560, 820, 600], [820, 960, 430], [960, 1180, 520], [1180, 1378, 380]];
    let body = P('M-10,846 H150 V818 H340 V540 H560 V600 H820 V430 H960 V520 H1180 V380 H1378', 2.2);
    const t0 = D;
    B.forEach((b, i) => { body += Pa(`M${b[0]},${b[2] + 12} H${b[1]}`, .5 + b[0] / 1368 * 1.6, .5, 'thin'); if (i) { const y = Math.max(b[2], B[i - 1][2]); body += Pa(`M${b[0]},${y} V912`, .7 + b[0] / 1368 * 1.6, .7, 'thin'); } });
    B.forEach(b => { for (let y = b[2] + 46; y < 880; y += 64) for (let x = b[0] + 26; x + 24 < b[1] - 14; x += 52) { if (r() > .78) continue; const dl = 1.2 + x / 1368 * 1.8 + r() * .5, d = `M${x},${y} h24 v30 h-24 Z`;
      if (sky !== 'day' && r() < (sky === 'night' ? .14 : .3)) body += G('lit', '', F(d, WARM, .3, '', dl), `animation-duration:${(18 + r() * 26).toFixed(0)}s;animation-delay:-${(r() * 30).toFixed(0)}s`);
      body += Pa(d, dl, .3, 'thin'); } });
    s += `<g mask="url(#fade)">${body}</g>`;
    D = t0 + .9;
    s += P('M440,540 V488 H520 V540 M470,540 v-34 h22 v34', .5);
    s += P('M842,430 V392 M938,430 V392 M842,414 L938,392', .4) + P('M834,392 V346 a56,18 0 0 1 112,0 V392 Z', .7) + P('M834,358 a56,18 0 0 0 112,0', .4, 'thin');
    s += P('M990,520 V448 M1156,520 V448', .4) + P('M990,452 Q1073,482 1156,452', .5, 'thin');
    s += G('sway2', '1073px 452px', F('M1018,464 h26 v34 h-26 Z', GINGER, .55) + P('M1018,464 h26 v34 h-26 Z', .3, 'thin') + P('M1062,470 l9,-4 l9,4 l9,-4 v36 h-27 Z', .3, 'thin') + P('M1108,466 h16 v24 h-16 Z', .25, 'thin'));
    s += P('M1306,380 V268 M1284,282 h44 M1288,298 h36 M1294,314 h24', .6); if (sky !== 'day') s += G('blink', '', `<circle cx="1306" cy="262" r="4" fill="${GINGER}" class="f" style="--d:${D.toFixed(2)}"/>`);
    s += P('M1214,380 v-20 M1198,338 a24,24 0 0 0 34,26 Z', .4);
    if (sky === 'day') s += sun(1090, 160, 40); else { s += moon(1090, 150, 38);
      [[640, 90, 5], [760, 200, 4], [900, 110, 4], [1000, 250, 4], [1210, 110, 5], [1280, 200, 4], [1160, 290, 4], [700, 330, 4], [600, 230, 4]].forEach((p, i) => s += star(p[0], p[1], p[2], D + i * .08)); }
    s += cloud(660, 150, 1.1, 20) + cloud(880, 290, .8, 45);
    return s; } },

{ id: 'room', name: 'Their room', time: { x: 800, y: 44, size: 190, cols: 2 },
  n1: 'On the wall at the top right, a little further left than before to make room beside it.',
  n2: 'Two columns on the wall under the time, like notes pinned above the armchair: timer and next event, then alarm and reminders, then lights.',
  n3: 'The wall shelf with the books is gone, the armchair sits a little lower and the floor lamp is shorter, so nothing reaches up into the statuses.',
  spots: [{ id: 'sill', x0: 130, x1: 660, y: 560 }, { id: 'floor', x0: 40, x1: 700, y: 850 }, { id: 'chairback', x0: 1000, x1: 1160, y: 640 }, { id: 'chairseat', x0: 990, x1: 1170, y: 766 }, { id: 'armL', x0: 928, x1: 968, y: 714, low: true }],
  sleep: [{ who: 'bebo', mode: 'curl', x: 1080, y: 766, mirror: true }, { who: 'evan', mode: 'curl', x: 420, y: 560 }],
  cats: [{ who: 'bebo', mode: 'sit', x: 520, y: 560, mirror: true }, { who: 'evan', mode: 'walk', x0: 190, x1: 600, y: 850 }],
  draw(sky) { let s = '';
    s += P('M-10,850 H1378', 1.4);
    s += P('M150,560 V130 a40,40 0 0 1 40,-40 H600 a40,40 0 0 1 40,40 V560', 1.3) + P('M395,90 V560 M150,320 H640', .6, 'thin');
    s += sky === 'day' ? sun(520, 200, 26) : moon(520, 190, 30) + star(220, 160) + star(300, 240, 4) + star(450, 140, 4) + star(580, 270, 4) + star(230, 390, 4);
    s += P('M150,524 c60,-50 130,-60 200,-20 c50,-40 120,-44 170,-8 c40,-20 80,-16 120,10', .9, 'thin');
    s += G('cloud', '', P('M230,230 a18,18 0 0 1 32,-11 a24,24 0 0 1 45,0 a18,18 0 0 1 29,11 Z', .6, 'thin'), 'animation-duration:50s');
    s += plank(110, 680, 560, 16, .8);
    s += P('M96,62 H694', .5);
    s += G('curt', '134px 62px', P('M112,62 c-8,160 14,330 -6,490 M134,62 c-10,170 16,340 0,490 M156,62 c-6,150 10,300 4,470', 1, 'thin'));
    s += G('curt', '667px 62px', P('M678,62 c8,160 -14,330 6,490 M656,62 c10,170 -16,340 0,490', 1, 'thin'), 'animation-delay:-2s');
    // sideboard with a plant and the fishbowl
    s += plank(720, 900, 700, 12, .7) + P('M736,712 V850 M884,712 V850', .5) + P('M736,790 H884', .4, 'thin');
    s += pot(740, 700);
    s += F('M822,700 a34,34 0 1 1 56,0 Z', '#9cc4ff', .14) + P('M822,700 a34,34 0 1 1 56,0 M832,648 h36', .6) + G('swim', '', F('M842,676 c8,-8 18,-8 24,0 c-6,8 -16,8 -24,0 l-8,-6 v12 Z', GINGER, .9));
    // armchair
    s += P('M975,766 V680 a40,40 0 0 1 40,-40 H1145 a40,40 0 0 1 40,40 V766', .9);
    s += P('M920,850 V742 a28,28 0 0 1 55,0 V850', .6) + P('M1185,850 V742 a28,28 0 0 1 55,0 V850', .6);
    s += P('M975,766 H1185 M975,808 H1185', .5) + P('M1010,678 c40,10 100,10 140,0', .4, 'thin');
    // floor lamp
    s += P('M1264,850 h60 M1294,850 V672', .6) + P('M1260,672 l16,-52 h36 l16,52 Z', .5);
    if (sky !== 'day') s += G('breathe', '', `<ellipse cx="1294" cy="750" rx="150" ry="150" fill="url(#glow)" class="f" style="--d:${(D + .2).toFixed(2)};--o:1"/>`);
    // rug
    s += P('M150,880 H700', .6, 'thin') + P('M150,880 v8 M166,880 v8 M182,880 v8 M668,880 v8 M684,880 v8 M700,880 v8', .3, 'thin');
    return s; } },

{ id: 'wall', name: 'The shelf wall', time: { x: 100, base: 440, size: 250, cols: 3 },
  n1: 'Standing on its own long shelf, big, a little higher up the wall than before.',
  n2: 'Hanging under the time’s shelf, three across: timer, next event and alarm, then reminders and lights below. The shelf is exactly as wide as the three columns.',
  n3: 'The low shelf with the box is gone from the middle; the box moved up to the right-hand shelf. The whole lower left belongs to the statuses.',
  spots: [{ id: 'timeshelf', x0: 'clockRight+40', x1: 880, y: 440 }, { id: 'digits', note: 'the tops of the clock numbers, as catDigits() does now' }, { id: 'shelfTop', x0: 880, x1: 1220, y: 220 }, { id: 'shelfMid', x0: 980, x1: 1180, y: 450 }, { id: 'treeBed', x0: 1122, x1: 1258, y: 640 }, { id: 'treePerch', x0: 1056, x1: 1170, y: 770 }, { id: 'cubbyTop', x0: 1238, x1: 1332, y: 792 }, { id: 'rug', x0: 1040, x1: 1170, y: 880 }],
  sleep: [{ who: 'bebo', mode: 'curl', x: 1190, y: 638, mirror: true }, { who: 'evan', mode: 'curl', x: 800, y: 440 }],
  cats: [{ who: 'bebo', mode: 'sit', x: 800, y: 440, mirror: true }, { who: 'evan', mode: 'walk', x0: 940, x1: 1150, y: 220 }],
  draw(sky) { let s = '';
    s += plank(70, 890, 440, 14, 1.1) + bracket(130, 454) + bracket(830, 454, true);
    s += plank(860, 1310, 220) + bracket(900, 232) + bracket(1270, 232, true) + pot(1240, 220);
    s += plank(960, 1320, 450) + bracket(1000, 462) + bracket(1280, 462, true);
    s += P('M1196,450 v-66 h100 v66 M1196,384 l-18,-22 M1296,384 l18,-22', .6);
    s += G('sway', '1010px 462px', P('M1010,462 V536', .4, 'thin') + F('M1010,536 m-20,20 a20,20 0 1 0 40,0 a20,20 0 1 0 -40,0', GINGER, .5) + P('M1010,536 m-20,20 a20,20 0 1 0 40,0 a20,20 0 1 0 -40,0', .5) + P('M994,548 c12,6 22,18 26,28 M998,566 c8,-12 20,-20 30,-22', .4, 'thin'));
    // the tree
    s += P('M1030,880 H1350', .6) + P('M1030,880 v8 M1046,880 v8 M1334,880 v8 M1350,880 v8', .3, 'thin');
    s += P('M1179,880 V652 M1201,880 V652', .9) + P('M1179,850 l22,-10 M1179,830 l22,-10 M1179,810 l22,-10 M1179,790 l22,-10', .5, 'thin');
    s += P('M1230,880 V792 H1340 V880', .5) + P('M1256,880 v-34 a29,29 0 0 1 58,0 v34', .4);
    s += plank(1046, 1179, 770, 12, .5) + P('M1179,818 L1112,782', .3);
    s += P('M1110,640 H1270 M1110,640 c0,-18 14,-22 26,-14 M1270,640 c0,-18 -14,-22 -26,-14', .7) + P('M1110,640 v12 H1270 v-12', .4);
    s += G('sway', '1068px 782px', P('M1068,782 V836', .35, 'thin') + F('M1068,836 l-12,16 h24 Z', TAG, .7) + P('M1068,836 l-12,16 h24 Z', .3));
    s += fly('M1150,120 c40,-60 130,-40 110,10 c-20,50 -130,40 -110,-10', 9);
    return s; } },

{ id: 'garden', name: 'The garden', time: { x: 56, y: 268, size: 190, cols: 2 },
  n1: 'On the left under the sun, moved up from the grass to the middle of the screen.',
  n2: 'Two columns under the time, filling the open lawn between the sun and the grass, stopping short of the wall.',
  n3: 'The time left the bottom corner, one of the two flowers went, and the low butterfly now flies over the wall instead of the lawn.',
  spots: [{ id: 'wall', x0: 640, x1: 1210, y: 660 }, { id: 'branch', x0: 800, x1: 1340, curve: 'M1378,150 C1200,140 1040,200 760,190', note: 'y follows the curve, like the weather screen’s curve spot' }],
  sleep: [{ who: 'bebo', mode: 'curl', x: 1162, y: 166, mirror: true }, { who: 'evan', mode: 'curl', x: 900, y: 660 }],
  cats: [{ who: 'bebo', mode: 'sit', x: 1162, y: 166, mirror: true }, { who: 'evan', mode: 'walk', x0: 720, x1: 1130, y: 660 }],
  draw(sky) { let s = '';
    // the branch
    s += P('M1378,150 C1200,140 1040,200 760,190', 1.4) + P('M1378,190 C1230,180 1090,228 900,214', 1, 'thin');
    s += P('M1000,197 c-40,-50 -90,-70 -150,-72', .6) + P('M1230,152 c-20,-40 -10,-80 24,-116', .6) + P('M860,193 c-40,24 -70,52 -84,96', .6);
    const t0 = D; let lv = '';
    [[850, 125, 200], [880, 118, 250], [910, 130, 160], [940, 150, 230], [776, 289, 100], [790, 262, 40], [812, 236, 130], [760, 190, 180], [790, 182, 220], [1254, 36, 300], [1240, 70, 210], [1262, 96, 330], [1100, 170, 250], [1040, 186, 240], [1300, 150, 260], [930, 204, 120], [1010, 226, 110]].forEach((l, i) => lv += leaf(l[0], l[1], l[2], t0 + i * .07));
    s += G('sway2', '1000px 190px', lv); D = t0 + 1;
    s += G('sway', '950px 187px', P('M950,187 V270', .4, 'thin') + F('M934,278 h32 v46 h-32 Z', WARM, sky === 'day' ? .16 : .5) + P('M934,278 h32 v46 h-32 Z M930,278 h40 M940,270 h20 M934,324 h32', .5));
    // the sun, or the moon
    if (sky === 'day') s += sun(220, 130, 46); else { s += moon(220, 122, 40); [[90, 70, 5], [360, 60, 4], [420, 200, 4], [600, 90, 5], [700, 270, 4], [130, 230, 4]].forEach((p, i) => s += star(p[0], p[1], p[2], D + i * .08)); }
    s += cloud(450, 110, 1.1, 10) + cloud(640, 360, .8, 40);
    // the wall
    s += P('M620,912 V660 H1378', 1.3) + P('M620,678 H1378', .8, 'thin');
    const r = rnd(5); for (let i = 0; i < 11; i++) { const x = 650 + i * 62 + r() * 6, y = 706 + ((i * 3 + Math.floor(r() * 2)) % 6) * 32; s += Pa(`M${x.toFixed(0)},${y} h58 v22 h-58 Z`, D + i * .05, .3, 'thin'); }
    D += .5;
    s += pot(1230, 660) + P('M1316,660 l4,-28 h26 l4,28', .4) + P('M1333,632 v-44 M1333,610 c-14,0 -16,-10 -16,-20 M1333,600 c14,0 16,-10 16,-22', .5, 'thin');
    // grass and flowers
    s += P('M-10,880 H620', .9);
    let tuft = ''; [30, 120, 230, 330, 430, 520].forEach((x, i) => tuft += Pa(`M${x},880 l-6,-18 M${x + 6},880 l2,-24 M${x + 12},880 l8,-16`, D + i * .05, .3, 'thin'));
    s += tuft; D += .4;
    s += G('sway2', '592px 880px', P('M592,880 c4,-20 -4,-40 0,-58', .5, 'thin') + F('M592,822 m-10,0 a10,10 0 1 0 20,0 a10,10 0 1 0 -20,0', TAG, .6) + P('M592,822 m-10,0 a10,10 0 1 0 20,0 a10,10 0 1 0 -20,0', .4), 'animation-delay:-1.5s');
    if (sky === 'day') s += fly('M680,580 c30,-60 90,-40 70,0 c-20,40 -100,50 -70,0', 8) + fly('M900,560 c60,-50 160,-30 130,20 c-30,50 -170,30 -130,-20', 13, 1);
    else [[690, 560], [760, 470], [880, 590], [1010, 520], [1120, 600], [600, 700], [820, 380]].forEach((p, i) => s += glowdot(p[0], p[1], i));
    // a falling leaf
    s += `<g opacity="0"><animate attributeName="opacity" values="0;.8;.8;0" keyTimes="0;.1;.85;1" dur="12s" begin="6s" repeatCount="indefinite"/><animateMotion dur="12s" begin="6s" repeatCount="indefinite" rotate="auto" path="M820,240 c40,80 -50,150 0,230 c40,70 -40,130 -10,190"/><path d="M0,0 c8,-10 22,-10 30,0 c-8,10 -22,10 -30,0 Z" fill="${SAGE}" fill-opacity=".5" stroke="${INK}" stroke-opacity=".5" stroke-width="1.5"/></g>`;
    return s; } }
];

const DEFS = `<defs>
  <filter id="hand" filterUnits="userSpaceOnUse" x="0" y="0" width="1368" height="912"><feTurbulence type="fractalNoise" baseFrequency=".011" numOctaves="1" seed="7" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="4" xChannelSelector="R" yChannelSelector="G"/></filter>
  <radialGradient id="glow"><stop offset="0" stop-color="#ffcf9c" stop-opacity=".2"/><stop offset="1" stop-color="#ffcf9c" stop-opacity="0"/></radialGradient>
  <linearGradient id="fg" gradientUnits="userSpaceOnUse" x1="0" y1="740" x2="0" y2="912"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#555"/></linearGradient>
  <mask id="fade" maskUnits="userSpaceOnUse" x="0" y="0" width="1368" height="912"><rect width="1368" height="912" fill="url(#fg)"/></mask></defs>`;

