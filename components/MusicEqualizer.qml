import QtQuick
import qs
import qs.services

// Ten octave bands replace the player and queue; edits reach MPD only on Apply.
Column {
    id: root
    spacing: Theme.popupSpacing
    signal back

    Component.onCompleted: MpdEqualizer.load()

    PopupHeader {
        width: root.width
        title: "Equalizer"

        PopupButton {
            label: "Music"
            glyph: Theme.glyph.track
            framed: true
            name: "Return to music"
            onTapped: root.back()
        }
        PopupButton {
            label: "Reset"
            glyph: Theme.glyph.equalizerReset
            framed: true
            live: (MpdEqualizer.dirty || MpdEqualizer.error !== "") && !MpdEqualizer.busy
            onTapped: MpdEqualizer.reset()
        }
        PopupButton {
            label: "Apply"
            glyph: Theme.glyph.check
            framed: true
            live: MpdEqualizer.dirty && !MpdEqualizer.busy && Mpd.connected
            onTapped: MpdEqualizer.apply()
        }
    }

    Row {
        x: Theme.popupInset
        spacing: 10

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Preset"
            color: Theme.label2
            font.pixelSize: Theme.captionSize
        }
        SettingDropdown {
            objectName: "equalizerPresets"
            popup.implicitHeight: popup.contentItem.implicitHeight + popup.topPadding + popup.bottomPadding
            enabled: MpdEqualizer.ready && !MpdEqualizer.busy
            setting: ({title: "Equalizer preset", options: MpdEqualizer.presets,
                placeholder: "Custom", get: () => MpdEqualizer.preset, set: value => MpdEqualizer.choose(value)})
        }
    }

    Item {
        width: root.width
        height: 198
        enabled: MpdEqualizer.ready && !MpdEqualizer.busy
        opacity: enabled ? 1 : 0.4

        Row {
            x: Theme.popupInset
            width: parent.width - 2 * x
            height: parent.height

            Repeater {
                model: 10

                delegate: Item {
                    id: band
                    required property int index
                    width: parent.width / 10
                    height: parent.height

                    PopupText {
                        width: parent.width
                        text: (MpdEqualizer.gains[band.index] > 0 ? "+" : "") + MpdEqualizer.gains[band.index].toFixed(1)
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.footnoteSize
                        color: Theme.label2
                    }

                    // Rotate the shared slider so its pointer, wheel and accessibility stay consistent.
                    Slider {
                        objectName: "equalizerBand" + band.index
                        x: (band.width - width) / 2
                        y: 86
                        width: 136
                        height: 22
                        rotation: -90
                        name: MpdEqualizer.frequencies[band.index] + " Hz gain"
                        value: (MpdEqualizer.gains[band.index] + 12) / 24
                        wheelStep: 0.5 / 24
                        wheelSnap: true
                        onMoved: value => MpdEqualizer.setBand(band.index, value * 24 - 12)

                        Rectangle {
                            anchors.centerIn: parent
                            width: 1
                            height: 10
                            color: Theme.label3
                        }
                    }

                    PopupText {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        text: MpdEqualizer.labels[band.index]
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.footnoteSize
                        color: Theme.label2
                    }
                }
            }
        }
    }

    PopupNote {
        width: root.width
        text: "-12 to +12 dB. Apply briefly interrupts playback."
        font.pixelSize: Theme.footnoteSize
    }
    PopupNote {
        width: root.width
        visible: MpdEqualizer.legacy && !MpdEqualizer.busy
        text: "These bands approximate your existing EQ. Apply replaces it with a ten-band EQ."
        font.pixelSize: Theme.footnoteSize
    }
    PopupNote {
        width: root.width
        visible: MpdEqualizer.preset === "Headphones"
        text: "General listening curve. No measured JBL Endurance Race 2 correction was found."
        font.pixelSize: Theme.footnoteSize
    }
    PopupNote {
        width: root.width
        visible: MpdEqualizer.busy || MpdEqualizer.error !== ""
        warn: MpdEqualizer.error !== ""
        text: MpdEqualizer.error || "Updating equalizer…"
    }
}
