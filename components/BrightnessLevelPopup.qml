import QtQuick
import Quickshell
import qs
import qs.services

// A vertical brightness readout, shown briefly after a bar scroll.
Popup {
    id: root

    readonly property int bodyWidth: 34
    hPadding: padding + Theme.popupInset
    vPadding: hPadding
    bottomPadding: vPadding
    probes: false
    takesKeys: false
    mask: Region {}

    LevelIndicator {
        width: root.bodyWidth
        name: "Brightness"
        readoutOnTop: true
        icon: NightMode.icon
        level: NightMode.brightness
    }
}
