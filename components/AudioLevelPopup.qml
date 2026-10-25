import QtQuick
import Quickshell
import qs
import qs.services

// A brief volume readout under the bar icon while its wheel adjusts the output.
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
        name: "Output volume"
        readoutOnTop: true
        level: Audio.volume
    }
}
