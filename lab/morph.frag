#version 440

// A pill turning into its popover (lab/MorphScene.qml): the pill's box and
// the panel's box as one piece of glass, joined by a smooth minimum, the
// panel narrowed towards its top by `bell` the way a drop hangs. Clear glass
// where it is the pill, frost where it is the panel, crossed by `frost`.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o morph.frag.qsb morph.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // This item's top left on the stage, and the stage's size.
    vec2 origin;
    vec2 stage;
    // x, y, width, height; the pill fully round, the panel at panelRadius.
    vec4 pill;
    vec4 panel;
    float panelRadius;
    // How far the two reach for each other, and how much narrower the
    // panel's top is than its foot (0 none, 1 a point).
    float join;
    float bell;
    // 0 all clear glass, 1 all frost; and the y below which it is frost
    // whatever `frost` says (the panel of a popover that hangs off its pill).
    float frost;
    float frostFrom;
    vec4 clearTint;
    vec4 frostTint;
    vec4 rimTop;
    vec4 rimBottom;
    float bend;
};

layout(binding = 1) uniform sampler2D backdrop;
layout(binding = 2) uniform sampler2D blurred;

float box(vec2 p, vec4 b, float r) {
    if (b.z <= 0.0 || b.w <= 0.0)
        return 1e5;
    vec2 h = b.zw * 0.5;
    r = min(r, min(h.x, h.y));
    vec2 q = abs(p - (b.xy + h)) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float field(vec2 p) {
    // The bell: the panel drawn narrower towards its top, by squeezing
    // space sideways there.
    float t = clamp((p.y - panel.y) / max(panel.w, 1.0), 0.0, 1.0);
    float s = mix(1.0, mix(0.35, 1.0, sqrt(t)), bell);
    float cx = panel.x + panel.z * 0.5;
    vec2 q = vec2(cx + (p.x - cx) / s, p.y);
    float dp = box(q, panel, panelRadius) * s;
    return smin(box(p, pill, pill.w * 0.5), dp, join);
}

vec3 sharp(vec2 p) {
    return texture(backdrop, (origin + p) / stage).rgb;
}
vec3 soft(vec2 p) {
    return texture(blurred, (origin + p) / stage).rgb;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = field(p);
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 grad = vec2(field(p + vec2(0.5, 0.0)) - field(p - vec2(0.5, 0.0)),
                     field(p + vec2(0.0, 0.5)) - field(p - vec2(0.0, 0.5)));
    d /= clamp(length(grad), 0.2, 1.0);
    vec2 n = normalize(grad + 1e-6);

    // The rounded bevel: the bend piles up in the last few pixels.
    float t = clamp(1.0 + d / 12.0, 0.0, 1.0);
    float lens = 1.0 - sqrt(1.0 - t * t);
    vec2 at = p - n * bend * lens;

    float f = max(frost, smoothstep(frostFrom, frostFrom + 6.0, p.y));
    vec3 c = sharp(at);
    c = clamp(mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, 1.5), 0.0, 1.0);
    vec3 clearGlass = mix(c, clearTint.rgb, clearTint.a);
    vec3 frosted = mix(soft(at), frostTint.rgb, frostTint.a);
    vec3 body = mix(clearGlass, frosted, f);

    float band = shape - clamp(0.5 - (d + 1.0), 0.0, 1.0);
    float top = min(pill.y, panel.y);
    float bottom = max(pill.y + pill.w, panel.y + panel.w);
    vec4 rim = mix(rimTop, rimBottom, clamp((p.y - top) / max(bottom - top, 1.0), 0.0, 1.0));
    float rimA = rim.a * band;
    vec3 rgb = rim.rgb * rimA + body * shape * (1.0 - rimA);
    fragColor = vec4(rgb, shape) * qt_Opacity;
}
