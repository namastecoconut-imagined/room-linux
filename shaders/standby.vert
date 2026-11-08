#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time; float level; float pitch; float dim; vec2 res; vec4 c1; vec4 c2; vec4 c3;
};
void main() { qt_TexCoord0 = qt_MultiTexCoord0; gl_Position = qt_Matrix * qt_Vertex; }
