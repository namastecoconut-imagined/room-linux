#version 440
// The redesign's vignette (room-motion.html): a soft dark edge — an ellipse 130 % × 110 % of the screen centred a
// little right of and above the middle, clear to 55 % and 42 % black at its rim — plus a shade down the left side,
// behind the clock (22 % black at the edge, gone by 38 % of the width). Drawn over everything but the alerts.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;         // this item's size (stage px)
    vec2 origin;       // where its top left sits on the stage
};
void main() {
    vec2 p = origin + qt_TexCoord0 * size;
    vec2 q = (p - vec2(0.55 * 1368.0, 0.40 * 912.0)) / vec2(1.3 * 1368.0, 1.1 * 912.0);
    float a1 = clamp((length(q) - 0.55) / 0.45, 0.0, 1.0) * 0.42;
    float a2 = clamp(1.0 - p.x / (0.38 * 1368.0), 0.0, 1.0) * 0.22;
    float a = 1.0 - (1.0 - a1) * (1.0 - a2);
    fragColor = vec4(0.0, 0.0, 0.0, a) * qt_Opacity;
}
