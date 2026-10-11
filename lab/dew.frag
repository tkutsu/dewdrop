#version 440

// Lab: a popup's frost (Hyprland's blur, popupBg over it) in a shape that can
// be a drop, a box, or a drop running into a box, joined with a smooth
// minimum the way shaders/liquid.frag joins pills. The box's bottom edge can
// bow down (or up) in the middle like gel. Nothing is drawn above `clipTop`,
// where the popup's window starts. Fills the stage; `blurred` is the stage's
// wallpaper already blurred.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 box;
    float radius;
    // A drop: centre (x, y), radius z; none at a radius of zero.
    vec4 drop;
    // How far the drop and box reach for each other.
    float join;
    // How far the middle of the bottom edge bows down.
    float sag;
    float clipTop;
    vec4 fill;
    // Light filling the frost, 0..1.
    float lit;
};

layout(binding = 1) uniform sampler2D blurred;

float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float field(vec2 p) {
    float d = 1e5;
    if (box.z > 0.0 && box.w > 0.0) {
        // Bow the bottom: the lower the point, the more of the sag it takes,
        // and the most in the middle.
        float u = (p.x - (box.x + box.z * 0.5)) / (box.z * 0.5);
        float down = clamp((p.y - box.y) / box.w, 0.0, 1.0);
        vec2 q0 = p - vec2(0.0, sag * max(1.0 - u * u, 0.0) * down);
        vec2 half_ = box.zw * 0.5;
        float r = min(radius, min(half_.x, half_.y));
        vec2 q = abs(q0 - (box.xy + half_)) - half_ + r;
        d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }
    if (drop.z > 0.0)
        d = smin(d, length(p - drop.xy) - drop.z, join);
    return d;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = field(p);
    float shape = clamp(0.5 - d, 0.0, 1.0) * step(clipTop, p.y);
    if (shape <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 c = mix(texture(blurred, qt_TexCoord0).rgb, fill.rgb, fill.a);
    c = mix(c, vec3(1.0), lit);
    // The dew is a bead: lighter through, with a glint up and to the left.
    if (drop.z > 0.0) {
        vec2 q = (p - drop.xy) / drop.z;
        float inDrop = clamp(0.5 - (length(p - drop.xy) - drop.z), 0.0, 1.0);
        vec2 g = q - vec2(-0.35, -0.4);
        c = mix(c, vec3(1.0), inDrop * (0.12 + 0.55 * exp(-dot(g, g) * 9.0)));
    }
    // A hairline lit from above round the whole shape, as Rim draws one
    // round a box, since this shape is no rectangle Rim could follow.
    float band = clamp(0.5 - d, 0.0, 1.0) - clamp(0.5 - (d + 1.0), 0.0, 1.0);
    float top = box.w > 0.0 ? clamp((p.y - box.y) / max(box.w, 1.0), 0.0, 1.0) : 0.5;
    c = mix(c, vec3(1.0), band * mix(0.2, 0.03, top));
    fragColor = vec4(c, 1.0) * shape * qt_Opacity;
}
