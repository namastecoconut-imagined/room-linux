#version 440
// The redesign's background, "Field" (room-motion.html): the screen takes its colour from the album cover.
// A base fill, then four soft lights — one per main colour of the cover, where that colour sits on the cover, as big
// as its share — drifting along the cover's light direction; film grain over them (13 %, overlay); then a dimmer.
// While music plays, the room's sound swells the lights (≤ 10 %) and brightens them (≤ 16 %). Inside the glass card the grain is gone and the colours a little richer (the card's
// frosted glass blurs what's behind it). Everything is worked out in stage pixels (the 1368 × 912 stage).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float ph;          // drift phase (cycles; advances by 1 every `period` seconds)
    float amp;         // how far the lights drift (stage px)
    float sound;       // the room's sound, 0…1
    float dimA;        // the dimmer (0…1)
    float grainA;      // the grain's strength (0.13)
    float glassR;      // the glass card's corner radius
    float pop;         // how far brighter lights are pushed from the base (1: as the cover has them)
    float rotP;        // the swirl's phases (radians, each kept within one turn, so they never jump): the turn
    vec4 orbX; vec4 orbY;   // each light's circling, across and up and down
    vec4 brP;          // each light's growing and shrinking
    float mv;          // how much the lights swirl (1; a room's light: calmer)
    vec2 size;         // this item's size (stage px)
    vec2 origin;       // where its top left sits on the stage
    vec2 dir;          // the cover's light direction
    vec4 base;         // the base fill
    vec4 dimC;         // the dimmer's colour
    vec4 c0; vec4 c1; vec4 c2; vec4 c3;    // the lights' colours
    vec4 b0; vec4 b1; vec4 b2; vec4 b3;    // the lights: x, y (centre, stage px), diameter, opacity
    vec4 glass;        // the glass card: x, y, w, h (stage px; w = 0: none)
};

const float TAU = 6.28318531;

float hash(vec2 p) {                        // a fixed random grey per stage pixel (the grain doesn't move)
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

vec3 over(vec3 under, vec3 col, float a) { return mix(under, col, clamp(a, 0.0, 1.0)); }

// Where light i is now. Two movements: the cover's own drift along its light direction (the design), and, while
// music plays, a swirl with the old music standby's liveliness — the lights turn slowly round the middle of the
// screen and each circles its own place (35–60 s a loop). Full swing (mv = 1): ±22°, ±16 % of the width, ±14 % of
// the height; Field sets how much.
vec2 place(int i, vec4 b) {
    float fi = float(i);
    float a = ph * TAU + fi * 1.7;
    float s = sin(a), k = cos(a * 0.7 + fi);
    vec2 d = vec2(dir.x * s * amp - dir.y * k * amp * 0.35, dir.y * s * amp + dir.x * k * amp * 0.35);
    vec2 cc = vec2(684.0, 456.0);
    float ang = 0.384 * sin(rotP) * mv;                     // 22°
    vec2 q = b.xy - cc;
    q = vec2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
    vec2 o = vec2(219.0 * sin(orbX[i] + fi * 1.3), 128.0 * cos(orbY[i] + fi * 2.1)) * mv;
    return cc + q + d + o;
}
float breathe(int i) {                       // and each grows and shrinks a little (±12 %), as the wash's copies did
    float fi = float(i);
    return 1.0 + 0.12 * sin(brP[i] + fi * 1.1) * mv;
}

vec3 light(vec3 under, vec2 p, int i, vec4 b, vec4 c) {
    if (b.w <= 0.0 || b.z <= 0.0) return under;
    float r = b.z * 0.5 * 1.12 * breathe(i) * (1.0 + 0.1 * sound);
    float f = 1.0 - length(p - place(i, b)) / r;         // full at the centre, nothing at the edge…
    if (f <= 0.0) return under;
    f = f * f * (3.0 - 2.0 * f);                         // …eased at both ends: no visible rim, no bright point
                                                         // (a straight fade showed its edge once the lights had contrast)
    // lights are pushed away from the base so they read as they move (a cover whose colours sit close together
    // otherwise gives one flat wash). A brighter light is pushed fully (it glows); a darker one only a little, never
    // below 60 % of its own colour, and never more than 0.35 darker than the base — a light cover's small dark patch
    // otherwise became a black stain wandering over it
    vec3 dv = c.rgb - base.rgb;
    float lb = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 col;
    if (dot(c.rgb, vec3(0.2126, 0.7152, 0.0722)) >= lb) {
        col = clamp(base.rgb + dv * pop, 0.0, 1.0);
    } else {
        col = max(clamp(base.rgb + dv * (1.0 + (pop - 1.0) * 0.4), 0.0, 1.0), c.rgb * 0.6);
        float lo = lb - 0.35, l = dot(col, vec3(0.2126, 0.7152, 0.0722));
        if (l < lo) col = mix(col, base.rgb, (lo - l) / max(0.001, lb - l));
    }
    col = min(col * (1.0 + 0.16 * sound), vec3(1.0));
    return over(under, col, f * b.w);
}

float roundBox(vec2 p, vec4 r, float rad) {
    vec2 h = r.zw * 0.5, q = abs(p - (r.xy + h)) - h + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

void main() {
    vec2 p = origin + qt_TexCoord0 * size;
    vec3 col = base.rgb;
    col = light(col, p, 0, b0, c0);
    col = light(col, p, 1, b1, c1);
    col = light(col, p, 2, b2, c2);
    col = light(col, p, 3, b3, c3);
    // inside the glass card: no grain, a little more colour (its frosted glass blurs and saturates what's behind)
    float inGlass = 0.0;
    if (glass.z > 0.0) {
        inGlass = 1.0 - smoothstep(-0.5, 0.5, roundBox(p, glass, glassR));
        float g = dot(col, vec3(0.2126, 0.7152, 0.0722));
        col = mix(col, clamp(mix(vec3(g), col, 1.3), 0.0, 1.0), inGlass);
    }
    // film grain, overlay-blended
    float n = hash(floor(p) + 17.0);
    vec3 ov = mix(2.0 * col * n, 1.0 - 2.0 * (1.0 - col) * (1.0 - n), step(0.5, col));
    col = mix(col, ov, grainA * (1.0 - inGlass));
    // the dimmer
    col = mix(col, dimC.rgb, dimA);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
