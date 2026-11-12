#version 440
// The redesign's background, "Field" (room-motion.html): the screen takes its colour from the album cover.
// A base fill, then four soft lights — one per main colour of the cover, where that colour sits on the cover, as big
// as its share — drifting along the cover's light direction; film grain over them (13 %, overlay); then a dimmer and
// the vignette.
// While music plays, the room's sound swells the lights (≤ 10 %) and brightens them (≤ 16 %). Inside the glass card the grain is gone and the colours a little richer (the card's
// frosted glass blurs what's behind it). Everything is worked out in stage pixels (the 1368 × 912 stage).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float dimA;        // the dimmer (0…1)
    float grainA;      // the grain's strength (0.13)
    float glassR;      // the glass card's corner radius
    float glassA;      // how much of the card there is (it fades in and out with it)
    vec2 size;         // this item's size (stage px)
    vec2 origin;       // where its top left sits on the stage
    vec4 base;         // the base fill
    vec4 dimC;         // the dimmer's colour
    // the four lights as they are this step — worked out once per step in Field.qml (where each has drifted and
    // swirled to, how big it is, its colour pushed from the base, the sound's swell), not again for every pixel:
    vec4 l0; vec4 l1; vec4 l2; vec4 l3;    // x, y (centre, stage px), radius, strength
    vec4 k0; vec4 k1; vec4 k2; vec4 k3;    // colours
    vec4 glass;        // the glass card: x, y, w, h (stage px; w = 0: none)
};

float hash(vec2 p) {                        // a fixed random grey per stage pixel (the grain doesn't move)
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

// a light: full at its centre, nothing at its edge, eased at both ends (no visible rim, no bright point)
vec3 light(vec3 under, vec2 p, vec4 L, vec4 K) {
    if (L.w <= 0.0 || L.z <= 0.0) return under;
    float f = 1.0 - length(p - L.xy) / L.z;
    if (f <= 0.0) return under;
    f = f * f * (3.0 - 2.0 * f);
    return mix(under, K.rgb, clamp(f * L.w, 0.0, 1.0));
}

float roundBox(vec2 p, vec4 r, float rad) {
    vec2 h = r.zw * 0.5, q = abs(p - (r.xy + h)) - h + rad;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

void main() {
    vec2 p = origin + qt_TexCoord0 * size;
    vec3 col = base.rgb;
    col = light(col, p, l0, k0);
    col = light(col, p, l1, k1);
    col = light(col, p, l2, k2);
    col = light(col, p, l3, k3);
    // inside the glass card: no grain, a little more colour (its frosted glass blurs and saturates what's behind)
    float inGlass = 0.0;
    if (glass.z > 0.0) {
        inGlass = (1.0 - smoothstep(-0.5, 0.5, roundBox(p, glass, glassR))) * glassA;
        float g = dot(col, vec3(0.2126, 0.7152, 0.0722));
        col = mix(col, clamp(mix(vec3(g), col, 1.3), 0.0, 1.0), inGlass);
    }
    // film grain, overlay-blended
    float n = hash(floor(p) + 17.0);
    vec3 ov = mix(2.0 * col * n, 1.0 - 2.0 * (1.0 - col) * (1.0 - n), step(0.5, col));
    col = mix(col, ov, grainA * (1.0 - inGlass));
    // the dimmer
    col = mix(col, dimC.rgb, dimA);
    // the design's vignette (it was its own layer drawn over the screen — a second full-screen pass each frame): soft
    // dark edges — an ellipse 130 % × 110 % of the screen, a little right of and above the middle, clear to 55 % and
    // 42 % black at its rim — and a shade down the left behind the clock (22 % at the edge, gone by 38 % of the width)
    vec2 q = (p - vec2(0.55 * 1368.0, 0.40 * 912.0)) / vec2(1.3 * 1368.0, 1.1 * 912.0);
    float v1 = clamp((length(q) - 0.55) / 0.45, 0.0, 1.0) * 0.42;
    float v2 = clamp(1.0 - p.x / (0.38 * 1368.0), 0.0, 1.0) * 0.22;
    col *= (1.0 - v1) * (1.0 - v2);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
