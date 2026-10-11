import QtQuick
import QtQuick.Shapes

// A drawn pointer, its tip at the item's top left, a touch smaller while held.
Shape {
    property bool down: false

    width: 12
    height: 19
    z: 10
    scale: down ? 0.88 : 1
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: "white"
        strokeColor: "black"
        strokeWidth: 1
        joinStyle: ShapePath.RoundJoin
        startX: 0
        startY: 0
        PathLine { x: 0; y: 16 }
        PathLine { x: 4; y: 12.5 }
        PathLine { x: 7; y: 18.5 }
        PathLine { x: 9.5; y: 17.5 }
        PathLine { x: 6.5; y: 11.5 }
        PathLine { x: 11.5; y: 11.5 }
        PathLine { x: 0; y: 0 }
    }
}
