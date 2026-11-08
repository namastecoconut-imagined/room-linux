#version 440
// The cover blurred into light: a tiny copy of the art, sampled softly, faded to nothing in a circle.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sat;       // saturation boost (1 = as is)
    float spread;    // how far apart the blur's samples are (0.035: soft; 0.12: just colour, no shapes)
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 uv = qt_TexCoord0;
    // a wide soft sample (the source is only 16 px across, so this is a big blur)
    vec3 c = vec3(0.0); float w = 0.0;
    for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
        float k = exp(-float(x * x + y * y) / 4.0);
        c += texture(source, clamp(uv + vec2(x, y) * spread, 0.0, 1.0)).rgb * k; w += k;
    }
    c /= w;
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    c = clamp(mix(vec3(l), c, sat), 0.0, 1.0);
    // every cover glows about as brightly: dark art is lifted (keeping its hue), pale art is held back
    float m = max(c.r, max(c.g, c.b));
    c *= min(4.0, 0.72 / max(m, 0.01));
    // round falloff: full at the middle, gone at the edge
    float d = length(uv - 0.5) * 2.0;
    float a = pow(1.0 - smoothstep(0.0, 1.0, d), 1.6);          // no edge anywhere: it just fades
    fragColor = vec4(c * a, a) * qt_Opacity;
}
