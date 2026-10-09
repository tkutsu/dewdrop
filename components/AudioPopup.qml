import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.services

// What the audio module's tooltip could not be, and what pavucontrol was
// opened for: which output is playing, a volume the pointer can grab, and one
// for each app that is making a sound.
Popup {
    id: root

    // Without a tracker a node's volume and description stay empty; the
    // service only tracks the default output. These are only worth keeping
    // bound while there is a popup to show them.
    PwObjectTracker {
        objects: Audio.sinks.concat(Audio.outStreams, Audio.sources)
    }

    spacing: 6

    PopupHeader {
        width: content.width
        inset: 0
        title: "Sound"
    }

    // The wheel moves whichever volume is under the pointer: an app's over
    // its row, the output's anywhere else, in the same steps as the wheel on
    // the bar icon, though down is louder here: the rows are sliders, and
    // the wheel goes the way it does on every Slider. A gap between sections
    // counts as the one below it, so the rule under the master row is the
    // border between the two. Accumulated
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
            spacing: 6

            // The outputs, the one in use ticked, as the Bluetooth and
            // network popups list theirs.
            PopupText {
                visible: Audio.sinks.length === 0
                text: "No audio output"
                color: Theme.label2
            }

            Column {
                Repeater {
                    model: ScriptModel {
                        values: Audio.sinks
                    }

                    delegate: ChoiceRow {
                        id: output

                        required property var modelData

                        width: master.width
                        text: modelData.description || modelData.name
                        current: modelData === Audio.sink
                        onTapped: Audio.setDefault(output.modelData)
                    }
                }
            }

            VolumeRow {
                id: master
                icon: Audio.icon
                volume: Audio.volume
                onMoved: value => Audio.setVolume(value)
                onIconTapped: Audio.toggleMute()
            }

            Rectangle {
                visible: Audio.streams.length > 0
                width: master.width
                height: Theme.pillBorder
                color: Theme.stroke
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
                        width: master.width
                        leftPadding: 32
                        elide: Text.ElideRight
                        text: Audio.appName(app.modelData)
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                    }

                    // The speaker is the app's mute, the way the bar's is
                    // the output's: struck through while it is silenced.
                    VolumeRow {
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

            // The input, after a rule, laid out as the output is: the
            // microphones to choose between when there is more than one, then
            // its level, the mic glyph its mute. Each part carries the source
            // as its node, so the wheel over any of it moves the mic.
            Rectangle {
                readonly property var modelData: Audio.source
                visible: !!Audio.source
                width: master.width
                height: Theme.pillBorder
                color: Theme.stroke
            }

            Column {
                readonly property var modelData: Audio.source
                visible: Audio.sources.length > 1

                Repeater {
                    model: ScriptModel {
                        values: Audio.sources
                    }

                    delegate: ChoiceRow {
                        id: input

                        required property var modelData

                        width: master.width
                        text: modelData.description || modelData.name
                        current: modelData === Audio.source
                        onTapped: Audio.setDefaultSource(input.modelData)
                    }
                }
            }

            VolumeRow {
                readonly property var modelData: Audio.source
                visible: !!Audio.source
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

    // The speaker, the track and the figure, for the output and for each app.
    component VolumeRow: Row {
        id: volumeRow

        property string icon
        property int volume
        property string name: "Output"
        signal moved(real value)
        signal iconTapped

        // On the lists' grid (ChoiceRow): the speaker in the tick's column,
        // the track starting where the names do.
        leftPadding: 8
        spacing: 10

        // A fixed box, with the speaker against its left edge: the struck-out
        // speaker is not the width of the others, and a glyph sized to its
        // own ink shoved the slider along whenever it came or went. Two
        // pixels past the font size holds either.
        Item {
            id: speaker

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.popupTextSize + 2
            height: Theme.popupTextSize + 4

            Glyph {
                height: parent.height
                text: volumeRow.icon
                fontSize: Theme.popupTextSize
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Toggle " + volumeRow.name.toLowerCase() + " mute"
            Accessible.onPressAction: if (enabled && visible)
                volumeRow.iconTapped()

            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: volumeRow.iconTapped()
            }
        }

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            name: volumeRow.name + " volume"
            value: volumeRow.volume / 100
            // PipeWire takes the change directly — no pamixer round trip,
            // so the track keeps up with the drag.
            onMoved: value => volumeRow.moved(value)
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: volumeRow.volume + "%"
        }
    }
}
