import QtQuick
import QtQuick.Shapes
import qs

// Something is under way and nobody knows how long it will take: a device
// connecting, a network being joined. A quarter-open ring turning, in the
// label colour, the size of the text beside it.
//
// It only turns while it is visible. A running animation redraws the popup at
// the monitor's rate, which is fine for the seconds a connection takes and
// not for a spinner that was merely hidden.
Item {
    id: root

    property int size: Theme.captionSize
    property real stroke: 1.5

    implicitWidth: size
    implicitHeight: size

    Shape {
        id: ring

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.label2
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: (root.size - root.stroke) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 270
            }
        }

        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: root.visible
        }
    }
}
