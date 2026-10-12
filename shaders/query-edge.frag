#version 440

// Fade only the scrolling query; the glass and fixed search icon stay intact.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o query-edge.frag.qsb query-edge.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float span;
    float fadeLeft;
    float fadeRight;
};
layout(binding = 1) uniform sampler2D source;

float fade(float distance, float reach) {
    return reach > 0.0 ? smoothstep(0.0, reach, distance) : 1.0;
}

void main() {
    float x = qt_TexCoord0.x * span;
    fragColor = texture(source, qt_TexCoord0)
        * fade(x, fadeLeft) * fade(span - x, fadeRight) * qt_Opacity;
}
