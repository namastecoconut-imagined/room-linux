// Room maps (the Room screen's drawing of a room, RoomMap.qml): the pen helpers. A room file (aviral.js…) calls
// setup() with its size and where it sits, lists its lamps, and adds its things; bake.py draws them.
//
// Coordinates: u along the room's back-left wall (cm-ish), y away from the other back wall, z up. Seen from the
// doorway: P() turns a point into stage coordinates (1368 × 912), mirrored so the drawing reads as the room does
// standing in it. Each thing is drawn whole — faces and lines — and the faces of nearer things hide the lines of
// what's behind them (render() below); the faces themselves are never shown: only lines, on Room's background.
let S, OX, OY, W, D, H;
function setup(r) { ({ S, OX, OY, W, D, H } = r); }
const P = (u, y, z) => [OX - (u - y) * 0.866 * S, OY + (u + y) * 0.5 * S - z * S];
const pts = a => a.map(p => P(...p).map(v => v.toFixed(1)).join(',')).join(' ');
const INK = '#f1e9df', INK2 = 'rgba(241,233,223,.55)', INK3 = 'rgba(241,233,223,.28)';
// tones for the faces (they only hide; see render) — kept so a thing reads the same if it's ever drawn filled
const C = { wall: '#3a261b', wall2: '#33221a', floor: '#2b1b13', face: '#40291d', top: '#4b3224', wood: '#5a3826', woodTop: '#664130',
  linen: '#6b5a4e', linenTop: '#7a685b', cushion: '#5d5248', leaf: '#3f4a30', leaf2: '#4a5638', dark: '#17100c', glass: '#3a3530' };
let out = '';
let LIT = new Set();                       // the lamps drawn lit (their shades filled): only in the shade pass
const lit = l => LIT.has(l.n);
const poly = (a, fill, st = INK, w = 1.3) => out += `<polygon points="${pts(a)}" fill="${fill}" stroke="${st}" stroke-width="${w}" stroke-linejoin="round"/>`;
const line = (a, st = INK2, w = 1, dash) => out += `<polyline points="${pts(a)}" fill="none" stroke="${st}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"${dash ? ` stroke-dasharray="${dash}"` : ''}/>`;
function box(u0, y0, z0, u1, y1, z1, f = C.face, t = C.top, st = INK, w = 1.3) {
  poly([[u0,y1,z0],[u1,y1,z0],[u1,y1,z1],[u0,y1,z1]], f, st, w);
  poly([[u1,y0,z0],[u1,y1,z0],[u1,y1,z1],[u1,y0,z1]], f, st, w);
  poly([[u0,y0,z1],[u1,y0,z1],[u1,y1,z1],[u0,y1,z1]], t, st, w);
}
function cyl(cu, cy, z0, z1, r, f = C.face, t = C.top, st = INK, w = 1.2) {
  const [x, ya] = P(cu, cy, z0), [, yb] = P(cu, cy, z1), rx = r * 0.866 * S * 1.15, ry = r * .5 * S * 1.15;
  out += `<path d="M${x - rx},${yb} V${ya} A${rx},${ry} 0 0 0 ${x + rx},${ya} V${yb}" fill="${f}" stroke="${st}" stroke-width="${w}"/>`;
  out += `<ellipse cx="${x}" cy="${yb}" rx="${rx}" ry="${ry}" fill="${t}" stroke="${st}" stroke-width="${w}"/>`;
  return [x, ya, yb, rx, ry];
}
const rgb = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
// a lamp's shade, lit: tinted in Room with the lamp's own colour (it's drawn white here, on its own)
const SHADE = 'keep:#ffffff';
function leafAt(u, y, z, ang, k = 1, fill = C.leaf) { const [a, b] = P(u, y, z);
  out += `<path d="M${a},${b} c${7*k},${-9*k} ${20*k},${-9*k} ${26*k},0 c${-6*k},${9*k} ${-19*k},${9*k} ${-26*k},0 Z" transform="rotate(${ang} ${a} ${b})" fill="${fill}" stroke="${INK2}" stroke-width=".9"/>`; }

// each thing: its depth (nearer = later), and how it's drawn
const things = [];
const add = (d, f) => things.push([d, f]);

// the drawing, nearest last, each thing's faces cutting away the lines of all before it.
// lines: every line, no shade filled. shade: only lamp n's shade, filled white (and hidden where things are in front).
function render(mode, n) {
  LIT = new Set(mode === 'shade' ? [n] : []);
  const sorted = things.slice().sort((a, b) => a[0] - b[0]);
  let acc = '';
  sorted.forEach((t, i) => {
    out = ''; t[1](); const raw = out;
    let vis = raw.replace(/fill="(?!none)(?!keep:)[^"]*"/g, 'fill="none"').replace(/fill="keep:([^"]*)"/g, 'fill="$1"');
    if (mode === 'shade') vis = vis.replace(/stroke="(?!none)[^"]*"/g, 'stroke="none"');
    if (i === 0 || t[0] >= 2000) { acc += vis; return; }
    const occ = raw.replace(/fill="(?!none)[^"]*"/g, 'fill="black"').replace(/stroke="(?!none)[^"]*"/g, 'stroke="black"');
    acc = `<mask id="m${i}" maskUnits="userSpaceOnUse" x="-3000" y="-3000" width="8000" height="8000"><rect x="-3000" y="-3000" width="8000" height="8000" fill="white"/>${occ}</mask><g mask="url(#m${i})">${acc}</g>${vis}`;
  });
  return acc;
}
