// Aviral's bedroom (from his photos and his sketch, 23 Nov): seen from the doorway — the desk wall ahead, the bed against
// the window wall on the right, the carpet and the lounge chair at the far left, the bench by the way in.
// Five WiZ lamps; match: words in their names in config.json (lights.py), so each drawn lamp is tied to its bulb.
// Left and right are as you face the bed (the left one is by the wardrobe, on the desk side).
setup({ S: 0.72, OX: 1095, OY: 306, W: 620, D: 360, H: 290 });
const L = [
 {n:1, name:'Bedside left',  at:[20,80,78],    match:['bedside lamp left', 'bedside left', 'left']},
 {n:2, name:'Bedside right', at:[20,297,78],   match:['bedside lamp right', 'bedside right', 'right']},
 {n:3, name:'Desk lamp',     at:[452,36,118],  match:['desk', 'uplight']},
 {n:4, name:'Lounge chair',  at:[578,126,148], match:['lounge', 'chair', 'floor']},
 {n:5, name:'Bench lamp',    at:[304,348,112], match:['bench']},
];
// floor, the two real walls, the carpet
add(-100, () => {
  poly([[0,0,0],[W,0,0],[W,D,0],[0,D,0]], C.floor, INK, 1.5);
  for (let u = 24; u < W; u += 24) line([[u,0,0],[u,D,0]], 'rgba(241,233,223,.06)');
  poly([[0,0,0],[W,0,0],[W,0,H],[0,0,H]], C.wall, INK, 1.5);
  poly([[0,0,0],[0,D,0],[0,D,H],[0,0,H]], C.wall2, INK, 1.5);
  poly([[-12,-12,H],[W,-12,H],[W,0,H],[0,0,H],[0,D,H],[-12,D,H]], '#5a4335', INK, 1.2);
  line([[0,0,8],[W,0,8]], INK3); line([[0,0,8],[0,D,8]], INK3);
  // window, blinds, AC; tube light over the desk
  poly([[0,100,92],[0,274,92],[0,274,212],[0,100,212]], '#2f3436', INK, 1.3);
  for (let z = 100; z < 208; z += 10) line([[0,102,z],[0,272,z]], 'rgba(241,233,223,.4)', 1);
  line([[0,187,92],[0,187,212]], INK2);
  line([[310,0,236],[420,0,236]], INK2, 2.5);
  // the carpet
  poly([[248,113,0],[W - 4,113,0],[W - 4,309,0],[248,309,0]], '#4a3a26', INK2, 1.1);
  poly([[260,125,0],[W - 16,125,0],[W - 16,297,0],[260,297,0]], 'none', INK3, .9);
  for (let i = 0; i < 6; i++) for (let j = 0; j < 3; j++) { const [a, b] = P(285 + i * 56, 160 + j * 56, 0);
    out += `<path d="M${a - 8},${b} L${a},${b - 4.5} L${a + 8},${b} L${a},${b + 4.5} Z" fill="none" stroke="${INK3}" stroke-width=".9"/>`; }
});
// AC (on the window wall, high)
add(5, () => box(0, 146, 224, 16, 228, 250, C.wood, C.woodTop));
// the wardrobe, floor to ceiling
add(40, () => { box(0, 0, 0, 60, 54, H - 2, '#4a3a30', '#56443a'); line([[60,27,10],[60,27,H - 10]], INK3); line([[60,0,206],[60,54,206]], INK3); });
// the bedside tables and their cane lamps
function table(u, y) { box(0, y, 0, 38, y + 46, 52, C.wood, C.woodTop); line([[0,y + 46,26],[38,y + 46,26]], INK3); }
function caneLamp(l, u, y) { cyl(u, y, 52, 62, 4.5, C.glass, C.glass);
  const [x, ya, yb, rx, ry] = cyl(u, y, 62, 90, 12, lit(l) ? SHADE : '#6a4a32', lit(l) ? SHADE : '#7a5a40');
  for (let i = -3; i <= 3; i++) out += `<line x1="${x + i * rx / 4}" y1="${yb + ry * Math.sqrt(1 - (i / 4) ** 2)}" x2="${x + i * rx / 4}" y2="${ya + ry * Math.sqrt(1 - (i / 4) ** 2)}" stroke="rgba(60,35,20,.5)" stroke-width="1"/>`; }
