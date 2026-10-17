import QtQuick
import qs

// Hands a press on `icon` to the glass under it (GlassPress), and gives back
// how big the icon should be drawn while the glass answers. `area` is what
// takes the press, a MouseArea or a TapHandler, and `down` the press itself:
// its `pressed`, or `acting` where only a button with something to do
// should press in. In place of the pixel's dip the bar's icons used to take.
QtObject {
    id: root

    required property Item icon
    required property var area
    property bool down: area.pressed
    // Text loses at most 2% or 2 px of width; icons keep their deeper press.
    property bool textPress: false
    readonly property real shrink: textPress ? Math.min(0.02, 2 / Math.max(1, icon.width)) : GlassPress.iconShrink
    readonly property real scale: 1 - Math.max(0, Math.min(1, GlassPress.popOf(icon))) * shrink

    // Where the pointer is, in the window's pixels: under a MouseArea's
    // pointer, at a TapHandler's point, or else the icon's middle.
    function contact(): point {
        if (area.mouseX !== undefined)
            return area.mapToItem(null, area.mouseX, area.mouseY);
        if (area.point && area.parent)
            return area.parent.mapToItem(null, area.point.position.x, area.point.position.y);
        return icon.mapToItem(null, icon.width / 2, icon.height / 2);
    }

    onDownChanged: down ? GlassPress.press(icon, contact()) : GlassPress.release(icon)
}
