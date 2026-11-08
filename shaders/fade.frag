#version 440
// A reflection's fade: the texture's alpha falls off from the top edge (where it meets the cover) to nothing.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float reach;     // how far down it fades out (0…1 of the height)
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float f = 1.0 - smoothstep(0.0, reach, qt_TexCoord0.y);
    fragColor = texture(source, qt_TexCoord0) * f * qt_Opacity;
}