add(70, () => { table(0, 57); caneLamp(L[0], 20, 80); });
// the palm
add(230, () => { cyl(200, 30, 0, 40, 18, '#d9d2c8', '#e8e2da', INK);
  for (let i = 0; i < 11; i++) { const a = i / 11 * Math.PI * 2, r = 44 + (i % 3) * 6;
    line([[200,30,40],[200 + Math.cos(a) * r * .45,30 + Math.sin(a) * r * .45,120],[200 + Math.cos(a) * r,30 + Math.sin(a) * r,145 + (i % 3) * 12]], '#9fb889', 1.4); } });
// the bed
add(280, () => {
  box(0, 106, 0, 8, 270, 98, C.wood, C.woodTop);
  for (let y = 118; y < 270; y += 12) line([[8,y,52],[8,y,90]], 'rgba(241,233,223,.2)');
  box(8, 106, 0, 206, 270, 34, C.wood, C.woodTop);
  box(10, 110, 34, 202, 266, 48, C.linen, C.linenTop);
  for (let u = 70; u < 202; u += 12) line([[u,110,48],[u,266,48]], 'rgba(241,233,223,.12)');
  box(16, 120, 48, 40, 184, 62, '#8a7a6c', '#988878'); box(16, 192, 48, 40, 256, 62, '#8a7a6c', '#988878');
});
add(330, () => { table(0, 274); caneLamp(L[1], 20, 297); });
// the desk: legs, top, monitor, the chair, the clamp lamp at its far end
add(380, () => {
  [[256,8],[458,8],[256,60],[458,60]].forEach(([u, y]) => line([[u,y,0],[u,y,72]], INK, 2));
  box(248, 0, 72, 466, 68, 77, C.wood, C.woodTop);
  line([[356,12,77],[356,12,96]], INK2, 2);
  poly([[310,12,96],[402,12,96],[402,12,134],[310,12,134]], C.dark, INK, 1.3);
  const l = L[2]; line([[460,10,77],[460,10,104],[454,22,120]], INK, 1.6);
  const [a, b] = P(452, 36, 118);
  out += `<path d="M${a + 8},${b - 10} L${a - 9},${b - 6} L${a - 7},${b + 9} L${a + 9},${b + 6} Z" fill="${lit(l) ? SHADE : '#b8b0a6'}" stroke="${INK}" stroke-width="1.2"/>`;
});
add(460, () => { line([[357,103,0],[357,103,44]], INK, 2); box(334, 82, 44, 380, 124, 50, C.dark, '#2a211c');
  poly([[334,124,50],[380,124,50],[380,124,104],[334,124,104]], C.dark, INK, 1.2); });
// the fig
add(530, () => { cyl(500, 30, 0, 38, 17, '#d9d2c8', '#e8e2da'); line([[500,30,38],[500,30,150]], INK2, 1.3);
  [[510,30,150,-30],[490,28,140,200],[508,34,124,-20],[490,32,110,190],[506,26,96,-40],[494,30,82,210],[504,32,68,-10]].forEach(([u,y,z,a], i) => leafAt(u, y, z, a, 1, i % 2 ? C.leaf : C.leaf2)); });
// the shelf cart in the corner
add(626, () => { [[574,12],[614,12],[574,58],[614,58]].forEach(([u, y]) => line([[u,y,0],[u,y,96]], INK, 1.4));
  [0, 32, 64, 96].forEach(z => poly([[574,12,z],[614,12,z],[614,58,z],[574,58,z]], 'rgba(160,170,170,.18)', INK2, 1)); });
