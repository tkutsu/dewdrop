import QtQuick
import qs

// A popup's box (shaders/frost.frag): its frost and the hairline round it,
// lit from above as Rim draws it, in a rounded box whose bottom edge can sag
// like gel. Fills its parent, the box, and reaches `room` below it for the
// sag to hang into. Draws the fill or the rim, or both.
ShaderEffect {
    // The box's colour and corner, from the item it draws.
    property color color: parent.color
    property real radius: parent.radius
    property real sag: 0
    property real showFill: 0
    property real showRim: 0

    readonly property real room: 14
    readonly property size size: Qt.size(width, height)
    readonly property real lineWidth: Theme.pillBorder
    readonly property vector4d fill: Qt.vector4d(color.r, color.g, color.b, color.a)
    readonly property vector4d rimTop: Qt.vector4d(Theme.rimTop.r, Theme.rimTop.g, Theme.rimTop.b, Theme.rimTop.a)
    readonly property vector4d rimBottom: Qt.vector4d(Theme.rimBottom.r, Theme.rimBottom.g, Theme.rimBottom.b, Theme.rimBottom.a)

    width: parent.width
    height: parent.height + room

    fragmentShader: Qt.resolvedUrl("../shaders/frost.frag.qsb")
}
