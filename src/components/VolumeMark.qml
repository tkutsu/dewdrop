import QtQuick
import QtQuick.Shapes

// The speaker, drawn rather than cut out of the font: Material's
// volume_high, measured and set on whole pixels, its two waves lit one after
// the other as the volume rises, so every level stands the same size and only
// the light moves. Muted strikes it through, the way volume_off does.
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

    // Part 0 is the body, 1 the inner wave, 2 the outer. Each wave comes up
    // from a quarter over three steps, the inner one first.
    function ink(part: int): color {
        const steps = part === 0 ? 3 : Math.min(3, Math.max(0, level - 3 * (part - 1)));
        return Qt.rgba(color.r, color.g, color.b, color.a * (0.25 + 0.25 * steps));
    }

    // The slash runs corner to corner at 45°, and the body is cut a gap clear
    // of its upper side; below, it runs into the slash, as in volume_off.
    readonly property bool muted: level < 0
    readonly property real slashLift: 0.15 * unit
    readonly property real slashGap: 1.2 * unit
    function below(point: point): real {
        return (point.y - point.x + slashLift) * Math.SQRT1_2;
    }

    // The part of a polygon where side(point) >= 0 (Sutherland–Hodgman
    // against one line, which holds for the body since each side of the
    // slash is one piece of it).
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

    readonly property var pieces: muted
        ? [clip(body, below), clip(body, p => -below(p) - stroke / 2 - slashGap)]
        : [body, []]

    component Piece: ShapePath {
        required property int index
        strokeColor: "transparent"
        fillColor: root.ink(0)

        PathPolyline {
            path: root.pieces[index]
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        Piece { index: 0 }
        Piece { index: 1 }

        // The inner wave, a half-moon on the upright.
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.ink(1)

            PathAngleArc {
                centerX: root.waveX
                centerY: root.centreY
                radiusX: 1.7 * root.unit
                radiusY: 2.75 * root.unit
                startAngle: -90
                sweepAngle: 180
            }
        }

        // The outer wave, a thin arc from the top of the ink to its foot.
        ShapePath {
            strokeColor: root.ink(2)
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root.waveX
                centerY: root.centreY
                radiusX: root.outerReach - root.stroke / 2
                radiusY: root.centreY - root.stroke / 2
                startAngle: -90
                sweepAngle: 180
            }
        }

        ShapePath {
            id: slash
            strokeColor: root.muted ? root.ink(0) : "transparent"
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            // Ends far enough in that their corners stay in the box.
            readonly property real inset: root.stroke * Math.SQRT1_2 / 2
            startX: inset + root.slashLift
            startY: inset

            PathLine {
                x: root.size - slash.inset + root.slashLift
                y: root.size - slash.inset
            }
        }
    }
}
