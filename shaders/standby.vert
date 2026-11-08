#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float bt; float gt; float period; float gday; float boost; float gstr; float glowV; float frozen;
    vec2 res; vec4 dotCol; vec4 c0; vec4 c1; vec4 c2; vec4 c3;
    vec4 r0; vec4 r1; vec4 r2; vec4 r3; vec4 r4; vec4 r5; vec4 rip0; vec4 rip1; vec4 rip2; vec4 rip3;
};
void main() { qt_TexCoord0 = qt_MultiTexCoord0; gl_Position = qt_Matrix * qt_Vertex; }
