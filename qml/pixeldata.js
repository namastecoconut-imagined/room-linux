.pragma library
// The pixel display's pictures, drawn dot by dot: clock faces, art loops, timers, effects (from pixelcontrol.html).
// Every frame is N*N*4 bytes (RGBA). Used by the Pixel screen's preview and tiles.
var N = 32;
function blank() { var p = new Uint8ClampedArray(N * N * 4); for (var i = 3; i < p.length; i += 4) p[i] = 255; return p; }
function hex(c) { return [1, 3, 5].map(function (i) { return parseInt(c.substr(i, 2), 16); }); }
var palette = ["#ffffff", "#ff4d2e", "#ff9f1c", "#ffd23f", "#3ddc84", "#2ec4ff", "#3a5bff", "#9b5de5", "#ff5ea8", "#8a8f93", "#000000"];
var DIGITS = { 0: "111101101101111", 1: "010110010010111", 2: "111001111100111", 3: "111001111001111", 4: "101101111001001", 5: "111100111001111", 6: "111100111101111", 7: "111001001001001", 8: "111101111101111", 9: "111101111001111", ":": "000010000010000" };
var FACES = [["classic", "Classic"], ["stack", "Stack"], ["tiny", "Tiny"], ["corner", "Corner"], ["diagonal", "Diagonal"], ["ring", "Ring"], ["orbit", "Orbit"], ["dots", "Dots"], ["rings", "Rings"], ["jumbo", "Jumbo"], ["outline", "Outline"], ["dial", "Dial"], ["solar", "Solar"], ["modular", "Modular"]];
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
function clockFrame(face, d, o) {
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
  } else if (face === "rings") {                 // three rings: minutes, hours, and the day (or seconds)
    const th = Math.max(1, Math.round(N / 16)), R1 = N / 2 - 0.5 - th / 2, R2 = R1 - 2 * th, R3 = R2 - 2 * th;
    const parts = [[R1, m / 60, col], [R2, ((d.getHours() % 12) + m / 60) / 12, mid2], [R3, secs ? d.getSeconds() / 60 : (d.getHours() * 60 + m) / 1440, secs ? ACCENT : dim]];
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) { const r = Math.hypot(x - c0, y - c0), f = frac(Math.atan2(x - c0, c0 - y) / TAU);
      for (const [R, part, on] of parts) if (Math.abs(r - R) <= th / 2) put(x, y, f < part ? on : faint); }
  } else if (face === "jumbo") {                 // the hour as large as it goes, minutes underneath
    const s = Math.max(1, Math.floor((N - 4) / 7)), s2 = Math.max(1, Math.floor(s / 3)), gap = Math.max(2, s2 * 2), y0 = Math.max(0, (N - (5 * s + gap + 5 * s2)) >> 1);
    word(hh, y0, s, col); word(mm, y0 + 5 * s + gap, s2, mid2);
  } else if (face === "outline") {               // hollow hour, solid minutes
    const s = N < 20 ? 1 : Math.max(2, Math.floor((N - 2) / 10)), s2 = Math.max(1, Math.floor(s * 0.67)), y0 = Math.max(0, (N - (5 * s + 2 + 5 * s2)) >> 1);
    const mask = new Uint8Array(N * N), mp = pen({ set: (v, i) => { mask[i >> 2] = 1; } });
    mp.word(hh, y0, s, [1, 1, 1]);
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (mask[y * N + x] && (s < 3 || !(x > 0 && mask[y * N + x - 1] && x < N - 1 && mask[y * N + x + 1] && y > 0 && mask[(y - 1) * N + x] && y < N - 1 && mask[(y + 1) * N + x]))) put(x, y, col);
    word(mm, y0 + 5 * s + 2, s2, mid2);
  } else if (face === "dial") {                  // tick marks, a heavy hour hand, a fine minute hand
    const R = N / 2 - 1, wide = N >= 32 ? 1 : 0;
    for (let k = 0; k < 12; k++) { const a = k * Math.PI / 6, len = (k % 3 ? 0.1 : 0.2) * R + 1; stroke(...polar(a, R), ...polar(a, R - len), k % 3 ? dim : col); }
    const ah = ((d.getHours() % 12) + m / 60) * Math.PI / 6, am = m * Math.PI / 30;
    for (let w = 0; w <= wide; w++) stroke(c0 + Math.cos(ah) * w, c0 + Math.sin(ah) * w, ...polar(ah, R * 0.5).map((v, i) => v + (i ? Math.sin(ah) : Math.cos(ah)) * w), col);
    stroke(c0, c0, ...polar(am, R * 0.82), mid2);
    if (secs) stroke(c0, c0, ...polar(d.getSeconds() * Math.PI / 30, R * 0.9), ACCENT);
    put(c0 - 0.5, c0 - 0.5, ACCENT); put(c0 + 0.5, c0 - 0.5, ACCENT); put(c0 - 0.5, c0 + 0.5, ACCENT); put(c0 + 0.5, c0 + 0.5, ACCENT);
  } else if (face === "solar") {                 // the sun's path over a horizon: left at 6, top at noon, right at 18
    const hz = Math.round(N * 0.6), R = N * 0.42, steps = Math.ceil(R * 8), f = (d.getHours() * 60 + m) / 1440, a = TAU * (f - 0.25);
    for (let k = 0; k < steps; k++) { const q = k / steps * TAU, y = hz - Math.sin(q) * R; put(c0 - Math.cos(q) * R, y, y <= hz ? dim : faint); }
    for (let x = 0; x < N; x++) put(x, hz, dim);
    const sx = c0 - Math.cos(a) * R, sy = hz - Math.sin(a) * R, big = N >= 32 ? 1 : 0, sun = sy <= hz ? col : dim;
    for (let i = -big; i <= big; i++) for (let j = -big; j <= big; j++) put(sx + i, sy + j, sun);
    const s = Math.max(1, Math.floor(N / 32)); for (let y = hz + 1; y < Math.min(N, hz + 3 + 5 * s + 1); y++) for (let x = 0; x < N; x++) if (Math.abs(x - c0) < (N >= 20 ? 11 : 9) * s) put(x, y, [0, 0, 0]);
    word(flat, Math.min(N - 5 * s, hz + 3), s, col);
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
    else if (face === "rings" || face === "dial") { /* these show seconds in their own way */ }
    else { const e = N - 1, k = Math.round(sec / 60 * 4 * e + e / 2) % (4 * e), side = Math.floor(k / e), r = k % e;   // along the outer edge, from top centre
      put(side === 0 ? r : side === 1 ? e : side === 2 ? e - r : 0, side === 0 ? 0 : side === 1 ? r : side === 2 ? e : e - r, col); }
  }
  return p;
}
var ART = [
  ["ripple", "Ripple", (x, y, t, g) => g.r > 1.05 ? 0 : Math.max(0, (Math.sin(g.r * 11 - TAU * t) - 0.55) / 0.45) * (1 - g.r * 0.55)],
  ["breathe", "Breathe", (x, y, t, g) => Math.max(near((g.r - (0.3 + 0.32 * (0.5 - 0.5 * Math.cos(TAU * t)))) * g.h, 1.1), g.r * g.h < 1 ? 1 : 0)],
  ["orbits", "Orbits", (x, y, t, g) => { let v = 0; for (let k = 0; k < 4; k++) { const R = (0.24 + k * 0.2) * g.h, a = TAU * (t * (4 - k) + k * 0.23); v = Math.max(v, near(Math.hypot(x - g.c - Math.sin(a) * R, y - g.c + Math.cos(a) * R), 1.4), near(g.r * g.h - R, 0.6) * 0.1); } return v; }],
  ["spiral", "Spiral", (x, y, t, g) => g.r > 1 ? 0 : Math.max(0, (Math.sin(g.a * 2 + g.r * 9 - TAU * t) - 0.72) / 0.28) * (0.35 + 0.65 * g.r)],
  ["waves", "Waves", (x, y, t, g) => { let v = 0; for (let k = 0; k < 3; k++) v = Math.max(v, near(y - (g.c + (k - 1) * g.h * 0.42 + Math.sin(x / g.n * TAU * 1.5 + TAU * t + k * 1.3) * g.h * 0.16), 1) * [0.35, 1, 0.6][k]); return v; }],
  ["rain", "Rain", (x, y, t, g) => { if (rnd1(x) > 0.55) return 0; const sp = 1 + Math.floor(rnd1(x + 50) * 2), head = ((t * sp + rnd1(x + 9)) % 1) * (g.n + 9) - 2, d = head - y; return d >= 0 && d < 7 ? 1 - d / 7 : 0; }],
  ["lattice", "Lattice", (x, y, t, g) => (x % g.p !== g.o || y % g.p !== g.o) ? 0 : 0.1 + 0.9 * Math.pow(Math.max(0, Math.sin(TAU * (t - (x + y) / (2 * g.n)))), 2)],
  ["contours", "Contours", (x, y, t, g) => { const v = Math.sin(g.u * 3 + TAU * t) + Math.sin(g.v * 4 - TAU * t) + Math.sin((g.u + g.v) * 3 + TAU * 2 * t); return Math.abs(v - 0.9) < 0.22 ? 1 : Math.abs(v + 0.6) < 0.16 ? 0.3 : 0; }],
  ["scan", "Scan", (x, y, t, g) => { const xl = g.c + g.h * 0.86 * Math.sin(TAU * t), d = (x - xl) * Math.sign(Math.cos(TAU * t)); return Math.max(near(x - xl, 0.8), d < 0 && d > -6 ? (1 + d / 6) * 0.35 : 0, (x % g.p === g.o && y % g.p === g.o) ? 0.12 : 0); }],
  ["stars", "Stars", (x, y, t, g) => { const k = rnd1(x * 57 + y * 131); return k > 0.045 ? 0 : Math.pow(0.5 + 0.5 * Math.sin(TAU * (t * (1 + Math.floor(rnd1(k * 999) * 2)) + rnd1(x + y * 7))), 3); }],
  ["blobs", "Blobs", (x, y, t, g) => { let f = 0; for (let k = 0; k < 3; k++) { const bx = Math.sin(TAU * (t * (k + 1) + k * 0.31)) * 0.5, by = Math.cos(TAU * (t * (3 - k) + k * 0.17)) * 0.5; f += 0.07 / ((g.u - bx) ** 2 + (g.v - by) ** 2 + 0.002); } return f > 1 ? 1 : f > 0.72 ? 0.28 : 0; }],
  ["levels", "Levels", (x, y, t, g) => { const w = Math.max(2, g.n >> 3), i = Math.floor(x / w); if (x % w === w - 1 || i > 7) return 0; const top = g.n - 2 - Math.round((0.12 + 0.76 * (0.5 + 0.5 * Math.sin(TAU * (t * (1 + i % 3) + rnd1(i))))) * (g.n - 4)); return y > g.n - 2 ? 0 : y === top ? 1 : y > top ? 0.3 : 0; }],
  ["pulse", "Pulse", (x, y, t, g) => { const s = ((x / g.n + t) % 1 + 1) % 1, k = s < 0.42 ? 0 : s < 0.47 ? (s - 0.42) / 0.05 * -0.25 : s < 0.52 ? -0.25 + (s - 0.47) / 0.05 * 1.05 : s < 0.58 ? 0.8 - (s - 0.52) / 0.06 * 1.15 : s < 0.63 ? -0.35 + (s - 0.58) / 0.05 * 0.35 : 0; return near(y - (g.c + g.h * 0.2 - k * g.h * 0.75), 1) * (0.35 + 0.65 * x / g.n); }],
  ["tunnel", "Tunnel", (x, y, t, g) => { const d = Math.max(Math.abs(g.u), Math.abs(g.v)); return d > 1 ? 0 : Math.max(0, (Math.sin(d * 10 - TAU * t) - 0.7) / 0.3) * (0.25 + 0.75 * d); }],
  ["radar", "Radar", (x, y, t, g) => { if (g.r > 1) return 0; const lag = frac((TAU * t - Math.atan2(g.u, -g.v)) / TAU) * TAU; return Math.max(lag < 0.14 ? 1 : 0, lag < 1.7 ? (1 - lag / 1.7) * 0.42 : 0, near((g.r - 0.97) * g.h, 0.7) * 0.22, rnd1(x * 13 + y * 71) < 0.012 ? Math.pow(Math.max(0, 1 - lag / 3), 2) : 0); }],
  ["interfere", "Interfere", (x, y, t, g) => { const v = Math.sin(Math.hypot(g.u + 0.5, g.v) * 12 - TAU * t) + Math.sin(Math.hypot(g.u - 0.5, g.v) * 12 - TAU * t); return v > 1.3 ? 1 : v > 0.75 ? 0.28 : 0; }],
  ["helix", "Helix", (x, y, t, g) => { const ph = y / g.n * TAU * 1.25 + TAU * t, s = Math.sin(ph) * g.h * 0.5, dp = Math.cos(ph); return Math.max(near(x - g.c - s, 1) * (0.55 + 0.45 * dp), near(x - g.c + s, 1) * (0.55 - 0.45 * dp), y % 4 === 1 && Math.abs(x - g.c) < Math.abs(s) - 1 ? 0.13 : 0); }],
  ["bounce", "Bounce", (x, y, t, g) => { let v = y === g.n - 1 ? 0.14 : 0; for (let k = 0; k < 5; k++) v = Math.max(v, near(Math.hypot(x - (k + 0.5) * g.n / 5, y - (g.n - 3 - Math.abs(Math.sin(Math.PI * (t * (1 + k % 2) + k * 0.19))) * (g.n - 6) * (0.55 + 0.09 * k))), 1.5)); return v; }],
  ["trace", "Trace", (x, y, t, g) => { let v = 0; for (let k = 0; k < 26; k++) { const q = t - k * 0.006; v = Math.max(v, near(Math.hypot(g.u - Math.sin(TAU * 2 * q) * 0.8, g.v - Math.sin(TAU * 3 * q + 0.5) * 0.8) * g.h, 1.2) * (1 - k / 26)); } return v; }],
  ["diamonds", "Diamonds", (x, y, t, g) => { const d = Math.abs(g.u) + Math.abs(g.v); return Math.max(0, (Math.sin(d * 8 - TAU * t) - 0.68) / 0.32) * (1 - d * 0.35); }],
  ["horizon", "Horizon", (x, y, t, g) => { if (g.v < 0.06) { const rr = Math.hypot(g.u, g.v + 0.12); return rr < 0.42 && g.v < 0.02 ? (y % 2 ? 0.75 : 0.12) : 0; } if (g.v < 0.11) return 0.55; const z = 0.3 / g.v, fade = Math.min(1, g.v * 1.9); return Math.max(frac(z * 1.4 + t) < 0.16 ? 1 : 0, Math.abs(frac(g.u * z * 1.6 + 0.5) - 0.5) < 0.07 * z ? 0.7 : 0) * fade; }],
  ["petals", "Petals", (x, y, t, g) => g.r > 1.05 ? 0 : Math.max(near((g.r - 0.9 * Math.abs(Math.cos(2 * g.a + TAU * t))) * g.h, 1.1), g.r * g.h < 1.2 ? 1 : 0)],
  ["eclipse", "Eclipse", (x, y, t, g) => g.r >= 0.64 ? near((g.r - 0.66) * g.h, 0.8) * 0.3 : Math.hypot(g.u + 1.6 - 3.2 * t, g.v) > 0.64 ? 1 : 0.05],
  ["pendulum", "Pendulum", (x, y, t, g) => { const an = 0.72 * Math.sin(TAU * t), px = g.c, py = 2, L = g.n * 0.74, bx = px + Math.sin(an) * L, by = py + Math.cos(an) * L, k = Math.max(0, Math.min(1, ((x - px) * (bx - px) + (y - py) * (by - py)) / (L * L))); return Math.max(near(Math.hypot(x - bx, y - by), Math.max(1.6, g.n / 14)), near(Math.hypot(x - px - k * (bx - px), y - py - k * (by - py)), 0.7) * 0.3, y === 1 && Math.abs(x - g.c) < g.h * 0.3 ? 0.2 : 0); }],
  ["loader", "Loader", (x, y, t, g) => { let v = 0; for (let k = 0; k < 10; k++) { const a = k * TAU / 10; v = Math.max(v, near(Math.hypot(g.u - Math.sin(a) * 0.62, g.v + Math.cos(a) * 0.62) * g.h, Math.max(1.2, g.n / 22)) * (0.1 + 0.9 * Math.pow(1 - frac(t - k / 10), 3))); } return v; }],
  ["heart", "Heart", (x, y, t, g) => { const beat = Math.pow(Math.max(0, Math.sin(TAU * t)), 10) + 0.6 * Math.pow(Math.max(0, Math.sin(TAU * (t - 0.17))), 10), s = 0.5 * (1 + 0.16 * beat), X = g.u / s, Y = -(g.v - 0.06) / s, f = Math.pow(X * X + Y * Y - 1, 3) - X * X * Y * Y * Y; return f < 0 ? 1 : f < 0.35 ? 0.16 * beat : 0; }],
  ["weave", "Weave", (x, y, t, g) => { const v = Math.sin(g.u * 7 + TAU * t) * Math.sin(g.v * 7 - TAU * t); return v > 0.55 ? 1 : v < -0.6 ? 0.22 : 0; }],
  ["snow", "Snow", (x, y, t, g) => { let v = 0; for (let k = 0; k < 22; k++) { const sp = 1 + (k % 2), fy = frac(t * sp + rnd1(k + 3)) * (g.n + 2) - 1, fx = rnd1(k) * g.n + Math.sin(TAU * (t * sp + rnd1(k + 5))) * 1.4; v = Math.max(v, near(Math.hypot(x - fx, y - fy), 0.95) * (0.45 + 0.55 * rnd1(k + 7))); } return v; }],
];
var ART_NAMES = {}, ART_FRAMES = 48; ART.forEach(function (a) { ART_NAMES[a[0]] = a[1]; });
function artFrame(id, t, col) {
  const fn = ART.find(a => a[0] === id)[2], p = new Uint8ClampedArray(N * N * 4), c = (N - 1) / 2, hN = N / 2, pitch = N >= 32 ? 4 : 3;
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
// the display's own clock (it draws this one itself; this is only its picture here): the time, and the date under it
function classicFrame(d, o) {
  var p = blank(), w = pen(p), h = d.getHours(); if (!o.h24) h = h % 12 || 12;
  var two = function (v) { return (v < 10 ? "0" : "") + v; };
  w.word(two(h) + ":" + two(d.getMinutes()), o.secs ? 8 : 13, 1, o.col);
  if (o.secs) w.word(two(d.getDate()) + ":" + two(d.getMonth() + 1), 19, 1, shade(o.col, 0.5));
  return p;
}
