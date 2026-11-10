#version 440
// The mic button while the assistant is ready: a small breathing light with the faintest turning rays (the
// listening screen's burst, very quiet), drifting through the panel's colours. Transparent around it, so the
// button's own circle shows; it fades out before the edge.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
    float level;     // 0…1, breathing
};

vec3 pal(float a) {
    a = fract(a) * 4.0;
    vec3 c0 = vec3(1.0, 0.76, 0.38), c1 = vec3(0.33, 0.72, 1.0), c2 = vec3(0.45, 0.88, 0.70), c3 = vec3(1.0, 0.56, 0.48);
    return a < 1.0 ? mix(c0, c1, a) : a < 2.0 ? mix(c1, c2, a - 1.0) : a < 3.0 ? mix(c2, c3, a - 2.0) : mix(c3, c0, a - 3.0);
}

float rays(float r, float a) {
    float sp = t * 0.3;
    float l1 = pow(0.5 + 0.5 * cos(13.0 * (a + sp)), mix(22.0, 8.0, level));
    float l2 = pow(0.5 + 0.5 * cos(9.0 * (a - sp * 0.7) + 1.3), mix(30.0, 10.0, level));
    float len = (0.62 + 0.2 * sin(a * 3.0 + t * 1.1) + 0.14 * sin(a * 5.0 - t * 1.7)) * (0.8 + 0.35 * level);
    float rr = (l1 + 0.75 * l2) * smoothstep(len, len * 0.05, r) * (0.55 + 0.45 * smoothstep(0.0, 0.5, r));
    float core = exp(-pow(r / (0.2 + 0.32 * level), 2.0));
    return rr + core * 1.2;
}

void main() {
    vec2 d = (qt_TexCoord0 - 0.5) * 2.0;                 // −1…1 across the button
    float r = length(d), a = atan(d.y, d.x);
    vec3 b = pal(t * 0.035);
    vec3 c = b * exp(-r * r * 6.0) * 0.33 + vec3(1.0, 0.96, 0.9) * exp(-r * r * 40.0) * 0.3;
    float v = rays(r / 0.8, a);
    vec3 base = pal(t * 0.035 + 0.1 * sin(a));
    c += mix(base, vec3(1.0, 0.97, 0.92), clamp(v * 0.6, 0.0, 1.0)) * clamp(v, 0.0, 1.3) * 0.15;
    c *= 1.0 - smoothstep(0.85, 1.0, r);
    c = min(c, vec3(1.0));
    fragColor = vec4(c, max(c.r, max(c.g, c.b))) * qt_Opacity;
}
