import QtQuick
import Quickshell
import qs
import qs.services

// What the audio module's tooltip could not be: the device name and a volume
// the pointer can actually grab.
Popup {
    id: root

    readonly property int fontSize: Theme.popupTextSize

    Column {
        spacing: 6

        PopupText {
            text: Audio.tooltip
        }

        Row {
            spacing: 8

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                text: Audio.icon
                fontSize: root.fontSize
                implicitHeight: root.fontSize + 4
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Audio.volume / 100
                // PipeWire takes the change directly — no pamixer round trip,
                // so the track keeps up with the drag.
                onMoved: value => Audio.setVolume(value)
            }

            PopupText {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: Audio.volume + "%"
            }
        }
    }
}
