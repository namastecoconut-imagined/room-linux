#version 440
// A sideways-only blur (the standby words' motion blur, room-motion.html's feGaussianBlur stdDeviation="σ 0").
// Run once when the words change — the blurred words are kept as a picture and only moved after that.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sigma;       // in texture widths (σ px / the picture's width)
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    for (int i = -12; i <= 12; i++) {
        float x = float(i) / 4.0;                       // −3σ … +3σ in 25 steps
        float w = exp(-0.5 * x * x);
        acc += texture(source, qt_TexCoord0 + vec2(x * sigma, 0.0)) * w;
        wsum += w;
    }
    fragColor = acc / wsum * qt_Opacity;
}
