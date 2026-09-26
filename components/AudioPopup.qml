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

            // On its advance rather than its ink: the speaker's waves come
            // and go with the level, and a glyph as wide as its ink shoved
            // the slider along every time one did. Material icons share one
            // box, so the speaker itself stays put too.
            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                tightWidth: false
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
