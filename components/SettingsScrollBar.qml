import QtQuick
import QtQuick.Controls as Controls
import qs

// Keep overflow discoverable even before the user starts scrolling.
Controls.ScrollBar {
    policy: Controls.ScrollBar.AsNeeded
    visible: size < 1
    minimumSize: 0.08
    hoverEnabled: true
    implicitWidth: 6
    padding: 0

    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 24
        radius: width / 2
        color: parent.pressed || parent.hovered ? Theme.label2 : Theme.label3
    }

    background: Item {}
}
