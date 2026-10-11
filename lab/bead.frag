#version 440

// Lab: a slider whose knob turns into a bead of glass while it is held.
// Draws the whole slider from `source`, the track rendered on its own: as it
// is outside the bead, and seen through it inside, where the glass leaves the
// middle nearly true and bends hard round the rim, the way a drop of water
// does (reel 4). `clear` runs from the solid knob (0) to the bead (1), so the
// glass comes on as the knob is taken hold of rather than fading in finished.
//
// The bead is a head where the knob is and a tail that trails it, joined
// into one teardrop (an uneven capsule); with the tail on the head it is
// round.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // Centres and radii: head (x, y, r) and tail (x, y, r).
    vec4 head;
    vec4 tail;
    float clear;
    // How far in the very rim looks, in pixels; how far in from the rim the
    // bend reaches, as a share of the radius; and how steeply it falls off
    // from the rim (1 is a straight ramp, higher keeps it to the rim).
    float bend;
    float depth;
    float steep;
    float magnify;
    float dispersion;
    vec4 knob;
    vec4 knobEdge;
};

layout(binding = 1) uniform sampler2D source;

// Distance to two circles and the hull between them (iq's uneven capsule).
float drop(vec2 p) {
    vec2 axis = tail.xy - head.xy;
    float h = length(axis);
    float r1 = head.z, r2 = tail.z;
    if (h < abs(r1 - r2) + 1e-3)
        return min(length(p - head.xy) - r1, length(p - tail.xy) - r2);
    vec2 u = axis / h;
    vec2 q = vec2(abs(dot(p - head.xy, vec2(-u.y, u.x))), dot(p - head.xy, u));
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(q, vec2(-b, a));
    if (k < 0.0)
        return length(q) - r1;
    if (k > a * h)
        return length(q - vec2(0.0, h)) - r2;
    return dot(q, vec2(a, b)) - r1;
}

vec4 track(vec2 p) {
    return texture(source, p / size);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec4 under = track(p);
    float d = drop(p);
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0 || head.z <= 0.0) {
        fragColor = under * qt_Opacity;
        return;
    }

    vec2 n = normalize(vec2(drop(p + vec2(0.5, 0.0)) - drop(p - vec2(0.5, 0.0)),
                            drop(p + vec2(0.0, 0.5)) - drop(p - vec2(0.0, 0.5))) + 1e-6);
    float reach = max(head.z * depth, 1.0);
    float t = clamp(1.0 + d / reach, 0.0, 1.0);
    float lens = pow(t, steep);
    vec2 centre = head.xy;
    vec2 seen = centre + (p - centre) / magnify;
    vec2 shift = n * bend * lens;
    vec4 glass = vec4(track(seen - shift * (1.0 - dispersion)).r,
                      track(seen - shift).g,
                      track(seen - shift * (1.0 + dispersion)).b,
                      track(seen - shift).a);
    // A breath of white in the body, and more of it where the rim bends.
    float body = 0.04 + 0.22 * lens;
    glass = glass * (1.0 - body) + vec4(body);
    // The rim: a pixel, lit from the top left and faint round the far side.
    float band = shape - clamp(0.5 - (d + 1.0), 0.0, 1.0);
    float lit = 0.25 + 0.45 * max(dot(-n, normalize(vec2(1.0, 1.0))), 0.0);
    glass = mix(glass, vec4(1.0), band * lit);

    // The solid knob, with its edge.
    vec4 solid = mix(knob, knobEdge, band);
    solid = vec4(solid.rgb * solid.a, solid.a);

    vec4 inside = mix(solid, glass, clear);
    fragColor = mix(under, inside, shape) * qt_Opacity;
}
