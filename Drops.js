.pragma library

// The bar's drop geometry (see the note over clockLeft in Bar.qml), built
// against the live Theme so its numbers stay the theme's.
function geometry(theme) {
    // A drop gathered up: a little shorter than a pill, so the neck that
    // joins it to the neighbour is a neck and not a straight run of glass.
    const bead = Math.round(theme.barHeight * 0.8);

    // The glass starts gathering after this first part of leaving.
    const settle = 0.2;

    // A pill's share of the glass at a given `reveal`. `edge` is the
    // neighbour's facing edge, `dir` which way the pill lies from it (1 right,
    // -1 left), `width` the pill at rest, `leaving` whether it is on its way in.
    function drop(edge, dir, width, reveal, leaving) {
        if (reveal <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const t = 1 - reveal;
        const height = theme.barHeight;
        // How far this side of the neighbour's edge the pill's inner end is.
        let gap, w, h;
        if (leaving) {
            w = width + (bead - width) * ease((t - settle) / 0.3);
            h = Math.min(height, Math.max(bead, w));
            const squash = wobble((t - 0.42) / 0.3, 0.1);
            w *= 1 - squash;
            h *= 1 + squash / 2;
            const fall = Math.pow(Math.max(0, Math.min(1, (t - 0.5) / 0.2)), 2);
            // All the way in: the bead ends up inside the neighbour's round end.
            gap = theme.pillSpread - (theme.pillSpread + bead + 3) * fall;
        } else {
            const close = ease((t - 0.25) / 0.5);
            const plunge = ease((t - 0.65) / 0.35);
            const shrink = 1 - 0.3 * plunge;
            w = (height + (width - height) * spring((0.5 - t) / 0.36)) * shrink;
            h = height * shrink;
            gap = theme.pillSpread * (1 - close) - height * 1.6 * plunge;
        }
        const inner = edge + dir * gap;
        return Qt.vector4d(dir > 0 ? inner : inner - w, theme.barInset + (height - h) / 2, w, h);
    }

    // How far the neighbour's end is pushed out by a drop at a given
    // `reveal`. Going in, it is shoved out by the bead and wobbles back.
    // Letting go, it gives a little the other way.
    function lip(reveal, leaving) {
        if (theme.reduceMotion)
            return 0;
        const phase = leaving ? (0.38 - reveal) / 0.38 : (reveal - 0.55) / 0.3;
        const c = Math.max(0, Math.min(1, phase));
        // Ease into the impact and taper its rebound to rest without a snap.
        const envelope = ease(c / 0.18) * (1 - ease(c));
        return (leaving ? 5 : -3) * envelope * Math.exp(-3 * c) * Math.sin(2 * Math.PI * c);
    }

    // Where the neighbour's glass bulges, above and below, at the end a drop
    // goes into: once, as the bead goes in, a pixel or so proud of the slab.
    // `end` is the neighbour's end the drop is on, `dir` which way the drop
    // lies from it, as for `drop`.
    function bulge(end, dir, reveal, leaving) {
        const phase = (0.36 - reveal) / 0.12;
        if (theme.reduceMotion || !leaving || phase <= 0 || phase >= 1)
            return Qt.vector4d(0, 0, 0, 0);
        const swell = 1.2 * Math.pow(Math.sin(Math.PI * phase), 2);
        if (swell <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const w = theme.barHeight * 1.2;
        return Qt.vector4d(dir > 0 ? end - w : end, theme.barInset - swell, w, theme.barHeight + 2 * swell);
    }

    // How far a drop reaches for its neighbour. At rest, the air between
    // them, so the two are drawn exactly as they are. Going in, it lets go of
    // the neighbour's end once the bead is inside it, or the end swelled out
    // square against the top and bottom of the slab. Coming out, half again
    // as far while it is on the move, so the neck stretches before it lets
    // go, and back to the air by the time it is out.
    function dropReach(reveal, leaving) {
        if (leaving)
            return theme.pillSpread * (1 - 0.8 * ease((0.36 - reveal) / 0.08));
        const t = 1 - reveal;
        return theme.pillSpread * (1 + 0.5 * ease((t - 0.25) / 0.3) * (1 - ease((t - 0.8) / 0.2)));
    }

    // Fade across the whole gathering stage, reaching zero at the circle.
    // The contents and tracker follow the glass while they are still visible.
    function contents(reveal) {
        return ease((reveal - 0.5) / 0.5);
    }

    // A damped forward spring: lift, dip, smaller rebound, then settle.
    function iconScale(progress) {
        if (theme.reduceMotion)
            return 1;
        const c = Math.max(0, Math.min(1, progress));
        return 1 + 0.3 * ease(c / 0.08) * Math.exp(-3 * c) * Math.sin(3 * Math.PI * c)
            * (1 - ease((c - 0.8) / 0.2));
    }

    // Empty pills have no contents to fade before their glass starts leaving.
    function emptyReveal(reveal) {
        return reveal * (1 - settle);
    }

    function ease(x) {
        const c = Math.max(0, Math.min(1, x));
        return c * c * (3 - 2 * c);
    }

    // 0 to 1 the way a spring gets there: past it by about 13%, back a touch
    // short, and on it. Near the pill width spring (Theme.foldDamping).
    function spring(x) {
        if (x >= 1)
            return 1;
        const c = Math.max(0, x);
        return 1 - Math.exp(-6 * c) * Math.cos(3 * Math.PI * c);
    }

    // A wobble of `size` over 0..1, at rest at both ends: out, back past
    // rest, and out a little again.
    function wobble(x, size) {
        const c = Math.max(0, Math.min(1, x));
        return size * Math.exp(-3 * c) * Math.sin(3 * Math.PI * c);
    }

    // A music or timer pill turning into its popover (Popup.morphs): its glass
    // gathers into a drop and sinks through the slab's foot. Closing, the drop
    // comes back up and springs out to the pill. `s` is Morph.value, 0 the
    // pill, 1 the drop, 2 gone; a little under 0 as the pill springs past its
    // width on the way back.
    function morph(box, s) {
        if (s >= 2)
            return Qt.vector4d(0, 0, 0, 0);
        if (s === 0 || box.z <= 0)
            return box;
        const gather = Math.min(1, s);
        const sink = Math.max(0, (s - 0.5) / 1.5);
        const mid = box.x + box.z / 2;
        const w = box.z + (theme.barHeight * 1.3 - box.z) * gather;
        return Qt.vector4d(mid - w / 2, box.y + box.w * sink, w, box.w);
    }

    // How much of a pill's contents show as it does: gone by halfway to the
    // drop, and back in as it springs out.
    function morphContents(s) {
        return Math.max(0, Math.min(1, 1 - 2 * s));
    }

    return { drop, lip, bulge, dropReach, contents, iconScale, emptyReveal, morph, morphContents };
}
