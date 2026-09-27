import QtQuick
import Quickshell
import qs
import qs.services

// What the audio module's tooltip could not be: the device name and a volume
// the pointer can actually grab.
Popup {
    id: root


    // The wheel anywhere on the popup moves the volume, in the same steps as
    // the wheel on the bar icon. Accumulated the same way BarItem does it, so
    // a touchpad's fractions add up to notches instead of each one being a
    // step. A MouseArea under the contents rather than a WheelHandler, which
    // never saw a wheel event in here; taking no buttons leaves clicks and
    // drags to the slider on top of it.
    MouseArea {
        property real acc: 0

        width: content.width
        height: content.height
        acceptedButtons: Qt.NoButton

        onWheel: function (wheel) {
            acc += wheel.angleDelta.y;
            while (acc >= 120) {
                acc -= 120;
                Audio.step(true);
            }
            while (acc <= -120) {
                acc += 120;
                Audio.step(false);
            }
        }

        Column {
            id: content
            spacing: 6

            PopupText {
                text: Audio.tooltip
            }

            Row {
                spacing: 8

                // A fixed box, with the speaker against its left edge: the waves
                // come and go with the level, and a glyph sized to its own ink
                // shoved the slider along every time one did. Two pixels past the
                // font size holds the widest of the five.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.popupTextSize + 2
                    height: Theme.popupTextSize + 4

                    Glyph {
                        height: parent.height
                        text: Audio.icon
                        fontSize: Theme.popupTextSize
                    }
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
}
