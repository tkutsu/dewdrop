import QtQuick
import qs

// A popover's box during a pill morph or a height change (shaders/drop.frag): its frost
// and the hairline round it, lit from above as Rim draws it, in a box that
// can be a drop, a bell or the popover. Fills its parent and draws `box`,
// in its parent's pixels. Draws the fill or the rim, or both.
ShaderEffect {
    property vector4d box
    property real radius
    property real bell: 0
    // The bottom's center can lag behind its corners while the box settles.
    property real sag: 0
    property color color
    property real showFill: 0
    property real showRim: 0

    readonly property size size: Qt.size(width, height)
    readonly property real lineWidth: Theme.pillBorder
    readonly property vector4d fill: Qt.vector4d(color.r, color.g, color.b, color.a)
    readonly property vector4d rimTop: Qt.vector4d(Theme.rimTop.r, Theme.rimTop.g, Theme.rimTop.b, Theme.rimTop.a)
    readonly property vector4d rimBottom: Qt.vector4d(Theme.rimBottom.r, Theme.rimBottom.g, Theme.rimBottom.b, Theme.rimBottom.a)

    anchors.fill: parent

    // A new URL also replaces Qt's cached shader when the live shell reloads.
    fragmentShader: Qt.resolvedUrl("../shaders/drop.frag.qsb?revision=bottom-flex")
}
