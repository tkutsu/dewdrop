#version 440

// The music pill's track, lit from above like every other edge the shell
// draws (see components/Rim.qml): full strength along the top, falling off in
// a straight line to `foot` of it at the bottom edge. Run over the track as a
// layer, because a stroke cannot take a gradient.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o track.frag.qsb track.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // How much of the light is left at the bottom edge, 0..1.
    float foot;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    // Premultiplied, so the whole colour scales with the light.
    fragColor = texture(source, qt_TexCoord0) * mix(1.0, foot, qt_TexCoord0.y) * qt_Opacity;
}
