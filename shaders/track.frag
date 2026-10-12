#version 440

// The same rounded-box edge as Liquid, with clockwise progress from nine o'clock.
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o track.frag.qsb track.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec2 slabSize;
    float lineWidth;
    float played;
    vec4 ink;
    float rest;
    float foot;
};

void main() {
    vec2 p = qt_TexCoord0 * size;
    // A pixel of room around the slab, matching the glass's pixel-centred coverage.
    p -= vec2(1.0);
    vec2 halfSize = slabSize * 0.5;
    float r = min(halfSize.x, halfSize.y);
    vec2 q = abs(p - halfSize) - halfSize + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float shape = clamp(0.5 - d, 0.0, 1.0);
    float band = shape - clamp(0.5 - d - lineWidth, 0.0, 1.0);

    float radius = max(r - lineWidth * 0.5, 0.001);
    float straight = max(slabSize.x - 2.0 * r, 0.0);
    const float pi = 3.14159265;
    float perimeter = 2.0 * straight + 2.0 * pi * radius;
    float travel;
    if (p.x < r) {
        float angle = atan(p.y - halfSize.y, p.x - r);
        travel = p.y < halfSize.y ? radius * (angle + pi)
            : 2.0 * straight + radius * (angle + pi);
    } else if (p.x > slabSize.x - r) {
        float angle = atan(p.y - halfSize.y, p.x - (slabSize.x - r));
        travel = straight + radius * (angle + pi);
    } else {
        travel = p.y < halfSize.y ? pi * radius * 0.5 + p.x - r
            : pi * radius * 1.5 + straight + slabSize.x - r - p.x;
    }
    float lit = clamp(played, 0.0, 1.0) * perimeter;
    float coverage = band;
    if (travel > lit) {
        // Round the moving tip and the origin, keeping both inside the glass.
        float gap = min(travel - lit, perimeter - travel);
        float tip = length(vec2(d + lineWidth * 0.5, gap)) - lineWidth * 0.5;
        coverage = min(shape, clamp(0.5 - tip, 0.0, 1.0));
    }
    if (played <= 0.0) coverage = 0.0;
    float alpha = max(band * rest, coverage) * ink.a;
    alpha *= mix(1.0, foot, clamp((p.y + 1.0) / size.y, 0.0, 1.0));
    fragColor = vec4(ink.rgb * alpha, alpha) * qt_Opacity;
}
