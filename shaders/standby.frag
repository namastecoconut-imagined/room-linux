#version 440
// Standby, as on the iPhone panel (StandbyView): a field of soft dots that breathes slowly over four drifting,
// breathing blobs of coloured light. The dots fade down around the words. A sound sends a ripple out from the right
// of the clock. Positions are worked out in the phone's own 568 × 320 points and drawn at the Surface's size.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float bt;        // breathing time (s, already slowed at night)
    float gt;        // glow time (s since the glow started)
    float period;    // glow loop length (80 s by day, ×1.25 evening, ×2 night)
    float gday;      // 1 by day: the blobs breathe a little quicker
    float boost;     // 1.5 by day, 1 otherwise (how bright the dots get)
    float gstr;      // blob strength (0.42 day, 0.34 otherwise)
    float glowV;     // a voice swell 0…1 (the glow grows ≤10%, brightens)
    float frozen;    // 1: no breathing (hot)
    vec2 res;        // size in pixels
    vec4 dotCol;     // the field's colour
    vec4 c0; vec4 c1; vec4 c2; vec4 c3;
    vec4 r0; vec4 r1; vec4 r2; vec4 r3; vec4 r4; vec4 r5;   // where the words are (phone points: x, y, w, h)
    vec4 rip0; vec4 rip1; vec4 rip2; vec4 rip3;                // ripples: x = start (glow time), y = strength
};

const float W = 568.0;
const float GAP = 20.0;
// the Surface is taller than the phone (3:2 vs 16:9): same 568-pt width, more height, same point size
float H = 568.0 * 912.0 / 1368.0;
const float PI = 3.14159265;

float nearWords(vec2 p, vec4 r) {
    if (r.z <= 0.0) return 1.0;
    float dx = max(max(r.x - p.x, 0.0), p.x - (r.x + r.z));
    float dy = max(max(r.y - p.y, 0.0), p.y - (r.y + r.w));
    float f = min(1.0, length(vec2(dx, dy)) / 22.0);
    return f * f * (3.0 - 2.0 * f);
}

float ripple(vec4 rp, vec2 pt, float keep) {
    if (rp.y <= 0.0) return 0.0;
    float dist = length(pt - vec2(W * 0.74, H * 0.5));
    float age = dist / 260.0, fade = 1.0 - age / 3.2;
    if (fade <= 0.0) return 0.0;
    float peak = min(0.6, rp.y * fade * 0.75 * keep);
    float local = gt - rp.x - age;
    if (local < 0.0 || local > 0.32) return 0.0;
    return peak * sin(PI * local / 0.32);
}

vec3 blob(vec2 p, int i, vec3 col, float a, float e) {
    vec3 f = i == 0 ? vec3(3.0, 4.0, 0.0) : i == 1 ? vec3(4.0, 2.0, 2.0) : i == 2 ? vec3(2.0, 3.0, 4.0) : vec3(2.0, 4.0, 5.5);
    vec2 c = vec2(W / 2.0 + 230.0 * sin(f.x * a + f.z), H / 2.0 + 110.0 * cos(f.y * a + f.z * 1.3));
    float d = (gday > 0.5 ? 4.0 : 5.5) + float(i) * 1.1;
    float u = mod(e, 2.0 * d) / d;
    float tri = u < 1.0 ? u : 2.0 - u;
    float sc = (0.72 + 0.33 * (0.5 - 0.5 * cos(PI * tri))) * (1.0 + 0.1 * glowV);
    float x = length(p - c) / (380.0 * sc);     // 760-pt-wide radial gradient
    // stops: 0 → 0.9, 0.2 → 0.62, 0.45 → 0.3, 0.72 → 0.09, 1 → 0
    float k = x < 0.2 ? mix(0.9, 0.62, x / 0.2) : x < 0.45 ? mix(0.62, 0.3, (x - 0.2) / 0.25)
            : x < 0.72 ? mix(0.3, 0.09, (x - 0.45) / 0.27) : x < 1.0 ? mix(0.09, 0.0, (x - 0.72) / 0.28) : 0.0;
    return col * k * gstr;
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * W, qt_TexCoord0.y * H);       // phone points
    float a = 2.0 * PI * mod(gt, period) / period;
    // the glow: four blobs layered ("over"), so overlapping light adds but never blows out
    vec3 g = vec3(0.0);
    vec3 b0 = blob(p, 0, c0.rgb, a, gt), b1 = blob(p, 1, c1.rgb, a, gt), b2 = blob(p, 2, c2.rgb, a, gt), b3 = blob(p, 3, c3.rgb, a, gt);
    g = b0; g = b1 + g * (1.0 - max(b1.r, max(b1.g, b1.b))); g = b2 + g * (1.0 - max(b2.r, max(b2.g, b2.b))); g = b3 + g * (1.0 - max(b3.r, max(b3.g, b3.b)));
    g *= 0.86 + 0.14 * glowV;

    // the dots: a grid 20 pt apart, centred on the screen
    vec2 cols = floor(vec2(W - 12.0, H - 12.0) / GAP);
    vec2 o = (vec2(W, H) - cols * GAP) / 2.0;
    vec2 id = floor((p - o) / GAP + 0.5);
    vec2 pt = o + id * GAP;
    float keep = 0.1 + 0.9 * min(min(min(nearWords(pt, r0), nearWords(pt, r1)), min(nearWords(pt, r2), nearWords(pt, r3))), min(nearWords(pt, r4), nearWords(pt, r5)));
    float i = floor(pt.x / GAP + 0.5), j = floor(pt.y / GAP + 0.5);
    float v = frozen > 0.5 ? 0.5 : 0.5 + 0.5 * sin(i * 0.42 + bt * 0.8) * cos(j * 0.5 - bt * 0.6);
    float al = (0.06 + 0.13 * v) * boost * keep;
    if (al < 0.02) al = 0.0;
    al = min(0.7, al);
    float rp = ripple(rip0, pt, keep) + ripple(rip1, pt, keep) + ripple(rip2, pt, keep) + ripple(rip3, pt, keep);
    float diam = (5.0 + al * 14.0) * 0.5 + rp * 9.0 * 0.5;
    float r = diam / 2.0;
    float d = length(p - pt) / max(r, 0.01);
    // a soft dot: full to 55% of its radius, then fading out
    float soft = d < 0.55 ? 1.0 : d < 1.0 ? mix(1.0, 0.0, (d - 0.55) / 0.45) : 0.0;
    float dotA = (al + rp) * soft;
    vec3 col = g * (1.0 - dotA) + dotCol.rgb * dotA;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
