#version 440

// Lab: a slider whose knob turns into a bead of glass while it is held.
// Draws the whole slider from `source`, the track rendered on its own: as it
// is outside the bead, and seen through it inside, bent in at the rim the way
// shaders/liquid.frag bends the wallpaper and magnified towards the middle.
// `clear` runs from the solid knob (0) to the bead (1), so the glass comes
// on as the knob is taken hold of rather than fading in finished.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // The knob or bead: x, y, width, height, drawn as a capsule.
    vec4 bead;
    float clear;
    // How far in the rim looks, in pixels, and how much the middle magnifies.
    float bend;
    float magnify;
    float dispersion;
    vec4 knob;
    vec4 knobEdge;
};

layout(binding = 1) uniform sampler2D source;

float capsule(vec2 p) {
    vec2 half_ = bead.zw * 0.5;
    float r = min(half_.x, half_.y);
    vec2 q = abs(p - (bead.xy + half_)) - half_ + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 track(vec2 p) {
    return texture(source, p / size);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec4 under = track(p);
    float d = capsule(p);
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0 || bead.z <= 0.0) {
        fragColor = under * qt_Opacity;
        return;
    }

    vec2 n = normalize(vec2(capsule(p + vec2(0.5, 0.0)) - capsule(p - vec2(0.5, 0.0)),
                            capsule(p + vec2(0.0, 0.5)) - capsule(p - vec2(0.0, 0.5))) + 1e-6);
    float depth = min(bead.z, bead.w) * 0.5;
    float t = clamp(1.0 + d / depth, 0.0, 1.0);
    float lens = 1.0 - sqrt(1.0 - t * t);
    // Magnified most in the middle and not at all at the rim, as a bead of
    // glass is thickest in the middle: the track swells through it.
    vec2 centre = bead.xy + bead.zw * 0.5;
    vec2 q = (p - centre) / (bead.zw * 0.5);
    float m = mix(magnify, 1.0, clamp(dot(q, q), 0.0, 1.0));
    vec2 seen = centre + (p - centre) / m;
    vec2 shift = n * bend * lens;
    vec4 glass = vec4(track(seen - shift * (1.0 - dispersion)).r,
                      track(seen - shift).g,
                      track(seen - shift * (1.0 + dispersion)).b,
                      track(seen - shift).a);
    // A breath of white in the body, and more of it where the rim bends.
    float body = 0.05 + 0.25 * lens;
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
