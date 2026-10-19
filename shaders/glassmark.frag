#version 440

// Grey workspace glass: the straight middle stays undistorted while the
// rounded caps bend the pill's glass beneath them, and the icons too while
// the mark is on its way.
// Compiled with: /usr/lib/qt6/bin/qsb --qt6 -o glassmark.frag.qsb glassmark.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    // The capsule: x, y, width, height, fully round at the ends.
    vec4 box;
    // How far in the very rim looks, in pixels; how far in from the rim the
    // pull reaches, as a share of the half height; how steeply it falls off
    // towards the middle of each rounded end.
    float bend;
    float depth;
    float steep;
    float dispersion;
    // Grey tint, cleared a little as the glass lifts.
    float tint;
    // How far the caps bend the icons along with the glass, 0..1.
    float refract;
    vec3 tintColor;
    float lineWidth;
    vec4 rimTop;
    vec4 rimBottom;
    vec4 sheen;
    // Where the wallpaper's texture lies in this item, and its size.
    vec2 wallOrigin;
    vec2 wallSize;
};

// The wallpaper, the pill's glass, and what the pill holds, laid out as
// this item is.
layout(binding = 1) uniform sampler2D wallpaper;
layout(binding = 2) uniform sampler2D slab;
layout(binding = 3) uniform sampler2D ink;

float capsule(vec2 p) {
    vec2 h = box.zw * 0.5;
    float r = min(h.x, h.y);
    vec2 q = abs(p - (box.xy + h)) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The pill's glass over the wallpaper, and the icons over that.
vec3 under(vec2 p) {
    vec3 wall = texture(wallpaper, (p - wallOrigin) / wallSize).rgb;
    vec4 c = texture(slab, p / size);
    return wall * (1.0 - c.a) + c.rgb;
}

vec3 inked(vec3 under, vec2 p) {
    vec4 c = texture(ink, p / size);
    return under * (1.0 - c.a) + c.rgb;
}

// Both, the icons pulled `refract` as far as the glass.
vec3 seenAt(vec2 p, vec2 shift) {
    return inked(under(p - shift), p - shift * refract);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float d = capsule(p);
    float shape = clamp(0.5 - d, 0.0, 1.0);
    if (shape <= 0.0 || box.z <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 around = (p - box.xy - box.zw * 0.5) / max(box.zw * 0.5, vec2(1.0));
    float diagonal = abs(dot(normalize(around + 1e-6), normalize(sheen.xy)));
    float shine = smoothstep(sheen.z, 0.96, diagonal);

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
    vec3 bent = vec3(seenAt(seen, shift * (1.0 - dispersion)).r,
                     seenAt(seen, shift).g,
                     seenAt(seen, shift * (1.0 + dispersion)).b);
    vec3 glass = mix(bent, tintColor, tint);
    float band = shape - clamp(0.5 - (d + lineWidth), 0.0, 1.0);
    vec4 rim = sheen.w > 0.0 ? vec4(rimTop.rgb, mix(rimBottom.a * 0.35, sheen.w, shine))
        : mix(rimTop, rimBottom, clamp((p.y - box.y) / max(box.w, 1.0), 0.0, 1.0));
    // Apply coverage once, after the body is laid over the underlying pill.
    vec3 covered = mix(inked(under(p), p), glass, shape);
    covered = mix(covered, rim.rgb, band * rim.a);

    // Opaque, the antialiased edge laid over what is under it: a part-covered
    // pixel would let Hyprland's blur through, which is darker than the
    // wallpaper, in a ring round the mark.
    fragColor = vec4(covered, 1.0) * qt_Opacity;
}
