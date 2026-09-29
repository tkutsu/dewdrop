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
    // Where box0 bulges as a drop pours into it: boxes taller than the slab,
    // which the glass is let out to (and shaders/liquid.frag blends in by
    // how far they stand out). None by default.
    property vector4d bulge0
    property vector4d bulge1

    // How close two boxes come before they start to pull towards each other.
    // The air between islands, so pills at rest are drawn exactly as they are
    // and only one on the move ever reaches its neighbour.
    property real reach: Theme.pillSpread
    // Or one reach per box, for glass whose boxes move on their own: each
    // box reaches for the ones before it, so a box goes after the one it
    // joins. The first number is unused.
    property vector4d reaches: Qt.vector4d(reach, reach, reach, reach)
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
    property real rimFrom: Theme.barInset
    property real rimTo: Theme.barInset + Theme.barHeight

    readonly property size size: Qt.size(width, height)

    // The wallpaper, for glass that sits on it: an Image of it, which the
    // glass draws bent at its edges instead of letting Hyprland's blur show
    // through a tint. Null (the default) for glass laid on other glass, like
    // the workspace mark, and the glass is the plain fill until it has loaded.
    property Image backdrop: null
    // Where this item's top left is on the screen, and the screen's size.
    property point origin: Qt.point(0, 0)
    property size screenSize: Qt.size(1, 1)

    readonly property real glass: backdrop?.status === Image.Ready ? 1 : 0
    readonly property size backdropSize: backdrop ? Qt.size(backdrop.implicitWidth, backdrop.implicitHeight) : Qt.size(1, 1)
    property real bend: Theme.glassBend
    property real bendDepth: Theme.glassBendDepth
    property real soften: Theme.glassSoften
    property real saturation: Theme.glassSaturation
    property real tint: Theme.glassTint

    fragmentShader: Qt.resolvedUrl("../shaders/liquid.frag.qsb")
}
