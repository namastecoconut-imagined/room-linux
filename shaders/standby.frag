#version 440
// Standby: a breathing dot field over a slow, blurred multicolour glow (the "morning" palette —
// peach and sky). The dots ripple out from the centre and swell with the room's sound.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;      // seconds
    float level;     // room loudness 0…1 (smoothed)
    float pitch;     // dot spacing in pixels
    float dim;       // 0…1 overall brightness (night)
    vec2 res;        // size in pixels
    vec4 c1;         // peach
    vec4 c2;         // sky
    vec4 c3;         // pale centre light
};

float blob(vec2 p, vec2 c, float r) { float d = length(p - c) / r; return exp(-d * d * 2.2); }

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 uv = qt_TexCoord0;
    float asp = res.x / res.y;
    vec2 q = vec2(uv.x * asp, uv.y);
    float t = time;
    float sp = 1.0 + 1.6 * level;   // the glow drifts faster when the room is loud

    // ---- the glow: three soft lights drifting on slow Lissajous paths
    vec2 a = vec2(0.32 * asp + 0.10 * sin(t * 0.050 * sp), 0.74 + 0.08 * cos(t * 0.043 * sp));
    vec2 b = vec2(0.78 * asp + 0.09 * cos(t * 0.037 * sp + 1.3), 0.28 + 0.09 * sin(t * 0.052 * sp));
    vec2 c = vec2(0.55 * asp + 0.12 * sin(t * 0.029 * sp + 2.1), 0.55 + 0.06 * sin(t * 0.061 * sp + 0.7));
    vec3 glow = c1.rgb * blob(q, a, 0.62) * 0.36
              + c2.rgb * blob(q, b, 0.66) * 0.30
              + c3.rgb * blob(q, c, 0.40) * (0.10 + 0.10 * level);

    // ---- the dots
    vec2 cell = px / pitch;
    vec2 id = floor(cell);
    vec2 f = fract(cell) - 0.5;
    vec2 cpx = (id + 0.5) * pitch;
    vec2 centre = res * vec2(0.55, 0.57);
    float dist = length(cpx - centre) / res.y;
    float wave = 0.5 + 0.5 * sin(dist * 16.0 - t * 0.9);                 // the slow breath outward
    float ripple = level * (0.5 + 0.5 * sin(dist * 34.0 - t * 5.0));     // sound ripples
    float fall = clamp(1.25 - dist * 0.85, 0.25, 1.0);
    float r = (0.085 + 0.035 * wave + 0.06 * ripple) * fall;
    float aa = 1.2 / pitch;
    float d = length(f);
    float dotMask = 1.0 - smoothstep(r - aa, r + aa, d);
    float dotA = (0.13 + 0.20 * wave + 0.40 * ripple) * fall;
    vec3 dotCol = mix(vec3(1.0), vec3(1.0) * 0.6 + glow * 1.4, 0.35);

    vec3 col = glow + dotCol * dotMask * dotA;
    fragColor = vec4(col * dim, 1.0) * qt_Opacity;
}
