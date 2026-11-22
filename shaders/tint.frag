#version 440
// A white picture in one colour (a room map's lit lamp shade, a lamp's light: RoomMap.qml) — its shape from the
// picture's alpha, its colour from `tint`.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    fragColor = vec4(tint.rgb, 1.0) * tint.a * texture(source, qt_TexCoord0).a * qt_Opacity;
}
