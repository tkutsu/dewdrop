import QtQuick
import Quickshell
import qs
import qs.services

// The display popup's brightness row, shown briefly after a bar scroll.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWidth
    vPadding: hPadding + Theme.popupInset
    bottomPadding: vPadding
    probes: false
    takesKeys: false
    mask: Region {}

    Row {
        id: row

        width: root.bodyWidth
        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        spacing: 10

        Slider {
            width: root.bodyWidth - Theme.popupInset * 2 - row.spacing - 34
            anchors.verticalCenter: parent.verticalCenter
            name: "Brightness"
            value: NightMode.brightness / 100
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: NightMode.brightness + "%"
        }
    }
}
