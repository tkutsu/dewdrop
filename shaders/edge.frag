#version 440

// A scrolling view's soft edges (see components/ScrollEdges.qml): what runs
// on past an edge of the view fades out over the last `fadeTop` or `fadeBottom`
// pixels before it, the way a list in a Mac's popover softens under its
// header rather than being cut off by it. Either reach is zero at rest, so a
// view sitting at its start is drawn untouched.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o edge.frag.qsb edge.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // The view's height, and how far in from its top and bottom the fade
    // reaches, in pixels.
    float span;
    float fadeTop;
    float fadeBottom;
};

layout(binding = 1) uniform sampler2D source;

// How much is left `d` pixels in from an edge that fades over `reach`. Eased
// rather than straight, so the fade has no visible line where it starts.
float fade(float d, float reach) {
    return reach > 0.0 ? smoothstep(0.0, reach, d) : 1.0;
}

void main() {
    float y = qt_TexCoord0.y * span;
    // Premultiplied, so the whole colour fades with the alpha.
    fragColor = texture(source, qt_TexCoord0) * fade(y, fadeTop) * fade(span - y, fadeBottom) * qt_Opacity;
}
