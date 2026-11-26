.pragma library
// The pixel display's pictures, drawn dot by dot: clock faces, art loops, timers, effects (from pixelcontrol.html).
// Every frame is N*N*4 bytes (RGBA). Used by the Pixel screen's preview and tiles.
var N = 32;
function blank() { var p = new Uint8ClampedArray(N * N * 4); for (var i = 3; i < p.length; i += 4) p[i] = 255; return p; }
function hex(c) { return [1, 3, 5].map(function (i) { return parseInt(c.substr(i, 2), 16); }); }
var palette = ["#ffffff", "#ff4d2e", "#ff9f1c", "#ffd23f", "#3ddc84", "#2ec4ff", "#3a5bff", "#9b5de5", "#ff5ea8", "#8a8f93", "#000000"];
var DIGITS = { 0: "111101101101111", 1: "010110010010111", 2: "111001111100111", 3: "111001111001111", 4: "101101111001001", 5: "111100111001111", 6: "111100111101111", 7: "111001001001001", 8: "111101111101111", 9: "111101111001111", ":": "000010000010000" };
var FACES = [["stack", "Stack"], ["tiny", "Tiny"], ["corner", "Corner"], ["diagonal", "Diagonal"], ["ring", "Ring"], ["orbit", "Orbit"], ["dots", "Dots"], ["dial", "Dial"], ["modular", "Modular"], ["moons", "Moons"], ["grid", "Grid"], ["comet", "Comet"], ["binary", "Binary"], ["edge", "Edge"], ["arc", "Arc"]];
var FACE_NAMES = {}; FACES.forEach(function (f) { FACE_NAMES[f[0]] = f[1]; });
var shade = (c, k) => c.map(v => Math.round(v * k));
var TAU = Math.PI * 2, frac = v => v - Math.floor(v), rnd1 = n => { const v = Math.sin(n * 127.1 + 311.7) * 43758.5453; return v - Math.floor(v); };
var near = (d, w) => Math.max(0, 1 - Math.abs(d) / w);
function pen(p) {
  const put = (x, y, c) => { x = Math.round(x); y = Math.round(y); if (x >= 0 && y >= 0 && x < N && y < N) p.set([c[0], c[1], c[2], 255], (y * N + x) * 4); };
  const glyph = (ch, x0, y0, s, c) => { const g = DIGITS[ch]; for (let r = 0; r < 5; r++) for (let k = 0; k < 3; k++) if (g[r * 3 + k] === "1") for (let a = 0; a < s; a++) for (let b = 0; b < s; b++) put(x0 + k * s + b, y0 + r * s + a, c); };
  const width = (str, s) => str.length * 3 * s + (str.length - 1) * s;
  const at = (str, x, y0, s, c) => { for (const ch of str) { glyph(ch, x, y0, s, c); x += 4 * s; } };
  const word = (str, y0, s, c, xa = 0, xb = N) => at(str, xa + ((xb - xa - width(str, s)) >> 1), y0, s, c);
  const stroke = (x0, y0, x1, y1, c) => { const n = Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0))) || 1; for (let i = 0; i <= n; i++) put(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, c); };
  return { put, glyph, width, at, word, stroke };
}
// the seconds dot: once round the outer edge a minute, from top centre
function edgeDot(put, sec, col) {
  var e = N - 1, k = Math.round(sec / 60 * 4 * e + e / 2) % (4 * e), side = Math.floor(k / e), r = k % e;
  put(side === 0 ? r : side === 1 ? e : side === 2 ? e - r : 0, side === 0 ? 0 : side === 1 ? r : side === 2 ? e : e - r, col);
}
function clockFrame(face, d, o) {
  if (NEWFACES[face]) {                           // the faces added on the Surface (below)
    var q = blank(); NEWFACES[face](q, d, o);
    if (o.secs && face !== "edge") edgeDot(pen(q).put, d.getSeconds(), o.col);     // (Edge's own dot walks the edge)
    return q;
  }
  const p = blank(), col = o.col, mid2 = shade(col, 0.6), dim = shade(col, 0.3), faint = shade(col, 0.14), { put, at, word, stroke } = pen(p);
  let h = d.getHours(); const m = d.getMinutes(); if (!o.h24) h = h % 12 || 12;
  const secs = o.secs, ACCENT = [215, 25, 33];
  const hh = String(h).padStart(2, "0"), mm = String(m).padStart(2, "0"), c0 = (N - 1) / 2, flat = N >= 20 ? hh + ":" + mm : hh + mm;
  const polar = (a, r) => [c0 + Math.sin(a) * r, c0 - Math.cos(a) * r];
  if (face === "stack") {
    const s = Math.max(1, Math.floor((N - 2) / 11)), y0 = (N - 11 * s) >> 1;
    word(hh, y0, s, col); word(mm, y0 + 6 * s, s, mid2);
  } else if (face === "tiny") {
    const s = Math.max(1, Math.floor(N / 20));
    word(flat, (N - 5 * s) >> 1, s, col);
    const len = Math.round(m / 59 * (N - 4)); for (let x = 0; x < N - 4; x++) put(2 + x, N - 2, x < len ? col : faint);
  } else if (face === "corner") {
    const s = Math.max(1, Math.floor(N / 24)), e = Math.max(1, N >> 4);
    at(flat, e + 1, N - e - 1 - 5 * s, s, col);
    put(N - e - 2, e + 1, col);
  } else if (face === "diagonal") {
    const s = Math.max(1, Math.floor((N - 4) / 14)), e = Math.max(1, (N - 14 * s) >> 2);
    at(hh, e, e, s, col); at(mm, N - e - 7 * s, N - e - 5 * s, s, mid2);
    stroke(N - e - 2, e + 1, N - e - 2 - 2 * s, e + 1 + 2 * s, faint); stroke(e + 1 + 2 * s, N - e - 2 - 2 * s, e + 1, N - e - 2, faint);
  } else if (face === "ring") {
    const R = N / 2 - 1.5;
    for (let k = 0; k < 12; k++) put(...polar(k * Math.PI / 6, R), k % 3 ? dim : col);
    stroke(c0, c0, ...polar(m * Math.PI / 30, R * 0.8), mid2);
    stroke(c0, c0, ...polar(((d.getHours() % 12) + m / 60) * Math.PI / 6, R * 0.5), col);
  } else if (face === "orbit") {
    const R = N / 2 - 2, s = Math.max(1, Math.floor(N / 20));
    for (let k = 0; k < 12; k++) put(...polar(k * Math.PI / 6, R), faint);
    const [mx, my] = polar(m * Math.PI / 30, R), b = N >= 32 ? 1 : 0;
    for (let a = -b; a <= b; a++) for (let q = -b; q <= b; q++) if (Math.abs(a) + Math.abs(q) <= 1) put(mx + a, my + q, col);
    word(hh, (N - 5 * s) >> 1, s, col);
  } else if (face === "dots") {                 // sixty dots, one per minute, under the hour
    const pitch = Math.max(1, Math.floor((N - 2) / 10)), size = Math.max(1, pitch >> 1), gx = (N - (9 * pitch + size)) >> 1, s = Math.max(1, Math.floor(N / 32));
    const top = Math.max(1, (N - (5 * s + 2 * s + 1 + 5 * pitch + size)) >> 1), gy = top + 5 * s + 2 * s + 1;
    word(hh, top, s, col);
    for (let k = 0; k < 60; k++) for (let a = 0; a < size; a++) for (let q = 0; q < size; q++) put(gx + (k % 10) * pitch + q, gy + Math.floor(k / 10) * pitch + a, k < m ? col : faint);
  } else if (face === "dial") {                  // tick marks, a heavy hour hand, a fine minute hand
    const R = N / 2 - 1, wide = N >= 32 ? 1 : 0;
    for (let k = 0; k < 12; k++) { const a = k * Math.PI / 6, len = (k % 3 ? 0.1 : 0.2) * R + 1; stroke(...polar(a, R), ...polar(a, R - len), k % 3 ? dim : col); }
    const ah = ((d.getHours() % 12) + m / 60) * Math.PI / 6, am = m * Math.PI / 30;
    for (let w = 0; w <= wide; w++) stroke(c0 + Math.cos(ah) * w, c0 + Math.sin(ah) * w, ...polar(ah, R * 0.5).map((v, i) => v + (i ? Math.sin(ah) : Math.cos(ah)) * w), col);
    stroke(c0, c0, ...polar(am, R * 0.82), mid2);
    if (secs) stroke(c0, c0, ...polar(d.getSeconds() * Math.PI / 30, R * 0.9), ACCENT);
    put(c0 - 0.5, c0 - 0.5, ACCENT); put(c0 + 0.5, c0 - 0.5, ACCENT); put(c0 - 0.5, c0 + 0.5, ACCENT); put(c0 + 0.5, c0 + 0.5, ACCENT);
  } else {                                       // modular: time, weekday, date and two progress bars
    const u = N / 32, s = Math.max(1, Math.floor(u)), s2 = N >= 32 ? 2 * s : s, P = v => Math.round(v * u), today = (d.getDay() + 6) % 7;
    at(flat, P(2), P(2), s, col);
    for (let i = 0; i < 7; i++) for (let q = 0; q < s; q++) for (let w = 0; w < s; w++) put(P(2) + i * P(4) + w, P(11) + q, i === today ? ACCENT : i < today ? dim : faint);
    const dy = N >= 32 ? P(17) : P(15); at(String(d.getDate()).padStart(2, "0"), P(2), dy, s2, mid2);
    const bx = P(2) + 7 * s2 + P(3), bw = N - P(2) - bx, bars = [[(d.getHours() * 60 + m) / 1440, dy], [m / 60, dy + 5 * s2 - 2 * s]];
    for (const [part, by] of bars) for (let x = 0; x < bw; x++) for (let q = 0; q < 2 * s; q++) put(bx + x, by + q, x < Math.round(part * bw) ? col : faint);
  }
  if (o.secs) {                 // one dot that goes round once a minute
    const sec = d.getSeconds();
    if (face === "ring" || face === "orbit") put(...polar(sec * Math.PI / 30, N / 2 - (face === "ring" ? 1.5 : 2)), face === "ring" ? col : mid2);
    else if (face === "dial") { /* it has a seconds hand */ }
    else edgeDot(put, sec, col);
  }
  return p;
}
var lat = function (x, y, g) { return x % g.p === g.o && y % g.p === g.o; };
var ART = [
  ["ripple", "Ripple", (x, y, t, g) => g.r > 1.05 ? 0 : Math.max(0, (Math.sin(g.r * 11 - TAU * t) - 0.55) / 0.45) * (1 - g.r * 0.55)],
  ["breathe", "Breathe", (x, y, t, g) => Math.max(near((g.r - (0.3 + 0.32 * (0.5 - 0.5 * Math.cos(TAU * t)))) * g.h, 1.1), g.r * g.h < 1 ? 1 : 0)],
  ["orbits", "Orbits", (x, y, t, g) => { let v = 0; for (let k = 0; k < 4; k++) { const R = (0.24 + k * 0.2) * g.h, a = TAU * (t * (4 - k) + k * 0.23); v = Math.max(v, near(Math.hypot(x - g.c - Math.sin(a) * R, y - g.c + Math.cos(a) * R), 1.4), near(g.r * g.h - R, 0.6) * 0.1); } return v; }],
  ["spiral", "Spiral", (x, y, t, g) => g.r > 1 ? 0 : Math.max(0, (Math.sin(g.a * 2 + g.r * 9 - TAU * t) - 0.72) / 0.28) * (0.35 + 0.65 * g.r)],
  ["rain", "Rain", (x, y, t, g) => { if (rnd1(x) > 0.55) return 0; const sp = 1 + Math.floor(rnd1(x + 50) * 2), head = ((t * sp + rnd1(x + 9)) % 1) * (g.n + 9) - 2, d = head - y; return d >= 0 && d < 7 ? 1 - d / 7 : 0; }],
  ["lattice", "Lattice", (x, y, t, g) => (x % g.p !== g.o || y % g.p !== g.o) ? 0 : 0.1 + 0.9 * Math.pow(Math.max(0, Math.sin(TAU * (t - (x + y) / (2 * g.n)))), 2)],
  ["stars", "Stars", (x, y, t, g) => { const k = rnd1(x * 57 + y * 131); return k > 0.045 ? 0 : Math.pow(0.5 + 0.5 * Math.sin(TAU * (t * (1 + Math.floor(rnd1(k * 999) * 2)) + rnd1(x + y * 7))), 3); }],
  ["blobs", "Blobs", (x, y, t, g) => { let f = 0; for (let k = 0; k < 3; k++) { const bx = Math.sin(TAU * (t * (k + 1) + k * 0.31)) * 0.5, by = Math.cos(TAU * (t * (3 - k) + k * 0.17)) * 0.5; f += 0.07 / ((g.u - bx) ** 2 + (g.v - by) ** 2 + 0.002); } return f > 1 ? 1 : f > 0.72 ? 0.28 : 0; }],
  ["tunnel", "Tunnel", (x, y, t, g) => { const d = Math.max(Math.abs(g.u), Math.abs(g.v)); return d > 1 ? 0 : Math.max(0, (Math.sin(d * 10 - TAU * t) - 0.7) / 0.3) * (0.25 + 0.75 * d); }],
  ["bounce", "Bounce", (x, y, t, g) => { let v = y === g.n - 1 ? 0.14 : 0; for (let k = 0; k < 5; k++) v = Math.max(v, near(Math.hypot(x - (k + 0.5) * g.n / 5, y - (g.n - 3 - Math.abs(Math.sin(Math.PI * (t * (1 + k % 2) + k * 0.19))) * (g.n - 6) * (0.55 + 0.09 * k))), 1.5)); return v; }],
  ["trace", "Trace", (x, y, t, g) => { let v = 0; for (let k = 0; k < 26; k++) { const q = t - k * 0.006; v = Math.max(v, near(Math.hypot(g.u - Math.sin(TAU * 2 * q) * 0.8, g.v - Math.sin(TAU * 3 * q + 0.5) * 0.8) * g.h, 1.2) * (1 - k / 26)); } return v; }],
  ["diamonds", "Diamonds", (x, y, t, g) => { const d = Math.abs(g.u) + Math.abs(g.v); return Math.max(0, (Math.sin(d * 8 - TAU * t) - 0.68) / 0.32) * (1 - d * 0.35); }],
  ["petals", "Petals", (x, y, t, g) => g.r > 1.05 ? 0 : Math.max(near((g.r - 0.9 * Math.abs(Math.cos(2 * g.a + TAU * t))) * g.h, 1.1), g.r * g.h < 1.2 ? 1 : 0)],
  ["loader", "Loader", (x, y, t, g) => { let v = 0; for (let k = 0; k < 10; k++) { const a = k * TAU / 10; v = Math.max(v, near(Math.hypot(g.u - Math.sin(a) * 0.62, g.v + Math.cos(a) * 0.62) * g.h, Math.max(1.2, g.n / 22)) * (0.1 + 0.9 * Math.pow(1 - frac(t - k / 10), 3))); } return v; }],
  ["heart", "Heart", (x, y, t, g) => { const beat = Math.pow(Math.max(0, Math.sin(TAU * t)), 10) + 0.6 * Math.pow(Math.max(0, Math.sin(TAU * (t - 0.17))), 10), s = 0.5 * (1 + 0.16 * beat), X = g.u / s, Y = -(g.v - 0.06) / s, f = Math.pow(X * X + Y * Y - 1, 3) - X * X * Y * Y * Y; return f < 0 ? 1 : f < 0.35 ? 0.16 * beat : 0; }],
  ["snow", "Snow", (x, y, t, g) => { let v = 0; for (let k = 0; k < 22; k++) { const sp = 1 + (k % 2), fy = frac(t * sp + rnd1(k + 3)) * (g.n + 2) - 1, fx = rnd1(k) * g.n + Math.sin(TAU * (t * sp + rnd1(k + 5))) * 1.4; v = Math.max(v, near(Math.hypot(x - fx, y - fy), 0.95) * (0.45 + 0.55 * rnd1(k + 7))); } return v; }],
  // lattice pieces and orbits, added on the Surface
  ["drift", "Drift", function (x, y, t, g) { if (!lat(x, y, g)) return 0; var dx = g.u - 0.62 * Math.sin(TAU * t), dy = g.v - 0.62 * Math.sin(TAU * 2 * t + 0.6); return 0.08 + 0.92 * Math.exp(-(dx * dx + dy * dy) / 0.16); }],
  ["pond", "Pond", function (x, y, t, g) { if (!lat(x, y, g)) return 0; return 0.07 + 0.93 * Math.pow(Math.max(0, Math.sin(g.r * 7 - TAU * t)), 3) * (1 - g.r * 0.35); }],
  ["bloom", "Bloom", function (x, y, t, g) { var cx = Math.round((x - g.o) / g.p) * g.p + g.o, cy = Math.round((y - g.o) / g.p) * g.p + g.o, dd = Math.abs(x - cx) + Math.abs(y - cy); if (dd > 1) return 0;
    var w = 0.5 + 0.5 * Math.sin(TAU * (t - Math.hypot(cx - g.c, cy - g.c) / g.n)); return dd === 0 ? 0.2 + 0.8 * w : w > 0.6 ? (w - 0.6) / 0.4 * 0.8 : 0; }],
  ["twinkle", "Twinkle", function (x, y, t, g) { if (!lat(x, y, g)) return 0; var k = rnd1(x * 7 + y * 13); return 0.06 + 0.94 * Math.pow(0.5 + 0.5 * Math.sin(TAU * (t * (1 + Math.floor(rnd1(k * 91) * 2)) + k)), 5); }],
  ["sway", "Sway", function (x, y, t, g) { if (y % g.p !== g.o) return 0; var s = Math.sin(TAU * (t + y / g.n)), off = Math.round(1.5 * s); return (((x - off) % g.p) + g.p) % g.p === g.o ? 0.3 + 0.7 * (0.5 + 0.5 * s) : 0; }],
  ["cascade", "Cascade", function (x, y, t, g) { if (!lat(x, y, g)) return 0; var col = (x - g.o) / g.p, row = (y - g.o) / g.p, rows = g.n / g.p, sp = 1 + Math.floor(rnd1(col + 40) * 2);
    var head = frac(t * sp + rnd1(col + 3)) * (rows + 4) - 1, d = head - row; return d >= 0 && d < 4 ? Math.max(0.08, 1 - d / 4) : 0.08; }],
  ["satellites", "Satellites", function (x, y, t, g) { var v = 0, k, a, px, py;      // Orbit, moving: two dots on two rings, opposite ways
    for (k = 0; k < 12; k++) { a = TAU * k / 12; if (Math.round(g.c + Math.sin(a) * 14) === x && Math.round(g.c - Math.cos(a) * 14) === y) v = 0.16; if (Math.round(g.c + Math.sin(a) * 8) === x && Math.round(g.c - Math.cos(a) * 8) === y) v = 0.16; }
    if (Math.abs(x - g.c) < 1 && Math.abs(y - g.c) < 1) v = 0.3;
    a = TAU * t; px = Math.round(g.c + Math.sin(a) * 14); py = Math.round(g.c - Math.cos(a) * 14); if (Math.abs(x - px) + Math.abs(y - py) <= 1) v = 1;
    a = -TAU * 2 * t + 2; px = Math.round(g.c + Math.sin(a) * 8); py = Math.round(g.c - Math.cos(a) * 8); if (Math.abs(x - px) + Math.abs(y - py) <= 1) v = Math.max(v, 0.6);
    return v; }],
  ["comet", "Comet", function (x, y, t, g) { var v = lat(x, y, g) ? 0.07 : 0, lag = frac((TAU * t - Math.atan2(g.u, -g.v)) / TAU);
    if (Math.abs(g.r * g.h - 12.5) < 0.8) v = Math.max(v, lag < 0.6 ? Math.pow(1 - lag / 0.6, 2.2) : 0); return Math.max(v, near(Math.hypot(x - g.c - Math.sin(TAU * t) * 12.5, y - g.c + Math.cos(TAU * t) * 12.5), 1.7)); }]
];
var ART_NAMES = {}, ART_FRAMES = 48; ART.forEach(function (a) { ART_NAMES[a[0]] = a[1]; });
function artFrame(id, t, col) {
  const fn = (ART.find(a => a[0] === id) || ART.find(a => a[0] === "lattice"))[2], p = new Uint8ClampedArray(N * N * 4), c = (N - 1) / 2, hN = N / 2, pitch = N >= 32 ? 4 : 3;
  const g = { n: N, c, h: hN, p: pitch, o: pitch >> 1, u: 0, v: 0, r: 0, a: 0 };
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    g.u = (x - c) / hN; g.v = (y - c) / hN; g.r = Math.hypot(g.u, g.v); g.a = Math.atan2(g.v, g.u);
    const k = Math.max(0, Math.min(1, fn(x, y, t, g))), i = (y * N + x) * 4;
    p[i] = col[0] * k; p[i + 1] = col[1] * k; p[i + 2] = col[2] * k; p[i + 3] = 255;
  }
  return p;
}
var mmss = s => [String(Math.min(99, Math.floor(s / 60))).padStart(2, "0"), String(s % 60).padStart(2, "0")];
function timerFrame(kind, secs, total, col) {
  const p = blank(), { put, word } = pen(p), [mm, ss] = mmss(secs);
  const s = Math.max(1, Math.floor((N - 4) / 11)), y0 = Math.max(0, ((N - 11 * s) >> 1) - 1), ly = N - 2, span = N - 4;
  word(mm, y0, s, col); word(ss, y0 + 6 * s, s, shade(col, 0.6));
  if (kind === "cd") { const len = total ? Math.round(secs / total * span) : 0; for (let x = 0; x < span; x++) put(2 + x, ly, x < len ? col : shade(col, 0.14)); }
  else put(2 + Math.round((secs % 60) / 59 * (span - 1)), ly, col);
  return p;
}
function scoreFrame(a, b, col) {
  const p = blank(), { put, word, width } = pen(p), half = N >> 1;
  [[String(a), 0, half - 1], [String(b), half + 1, N]].forEach(([str, xa, xb]) => { let s = 1; while (width(str, s + 1) <= xb - xa - 2 && 5 * (s + 1) <= N - 4) s++; word(str, (N - 5 * s) >> 1, s, col, xa, xb); });
  for (let y = N >> 2; y < N - (N >> 2); y += 2) put(half - (N % 2 ? 0 : 0.5), y, shade(col, 0.3));
  return p;
}
function solid(col, dim) { var p = new Uint8ClampedArray(N * N * 4), k = dim === undefined ? 1 : dim; for (var i = 0; i < N * N; i++) p.set([col[0] * k, col[1] * k, col[2] * k, 255], i * 4); return p; }
var EFFECTS = [[0, "Gradient sweep"], [3, "Vertical sweep"], [4, "Diagonal sweep"], [5, "Stripes"], [1, "Sparkle"], [2, "Starfield"], [6, "Noise"]];
function effectFrame(style, cols, f) {
  var F = 24, seed = 7 + f * 131, p = new Uint8ClampedArray(N * N * 4);
  var rnd = function () { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  var lerp = function (a, b, t) { return a.map(function (v, k) { return Math.round(v + (b[k] - v) * t); }); };
  var at = function (t) { t = ((t % 1) + 1) % 1; var s = t * cols.length, i = Math.floor(s); return lerp(cols[i], cols[(i + 1) % cols.length], s - i); };
  for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) {
    var c;
    if (style === 0) c = at(x / N + f / F);
    else if (style === 3) c = at(y / N + f / F);
    else if (style === 4) c = at((x + y) / (2 * N) + f / F);
    else if (style === 5) c = ((x + y + f) % 6 < 2) ? at((x - y) / N + f / F) : [0, 0, 0];
    else if (style === 1) c = rnd() < .08 ? cols[(rnd() * cols.length) | 0] : [0, 0, 0];
    else if (style === 2) c = rnd() < .05 ? [255, 255, 255] : at(f / F).map(function (v) { return Math.round(v * .35); });
    else c = cols[(rnd() * cols.length) | 0];
    p.set([c[0], c[1], c[2], 255], (y * N + x) * 4);
  }
  return p;
}

