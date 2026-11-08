#version 440
// The Alexa screen: the standby dot grid, with the voice sending rings of brighter, bigger dots out from the middle.
// Thinking: slow rings. Positions in stage pixels (1368 × 912).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;         // seconds
    float lvl;       // 0…1, how loud
    float think;     // 1 while thinking
    vec2 res;        // size in stage pixels
    vec2 centre;     // where the rings start
};
void main() {
    vec2 p = qt_TexCoord0 * res;
    const float gap = 34.0;
    vec2 c = (floor(p / gap) + 0.5) * gap;
    float d = distance(c, centre);
    float fade = max(0.0, 1.0 - d / 520.0);
    float ring = think > 0.5 ? max(0.0, cos(d / 40.0 - t * 5.0)) * 0.4
                             : max(0.0, sin(d / 38.0 - t * 8.0)) * lvl;
    float bottom = clamp((560.0 - c.y) / 90.0, 0.0, 1.0);    // the dots stop above the words
    float a = (0.07 + 0.75 * fade * ring + 0.2 * fade) * bottom;
    float r = 2.5 + 9.0 * fade * ring;
    float m = 1.0 - smoothstep(r - 1.0, r + 0.6, length(p - c));
    vec3 col = vec3(1.0, (226.0 - 40.0 * ring * fade) / 255.0, (196.0 - 80.0 * ring * fade) / 255.0);
    // a warm light behind, swelling with the voice
    float g = (0.1 + 0.15 * lvl) * exp(-pow(distance(p, centre) / 330.0, 2.0));
    vec3 glow = vec3(1.0, 0.745, 0.478) * g;
    float am = a * m;
    fragColor = vec4(col * am + glow * (1.0 - am), max(am, g)) * qt_Opacity;
}
