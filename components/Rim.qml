import QtQuick
import QtQuick.Shapes
import qs

// The edge of a surface: a hairline lit from above, bright along the top and
// fading to almost nothing by the bottom. It is what turns a tinted rectangle
// into glass — a flat hairline at one alpha was either invisible over the
// wallpaper or a drawn box over a window, and light only ever comes from one
// side.
//
// A ring rather than a stroke, because a stroke cannot take a gradient here:
// two rounded rectangles one inside the other, filled odd-even so that only
// the band between them is painted. The inner one is inset by the line's
// width and its radius by the same, so the band is the same width all the way
// round and stays concentric with whatever it is the edge of.
//
// Sized by its parent: anchors.fill the surface it rims, and give it that
// surface's radius.
Shape {
    id: root

    property real radius: 0
    property real lineWidth: Theme.pillBorder
    property color topColor: Theme.rimTop
    property color bottomColor: Theme.rimBottom

    // The curve renderer, for the same reason the music pill's track uses it:
    // a hairline on a curve is where the triangulated one shows its steps.
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0
            y1: 0
            x2: 0
            y2: root.height

            GradientStop {
                position: 0
                color: root.topColor
            }
            GradientStop {
                position: 1
                color: root.bottomColor
            }
        }

        PathRectangle {
            width: root.width
            height: root.height
            radius: Math.min(root.radius, root.width / 2, root.height / 2)
        }

        PathRectangle {
            x: root.lineWidth
            y: root.lineWidth
            width: Math.max(0, root.width - root.lineWidth * 2)
            height: Math.max(0, root.height - root.lineWidth * 2)
            radius: Math.max(0, Math.min(root.radius, root.width / 2, root.height / 2) - root.lineWidth)
        }
    }
}
