#version 440
// The redesign's background, "Field" (room-motion.html): the screen takes its colour from the album cover.
// A base fill, then four soft lights — one per main colour of the cover, where that colour sits on the cover, as big
// as its share — drifting along the cover's light direction; film grain over them (13 %, overlay); then a dimmer.
// The room's sound swells the lights (≤ 10 %) and brightens them (≤ 16 %); a sudden jump (a clap, a beat) sends a
// soft wave of light out from the brightest one, across the screen. Inside the glass card the grain is gone and the colours a little richer (the card's
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
    float waveT;       // seconds since the last wave started (≥ 3.4: none)
    float waveS;       // its strength
    float glassR;      // the glass card's corner radius
    float waveI;       // which light the wave starts from (the brightest)
    float tm;          // the swirl's clock (seconds, quicker for a lively cover)
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

// Where light i is now. Two movements: the cover's own drift along its light direction (the design), and the old
// colour wash's swirl, brought back — the lights turn slowly round the middle of the screen (±22°, about a minute
// a turn) and each circles its own place (±16 % of the width, ±14 % of the height, 35–60 s a loop), so the colours
// keep moving across the screen the way the wash's did.
vec2 place(int i, vec4 b) {
    float fi = float(i);
    float a = ph * TAU + fi * 1.7;
    float s = sin(a), k = cos(a * 0.7 + fi);
    vec2 d = vec2(dir.x * s * amp - dir.y * k * amp * 0.35, dir.y * s * amp + dir.x * k * amp * 0.35);
    vec2 cc = vec2(684.0, 456.0);
    float ang = 0.384 * sin(tm / 9.0) * mv;                 // 22°
    vec2 q = b.xy - cc;
    q = vec2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
    vec2 o = vec2(219.0 * sin(tm / (6.0 + fi * 0.8) + fi * 1.3), 128.0 * cos(tm / (7.5 + fi * 0.6) + fi * 2.1)) * mv;
    return cc + q + d + o;
}
float breathe(int i) {                       // and each grows and shrinks a little (±12 %), as the wash's copies did
    float fi = float(i);
    return 1.0 + 0.12 * sin(tm / (5.0 + fi * 0.9) + fi * 1.1) * mv;
}

vec3 light(vec3 under, vec2 p, int i, vec4 b, vec4 c) {
    if (b.w <= 0.0 || b.z <= 0.0) return under;
    float r = b.z * 0.5 * breathe(i) * (1.0 + 0.1 * sound);
    float f = 1.0 - length(p - place(i, b)) / r;         // closest-side radial: full at the centre, nothing at the edge
    if (f <= 0.0) return under;
    vec3 col = min(c.rgb * (1.0 + 0.16 * sound), vec3(1.0));
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
    // the wave: a soft band of light that travels out from the brightest light across the whole screen and fades
    // (3.4 s) — a brightening, screen-blended, never a drawn ring
    if (waveT < 3.4 && waveS > 0.0) {
        int wi = int(waveI + 0.5);
        vec4 wb = wi == 0 ? b0 : wi == 1 ? b1 : wi == 2 ? b2 : b3;
        vec3 wcol = wi == 0 ? c0.rgb : wi == 1 ? c1.rgb : wi == 2 ? c2.rgb : c3.rgb;
        float u = waveT / 3.4;
        float e = 1.0 - pow(1.0 - u, 3.0);                   // fast out, slowing as it spreads
        float R = 40.0 + 1500.0 * e;                         // the front
        float w = 110.0 + 230.0 * e;                         // its softness
        float dd = length(p - place(wi, wb)) - R;
        float a = 0.36 * waveS * pow(1.0 - u, 1.4) * exp(-dd * dd / (2.0 * w * w));
        col = 1.0 - (1.0 - col) * (1.0 - mix(wcol, vec3(1.0), 0.45) * a);
    }
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
