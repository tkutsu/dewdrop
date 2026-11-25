import QtQuick
import QtQuick.Shapes

// The speaker, drawn rather than cut out of the font: Material's
// volume_high, measured and set on whole pixels, its two waves lit one after
// the other as the volume rises, so every level stands the same size and only
// the light moves. Muted lights everything and strikes it through, the way
// volume_off does.
//
// Glyph draws one for any Theme.glyph entry spelled "volume:<level>" or
// "volume:muted", so every place that shows a glyph can show this too.
//
// The body's straight edges fall on pixel edges, so it comes out sharp
// where the font's, scaled to the glyph size, landed between pixels.
Item {
    id: root

    // Audio.level's steps, 0 to 6, or -1 muted.
    property int level: 6
    // The height of the ink, top of the outer wave to its foot.
    property int size: 12
    property color color: "white"

    // Designed 12px tall, the font's speaker at the bar's glyph size.
    readonly property real unit: size / 12
    // As thin as the Wi-Fi fan's arcs at the same height.
    readonly property real stroke: 1.5 * size / 13
    readonly property real centreY: size / 2

    // The body: a box for the magnet, then the cone flaring out at 45°.
    readonly property int neckTop: Math.round(centreY - 2 * unit)
    readonly property int mouthTop: Math.round(centreY - 5 * unit)
    readonly property int neck: Math.round(3 * unit)
    readonly property int mouth: neck + neckTop - mouthTop
    readonly property var body: [
        Qt.point(0, neckTop), Qt.point(neck, neckTop), Qt.point(mouth, mouthTop),
        Qt.point(mouth, size - mouthTop), Qt.point(neck, size - neckTop), Qt.point(0, size - neckTop)
    ]

    // Both waves stand on one upright, a gap clear of the mouth.
    readonly property real waveX: mouth + 1.4 * unit
    readonly property real outerReach: 4.6 * unit

    implicitHeight: size
    implicitWidth: Math.ceil(waveX + outerReach)

    // Half an ellipse on the upright, top to foot, in enough steps to read
    // as a curve at these sizes.
    function halfEllipse(radiusX: real, radiusY: real): var {
        const steps = 16;
        return Array.from({ length: steps + 1 }, (_, step) => {
            const angle = Math.PI * (step / steps - 0.5);
            return Qt.point(waveX + radiusX * Math.cos(angle), centreY + radiusY * Math.sin(angle));
        });
    }

    // The inner wave is a half-moon; the outer, a thin arc from the top of
    // the ink to its foot.
    readonly property var inner: halfEllipse(1.7 * unit, 2.75 * unit)
    readonly property var outer: halfEllipse(outerReach, centreY)
        .concat(halfEllipse(outerReach - stroke, centreY - stroke).reverse())

    // Part 0 is the body, 1 the inner wave, 2 the outer. Each wave comes up
    // from a quarter over three steps, the inner one first. Muted lights
    // them all, and the slash says they are silent.
    readonly property bool muted: level < 0
    function ink(part: int): color {
        const steps = part === 0 || muted ? 3 : Math.min(3, Math.max(0, level - 3 * (part - 1)));
        return Qt.rgba(color.r, color.g, color.b, color.a * (0.25 + 0.25 * steps));
    }

    // The slash runs corner to corner at 45°. Every part is cut a gap clear
    // of its upper side; below, it runs into the slash, as in volume_off.
    readonly property real slashLift: 0.15 * unit
    readonly property real slashGap: 1.2 * unit
    function below(point: point): real {
        return (point.y - point.x + slashLift) * Math.SQRT1_2;
    }
    function aboveGap(point: point): real {
        return -below(point) - stroke / 2 - slashGap;
    }
    // Its square ends far enough in that their corners stay in the box.
    readonly property var slash: {
        const half = stroke * Math.SQRT1_2 / 2;
        const start = Qt.point(half + slashLift, half);
        const end = Qt.point(size - half + slashLift, size - half);
        return [Qt.point(start.x + half, start.y - half), Qt.point(end.x + half, end.y - half),
            Qt.point(end.x - half, end.y + half), Qt.point(start.x - half, start.y + half)];
    }

    // The part of a polygon where side(point) >= 0 (Sutherland–Hodgman
    // against one line). Where one side holds two pieces of the outer wave,
    // they come out joined by an edge along the line and back, which fills
    // nothing.
    function clip(points: var, side: var): var {
        const kept = [];
        points.forEach((a, index) => {
            const b = points[(index + 1) % points.length];
            const sa = side(a);
            const sb = side(b);
            if (sa >= 0)
                kept.push(a);
            if ((sa >= 0) !== (sb >= 0)) {
                const t = sa / (sa - sb);
                kept.push(Qt.point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)));
            }
        });
        return kept;
    }

    // What is filled: each part whole, or muted, each cut in two along the
    // slash, then the slash.
    readonly property var pieces: {
        const parts = [body, inner, outer].map((points, part) => ({ points, ink: ink(part) }));
        if (!muted)
            return parts;
        const cut = [];
        for (const part of parts) {
            for (const side of [below, aboveGap])
                cut.push({ points: clip(part.points, side), ink: part.ink });
        }
        return cut.concat([{ points: slash, ink: ink(0) }]);
    }

    // A slot for every piece muted can have, so a change of level relights
    // them rather than making them again.
    Repeater {
        model: 7

        Shape {
            id: piece
            required property int index
            readonly property var shown: root.pieces?.[index] ?? { points: [], ink: "transparent" }
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: piece.shown.ink

                PathPolyline {
                    path: piece.shown.points
                }
            }
        }
    }
}
