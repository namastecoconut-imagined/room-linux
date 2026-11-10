#version 440
// The assistant's edge: a soft light just inside the screen's rounded edge, in the panel's colours turning slowly
// round it, deeper and brighter with the voice. Sizes in pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float t;         // seconds
    float level;     // 0…1, the voice
    float depth;     // how far in the light reaches at rest (px)
    vec4 c0;
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

void main() {
    vec2 p = qt_TexCoord0 * res;
    // distance inside a rounded rectangle (corners follow the screen's rounding)
    float r = 36.0;
    vec2 q = abs(p - res * 0.5) - (res * 0.5 - vec2(r));
    float d = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r);
    float reach = depth * (1.0 + level * 1.6);
    float g = exp(-max(d, 0.0) / reach) * (0.22 + level * 0.6) + exp(-max(d, 0.0) / (reach * 0.25)) * (0.12 + level * 0.25);
    vec2 u = (p - res * 0.5) / res;
    float a = fract(atan(u.y, u.x) / 6.2831853 + t * 0.04);
    float s = a * 4.0;
    vec3 c = s < 1.0 ? mix(c0.rgb, c1.rgb, s) : s < 2.0 ? mix(c1.rgb, c2.rgb, s - 1.0)
           : s < 3.0 ? mix(c2.rgb, c3.rgb, s - 2.0) : mix(c3.rgb, c0.rgb, s - 3.0);
    g = clamp(g, 0.0, 1.0);
    float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    fragColor = vec4(c * g + n / 255.0, g) * qt_Opacity;
}