var F57 = { A: "01110100011000111111100011000110001", B: "11110100011000111110100011000111110", C: "01110100011000010000100001000101110", E: "11111100001000011110100001000011111", G: "01110100011000010111100011000101110", H: "10001100011000111111100011000110001", I: "01110001000010000100001000010001110", K: "10001100101010011000101001001010001", L: "10000100001000010000100001000011111", N: "10001110011010110011100011000110001", O: "01110100011000110001100011000101110", R: "11110100011000111110101001001010001", S: "01111100001000001110000010000111110", T: "11111001000010000100001000010000100", Y: "10001100010101000100001000010000100",
  0: "01110100011001110101110011000101110", 1: "00100011000010000100001000010001110", 2: "01110100010000100010001000100011111", 3: "11111000100010000010000011000101110", 4: "00010001100101010010111110001000010", 5: "11111100001111000001000011000101110", 6: "00110010001000011110100011000101110", 7: "11111000010001000100010000100001000", 8: "01110100011000101110100011000101110", 9: "01110100011000101111000010001001100", ":": "00000001000000000000000000010000000", " ": "00000000000000000000000000000000000" };
// a message in 5 by 7 dot letters, twice their size, `off` dots along its scroll
function textFrame(str, off, fg, bg) {
  var p = solid(bg), s = 2, x0 = N - off, y0 = (N - 7 * s) >> 1;
  for (var n = 0; n < str.length; n++) {
    var gl = F57[str[n]] || F57[" "];
    for (var r = 0; r < 7; r++) for (var c = 0; c < 5; c++) if (gl[r * 5 + c] === "1") for (var a = 0; a < s; a++) for (var b = 0; b < s; b++) {
      var x = x0 + c * s + b, y = y0 + r * s + a; if (x >= 0 && x < N) p.set([fg[0], fg[1], fg[2], 255], (y * N + x) * 4);
    }
    x0 += 6 * s;
  }
  return p;
}

