#version 440
// The mic button on Home while the assistant is ready (design: "Horizon fog" orb): the fog's light falling into the
// round button from the top edge, a few colours drifting in it; the mic icon is drawn on top (in QML). amount:
// Ready ~0.8 (breathing), Pressed 1.0, Heard you 1.25 (the fog rolls further down).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
    float amount;
};

vec3 pal(float a) {
    a = fract(a) * 4.0;
    vec3 c0 = vec3(1.0, 0.76, 0.38), c1 = vec3(0.33, 0.72, 1.0), c2 = vec3(0.45, 0.88, 0.70), c3 = vec3(1.0, 0.56, 0.48);
    return a < 1.0 ? mix(c0, c1, a) : a < 2.0 ? mix(c1, c2, a - 1.0) : a < 3.0 ? mix(c2, c3, a - 2.0) : mix(c3, c0, a - 3.0);
}

void main() {
    vec2 q = qt_TexCoord0;                        // 0…1, y down
    float k = amount;
    float reach = 0.18 + 0.12 * (k - 0.8);        // how far down the cloud comes
    vec3 blue = vec3(0.33, 0.72, 1.0);
    vec3 c = blue * (pow(1.0 - q.y, 2.2) * 0.42 * k);                 // the wash, from the top
    // three soft blobs of cloud along the top edge, drifting
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 p = vec2(0.2 + 0.3 * fi + 0.06 * sin(t * 0.5 + fi * 2.1), reach * (0.4 + 0.25 * sin(t * 0.7 + fi)));
        vec2 d = (q - p) / vec2(0.32, 0.2 + 0.08 * (k - 0.8));
        vec3 col = i == 1 ? pal(t * 0.03) : blue;
        c += col * exp(-dot(d, d)) * 0.55 * k;
    }
    c += vec3(1.0, 0.97, 0.92) * exp(-pow((q.y - reach * 0.3) / 0.08, 2.0) - pow((q.x - 0.5) / 0.22, 2.0)) * 0.3 * k;
    float inside = smoothstep(0.5, 0.48, length(q - 0.5));             // the button's circle
    c = min(c, vec3(1.0)) * inside;
    fragColor = vec4(c, max(c.r, max(c.g, c.b))) * qt_Opacity;
}
