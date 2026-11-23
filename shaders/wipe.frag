#version 440
// Written on, left to right (the lyric sheet's hook, Lyrics.qml): a soft pen edge sweeps across the words —
// what's behind it shows, what's ahead of it doesn't yet. `u` 0 → nothing, 1 → all of it. The edge leans a little
// (`lean`), as a hand moving along a line would.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u;
    float soft;
    float lean;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float x = qt_TexCoord0.x + lean * (0.5 - qt_TexCoord0.y);
    float edge = mix(-soft - lean, 1.0 + lean, u);
    float a = 1.0 - smoothstep(edge, edge + soft, x);
    fragColor = texture(source, qt_TexCoord0) * a * qt_Opacity;
}
