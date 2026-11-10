#version 440

// A popup's list running on under the header above it (reel 7; see
// components/ScrollUnder.qml). Drawn from the top of the popup's box down to
// the list's foot, out to the box's sides: below `edge`, where the list
// starts, the list as it is, fading out over its last `fadeBottom` pixels
// while there is more below; above it, under the header, the list's blurred
// copy, dimmed so the header reads over it and pulled down near the edge the
// way the rim of a lens pulls what is beyond it, so the rows bend up into the
// header as they go under. All of it inside the box's rounded corners.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o under.frag.qsb under.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float edge;
    // How soft the edge is, in pixels.
    float soft;
    // How far the edge pulls in, how far up it reaches, how steeply it falls.
    float bend;
    float reach;
    float steep;
    // How much of what is under the header shows (1 is all of it).
    float through;
    float fadeBottom;
    // The box's height and corner, to stay inside it.
    float boxHeight;
    float radius;
};

layout(binding = 1) uniform sampler2D sharp;
layout(binding = 2) uniform sampler2D blurred;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec4 below = texture(sharp, qt_TexCoord0);
    if (fadeBottom > 0.0)
        below *= smoothstep(0.0, fadeBottom, size.y - p.y);

    float t = clamp(1.0 - (edge - p.y) / max(reach, 1.0), 0.0, 1.0);
    vec2 seen = vec2(p.x, p.y + bend * pow(t, steep));
    vec4 under = texture(blurred, seen / size) * through;

    float k = smoothstep(edge - soft * 0.5, edge + soft * 0.5, p.y);
    vec4 c = mix(under, below, k);

    vec2 half_ = vec2(size.x, boxHeight) * 0.5;
    vec2 q = abs(p - half_) - half_ + radius;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    fragColor = c * clamp(0.5 - d, 0.0, 1.0) * qt_Opacity;
}
