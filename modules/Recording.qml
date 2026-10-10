import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The Mac's recording indicator: while an app is using a microphone or
// sharing the screen (services/Privacy.qml), a pill of its own comes out of
// the right pill with a red dot breathing on it, and what is live beside the
// dot. Click it for who, and to mute or stop them (PrivacyPopup).
//
// Comes out of the right pill and is drawn back into it; the bar draws the
// pill off `reveal` (Bar.drop), and nothing folds.
BarItem {
    id: root
    name: "Recording"

    stowed: !Privacy.active
    folds: false
    tooltip: Privacy.summary
    popup: PrivacyPopup {}

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

        SequentialAnimation on opacity {
            running: Privacy.active
            loops: Animation.Infinite
            alwaysRunToEnd: true

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

    Glyph {
        Layout.fillHeight: true
        visible: Privacy.listening
        text: Theme.glyph.mic
    }

    Glyph {
        Layout.fillHeight: true
        visible: Privacy.sharing
        text: Theme.glyph.screenShare
    }
}
