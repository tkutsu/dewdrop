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
        objects: Audio.sinks.concat(Audio.streams)
    }

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

            // One output is only a name. Several are a choice, and the one
            // in use carries the tick.
            PopupText {
                visible: Audio.sinks.length < 2
                text: Audio.tooltip
            }

            Column {
                visible: Audio.sinks.length > 1

                Repeater {
                    model: ScriptModel {
                        values: Audio.sinks
                    }

                    delegate: PopupRow {
                        id: output

                        required property var modelData
                        readonly property bool current: modelData === Audio.sink

                        width: master.width
                        height: 22
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: Audio.setDefault(output.modelData)

                        Glyph {
                            x: 1
                            height: parent.height
                            visible: output.current
                            text: Theme.glyph.check
                            fontSize: Theme.popupTextSize
                        }

                        PopupText {
                            x: master.lead
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 4
                            elide: Text.ElideRight
                            text: output.modelData.description || output.modelData.name
                            opacity: output.current ? 1 : 0.7
                        }
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
                        elide: Text.ElideRight
                        text: Audio.appName(app.modelData)
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                    }

                    // The speaker is the app's mute, the way the bar's is
                    // the output's: struck through while it is silenced.
                    VolumeRow {
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
        }
    }

    // The speaker, the track and the figure, for the output and for each app.
    component VolumeRow: Row {
        id: volumeRow

        property string icon
        property int volume
        signal moved(real value)
        signal iconTapped

        // Where the text starts on a row above that lines up with the track.
        readonly property int lead: speaker.width + spacing

        spacing: 8

        // A fixed box, with the speaker against its left edge: the waves
        // come and go with the level, and a glyph sized to its own ink
        // shoved the slider along every time one did. Two pixels past the
        // font size holds the widest of the five.
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

            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: volumeRow.iconTapped()
            }
        }

        Slider {
            anchors.verticalCenter: parent.verticalCenter
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
