import QtQuick
import Quickshell
import qs
import qs.services

// A brief volume readout under the bar icon while its wheel adjusts the output.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWidth
    vPadding: hPadding + Theme.popupInset
    bottomPadding: vPadding
    probes: false
    takesKeys: false
    mask: Region {}

    VolumeRow {
        sliderWidth: root.bodyWidth - Theme.popupInset * 6 - (Theme.popupTextSize + 2) - 34
        icon: Audio.icon
        volume: Audio.volume
    }
}
