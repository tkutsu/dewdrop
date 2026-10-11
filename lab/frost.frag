#version 440

// Lab: a popup's frost as Hyprland draws it (its blur, popupBg laid over it)
// inside a rounded box that can change shape as it opens. Fills the stage;
// `blurred` is the stage's wallpaper already blurred.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 box;
    float radius;
    vec4 fill;
    // Light filling the frost, 0..1.
    float lit;
};

layout(binding = 1) uniform sampler2D blurred;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 half_ = box.zw * 0.5;
    float r = min(radius, min(half_.x, half_.y));
    vec2 q = abs(p - (box.xy + half_)) - half_ + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0 || box.z <= 0.0 || box.w <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 c = mix(texture(blurred, qt_TexCoord0).rgb, fill.rgb, fill.a);
    c = mix(c, vec3(1.0), lit);
    fragColor = vec4(c, 1.0) * shape * qt_Opacity;
}
