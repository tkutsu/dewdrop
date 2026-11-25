import QtQuick
import QtQuick.Shapes

// The Wi-Fi fan, drawn rather than taken from a file or the font: a dot and
// three thin arcs about it, lit from the dot up with the rest left faint, so
// every strength stands the same size and only the light moves. The font's
// own Wi-Fi is a cone that fills solid as the signal rises.
//
// Glyph draws one for any Theme.glyph entry spelled "wifi:<bars>", so every
// place that shows a glyph can show this too.
//
// Laid out on whole pixels: the box is an odd number of pixels wide and the
// dot's centre sits on a pixel's centre, so the dot comes out round and
// sharp rather than smeared over four pixels, and the arcs fall evenly
// either side of it.
Item {
    id: root

    // nm-applet's five steps (Network.bars), or -1 with the radio off.
    // Nought and one light only the dot; each step after lights one more arc.
    property int bars: 4
    // The height of the ink, top of the outer arc to the foot of the dot.
    property int size: 13
    property color color: "white"

    // Designed 13px tall: 1.5px arcs, as thin as the font's outlines at the
    // bar's glyph size, spaced evenly out from the dot.
    readonly property real unit: size / 13
    readonly property real stroke: 1.5 * unit
    readonly property real dot: 1.3 * unit
    readonly property real centreX: width / 2
    readonly property real centreY: Math.floor(size - dot) + 0.5
    readonly property real outer: centreY - stroke / 2
    readonly property real spacing: outer * 0.3165

    implicitHeight: size
    // Each arc spans a quarter turn about the vertical, so the outer one's
    // ends set the width: the least odd number of pixels that holds them.
    implicitWidth: 2 * Math.ceil(outer * Math.SQRT1_2 + stroke / 2 - 0.5) + 1

    // Part 0 is the dot, 1 to 3 the arcs from the inside out.
    function ink(part: int): color {
        const lit = part === 0 ? bars >= 0 : bars > part;
        return Qt.rgba(color.r, color.g, color.b, color.a * (lit ? 1 : 0.25));
    }

    component Arc: ShapePath {
        id: arc
        required property int part
        strokeColor: root.ink(part)
        strokeWidth: root.stroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            centerX: root.centreX
            centerY: root.centreY
            radiusX: root.outer - (3 - arc.part) * root.spacing
            radiusY: radiusX
            startAngle: -135
            sweepAngle: 90
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.ink(0)

            PathAngleArc {
                centerX: root.centreX
                centerY: root.centreY
                radiusX: root.dot
                radiusY: root.dot
                sweepAngle: 360
            }
        }

        Arc { part: 1 }
        Arc { part: 2 }
        Arc { part: 3 }
    }
}
