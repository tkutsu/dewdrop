import QtQuick
import qs
import qs.services

// One text primitive for the whole bar, carrying the vertical nudge that puts
// each glyph on a shared optical baseline. It used to carry style.css's 1px
// drop shadow too; that went with the move to the system's own idiom, where a
// label is never shadowed and the material under it is what earns its
// contrast.
//
// Everything it reports is rounded to a whole pixel. A fractional width here
// pushes every module to its right onto a half pixel, and a glyph drawn on a
// half pixel is a blurred glyph.
Item {
    id: root

    property alias text: metrics.text
    property int fontSize: Theme.textSize
    property string family: Theme.bodyFont
    property int weight: Theme.bodyWeight
    property color color: Theme.fg
    property color inkColor: Theme.barInk(root, root.color)

    Behavior on inkColor {
        ColorAnimation { duration: Theme.fadeMs; easing.type: Easing.InOutQuad }
    }

    // config.jsonc nudged every icon with a hand-picked Pango `rise` because the
    // Material Design glyphs sit high in a font box sized for Latin text. QML
    // has no `rise`, so instead measure the glyph's ink and centre that. Same
    // intent, no magic number per icon, and it survives a font or size change.
    property bool opticalCentre: false
    property real nudge: 0

    // Measure the ink rather than the advance width. Nerd Font icons carry wildly
    // different side bearings, so laying them out by advance leaves invisible
    // padding that varies per icon — which is why the gaps between modules never
    // looked even. Text keeps its advance, so a clock does not jitter as its
    // digits change.
    property bool tightWidth: false

    // Where the ink really is. The font's tightBoundingRect is the outline's
    // box; the rasteriser then hints the strokes onto whole rows and columns,
    // and at bar sizes the pixels land a row or two from where the outline
    // said — which is why a row of glyphs each centred on its own metrics
    // still stepped up and down by a pixel. So once drawn, the glyph is
    // grabbed and scanned (InkProbe), and from then on it is placed by what
    // the scan found. Until the scan comes back it sits where the metrics put
    // it, which is within a pixel or two, so nothing jumps on load.
    //
    // Only for what is centred or measured on ink; text laid out on its
    // advance and cap height is left to the metrics, which are what a run of
    // text should be laid out on.
    readonly property bool probed: opticalCentre || tightWidth
    readonly property string inkKey: GlyphInk.keyOf(root.family, root.weight, root.fontSize, shown.text)
    readonly property var inked: probed ? GlyphInk.boundsOf(inkKey) : null

    // Room around the drawn text so the grab catches ink that hangs outside
    // the advance box — a Nerd Font glyph with a negative side bearing, a
    // descender past the line box. Given to the Text as padding and taken
    // back off its position, so the ink lands exactly where it did before.
    readonly property int inkPad: 4

    // A ceiling, for the one kind of text on the bar that does not come from
    // the bar: a song title, which can be any length and arrives at whatever
    // one someone else chose. Past it the line elides instead of pushing its
    // neighbours along every time the track changes. 0 is no ceiling.
    property int maxWidth: 0

    implicitWidth: {
        if (tightWidth && inked)
            return inked.right - inked.left + 1;
        return tightWidth && _ink.width > 0 ? Math.ceil(_ink.width) : Math.ceil(shown.advanceWidth);
    }
    implicitHeight: Theme.barHeight
    baselineOffset: _y + fm.ascent

    TextMetrics {
        id: metrics
        font.family: root.family
        font.pixelSize: root.fontSize
        font.weight: root.weight
        // Tabular figures everywhere on the bar, so nothing that counts —
        // the clock, a timer, a song's position — changes width as it does.
        font.features: Theme.figures
        elide: root.maxWidth > 0 ? Text.ElideRight : Text.ElideNone
        elideWidth: root.maxWidth
    }

    // What is actually drawn, measured in its own right: an elided string is
    // shorter than the one it was cut from, and reserving the full ceiling for
    // it would leave a gap the width of everything that got cut.
    TextMetrics {
        id: shown
        font: metrics.font
        text: root.maxWidth > 0 ? metrics.elidedText : metrics.text
    }

    FontMetrics {
        id: fm
        font: metrics.font
    }

    readonly property rect _ink: metrics.tightBoundingRect
    readonly property real _x: {
        if (root.tightWidth && inked)
            return inkPad - inked.left;
        return root.tightWidth && _ink.width > 0 ? Math.round(-_ink.x) : 0;
    }
    // Both branches centre on ink rather than on the font box, which is what
    // the Pango `rise` values in config.jsonc were approximating by hand. Text
    // uses the cap height so a string does not hop about as its letters change;
    // glyphs measure their own ink, because a Material Design icon can sit
    // anywhere inside a font box sized for Latin text.
    readonly property real _y: {
        // Measured: put the ink's first row where a box of its height sits
        // centred in ours. Ceil rather than round, so an even ink in an odd
        // slab always lands the same half-pixel low rather than sometimes
        // high — one rule for the whole row, which is what makes it a row.
        if (root.opticalCentre && inked)
            return Math.ceil((root.height - (inked.bottom - inked.top + 1)) / 2) - inked.top + inkPad + root.nudge;
        return Math.round(root.opticalCentre && _ink.height > 0
            // tightBoundingRect is relative to the baseline, which a Text item
            // puts at `ascent` below its own top — hence the shift back out.
            ? (root.height - _ink.height) / 2 - fm.ascent - _ink.y + root.nudge
            : (root.height + fm.capitalHeight) / 2 - fm.ascent + root.nudge);
    }

    Text {
        id: drawn

        x: root._x - root.inkPad
        y: root._y - root.inkPad
        padding: root.inkPad
        text: shown.text
        font: metrics.font
        color: root.inkColor
    }

    // Measure once per glyph, the first time it is drawn anywhere; every
    // other copy reads the cache. Grabbed at the Text's own size so the scan
    // is in real pixels, not a scaled copy of them.
    Loader {
        active: root.probed && root.inked === null && shown.text !== "" && root.visible

        sourceComponent: InkProbe {
            target: drawn
            width: Math.ceil(drawn.width)
            height: Math.ceil(drawn.height)
            ready: true
            onBounds: (top, bottom, left, right) => GlyphInk.remember(root.inkKey, top, bottom, left, right)
        }
    }
}
