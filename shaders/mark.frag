#version 440

// The workspace mark as a bead of glass (components/BeadMark.qml): a capsule
// over the left pill and the wallpaper round it, seen through glass that
// keeps the straight middle undistorted and bends only the round ends. `clear` runs
// from the mark at rest (0), a capsule inside the pill with a breath of
// white, to the bead (1) it swells into on the move, as tall as the bar's
// window and clear.
//
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o mark.frag.qsb mark.frag
// A hot reload keeps drawing with the shader it already loaded, so restart
// Quickshell after recompiling.

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
    // towards the middle of each rounded end.
    float bend;
    float depth;
    float steep;
    float dispersion;
    // The tint laid in the glass at rest and while moving.
    float restTint;
    float beadTint;
    vec3 tintColor;
    float lineWidth;
    vec4 rimTop;
    vec4 rimBottom;
    vec4 sheen;
    // Where the wallpaper's texture lies in this item, and its size.
    vec2 wallOrigin;
    vec2 wallSize;
};

// The wallpaper, and the pill drawn without the mark over it, laid out as
// this item is.
layout(binding = 1) uniform sampler2D wallpaper;
layout(binding = 2) uniform sampler2D pill;

float capsule(vec2 p) {
    vec2 h = box.zw * 0.5;
    float r = min(h.x, h.y);
    vec2 q = abs(p - (box.xy + h)) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 under(vec2 p) {
    vec3 wall = texture(wallpaper, (p - wallOrigin) / wallSize).rgb;
    vec4 c = texture(pill, p / size);
    return wall * (1.0 - c.a) + c.rgb;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = capsule(p);
    float shape = clamp(0.5 - d, 0.0, 1.0);
    vec2 around = (p - box.xy - box.zw * 0.5) / max(box.zw * 0.5, vec2(1.0));
    float diagonal = abs(dot(normalize(around + 1e-6), normalize(sheen.xy)));
    float shine = smoothstep(sheen.z, 0.96, diagonal);
    if (shape <= 0.0 || box.z <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 n = normalize(vec2(capsule(p + vec2(0.5, 0.0)) - capsule(p - vec2(0.5, 0.0)),
                            capsule(p + vec2(0.0, 0.5)) - capsule(p - vec2(0.0, 0.5))) + 1e-6);
    float reach = max(min(box.z, box.w) * 0.5 * depth, 1.0);
    float lens = pow(clamp(1.0 + d / reach, 0.0, 1.0), steep);
    vec2 centre = box.xy + box.zw * 0.5;
    // Fade the bend in beyond the straight section, keeping its contents
    // at their original coordinates even along the top and bottom edges.
    float radius = min(box.z, box.w) * 0.5;
    float cap = smoothstep(0.0, max(radius * 0.35, 1.0), abs(p.x - centre.x) - (box.z * 0.5 - radius));
    lens *= cap;
    vec2 seen = p;
    vec2 shift = n * bend * lens;
    vec3 glass = vec3(under(seen - shift * (1.0 - dispersion)).r,
                      under(seen - shift).g,
                      under(seen - shift * (1.0 + dispersion)).b);
    float white = mix(restTint, beadTint, clear) + 0.18 * lens * clear;
    glass = mix(glass, tintColor, white);
    float band = shape - clamp(0.5 - (d + lineWidth), 0.0, 1.0);
    vec4 rim = sheen.w > 0.0 ? vec4(rimTop.rgb, mix(rimBottom.a * 0.35, sheen.w, shine))
        : mix(rimTop, rimBottom, clamp((p.y - box.y) / max(box.w, 1.0), 0.0, 1.0));
    // Apply coverage once, after the body is laid over the underlying pill.
    vec3 covered = mix(under(p), glass, shape);
    covered = mix(covered, rim.rgb, band * rim.a);

    // Opaque, the antialiased edge laid over what is under it: a part-covered
    // pixel would let Hyprland's blur through, which is darker than the
    // wallpaper, in a ring round the bead.
    fragColor = vec4(covered, 1.0) * qt_Opacity;
}
