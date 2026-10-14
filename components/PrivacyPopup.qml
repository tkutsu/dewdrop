import QtQuick
import Quickshell
import qs
import qs.services

// Active captures, with separate controls for an app and its input device.
Popup {
    id: root

    readonly property int bodyWidth: 300

    spacing: 6

    PopupHeader {
        width: root.bodyWidth
        title: "Recording"
    }

    component Section: PopupText {
        width: root.bodyWidth
        leftPadding: Theme.popupInset
        color: Theme.label2
        font.pixelSize: Theme.captionSize
    }

    // Both capture lists use the standard icon/name grid and 20px controls.
    component Entry: PopupRow {
        id: entry

        property string title
        property string detail
        property string glyph
        property bool muted: false
        property bool recording: false
        default property alias control: end.data

        width: root.bodyWidth
        height: 40
        gesturePolicy: TapHandler.ReleaseWithinBounds

        Glyph {
            id: leadingIcon
            x: Theme.popupInset + Math.round((18 - implicitWidth) / 2)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.glyph
            fontSize: Theme.popupTextSize
            color: entry.muted ? Theme.label2 : Theme.fg
        }

        PopupText {
            id: line
            x: 32
            y: 4
            width: Math.min(implicitWidth, Math.max(0, end.x - x - 22))
            text: entry.title
            elide: Text.ElideRight
            font.pixelSize: Theme.captionSize
            color: entry.muted ? Theme.label2 : Theme.fg
        }

        PopupText {
            x: line.x
            y: 21
            width: end.x - x - 8
            text: entry.detail
            elide: Text.ElideRight
            color: Theme.label2
            font.pixelSize: Theme.footnoteSize
        }

        Rectangle {
            id: statusDot
            visible: entry.recording
            x: line.x + line.width + 6
            y: line.y + Math.round((line.height - height) / 2)
            width: 8
            height: 8
            radius: 4
            color: Theme.recording

            SequentialAnimation on opacity {
                running: root.visible && entry.recording && !Theme.reduceMotion
                loops: Animation.Infinite
                onRunningChanged: if (!running) statusDot.opacity = 1
                NumberAnimation { to: 0.4; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }

        Row {
            id: end
            anchors.right: parent.right
            anchors.rightMargin: Theme.popupInset
            anchors.verticalCenter: parent.verticalCenter
            height: 22
            spacing: 6

        }
    }

    PopupText {
        visible: !Privacy.active
        width: root.bodyWidth
        leftPadding: Theme.popupInset
        text: "No active captures"
        color: Theme.label2
    }

    Section {
        visible: Privacy.listening
        text: "Apps receiving audio"
    }

    Column {
        Repeater {
            id: micRows
            model: ScriptModel {
                values: Privacy.mics
                objectProp: "node"
            }

            delegate: Entry {
                id: mic

                required property var modelData
                readonly property bool appMuted: mic.modelData.node.audio?.muted ?? false
                muted: Privacy.muted(mic.modelData)

                title: mic.modelData.app
                detail: mic.modelData.source.description || mic.modelData.source.name || "Microphone"
                glyph: mic.muted ? Theme.glyph.micMuted : Theme.glyph.mic
                recording: !mic.muted && (mic.modelData.node.audio?.volume ?? 1) > 0 && (mic.modelData.source.audio?.volume ?? 1) > 0
                PopupButton {
                    anchors.verticalCenter: parent.verticalCenter
                    framed: true
                    implicitWidth: 62
                    label: mic.appMuted ? "Unmute" : "Mute"
                    name: label + " " + mic.modelData.app
                    onTapped: Privacy.toggleApp(mic.modelData.node)
                }
            }
        }
    }

    Section {
        visible: Privacy.listening
        text: "Microphones"
    }

    Column {
        Repeater {
            id: inputRows
            model: ScriptModel { values: Privacy.inputs }

            delegate: Column {
                id: input
                required property var modelData
                readonly property bool muted: input.modelData.audio?.muted ?? false
                readonly property int appCount: Privacy.mics.filter(m => m.source.id === input.modelData.id).length
                readonly property string title: input.modelData.description || input.modelData.name || "Microphone"
                width: root.bodyWidth
                spacing: 2

                Entry {
                    muted: input.muted
                    title: input.title
                    detail: input.muted ? "Muted for all apps" : input.appCount + (input.appCount === 1 ? " app using this input" : " apps using this input")
                    glyph: input.muted ? Theme.glyph.micMuted : Theme.glyph.mic
                    recording: Privacy.mics.some(m => m.source.id === input.modelData.id && !Privacy.muted(m) && (m.node?.audio?.volume ?? 1) > 0 && (m.source?.audio?.volume ?? 1) > 0)

                    PopupButton {
                        anchors.verticalCenter: parent.verticalCenter
                        framed: true
                        implicitWidth: 62
                        label: input.muted ? "Unmute" : "Mute"
                        name: label + " " + input.title + " for all apps"
                        onTapped: Privacy.toggleInput(input.modelData)
                    }
                }

                Row {
                    x: 32
                    spacing: 8
                    height: 22

                    Slider {
                        id: inputVolume
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.bodyWidth - 32 - Theme.popupInset - 34 - parent.spacing
                        name: input.title + " input volume"
                        wheelStep: 0.05
                        wheelSnap: true
                        value: input.modelData.audio?.volume ?? 0
                        onMoved: value => {
                            if (input.modelData.audio)
                                input.modelData.audio.volume = value;
                        }
                    }

                    PopupText {
                        width: 34
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((input.modelData.audio?.volume ?? 0) * 100) + "%"
                        font.pixelSize: Theme.captionSize
                        color: Theme.label2
                    }
                }
            }
        }
    }

    Rectangle {
        id: shareDivider
        visible: Privacy.listening && Privacy.sharing
        width: root.bodyWidth
        height: Theme.pillBorder
        color: Theme.stroke
    }

    Section {
        visible: Privacy.sharing
        text: "Screen shares"
    }

    Column {
        Repeater {
            id: shareRows
            model: ScriptModel {
                values: Privacy.shares
                objectProp: "source"
            }

            delegate: Entry {
                id: share
                required property var modelData

                title: Privacy.names(share.modelData.apps)
                detail: Privacy.shareName(share.modelData.source)
                glyph: Theme.glyph.screenShare
                recording: true

                PopupButton {
                    anchors.verticalCenter: parent.verticalCenter
                    framed: true
                    implicitWidth: 62
                    label: "Stop"
                    name: "Stop sharing with " + share.title
                    onTapped: Privacy.stopShare(share.modelData.source)
                }
            }
        }
    }
}
