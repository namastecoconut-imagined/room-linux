#version 440
// The assistant's "window of light" (the phone's VoiceView): a vertical gradient in a soft-edged rounded rectangle,
// two coloured hazes drifting through it and a pale orb that swells with the voice. Sizes in window pixels.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // window size
    float radius;    // corner radius
    float blur;      // edge softness
    vec4 gTop;       // gradient: top, middle (at 0.45), bottom
    vec4 gMid;
    vec4 gBot;
    vec4 hazeC;      // haze colours
    vec4 haze2C;
    vec4 orbC;
    vec3 haze;       // x, y, radius
    vec3 haze2;
    vec3 orb;
};

float glow(vec2 p, vec3 g) {
    float t = clamp(distance(p, g.xy) / (g.z * 0.7), 0.0, 1.0);
    return 1.0 - smoothstep(0.0, 1.0, t);
}

void main() {
    vec2 p = qt_TexCoord0 * res;
    float v = qt_TexCoord0.y;
    vec3 c = v < 0.45 ? mix(gTop.rgb, gMid.rgb, v / 0.45) : mix(gMid.rgb, gBot.rgb, (v - 0.45) / 0.55);
    c = mix(c, hazeC.rgb, 0.8 * 0.7 * glow(p, haze));
    c = mix(c, haze2C.rgb, 0.75 * 0.65 * glow(p, haze2));
    c = mix(c, orbC.rgb, 0.95 * glow(p, orb));
    // the soft rounded mask: a rounded rectangle inset a little, its edge blurred out to the window's edge
    float inset = blur * 1.2;
    vec2 h = res * 0.5 - vec2(inset);
    float r = min(radius, min(h.x, h.y));
    vec2 q = abs(p - res * 0.5) - (h - vec2(r));
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float a = 1.0 - smoothstep(-blur, blur, sd);
    // tiny dither so the gradient never bands on the Surface's panel
    float n = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    fragColor = vec4((c + n / 255.0) * a, a) * qt_Opacity;
}
