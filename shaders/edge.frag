#version 440
// The assistant's edge glow: the screen's border lit in the window's four colours, slowly turning round the edge,
// brighter and deeper the louder the voice. Sizes in pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float t;         // seconds
    float level;     // 0…1, the voice
    float depth;     // how far in the glow reaches at rest (px)
    vec4 c0;
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

void main() {
    vec2 p = qt_TexCoord0 * res;
    float d = min(min(p.x, res.x - p.x), min(p.y, res.y - p.y));          // distance to the nearest edge
    float reach = depth * (1.0 + level * 2.2);
    float g = exp(-d / reach) * (0.35 + level * 0.9);
    // colour by the angle round the centre, turning slowly
    vec2 q = (p - res * 0.5) / res;
    float a = fract(atan(q.y, q.x) / 6.2831853 + t * 0.05);
    float s = a * 4.0;
    vec3 c = s < 1.0 ? mix(c0.rgb, c1.rgb, s) : s < 2.0 ? mix(c1.rgb, c2.rgb, s - 1.0)
           : s < 3.0 ? mix(c2.rgb, c3.rgb, s - 2.0) : mix(c3.rgb, c0.rgb, s - 3.0);
    g = clamp(g, 0.0, 1.0);
    float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    fragColor = vec4(c * g + n / 255.0, g) * qt_Opacity;
}
