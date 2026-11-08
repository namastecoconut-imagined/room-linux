#version 440
// Music background: the cover, blurred, seen through a grille of dots — light through a speaker grille.
// Each dot takes the colour of the cover behind it and grows with its brightness (halftone); a slow wave
// breathes across the field.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float pitch;     // dot spacing in pixels
    float beat;      // 0…1, extra swell (playing)
    float pad;
    vec2 res;
};
layout(binding = 1) uniform sampler2D src;   // the blurred cover

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 cell = floor(px / pitch);
    vec2 c = (cell + 0.5) * pitch;
    vec2 uv = c / res;
    vec3 col = texture(src, uv).rgb;
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float d = length(uv - vec2(0.42, 0.45));
    float wave = 0.5 + 0.5 * sin(d * 9.0 - time * 0.8);
    float r = pitch * (0.06 + 0.20 * smoothstep(0.05, 0.85, lum)) * (0.85 + 0.20 * wave + 0.20 * beat);
    float dist = length(px - c);
    float aa = 1.0;
    float m = 1.0 - smoothstep(r - aa, r + aa, dist);
    // a faint wash between the dots so the colour carries, dots brighter on top
    vec3 base = col * 0.55;
    vec3 dotc = mix(col, vec3(1.0), 0.15) * (0.72 + 0.26 * wave);
    fragColor = vec4(mix(base, dotc, m), 1.0) * qt_Opacity;
}
