import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The Mac's recording indicator: while an app is using a microphone or
// sharing the screen (services/Privacy.qml), a pill of its own comes out of
// the centre pill with a red dot breathing on it, and what is live beside the
// dot. Click it for who, and to mute or stop them (PrivacyPopup).
//
// Comes out of the centre pill and is drawn back into it; the bar draws the
// pill off `reveal` (Bar.drop), and nothing folds. Silent captures return to
// the central icon once their controls are closed.
BarItem {
    id: root
    name: "Recording"

    stowed: !Privacy.recording && !popupOpen
    folds: false
    tooltip: Privacy.summary
    popup: PrivacyPopup { morphs: true }

    // Hold the departing symbols after capture ends, just as media keeps its title.
    readonly property var current: Privacy.active ? {
        listening: Privacy.listening, sharing: Privacy.sharing,
        muted: Privacy.microphonesMuted, recording: Privacy.recording
    } : null
    property var kept: ({listening: false, sharing: false, muted: false, recording: false})
    onCurrentChanged: if (current) kept = current

    readonly property bool sliding: pill?.slidesContent ?? false
    readonly property real glassWidth: sliding ? pill.foldBox.z : width
    readonly property real glassLeft: sliding ? pill.foldBox.x : 0
    readonly property real iconInset: Math.min(padLeft, Math.max(0, (glassWidth - microphone.width) / 2))
    readonly property real contentLoss: sliding ? Math.max(0, pill.width - glassWidth) : 0
    // Move and crossfade into the central icon as the glass joins it, the
    // same path the media pills take.
    property Item mergedIcon: null
    readonly property MediaIconHandoff iconHandoff: MediaIconHandoff {
        source: microphone
        target: root.mergedIcon
        reveal: root.reveal
        restingX: root.sliding ? root.glassLeft + root.iconInset - root.padLeft : 0
    }
    readonly property bool iconInCentre: iconHandoff.progress > 0

    Glyph {
        id: microphone
        scale: root.sliding ? root.pill.iconScale : 1
        Layout.fillHeight: true
        visible: root.kept.listening || root.kept.sharing
        opacity: 1 - root.iconHandoff.progress
        text: root.kept.listening ? (root.kept.muted ? Theme.glyph.micMuted : Theme.glyph.mic) : Theme.glyph.screenShare
        transform: Translate { x: root.iconHandoff.sourceX }
    }

    Item {
        id: details
        Layout.fillHeight: true
        implicitWidth: parts.implicitWidth
        visible: root.kept.recording || (root.kept.listening && root.kept.sharing)
        transform: Translate { x: root.sliding ? root.glassLeft + root.iconInset - root.padLeft : 0 }

        Marquee {
            width: Math.max(0, details.width - root.contentLoss)
            height: parent.height
            contentWidth: parts.implicitWidth
            active: true
            paused: true
            travel: root.contentLoss

            RowLayout {
                id: parts
                width: implicitWidth
                height: parent.height
                spacing: root.spacing

                Glyph {
                    scale: root.sliding ? root.pill.iconScale : 1
                    Layout.fillHeight: true
                    visible: root.kept.listening && root.kept.sharing
                    text: Theme.glyph.screenShare
                }

                // A dot, not a glyph: it is a light, and a light is round at any size.
                // It breathes rather than blinks, and dims rather than goes out, so it
                // reads as "on" from across the room and is not something flashing at you.
                Rectangle {
                    id: dot

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: Theme.recording
                    visible: root.kept.recording

                    SequentialAnimation on opacity {
                        running: Privacy.recording && !Theme.reduceMotion
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) dot.opacity = 1

                        NumberAnimation {
                            to: 0.4
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: 1
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }
        }
    }
}
