#version 440

// Grey workspace glass: the straight middle stays undistorted while the
// rounded caps bend the pill's glass beneath them, the icons seen straight
// through. As clear glass (wholeRim) it looks most of the way through the
// pill to the sharp wallpaper; whatever bend it is given runs round the whole
// edge and lights the rim. The icons are magnified evenly, and curve only
// sideways round the caps: pulled along the bend they stretch tall and break up.
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
    // 0 bends the round caps only, 1 the whole rim; how much brighter the
    // glass gets where it bends.
    float wholeRim;
    float glow;
    // How much larger the icons are seen through clear glass.
    float magnify;
    // Grey tint, cleared a little by movement and held presses.
    float tint;
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

vec3 wall(vec2 p) {
    return texture(wallpaper, (p - wallOrigin) / wallSize).rgb;
}

// The pill's glass over the wallpaper.
vec3 under(vec2 p) {
    vec4 c = texture(slab, p / size);
    return wall(p) * (1.0 - c.a) + c.rgb;
}

// What the mark's own glass bends.
vec3 behind(vec2 p) {
    return mix(under(p), wall(p), wholeRim * 0.7);
}

vec3 inked(vec3 under, vec2 p) {
    vec4 c = texture(ink, p / size);
    return under * (1.0 - c.a) + c.rgb;
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
    lens *= mix(cap, 1.0, wholeRim);
    vec2 seen = p;
    // Never past the mark's middle line, where the two rims would cross.
    float pull = bend * lens;
    vec2 shift = n * mix(pull, min(pull, max(0.0, 0.85 * (radius + d))), wholeRim);
    vec3 bent = vec3(behind(seen - shift * (1.0 - dispersion)).r,
                     behind(seen - shift).g,
                     behind(seen - shift * (1.0 + dispersion)).b);
    bent = min(bent * (1.0 + glow * lens), 1.0);
    vec2 inkAt = mix(p, centre + (p - centre) / (1.0 + magnify) - vec2(n.x * pull * 0.1, 0.0), wholeRim);
    vec3 glass = mix(inked(bent, inkAt), tintColor, tint);
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
