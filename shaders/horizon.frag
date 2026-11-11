#version 440
// The assistant's light (room-motion.html aGlow + aLine): a thin line of light across the screen with a wide soft glow
// sitting just under it, in the state's two colours (c0 the light, c1 its edge) — cool blue and mint while it listens,
// violet and coral thinking, amber and coral while Room answers. The glow grows taller with the voice and the line
// reaches further; while it thinks the glow drifts sideways (shift). Added to what's behind (the design's "screen"
// blend): the shader only ever adds light. Sizes in pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    float lineY;     // where the line is, from the top of this item
    float v;         // 0…1: the voice (yours while it listens, Room's while it answers)
    float shift;     // the glow's sideways drift, px
    float lineOn;    // 0…1
    vec4 c0;
    vec4 c1;
};

void main() {
    vec2 p = qt_TexCoord0 * res;

    // the glow: an ellipse a little below the line (CSS: radial-gradient 48% × 34% of 1888 × 440, at 58 % down) —
    // c0 at the centre, c1 by 42 %, nothing by ~75 %
    vec2 c = vec2(res.x * 0.5 + shift, lineY + 39.0);
    vec2 r = vec2(906.0 * (1.0 + v * 0.08), 150.0 * (0.55 + v * 0.9));
    float d = length((p - c) / r);
    vec4 g = mix(c0, c1, smoothstep(0.0, 0.42, d));
    g.a *= 1.0 - smoothstep(0.38, 0.78, d);
    vec3 light = g.rgb * g.a;

    // the line: white in the middle, the light's colour further out, gone at the ends; a soft halo round it
    float u = abs(p.x - res.x * 0.5) / (res.x * 0.5 * (0.7 + v * 0.3));
    float dy = p.y - lineY;
    float core = exp(-dy * dy / 1.4);
    float halo = exp(-dy * dy / 260.0);
    vec3 lc = mix(vec3(1.0), c0.rgb, smoothstep(0.0, 0.45, u));
    light += lineOn * (core * (1.0 - smoothstep(0.35, 1.0, u)) * lc * 0.95
                       + halo * (1.0 - smoothstep(0.75, 1.05, u)) * c0.rgb * c0.a * 0.42);

    fragColor = vec4(light, 0.0) * qt_Opacity;
}