// ---- clock faces added on the Surface (p: the frame to draw on, d: the time, o: { col, h24, secs })
var NEWFACES = {
  moons: function (p, d, o) {              // no digits: the hour on the inner orbit, the minute on the outer
    var w = pen(p), c0 = (N - 1) / 2, col = o.col, faint = shade(col, 0.14), m = d.getMinutes(), k;
    var polar = function (a, r) { return [c0 + Math.sin(a) * r, c0 - Math.cos(a) * r]; };
    var dot = function (q, c) { for (var a = -1; a <= 1; a++) for (var b = -1; b <= 1; b++) if (Math.abs(a) + Math.abs(b) <= 1) w.put(q[0] + a, q[1] + b, c); };
    for (k = 0; k < 12; k++) { w.put.apply(null, polar(k * Math.PI / 6, 14).concat([faint])); w.put.apply(null, polar(k * Math.PI / 6, 8).concat([faint])); }
    w.put(c0 - 0.5, c0 - 0.5, shade(col, 0.3)); w.put(c0 + 0.5, c0 - 0.5, shade(col, 0.3)); w.put(c0 - 0.5, c0 + 0.5, shade(col, 0.3)); w.put(c0 + 0.5, c0 + 0.5, shade(col, 0.3));
    dot(polar(m * Math.PI / 30, 14), shade(col, 0.6)); dot(polar(((d.getHours() % 12) + m / 60) * Math.PI / 6, 8), col);
  },
  grid: function (p, d, o) {               // the time written on the lattice's own dots
    var w = pen(p), col = o.col, h = d.getHours(), x, y; if (!o.h24) h = h % 12 || 12;
    var two = function (v) { return (v < 10 ? "0" : "") + v; };
    for (y = 2; y < N; y += 4) for (x = 2; x < N; x += 4) w.put(x, y, shade(col, 0.2));
    var write = function (str, y0, c) { for (var n = 0; n < 2; n++) { var gl = DIGITS[str[n]]; for (var r = 0; r < 5; r++) for (var k = 0; k < 3; k++) if (gl[r * 3 + k] === "1") w.put(10 + n * 8 + k * 2, y0 + r * 2, c); } };
    write(two(h), 6, col); write(two(d.getMinutes()), 18, shade(col, 0.6));
  },
  comet: function (p, d, o) {              // Orbit with a tail: the minute's dot drags a quarter-hour of light
    var w = pen(p), c0 = (N - 1) / 2, col = o.col, m = d.getMinutes(), h = d.getHours(), k; if (!o.h24) h = h % 12 || 12;
    var polar = function (a, r) { return [c0 + Math.sin(a) * r, c0 - Math.cos(a) * r]; };
    for (k = 0; k < 12; k++) w.put.apply(null, polar(k * Math.PI / 6, 14).concat([shade(col, 0.12)]));
    for (k = 15; k >= 1; k--) w.put.apply(null, polar((m - k) * Math.PI / 30, 14).concat([shade(col, 0.08 + 0.5 * Math.pow(1 - k / 16, 2))]));
    var q = polar(m * Math.PI / 30, 14); for (var a = -1; a <= 1; a++) for (var b = -1; b <= 1; b++) if (Math.abs(a) + Math.abs(b) <= 1) w.put(q[0] + a, q[1] + b, col);
    w.word((h < 10 ? "0" : "") + h, 11, 2, col);
  },
  binary: function (p, d, o) {             // four columns of dots: each digit of the time in binary (8 · 4 · 2 · 1, top to bottom)
    var w = pen(p), col = o.col, h = d.getHours(), m = d.getMinutes(); if (!o.h24) h = h % 12 || 12;
    var ds = [Math.floor(h / 10), h % 10, Math.floor(m / 10), m % 10];
    for (var c = 0; c < 4; c++) for (var r = 0; r < 4; r++) {
      var on = (ds[c] >> (3 - r)) & 1, x0 = 5 + c * 6 + (c > 1 ? 2 : 0), y0 = 6 + r * 6, cc = on ? (c < 2 ? col : shade(col, 0.6)) : shade(col, 0.2);
      w.put(x0, y0, cc); w.put(x0 + 1, y0, cc); w.put(x0, y0 + 1, cc); w.put(x0 + 1, y0 + 1, cc);
    }
  },
  edge: function (p, d, o) {               // the minute walks the display's edge once an hour; the hour sits in the middle
    var w = pen(p), col = o.col, m = d.getMinutes(), h = d.getHours(), e = N - 3, k; if (!o.h24) h = h % 12 || 12;
    var at = function (s) { s = ((Math.round(s) % (4 * e)) + 4 * e) % (4 * e); var side = Math.floor(s / e), r = s % e;
      return side === 0 ? [1 + r, 1] : side === 1 ? [1 + e, 1 + r] : side === 2 ? [1 + e - r, 1 + e] : [1, 1 + e - r]; };
    var head = m / 60 * 4 * e + e / 2;
    for (k = 0; k < 4; k++) w.put.apply(null, at(k * e + e / 2).concat([shade(col, 0.14)]));
    for (k = 18; k >= 1; k--) w.put.apply(null, at(head - k).concat([shade(col, 0.06 + 0.45 * Math.pow(1 - k / 19, 2))]));
    var q = at(head); w.put(q[0], q[1], col);
    w.word((h < 10 ? "0" : "") + h, 8, 2, col); w.word((m < 10 ? "0" : "") + m, 20, 1, shade(col, 0.55));
  },
  arc: function (p, d, o) {                // one thin ring that fills with the hour's minutes; the hour inside it
    var w = pen(p), c0 = (N - 1) / 2, col = o.col, m = d.getMinutes(), h = d.getHours(); if (!o.h24) h = h % 12 || 12;
    for (var k = 0; k < 120; k++) { var a = k * Math.PI / 60, lit = k / 2 <= m;
      w.put(c0 + Math.sin(a) * 14, c0 - Math.cos(a) * 14, lit ? shade(col, 0.45) : shade(col, 0.1)); }
    var q = [c0 + Math.sin(m * Math.PI / 30) * 14, c0 - Math.cos(m * Math.PI / 30) * 14]; w.put(q[0], q[1], col);
    w.word((h < 10 ? "0" : "") + h, 11, 2, col);
  }
};

