#version 440

// The pills around the clock as one piece of glass (see components/Liquid.qml).
// Each pill is a rounded box; the boxes are joined with a smooth minimum, so two
// that come within reach of each other grow a neck between them and one that
// moves inside another is absorbed rather than overlapped. Drawn as one shape,
// so the translucent fill never doubles up where two of them meet.
//
// Given what is behind it (glass = 1), it is clear glass rather than a tint:
// it draws the wallpaper itself, bent in towards the middle near the edge the
// way the rim of a lens pulls what is under it, softened a little and
// brightened in colour. Red bends a little less and blue a little more, as
// they do through real glass, so the edge fringes with colour. Opaque, so Hyprland's blur underneath never shows.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o liquid.frag.qsb liquid.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // x, y, width, height in the item's pixels. A width of zero is no box.
    vec4 box0;
    vec4 box1;
    vec4 box2;
    vec4 box3;
    // Swellings on box0, the one a drop pours into: boxes taller than the
    // slab, where it bulges with what has come in. A width of zero is none.
    vec4 bulge0;
    vec4 bulge1;
    // How far each of box1..box3 reaches for the boxes before it (x unused).
    vec4 reaches;
    float lineWidth;
    // Straight (not premultiplied) alpha.
    vec4 fill;
    vec4 rimTop;
    vec4 rimBottom;
    // The slab's top and bottom: the rim's gradient runs between them, and
    // nothing is drawn above or below them.
    float rimFrom;
    float rimTo;
    // Whether the backdrop is there to be drawn. Zero is the plain translucent
    // fill, with Hyprland's blur doing the rest.
    float glass;
    // This item's top left on the backdrop, and the backdrop's size: the
    // backdrop is the strip of wallpaper behind the bar, laid out over it.
    vec2 origin;
    vec2 backdropSize;
    // How far in the glass looks at the very edge, and how far in from the
    // edge it bends at all.
    float bend;
    float bendDepth;
    // Blur radius, in pixels.
    float soften;
    float saturation;
    // How much of fill's colour is laid over what the glass shows.
    float tint;
    // How much less red bends, and how much more blue, than green does.
    float dispersion;
};

layout(binding = 1) uniform sampler2D backdrop;

float box(vec2 p, vec4 b) {
    if (b.z <= 0.0 || b.w <= 0.0)
        return 1e5;
    vec2 half_ = b.zw * 0.5;
    float r = min(half_.x, half_.y);
    vec2 q = abs(p - (b.xy + half_)) - half_ + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Polynomial smooth minimum: exactly min() wherever the two distances differ by
// more than k, so shapes further apart than their reach are drawn untouched. A reach
// of zero is a plain union: the workspace mark lets it fall to that at rest,
// where its two ends lie on top of each other and any reach would swell them.
float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// How far a bulge stands proud of the slab, above and below.
float swell(vec4 b) {
    return b.z > 0.0 ? max((b.w - (rimTo - rimFrom)) * 0.5, 0.0) : 0.0;
}

// How far p is outside the glass (negative inside).
float field(vec2 p) {
    // A bulge is blended in by as much as it stands out, so it grows out of
    // the slab from nothing and goes back into it without a jump.
    float s0 = swell(bulge0);
    float s1 = swell(bulge1);
    float k0 = min(8.0, s0 * 3.0);
    float k1 = min(8.0, s1 * 3.0);

    float d = box(p, box0);
    d = smin(d, box(p, bulge0), k0);
    d = smin(d, box(p, bulge1), k1);
    d = smin(d, box(p, box1), reaches.y);
    d = smin(d, box(p, box2), reaches.z);
    d = smin(d, box(p, box3), reaches.w);

    // The smooth minimum swells a join out in every direction, which made
    // the glass taller than a pill wherever two met, and only on top: the
    // bar's window ends at the slabs' bottom edge. Held to the slab's height,
    // so a join only ever fills out sideways. A bulge is let through, and
    // what its blend rounds it out by.
    float proud = max(s0 + k0 * 0.25, s1 + k1 * 0.25);
    return max(d, abs(p.y - (rimFrom + rimTo) * 0.5) - (rimTo - rimFrom) * 0.5 - proud);
}

// The wallpaper under p.
vec3 behind(vec2 p) {
    return texture(backdrop, (origin + p) / backdropSize).rgb;
}

// The same, averaged over a small ring round p.
vec3 softened(vec2 p) {
    vec3 c = behind(p) * 0.2;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853982;
        c += behind(p + soften * vec2(cos(a), sin(a))) * 0.1;
    }
    return c;
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
    float inner = clamp(0.5 - (d + lineWidth), 0.0, 1.0);
    float band = shape - inner;

    vec4 rim = mix(rimTop, rimBottom, clamp((p.y - rimFrom) / (rimTo - rimFrom), 0.0, 1.0));

    vec3 body = fill.rgb;
    float bodyA = fill.a * shape;
    if (glass > 0.0) {
        // Which way the edge nearest p faces, and how far in p is: the
        // nearer the edge, the further in towards the middle the glass
        // looks, easing off to nothing at bendDepth.
        vec2 n = normalize(vec2(field(p + vec2(0.5, 0.0)) - field(p - vec2(0.5, 0.0)),
                                field(p + vec2(0.0, 0.5)) - field(p - vec2(0.0, 0.5))) + 1e-6);
        float t = clamp(1.0 + d / bendDepth, 0.0, 1.0);
        vec2 shift = n * bend * t * t;
        vec3 c = vec3(softened(p - shift * (1.0 - dispersion)).r,
                      softened(p - shift).g,
                      softened(p - shift * (1.0 + dispersion)).b);
        c = clamp(mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, saturation), 0.0, 1.0);
        vec3 glassBody = mix(c, fill.rgb, tint);
        float alpha = mix(fill.a, 1.0, glass);
        body = mix(fill.rgb * fill.a, glassBody, glass) / max(alpha, 1e-6);
        bodyA = alpha * shape;
    }

    // Rim over the body, premultiplied.
    float rimA = rim.a * band;
    vec3 rgb = rim.rgb * rimA + body * bodyA * (1.0 - rimA);
    float a = rimA + bodyA * (1.0 - rimA);

    // The glass lays its antialiased edge over the wallpaper itself, opaque:
    // a part-covered pixel would otherwise let Hyprland's blur through, which
    // is darker than the wallpaper (brightness 0.8172), in a ragged ring
    // wherever the edge's coverage crosses the bar's ignore_alpha.
    rgb += behind(p) * (1.0 - a) * glass;
    a += (1.0 - a) * glass;

    fragColor = vec4(rgb, a) * qt_Opacity;
}
