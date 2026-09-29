#version 440

// The pills around the clock as one piece of glass (see components/Liquid.qml).
// Each pill is a rounded box; the boxes are joined with a smooth minimum, so two
// that come within reach of each other grow a neck between them and one that
// moves inside another is absorbed rather than overlapped. Drawn as one shape,
// so the translucent fill never doubles up where two of them meet.
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
    // How much of a lip the glass has, 0..1 (see main). None is the plain
    // rim, lit top to bottom, that a Pill's Rim draws.
    float lip;
};

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

// The glass's edge, as a distance: negative inside, positive outside.
float glass(vec2 p) {
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

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = glass(p);

    // Which way the edge faces, from the distance's slope. Worked out by
    // hand rather than with dFdx/dFdy, whose y runs whichever way the
    // target does.
    vec2 n = vec2(glass(p + vec2(0.5, 0.0)) - glass(p - vec2(0.5, 0.0)),
                  glass(p + vec2(0.0, 0.5)) - glass(p - vec2(0.0, 0.5)));
    n = length(n) > 0.0 ? normalize(n) : vec2(0.0, -1.0);

    // The plain rim is lit by height, bright along the top and fading by the
    // bottom, the way Rim.qml draws it. Glass with a lip is lit from straight
    // above instead (y runs down): an edge takes the light by as much as it
    // faces up, the top in full and the round ends by how far they turn
    // towards it. Wide enough that an end facing sideways keeps about the
    // light the plain rim gave it, so the outline holds on a dark wallpaper.
    vec4 plain = mix(rimTop, rimBottom, clamp((p.y - rimFrom) / (rimTo - rimFrom), 0.0, 1.0));
    vec4 lit = mix(rimBottom, rimTop, smoothstep(-0.6, 0.9, -n.y));
    vec4 rim = mix(plain, lit, lip);

    // A pixel of antialiasing across the edge, and the same across the rim's
    // inner edge, so the rim is the band between the two.
    float shape = clamp(0.5 - d, 0.0, 1.0);
    float inner = clamp(0.5 - (d + lineWidth), 0.0, 1.0);
    float band = shape - inner;

    // The lip: the rim's light carried a few pixels in and dying away, so
    // the edge reads as a rounded piece of glass and not a drawn line.
    float depth = max(-d - lineWidth, 0.0);
    float glowA = lip * rim.a * inner * exp(-depth / 3.5);

    // Fill, then the glow over it, then the rim over both, premultiplied.
    float a = fill.a * shape;
    vec3 rgb = fill.rgb * a;
    rgb = rim.rgb * glowA + rgb * (1.0 - glowA);
    a = glowA + a * (1.0 - glowA);
    float rimA = rim.a * band;
    rgb = rim.rgb * rimA + rgb * (1.0 - rimA);
    a = rimA + a * (1.0 - rimA);

    fragColor = vec4(rgb, a) * qt_Opacity;
}