// ---- the assistant's faces: up on the display from the moment it hears "Alexa" until it's done. Drawn here like
// the art loops, in one colour, ASSIST_FRAMES frames to a loop; each is function (p, t, col), t going 0 → 1.
function brush(p) {
  var g = pen(p), put = g.put;
  function box(x0, y0, x1, y1, c, r) {
    x0 = Math.round(x0); y0 = Math.round(y0); x1 = Math.round(x1); y1 = Math.round(y1);
    for (var y = y0; y <= y1; y++) for (var x = x0; x <= x1; x++) {
      if (r) { var dx = Math.min(x - x0, x1 - x), dy = Math.min(y - y0, y1 - y);
               if (dx < r && dy < r && (r - dx) + (r - dy) > r) continue; }
      put(x, y, c);
    }
  }
  function disc(cx, cy, rad, c, ring) {
    for (var y = 0; y < N; y++) for (var x = 0; x < N; x++) {
      var d = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (ring ? Math.abs(d - rad) < 0.65 : d <= rad + 0.2) put(x, y, c);
    }
  }
  return { put: put, stroke: g.stroke, box: box, disc: disc };
}
var blinkAt = function (t, at, w) { return Math.max(0, 1 - Math.abs(frac(t - at + 0.5) - 0.5) / w); };
var ASSIST = [
["blink", "Blink", function (p, t, col) {               // two eyes, glancing and blinking
  var b = brush(p), faint = shade(col, 0.1), lid = shade(col, 0.45);
  for (var y = 3; y < N; y += 6) for (var x = 3; x < N; x += 6) b.put(x, y, faint);
  var ox = Math.round(2 * Math.sin(TAU * t)), sh = blinkAt(t, 0.52, 0.055);
  var h = Math.max(0.5, 5.5 * (1 - sh));
  [10, 21].forEach(function (cx) {
    b.box(cx - 3 + ox, 15.5 - h, cx + 3 + ox, 15.5 + h, col, h > 2.5 ? 2 : 0);
    if (sh > 0.6) b.box(cx - 3 + ox, 15.5 - h, cx + 3 + ox, 15.5 + h, lid, 0);
  });
}],
["cat", "Cat", function (p, t, col) {                   // ears, whiskers, a blink — Bebo and Evan
  var b = brush(p), dim = shade(col, 0.45);
  b.stroke(7, 11, 10, 4, col); b.stroke(10, 4, 13, 9, col);        // ears
  b.stroke(24, 11, 21, 4, col); b.stroke(21, 4, 18, 9, col);
  b.disc(15.5, 17, 9.5, col, true);                                 // head
  var sh = blinkAt(t, 0.58, 0.05), h = sh > 0.5 ? 0 : 1;
  b.box(11, 15 - h, 12, 15 + h, col); b.box(19, 15 - h, 20, 15 + h, col);
  b.box(15, 19, 16, 20, col);                                       // nose
  var w = Math.round(Math.sin(TAU * t) * 0.6);
  b.stroke(3, 18 + w, 9, 20, dim); b.stroke(3, 22 + w, 9, 21, dim);
  b.stroke(28, 18 - w, 22, 20, dim); b.stroke(28, 22 - w, 22, 21, dim);
}],
["orb", "Orb", function (p, t, col) {                   // a breathing orb with a dot going round it
  var b = brush(p), soft = shade(col, 0.2), r = 7 + 1.6 * Math.sin(TAU * t);
  b.disc(15.5, 15.5, r, soft); b.disc(15.5, 15.5, r, col, true);
  var a = TAU * t;
  b.box(15.5 + Math.sin(a) * 13 - 0.5, 15.5 - Math.cos(a) * 13 - 0.5, 15.5 + Math.sin(a) * 13 + 0.5, 15.5 - Math.cos(a) * 13 + 0.5, col);
}],
["talk", "Talk", function (p, t, col) {                 // eyes and a mouth that moves as it speaks
  var b = brush(p), sh = blinkAt(t, 0.8, 0.05), h = sh > 0.5 ? 0.5 : 2;
  b.box(9, 10 - h, 11, 10 + h, col); b.box(20, 10 - h, 22, 10 + h, col);
  var m = 1 + 3.2 * Math.abs(Math.sin(TAU * t * 2.5));
  b.box(9, 21 - m, 22, 21 + m, col, m > 2 ? 2 : 0);
}],
["wave", "Wave", function (p, t, col) {                 // eyes, and speech moving under them
  var b = brush(p), dim = shade(col, 0.45);
  b.box(9, 8, 11, 12, col, 1); b.box(20, 8, 22, 12, col, 1);
  var amp = 1.2 + 3.2 * (0.5 + 0.5 * Math.sin(TAU * t * 1.5));
  for (var x = 3; x < 29; x++) {
    var e = Math.min(1, (x - 2) / 6) * Math.min(1, (28 - x) / 6);
    var y = 21 + Math.sin(TAU * (x / 11 - t * 2)) * amp * e;
    b.put(x, y, col); b.put(x, y + (Math.sin(TAU * (x / 11 - t * 2)) > 0 ? -1 : 1), dim);
  }
}],
["owl", "Owl", function (p, t, col) {                   // two big eyes, tufts, a slow blink
  var b = brush(p), dim = shade(col, 0.4);
  b.stroke(5, 10, 8, 4, col); b.stroke(8, 4, 11, 9, col);           // tufts
  b.stroke(26, 10, 23, 4, col); b.stroke(23, 4, 20, 9, col);
  var sh = blinkAt(t, 0.6, 0.06), g = Math.round(Math.sin(TAU * t) * 1.5);
  [9, 22].forEach(function (cx) {
    if (sh > 0.5) for (var x = cx - 6; x <= cx + 6; x++) b.put(x, 16, col);
    else { b.disc(cx, 16, 6, col, true); b.box(cx - 1 + g, 15, cx + g, 17, col); }
  });
  b.stroke(14, 20, 15.5, 24, col); b.stroke(17, 20, 15.5, 24, col); // beak
  b.stroke(10, 26, 15.5, 28, dim); b.stroke(21, 26, 15.5, 28, dim); // chin
}],
["visor", "Visor", function (p, t, col) {               // a light going back and forth behind a visor
  var b = brush(p), dim = shade(col, 0.3);
  b.box(3, 8, 28, 24, col, 3); b.box(5, 10, 26, 22, [0, 0, 0], 2);  // head, hollowed out
  b.box(7, 13, 24, 18, dim, 1);                                     // the visor
  var k = Math.abs(frac(t * 2) * 2 - 1), x0 = 8 + k * 11;
  b.box(x0, 13, x0 + 4, 18, col, 1);
  var v = shade(col, 0.4 + 0.6 * Math.abs(Math.sin(TAU * t * 3)));
  b.stroke(15.5, 4, 15.5, 7, dim); b.box(15, 2, 16, 3, v, 0);       // antenna
}],
["dots", "Dots", function (p, t, col) {                 // three dots, thinking it over
  var b = brush(p);
  for (var k = 0; k < 3; k++) {
    var v = Math.max(0, Math.sin(TAU * (t - k * 0.13)));
    var y = 18 - 5 * v * v;
    b.box(6 + k * 8, y - 2, 9 + k * 8, y + 1, shade(col, 0.4 + 0.6 * v), 1);
  }
}]
];
var ASSIST_NAMES = {}, ASSIST_FRAMES = 24, ASSIST_MS = 70; ASSIST.forEach(function (a) { ASSIST_NAMES[a[0]] = a[1]; });
function assistFrame(id, t, col) {
  var a = null; for (var i = 0; i < ASSIST.length; i++) if (ASSIST[i][0] === id) a = ASSIST[i];
  var p = blank(); if (a) a[2](p, frac(t), col); return p;
}
