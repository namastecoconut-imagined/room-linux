#version 440
// The assistant's background: light moving behind fluted (ribbed) glass. Two soft lights drift behind the glass in
// the panel's colours (warm, blue, mint, coral, slowly turning); the voice makes them brighter and wider. Each rib
// squeezes and flips what's behind it, is a little darker at its edges and catches a fine highlight. Brightest in
// the upper middle, falling to black at the bottom where the words are. A faint starburst sits behind the glass in
// the middle too, so the ribs break it up like the rest: it opens a little as you speak, turns faster while
// thinking. Sizes in pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float t;
    float level;     // 0…1, the voice
    float think;     // 0…1
};

vec3 pal(float a) {
    a = fract(a) * 4.0;
    vec3 c0 = vec3(1.0, 0.76, 0.38), c1 = vec3(0.33, 0.72, 1.0), c2 = vec3(0.45, 0.88, 0.70), c3 = vec3(1.0, 0.56, 0.48);
    return a < 1.0 ? mix(c0, c1, a) : a < 2.0 ? mix(c1, c2, a - 1.0) : a < 3.0 ? mix(c2, c3, a - 2.0) : mix(c3, c0, a - 3.0);
}

// the starburst: thin rays turning two ways round a soft core (0…1 r is its radius)
float rays(float r, float a) {
    float sp = t * (0.3 + 0.4 * think);
    float l1 = pow(0.5 + 0.5 * cos(13.0 * (a + sp)), mix(22.0, 8.0, level));
    float l2 = pow(0.5 + 0.5 * cos(9.0 * (a - sp * 0.7) + 1.3), mix(30.0, 10.0, level));
    float len = (0.62 + 0.2 * sin(a * 3.0 + t * 1.1) + 0.14 * sin(a * 5.0 - t * 1.7)) * (0.8 + 0.35 * level) * (1.0 - 0.2 * think);
    float rr = (l1 + 0.75 * l2) * smoothstep(len, len * 0.05, r) * (0.55 + 0.45 * smoothstep(0.0, 0.5, r));
    float core = exp(-pow(r / (0.2 + 0.32 * level + 0.08 * think * (0.6 + 0.4 * sin(t * 4.0))), 2.0));
    return rr + core * 1.2;
}

vec3 burst(vec2 p) {
    vec2 d = (p - vec2(res.x * 0.5, res.y * 0.30)) / (res.y * 0.30);
    float r = length(d), a = atan(d.y, d.x);
    float v = rays(r, a), w = rays(r * 0.92, a);
    vec3 base = pal(t * 0.035 + 0.1 * sin(a));
    vec3 c = mix(base, vec3(1.0, 0.97, 0.92), clamp(v * 0.6, 0.0, 1.0)) * clamp(v, 0.0, 1.3);
    c += vec3(1.0, 0.5, 0.55) * max(0.0, w - v) * 0.4;                 // a faint warm fringe on the rays
    return (c + base * exp(-r * r * 2.5) * 0.2) * 0.32;
}

vec3 light(vec2 p) {
    vec2 q = p / res;
    float sweep = 0.5 + 0.38 * sin(t * 0.42) + 0.06 * level * sin(t * 7.0);   // a quiver with the voice
    float spread = 0.13 + 0.30 * level + 0.04 * think;
    float b1 = exp(-pow((q.x - sweep) / spread, 2.0));
    float b2 = exp(-pow((q.x - (0.5 - 0.3 * sin(t * 0.29 + 1.0))) / (0.09 + 0.14 * level), 2.0)) * 0.7;
    float v = exp(-pow((q.y - 0.28) / 0.40, 2.0));
    vec3 c1 = pal(t * 0.035), c2 = pal(t * 0.035 + 0.35);
    // the voice mostly widens and moves the light; it brightens only a little (it got too bright)
    return (c1 * b1 * (0.36 + 0.24 * level) + c2 * b2 * (0.24 + 0.16 * level)) * v + vec3(0.01, 0.02, 0.03) * v
           + burst(p);
}

void main() {
    vec2 p = qt_TexCoord0 * res;
    float w = res.x / 46.0;                                   // rib width
    float local = fract(p.x / w);
    float sx = p.x + (local - 0.5) * w * (-2.2 - 1.6 * level); // each rib squeezes and flips the light behind it — more as you speak
    vec3 c = light(vec2(sx, p.y));
    float shade = 0.6 + 0.4 * sin(local * 3.14159);           // rounded ribs
    float hi = smoothstep(0.9, 1.0, local) * 0.28;            // a fine highlight on each rib's edge
    float col = 0.9 + 0.1 * fract(sin(floor(p.x / w) * 12.9898) * 43758.5453);
    c = c * shade * col + light(p) * hi;
    float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    fragColor = vec4(min(c, vec3(1.0)) + n / 255.0, 1.0) * qt_Opacity;
}
