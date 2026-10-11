#version 440

// A popup's box (components/Popup.qml): its frost, which is a thin fill over
// Hyprland's blur, and the hairline round it lit from above as Rim draws it,
// in a rounded box whose bottom edge can sag in the middle like gel as the
// popup opens. Drawn as one shape rather than a Rectangle and a Rim because
// neither can bend. The item reaches `room` pixels below the box, for the sag
// to hang into.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o frost.frag.qsb frost.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float room;
    float radius;
    // How far the middle of the bottom edge hangs below it (above it, if
    // negative).
    float sag;
    float lineWidth;
    // Straight (not premultiplied) alpha.
    vec4 fill;
    vec4 rimTop;
    vec4 rimBottom;
    // Which parts to draw, 0 or 1 each: the fill goes under a popup's rows
    // and the rim over them, so the two are drawn as two layers.
    float showFill;
    float showRim;
};

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 box = vec2(size.x, size.y - room);

    // Bow the bottom: the lower the point, the more of the sag it takes, and
    // the most in the middle.
    float u = (p.x - box.x * 0.5) / (box.x * 0.5);
    float down = clamp(p.y / box.y, 0.0, 1.0);
    vec2 q0 = p - vec2(0.0, sag * max(1.0 - u * u, 0.0) * down);

    vec2 half_ = box * 0.5;
    float r = min(radius, min(half_.x, half_.y));
    vec2 q = abs(q0 - half_) - half_ + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;

    // A pixel of antialiasing across the edge, and the same across the rim's
    // inner edge, so the rim is the band between the two.
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    float band = shape - clamp(0.5 - (d + lineWidth), 0.0, 1.0);
    vec4 rim = mix(rimTop, rimBottom, clamp(p.y / box.y, 0.0, 1.0));

    // Rim over the fill, premultiplied.
    float rimA = rim.a * band * showRim;
    float fillA = fill.a * shape * showFill;
    vec3 rgb = rim.rgb * rimA + fill.rgb * fillA * (1.0 - rimA);
    float a = rimA + fillA * (1.0 - rimA);
    fragColor = vec4(rgb, a) * qt_Opacity;
}
