import QtQuick
import qs

// Where a dragged thing will land: a thin upright line between items,
// gliding from slot to slot rather than jumping. Centred on the bar in its
// parent, which is a pill or a strip as tall as one.
Rectangle {
    id: root

    // The x of the line's middle in its parent, or NaN for no line.
    property real target: NaN

    // Kept where it was while the line fades out.
    property real _at: 0
    onTargetChanged: if (!isNaN(target)) _at = target

    x: Math.round(_at - width / 2)
    y: Math.round(Theme.pillTop(parent.height) + (Theme.barHeight - height) / 2)
    z: 9
    width: 2
    height: Theme.iconSize
    radius: 1
    color: Theme.fg
    opacity: isNaN(target) ? 0 : 0.5

    Behavior on opacity {
        NumberAnimation {
            duration: 120
        }
    }

    Behavior on _at {
        enabled: root.opacity > 0

        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
}
