#version 440
// A standby scene drawing itself (SceneArt.qml, tools/scenes/bake.py): the finished picture, and a map of when each
// pixel appears. A line's pixel shows once the pen has reached it (now ≥ its time); a fill's fades in over `fade`
// from its time, as in the prototype. Drawing on is `now` going up; rubbing out, coming back down. Nothing else moves.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float now;         // build units drawn so far
    float fade;        // a fill's fade, in build units
    float tmax;        // the map's times run 0 … tmax
};
layout(binding = 1) uniform sampler2D art;
layout(binding = 2) uniform sampler2D map;
void main() {
    vec4 c = texture(art, qt_TexCoord0);
    vec4 m = floor(texture(map, qt_TexCoord0) * 255.0 + 0.5);    // (read without smoothing: the bytes as they are)
    float v = m.r * 256.0 + m.g;                                  // a line's time (12 bits), how much is line (4)
    float w = mod(v, 16.0) / 15.0;
    float tl = floor(v / 16.0) / 4095.0 * tmax;
    float tf = m.b / 255.0 * tmax;
    float lv = step(tl, now);
    float fv = clamp((now - tf) / fade, 0.0, 1.0);
    fv = fv * fv * (3.0 - 2.0 * fv);
    fragColor = c * mix(fv, lv, w) * qt_Opacity;
}
