#version 440
// The redesign's background, "Field" (room-motion.html): the screen takes its colour from the album cover.
// A base fill, then four soft lights — one per main colour of the cover, where that colour sits on the cover, as big
// as its share — drifting along the cover's light direction; film grain over them (13 %, overlay); then a dimmer.
// The room's sound swells the lights (≤ 10 %) and brightens them (≤ 16 %); a sudden jump sends a soft wave of light
// out from the first one. Inside the glass card the grain is gone and the colours a little richer (the card's
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

vec3 light(vec3 under, vec2 p, int i, vec4 b, vec4 c) {
    if (b.w <= 0.0 || b.z <= 0.0) return under;
    float fi = float(i);
    float a = ph * TAU + fi * 1.7;
    float s = sin(a), k = cos(a * 0.7 + fi);
    vec2 d = vec2(dir.x * s * amp - dir.y * k * amp * 0.35, dir.y * s * amp + dir.x * k * amp * 0.35);
    float r = b.z * 0.5 * (1.0 + 0.1 * sound);
    float f = 1.0 - length(p - (b.xy + d)) / r;          // closest-side radial: full at the centre, nothing at the edge
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
    // the wave: a soft brightening that spreads out from the first light (screen blend), gone in 3.4 s
    if (waveT < 3.4 && waveS > 0.0) {
        float u = waveT / 3.4;
        float e = 1.0 - pow(1.0 - u, 3.0);
        float R = 10.0 + 1090.0 * e;
        float sg = 1.8 * R;
        float a = 0.22 * waveS * 0.25 * (1.0 - smoothstep(0.0, 1.0, u)) * exp(-dot(p - b0.xy, p - b0.xy) / (2.0 * sg * sg));
        col = 1.0 - (1.0 - col) * (1.0 - c0.rgb * a);
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
