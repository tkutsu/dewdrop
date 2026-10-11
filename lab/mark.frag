#version 440

// The workspace mark as a bead of glass (lab/MarkScene.qml, variant A): a
// capsule over `source`, the pill and its icons as drawn without the mark,
// seen through glass that leaves the middle nearly true and pulls hard round
// the rim. `clear` runs from the mark at rest (0), a capsule inside the pill
// with a breath of white, to the bead (1), taller than the pill and clear.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o mark.frag.qsb mark.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // The capsule: x, y, width, height, fully round at the ends.
    vec4 box;
    float clear;
    // How far in the very rim looks, in pixels; how far in from the rim the
    // pull reaches, as a share of the half height; how steeply it falls off
    // towards the middle; and how much the middle is magnified.
    float bend;
    float depth;
    float steep;
    float zoom;
    float dispersion;
    // The white laid in the glass at rest and as a bead.
    float restTint;
    float beadTint;
};

layout(binding = 1) uniform sampler2D source;

float capsule(vec2 p) {
    vec2 h = box.zw * 0.5;
    float r = min(h.x, h.y);
    vec2 q = abs(p - (box.xy + h)) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 under(vec2 p) {
    return texture(source, p / size);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec4 below = under(p);
    float d = capsule(p);
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0 || box.z <= 0.0) {
        fragColor = below * qt_Opacity;
        return;
    }

    vec2 n = normalize(vec2(capsule(p + vec2(0.5, 0.0)) - capsule(p - vec2(0.5, 0.0)),
                            capsule(p + vec2(0.0, 0.5)) - capsule(p - vec2(0.0, 0.5))) + 1e-6);
    float reach = max(min(box.z, box.w) * 0.5 * depth, 1.0);
    float lens = pow(clamp(1.0 + d / reach, 0.0, 1.0), steep);
    vec2 centre = box.xy + box.zw * 0.5;
    vec2 seen = centre + (p - centre) / mix(1.0, zoom, clear);
    vec2 shift = n * bend * lens;
    vec4 glass = vec4(under(seen - shift * (1.0 - dispersion)).r,
                      under(seen - shift).g,
                      under(seen - shift * (1.0 + dispersion)).b,
                      under(seen - shift).a);
    // Glass over the wallpaper beyond the pill is seen as glass too.
    glass.a = 1.0;
    float white = mix(restTint, beadTint, clear) + 0.18 * lens * clear;
    glass.rgb = mix(glass.rgb, vec3(1.0), white);
    // The rim: a pixel, lit from the top left and faint round the far side,
    // brighter as a bead.
    float band = shape - clamp(0.5 - (d + 1.0), 0.0, 1.0);
    float lit = mix(0.22, 0.3, clear) + mix(0.1, 0.45, clear) * max(dot(-n, normalize(vec2(1.0, 1.0))), 0.0);
    glass.rgb = mix(glass.rgb, vec3(1.0), band * lit);

    fragColor = mix(below, glass, shape) * qt_Opacity;
}