// the floor lamp, in front of the shelf
add(736, () => { const l = L[3];
  const [x0, y0] = P(596, 140, 0); out += `<ellipse cx="${x0}" cy="${y0}" rx="12" ry="6" fill="${C.dark}" stroke="${INK}" stroke-width="1.2"/>`;
  line([[596,140,0],[596,140,152],[592,132,166],[584,128,162]], INK, 2);
  const [a, b] = P(578, 126, 148);
  out += `<path d="M${a - 14},${b - 16} L${a + 6},${b - 18} L${a + 16},${b + 8} L${a - 8},${b + 12} Z" fill="${C.dark}" stroke="${INK}" stroke-width="1.3"/>`;
  out += `<ellipse cx="${a + 4}" cy="${b + 10}" rx="12" ry="4.5" fill="${lit(l) ? SHADE : '#5a4a3e'}"/>`; });
// the ottoman (in front of the lounge chair)
add(690, () => { [[452,208],[486,208],[452,246],[486,246]].forEach(([u, y]) => line([[u,y,0],[u,y,14]], INK, 2));
  box(448, 204, 14, 490, 250, 40, '#7a6448', '#8a7254'); });
// the lounge chair: by the far wall at the carpet's end, facing the bed (bentwood frame, a cushion)
add(800, () => {
  const side = y => { line([[604,y,2],[530,y,2],[520,y,8],[522,y,18],[540,y,34],[586,y,48],[592,y,54]], '#e2c9a0', 2.4);
    line([[520,y,8],[528,y,52],[582,y,56]], '#e2c9a0', 2.2); };
  side(186);
  poly([[530,188,42],[530,262,42],[580,262,28],[580,188,28]], C.cushion, INK, 1.2);
  poly([[580,188,28],[580,262,28],[606,262,110],[606,188,110]], C.cushion, INK, 1.2);
  line([[586,190,40],[586,260,40]], INK3); line([[594,190,70],[594,260,70]], INK3);
  side(264);
});
// the bench wall (cut away): the bench with the brass lamp, the monstera
add(705, () => { box(289, 336, 0, 426, 360, 42, C.wood, C.woodTop);
  for (let u = 300; u < 426; u += 12) line([[u,336,42],[u,360,42]], 'rgba(30,18,10,.5)');
  const l = L[4];
  line([[304,348,42],[304,348,94]], '#e6c07a', 2.2);
  const [x, y] = P(304, 348, 42); out += `<ellipse cx="${x}" cy="${y}" rx="7" ry="3.5" fill="#c9a060" stroke="#e6c07a" stroke-width="1"/>`;
  cyl(304, 348, 94, 130, 11, lit(l) ? SHADE : '#cfc3b0', lit(l) ? SHADE : '#ddd2c0'); });
add(792, () => { cyl(452, 340, 0, 36, 16, '#d9d2c8', '#e8e2da'); line([[452,340,36],[452,340,128]], INK2, 1.3);
  [[466,330,60,-40],[438,344,78,200],[466,350,98,-20],[436,334,116,210],[460,342,132,-60],[444,348,92,170]].forEach(([u,y,z,a], i) => leafAt(u, y, z, a, 1.25, i % 2 ? C.leaf : C.leaf2)); });
// the two cut-away walls as ghosts, and what hangs on them: the picture and the wall light (far wall), the cat
// painting, the mirror, the cupboard and the way in (bench wall)
add(2000, () => {
  const G = 'rgba(241,233,223,.32)', g = (a) => poly(a, 'none', G, 1);
  out += `<g stroke-dasharray="5 6">`;
  g([[W,0,0],[W,D,0],[W,D,H],[W,0,H]]); g([[0,D,0],[W,D,0],[W,D,H],[0,D,H]]);
  g([[W - 2,72,0],[W - 2,150,0],[W - 12,150,150],[W - 12,72,150]]);
  g([[260,D,150],[440,D,150],[440,D,212],[260,D,212]]);
  g([[486,D - 4,0],[514,D - 4,0],[514,D - 8,170],[486,D - 8,170]]);
  g([[48,D,0],[120,D,0],[120,D,230],[48,D,230]]); g([[48,300,230],[120,300,230],[120,D,230],[48,D,230]]); g([[120,300,0],[120,D,0],[120,D,230],[120,300,230]]);
  g([[520,D,0],[W - 4,D,0],[W - 4,D,205],[520,D,205]]);
  out += `</g>`;
  line([[W,250,198],[W - 8,250,202]], G, 1.6);
});
