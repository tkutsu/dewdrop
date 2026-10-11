#version 440

// A popover that a pill turns into (components/Popup.qml, `morphs`): its
// frost, a thin fill over Hyprland's blur, and the hairline round it lit
// from above as Rim draws it, in a box that starts as a drop where the pill
// was and swells into the popover. Narrowed towards its top by `bell`, the
// way a hanging drop is, so it swells foot first. Drawn as one shape rather
// than a Rectangle and a Rim because neither can bend.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o drop.frag.qsb drop.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // The box (x, y, width, height), its corner, and how much narrower its
    // top is than its foot (0 none, 1 a point).
    vec4 box;
    float radius;
    float bell;
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

float field(vec2 p) {
    if (box.z <= 0.0 || box.w <= 0.0)
        return 1e5;
    // The bell: space squeezed sideways towards the top, so the box is drawn
    // narrower there.
    float t = clamp((p.y - box.y) / box.w, 0.0, 1.0);
    float s = mix(1.0, mix(0.35, 1.0, sqrt(t)), bell);
    float cx = box.x + box.z * 0.5;
    vec2 q0 = vec2(cx + (p.x - cx) / s, p.y);

    vec2 half_ = box.zw * 0.5;
    float r = min(radius, min(half_.x, half_.y));
    vec2 q = abs(q0 - (box.xy + half_)) - half_ + r;
    return (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r) * s;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = field(p);

    // A pixel of antialiasing across the edge, and the same across the rim's
    // inner edge, so the rim is the band between the two.
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    float band = shape - clamp(0.5 - (d + lineWidth), 0.0, 1.0);
    vec4 rim = mix(rimTop, rimBottom, clamp((p.y - box.y) / max(box.w, 1.0), 0.0, 1.0));

    // Rim over the fill, premultiplied.
    float rimA = rim.a * band * showRim;
    float fillA = fill.a * shape * showFill;
    vec3 rgb = rim.rgb * rimA + fill.rgb * fillA * (1.0 - rimA);
    float a = rimA + fillA * (1.0 - rimA);
    fragColor = vec4(rgb, a) * qt_Opacity;
}
