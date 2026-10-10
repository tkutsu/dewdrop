import QtQuick
import Quickshell
import qs
import qs.services

// What the recording pill is about (modules/Recording.qml): each app using a
// microphone, and each screen share with the apps it goes to, with the way
// to stop it on its row. An app's mic is muted at its own stream, so only it
// hears silence; the header's switch mutes the microphone for everyone.
Popup {
    id: root

    readonly property int bodyWidth: 264

    spacing: 6

    PopupHeader {
        width: root.bodyWidth
        title: "Recording"

        PopupButton {
            framed: true
            visible: Privacy.listening
            glyph: Audio.micMuted ? Theme.glyph.micMuted : Theme.glyph.mic
            name: Audio.micMuted ? "Unmute the microphone" : "Mute the microphone"
            lit: Audio.micMuted
            onTapped: Audio.toggleMic()
        }
    }

    component Section: PopupText {
        width: root.bodyWidth
        leftPadding: 6
        color: Theme.label2
        font.pixelSize: Theme.captionSize
    }

    // One line of what, one of where, and the control at the right edge.
    component Entry: PopupRow {
        id: entry

        property string title
        property string detail
        default property alias control: end.data

        width: root.bodyWidth
        height: 40
        gesturePolicy: TapHandler.ReleaseWithinBounds

        PopupText {
            id: line
            x: 6
            y: 5
            width: end.x - x - 8
            text: entry.title
            elide: Text.ElideRight
            font.pixelSize: Theme.captionSize
            font.weight: Font.DemiBold
        }

        PopupText {
            x: 6
            anchors.top: line.bottom
            width: end.x - x - 8
            text: entry.detail
            elide: Text.ElideRight
            color: Theme.label2
            font.pixelSize: Theme.captionSize
        }

        Row {
            id: end
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Section {
        visible: Privacy.listening
        text: "Microphone"
    }

    Repeater {
        model: ScriptModel {
            values: Privacy.mics
            objectProp: "node"
        }

        delegate: Entry {
            id: mic

            required property var modelData
            readonly property bool muted: mic.modelData.node.audio?.muted ?? false

            title: mic.modelData.app
            detail: (mic.muted ? "Muted · " : "") + (mic.modelData.source.description || mic.modelData.source.name)
            name: (mic.muted ? "Unmute " : "Mute ") + mic.modelData.app
            onTapped: Privacy.toggleApp(mic.modelData.node)

            PopupButton {
                glyph: mic.muted ? Theme.glyph.micMuted : Theme.glyph.mic
                name: mic.name
                lit: mic.muted
                onTapped: Privacy.toggleApp(mic.modelData.node)
            }
        }
    }

    Section {
        visible: Privacy.sharing
        text: "Screen"
    }

    Repeater {
        model: ScriptModel {
            values: Privacy.shares
            objectProp: "source"
        }

        delegate: Entry {
            id: share

            required property var modelData

            title: Privacy.names(share.modelData.apps)
            detail: "Sharing your screen"

            PopupButton {
                framed: true
                label: "Stop"
                name: "Stop sharing with " + share.title
                onTapped: Privacy.stopShare(share.modelData.source)
            }
        }
    }
}
