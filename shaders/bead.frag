#version 440

// A slider whose knob turns into a bead of glass while it is held
// (components/Slider.qml). Draws the whole slider from `source`, the track
// rendered on its own: as it is outside the bead, and seen through it inside,
// where the glass leaves the middle true and pulls hard round the rim, so the
// track curls round the inside of the rim the way it does under a drop of
// water. `clear` runs from the solid knob (0) to the bead (1), so the glass
// comes on as the knob is taken hold of rather than fading in finished.
//
// The bead is a circle centred on the knob.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o bead.frag.qsb bead.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // Centre and radius: head (x, y, r).
    vec4 head;
    float clear;
    // How far in the very rim looks, in pixels; how far in from the rim the
    // pull reaches, as a share of the radius; and how steeply it falls off
    // towards the middle (1 is a straight ramp, higher keeps it to the rim).
    float bend;
    float depth;
    float steep;
    // How much less red bends, and how much more blue, than green does.
    float dispersion;
    // The solid knob's fill and edge, straight alpha.
    vec4 knob;
    vec4 knobEdge;
};

layout(binding = 1) uniform sampler2D source;

// Distance to the bead's circular edge.
float drop(vec2 p) {
    return length(p - head.xy) - head.z;
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
    float lens = pow(clamp(1.0 + d / reach, 0.0, 1.0), steep);
    vec2 shift = n * bend * lens;
    vec4 glass = vec4(track(p - shift * (1.0 - dispersion)).r,
                      track(p - shift).g,
                      track(p - shift * (1.0 + dispersion)).b,
                      track(p - shift).a);
    // A breath of white in the body, and more of it where the rim pulls.
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
