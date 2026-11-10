#version 440
// The assistant's screen (design: "Horizon fog", Figma "Room — Assistant & Orb"): a band of glowing cloud across
// the upper middle, in three of the panel's colours (warm, blue, mint, coral — c1…c3, set per state by the screen),
// with soft rays of light falling from it, light flowing down them. Your voice makes the cloud billow, brighten and drop a little; the rays
// reach further. Everything below fades to the near-black the words sit on. Sizes in pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float t;
    float level;     // 0…1, your voice (or Room's while it speaks)
    float amount;    // 0…1, how much fog the state has (listening 0.7, thinking 0.6, missed 0.28 …)
    float voice;     // 0…1, the voice, quick: brightens the cores and the rays, speeds the flow (doesn't move the cloud)
    float flow;      // where the light flowing through the rays has got to (up while listening, down while speaking)
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}

// the colour of the fog here: the three colours drifting slowly along the band
vec3 tint(vec2 q) {
    float w = fbm(vec2(q.x * 1.6 + t * 0.035, q.y * 2.6 + 3.1));
    float v = fbm(vec2(q.x * 2.3 - t * 0.028, q.y * 3.1 + 8.7));
    vec3 c = mix(c1.rgb, c2.rgb, smoothstep(0.36, 0.66, w));
    return mix(c, c3.rgb, smoothstep(0.44, 0.72, v) * 0.85);
}

void main() {
    vec2 q = qt_TexCoord0;                       // 0…1, y down
    float aspect = res.x / res.y;
    float k = amount + 0.45 * level;             // the voice adds to the state's fog
    float y0 = 0.26 + 0.08 * level;             // the band's middle (drops a little as you speak)

    // the cloud: a soft band, its edge and density broken up by slowly moving noise
    float n = fbm(vec2(q.x * 3.2 * aspect / 1.5 + t * 0.05, q.y * 5.0 - t * 0.03));
    float m = fbm(vec2(q.x * 7.0 - t * 0.04, q.y * 9.0 + t * 0.02));
    float dy = q.y - y0 - 0.07 * (n - 0.5);
    float band = exp(-pow(dy / (0.08 + 0.04 * k + 0.07 * level), 2.0)) * (0.45 + 0.75 * n) * (0.8 + 0.4 * m);
    vec3 col = tint(q);
    vec3 c = col * band * (0.85 + 0.35 * voice) * k;
    c += vec3(1.0, 0.97, 0.92) * pow(band, 3.0) * (0.3 + 0.7 * voice) * k;          // brighter cores in the cloud

    // the rays: fanning down from a point above the band, soft, flickering slowly
    float below = q.y - (y0 + 0.02);
    if (below > 0.0) {
        float src = y0 - 0.25;
        float a = (q.x - 0.5) * aspect / (q.y - src);                  // the ray's direction from the source
        float r = pow(0.5 + 0.5 * sin(a * 15.0 + 2.0 * fbm(vec2(a * 2.0, t * 0.06))), 3.0);
        r += 0.4 * pow(0.5 + 0.5 * sin(a * 23.0 - t * 0.04 + 2.0), 4.0);
        float reach = exp(-below * (3.4 - 1.2 * level));
        // light flowing down each ray: soft pulses travelling away from the cloud, each ray at its own pace and phase
        float id = floor(a * 15.0 / 6.2832 + 0.5);
        float ph = hash(vec2(id, 3.7)), sp = 0.7 + 0.6 * hash(vec2(id, 9.1));
        float fl = pow(0.5 + 0.5 * sin(below * 11.0 - flow * 1.3 * sp + ph * 6.2832), 4.0);
        c += tint(vec2(0.5 + a * 0.3, y0 + 0.1)) * r * reach * smoothstep(0.0, 0.05, below) * (0.16 + (0.32 + 0.4 * voice) * fl) * k;
    }
    float g = hash(q * res + t) - 0.5;                                  // a whisper of grain (no banding)
    vec3 bg = vec3(0.020, 0.024, 0.031);
    fragColor = vec4(min(bg + c, vec3(1.0)) + g / 255.0, 1.0) * qt_Opacity;
}
