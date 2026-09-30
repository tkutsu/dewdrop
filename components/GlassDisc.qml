import QtQuick
import qs

// The disc a badge or a pin mark stands on: the workspace mark's look, made
// solid. The mark is white laid over the pill's glass, so the wallpaper shows
// through it; a badge cannot be see-through, because it sits over an icon's
// strokes and rises off the pill's edge where there is no glass under it. So
// it draws its own glass — the wallpaper behind it, the pill's way, unbent
// since a disc this size would be all edge — and lays the mark's white and
// rim over that. With no image (a flat colour) it is the pill's fill, solid.
//
// Round at any width: a count past one digit makes it a capsule. Contents go
// on top.
Item {
    id: root

    // The wallpaper the pill this disc is on draws its glass from.
    readonly property Image backdrop: {
        for (let p = parent; p; p = p.parent) {
            if (p.backdrop !== undefined)
                return p.backdrop;
        }
        return null;
    }

    Liquid {
        id: pane

        anchors.fill: parent
        backdrop: root.backdrop
        box0: Qt.vector4d(0, 0, width, height)
        reach: 0
        bend: 0
        lineWidth: 0
        fill: pane.glass ? Qt.vector4d(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, 1) : Qt.vector4d(Theme.badgeBg.r, Theme.badgeBg.g, Theme.badgeBg.b, 1)
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.selectionStrong

        Rim {
            anchors.fill: parent
            radius: parent.radius
            topColor: Theme.markRimTop
        }
    }
}
