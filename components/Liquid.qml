import QtQuick
import qs

// The glass under the clock and the pills that come and go beside it, drawn as
// one surface so that a pill arriving or leaving does it the way a drop does:
// it pulls itself round, reaches its neighbour, a neck forms between the two,
// and it is drawn into it. The pills themselves draw no slab while this is
// under them (Pill.drawsSlab), only their contents.
//
// Up to four boxes, in this item's own pixels, as Qt.vector4d(x, y, width,
// height); a box of no width is not there. Each is drawn fully round at the
// ends, the way a pill is.
ShaderEffect {
    id: root

    property vector4d box0
    property vector4d box1
    property vector4d box2
    property vector4d box3
    // Each box's corner radius, in the same order. Negative is round at the
    // ends, which is what a pill is and what every box is unless told
    // otherwise; the launcher's box has corners of its own.
    property vector4d radii: Qt.vector4d(-1, -1, -1, -1)

    // How close two boxes come before they start to pull towards each other.
    // The air between islands, so pills at rest are drawn exactly as they are
    // and only one on the move ever reaches its neighbour.
    property real reach: Theme.pillSpread
    property real lineWidth: Theme.pillBorder

    // The colours a Pill's own slab and Rim would have used, straight alpha.
    // Settable for glass that is not a pill: the workspace mark is a lighter
    // fill with no rim.
    property vector4d fill: Qt.vector4d(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, Theme.barBg.a)
    property vector4d rimTop: Qt.vector4d(Theme.pillRimTop.r, Theme.pillRimTop.g, Theme.pillRimTop.b, Theme.pillRimTop.a)
    property vector4d rimBottom: Qt.vector4d(Theme.rimBottom.r, Theme.rimBottom.g, Theme.rimBottom.b, Theme.rimBottom.a)

    // The rim is lit over the slab's own height, not over the height of a drop
    // that has shrunk inside it, so a drop on its way in stays lit like the
    // pill it came from. Nothing is drawn above or below these either, so
    // glass inset inside a pill moves them in with it.
    property real rimFrom: Theme.barMargin
    property real rimTo: Theme.barMargin + Theme.barHeight

    // A shadow under the whole shape, for glass that floats over a window.
    // None by default: the pills sit on the wallpaper. Give the item room
    // round the boxes for it to fall into (Theme.shadowPad).
    property vector4d shadow: Qt.vector4d(0, 0, 0, 0)
    property real shadowBlur: Theme.shadowBlur
    property real shadowY: Theme.shadowY

    readonly property size size: Qt.size(width, height)

    fragmentShader: Qt.resolvedUrl("../shaders/liquid.frag.qsb")
}
