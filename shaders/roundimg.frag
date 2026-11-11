#version 440
// A picture with rounded corners, cut sharp at any size (the covers): the corners are worked out per pixel rather
// than masked through an extra picture. A picture that isn't square is cropped to the middle, like PreserveAspectCrop.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;      // corner radius (item units)
    float aa;          // one screen pixel, in item units (the edge's softness)
    float aspect;      // the picture's width / height
    vec2 size;         // the item's size
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 uv = qt_TexCoord0;
    float ia = size.x / size.y;
    if (aspect > ia) uv.x = 0.5 + (uv.x - 0.5) * ia / aspect;
    else uv.y = 0.5 + (uv.y - 0.5) * aspect / ia;
    vec2 p = qt_TexCoord0 * size, h = size * 0.5;
    vec2 q = abs(p - h) - h + radius;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float a = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, d);
    fragColor = texture(source, uv) * a * qt_Opacity;
}
