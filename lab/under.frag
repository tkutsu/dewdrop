#version 440

// Lab: a list that runs on under its popup's header (reel 7). Below the
// header's edge it is drawn as it is; under the header it is drawn from its
// blurred copy, dimmed so the header's own text reads over it, and near the
// edge pulled down, the way the rim of a lens pulls what is beyond it, so the
// rows bend up into the header as they go under. The edge between the two is
// soft, and can be lit like glass.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // Where the header ends, in pixels from the top.
    float edge;
    // How soft the edge is, in pixels.
    float soft;
    // How far the edge pulls in, how far up it reaches, how steeply it falls.
    float bend;
    float reach;
    float steep;
    // How much of what is under the header is let through (1 is all of it).
    float through;
    // A band of glass over the header: a fill (premultiplied) and a lit edge.
    vec4 band;
    float lit;
};

layout(binding = 1) uniform sampler2D sharp;
layout(binding = 2) uniform sampler2D blurred;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec4 below = texture(sharp, qt_TexCoord0);

    float above = edge - p.y;
    float t = clamp(1.0 - above / max(reach, 1.0), 0.0, 1.0);
    float lens = pow(t, steep);
    vec2 seen = vec2(p.x, p.y + bend * lens);
    vec4 under = texture(blurred, seen / size) * through;
    under = band + under * (1.0 - band.a);
    // The lit edge: a pixel along the header's foot, fading off sideways.
    float line = clamp(1.0 - abs(p.y - edge + 0.5), 0.0, 1.0);
    under = mix(under, vec4(1.0), line * lit);

    float k = smoothstep(edge - soft * 0.5, edge + soft * 0.5, p.y);
    fragColor = mix(under, below, k) * qt_Opacity;
}
