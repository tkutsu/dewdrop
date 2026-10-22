import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.services

// What the audio module's tooltip could not be, and what pavucontrol was
// opened for: a volume the pointer can grab, which output is playing, one for
// each app that is making a sound, and the input. Laid out as the Mac's Sound
// menu: the output volume and devices under the title, then apps and input.
Popup {
    id: root

    // Without a tracker a node's volume and description stay empty; the
    // service only tracks the default output. These are only worth keeping
    // bound while there is a popup to show them.
    PwObjectTracker {
        objects: Audio.sinks.concat(Audio.outStreams, Audio.sources)
    }

    readonly property int bodyWidth: Theme.popupWidth
    // The track takes what the row's speaker, readout and gaps leave
    // (VolumeRow: the inset, the speaker, two gaps, the readout, the inset).
    readonly property real sliderWidth: root.bodyWidth - Theme.popupInset * 6 - (Theme.popupTextSize + 2) - 34

    PopupHeader {
        width: root.bodyWidth
        title: "Sound"
    }

    // The wheel moves whichever volume is under the pointer: an app's over
    // its row, the output's anywhere else, in the same steps as the wheel on
    // the bar icon: down is louder, the way it is on every Slider. A gap
    // between parts counts as the one below it, and the Input heading carries the mic, so
    // the wheel over it moves the input. Accumulated
    // the same way BarItem does it, so a touchpad's fractions add up to notches
    // instead of each one being a step. A MouseArea under the contents rather
    // than a WheelHandler, which never saw a wheel event in here; taking no
    // buttons leaves clicks and drags to the slider on top of it.
    MouseArea {
        property real acc: 0

        width: content.width
        height: content.height
        acceptedButtons: Qt.NoButton

        onWheel: function (wheel) {
            // The app rows and the input section carry a node; the outputs
            // and master don't.
            const row = content.childAt(0, wheel.y) ?? content.childAt(0, wheel.y + content.spacing);
            const node = row?.modelData ?? null;
            const step = up => node ? Audio.stepNode(node, up) : Audio.step(up);
            acc -= wheel.angleDelta.y;
            while (acc >= 120) {
                acc -= 120;
                step(true);
            }
            while (acc <= -120) {
                acc += 120;
                step(false);
            }
        }

        Column {
            id: content
            spacing: Theme.popupSpacing

            VolumeRow {
                id: master
                sliderWidth: root.sliderWidth
                icon: Audio.icon
                volume: Audio.volume
                onMoved: value => Audio.setVolume(value)
                onIconTapped: Audio.toggleMute()
            }

            PopupNote {
                width: root.bodyWidth
                visible: Audio.availableSinks.length === 0
                text: "No audio output"
            }

            Column {
                Repeater {
                    model: ScriptModel {
                        // Keep the selected device directly under its volume.
                        values: Audio.availableSinks.slice().sort((a, b) => Number(b === Audio.sink) - Number(a === Audio.sink))
                    }

                    delegate: ChoiceRow {
                        id: output

                        required property var modelData

                        width: root.bodyWidth
                        text: Audio.deviceName(modelData)
                        current: modelData === Audio.sink
                        onTapped: Audio.setDefault(output.modelData)
                    }
                }
            }

            PopupSection {
                visible: Audio.streams.length > 0
                width: root.bodyWidth
                title: "Apps"
            }

            Repeater {
                model: ScriptModel {
                    values: Audio.streams
                }

                delegate: Column {
                    id: app

                    required property var modelData
                    readonly property int volume: Math.round((modelData.audio?.volume ?? 0) * 100)
                    readonly property bool muted: modelData.audio?.muted ?? false

                    spacing: 2

                    PopupText {
                        width: root.bodyWidth
                        leftPadding: 32
                        elide: Text.ElideRight
                        text: Audio.appName(app.modelData)
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                    }

                    // The speaker is the app's mute, the way the bar's is
                    // the output's: struck through while it is silenced.
                    VolumeRow {
                        sliderWidth: root.sliderWidth
                        name: Audio.appName(app.modelData)
                        icon: Audio.level(app.volume, app.muted)
                        volume: app.volume
                        onMoved: value => {
                            if (app.modelData.audio)
                                app.modelData.audio.volume = value;
                        }
                        onIconTapped: {
                            if (app.modelData.audio)
                                app.modelData.audio.muted = !app.muted;
                        }
                    }
                }
            }

            // The input, laid out as the output is: the microphones to
            // choose from, then its level, the
            // mic glyph its mute. Each part carries the source as its node,
            // so the wheel over any of it moves the mic.
            PopupSection {
                readonly property var modelData: Audio.source
                visible: Audio.availableSources.length > 0
                width: root.bodyWidth
                title: "Input"
            }

            Column {
                readonly property var modelData: Audio.source
                visible: Audio.availableSources.length > 0

                Repeater {
                    model: ScriptModel {
                        values: Audio.availableSources
                    }

                    delegate: ChoiceRow {
                        id: input

                        required property var modelData

                        width: root.bodyWidth
                        text: Audio.deviceName(modelData)
                        current: modelData === Audio.source
                        onTapped: Audio.setDefaultSource(input.modelData)
                    }
                }
            }

            VolumeRow {
                readonly property var modelData: Audio.source
                visible: Audio.source !== null && Audio.availableSources.includes(Audio.source)
                sliderWidth: root.sliderWidth
                name: "Microphone"
                icon: Audio.micMuted ? Theme.glyph.micMuted : Theme.glyph.mic
                volume: Audio.micVolume
                onMoved: value => {
                    if (Audio.source?.audio)
                        Audio.source.audio.volume = value;
                }
                onIconTapped: Audio.toggleMic()
            }
        }
    }

}
