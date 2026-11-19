import QtQuick
import qs.src.core

// A password shown as the keys it took, a dot or an asterisk for each as
// Password Fields' Character says, dropping into place as it is typed when Typing
// Animation says so. The lock screen and the polkit panel both draw theirs
// with it.
Row {
    id: root

    property int count: 0
    // Each character's room, to sit over a field's own hidden characters;
    // 0 packs them `spacing` apart.
    property real cell: 0
    // A dot's size; an asterisk is drawn to match it.
    property real dot: 8
    property color color: Theme.fg

    readonly property bool asterisks: Settings.passwordStyle === "asterisks"

    spacing: root.cell ? 0 : 5

    // Added and taken at the end rather than rebuilt from a number, so the
    // characters already shown stay put and only a new one drops in.
    function sync(): void {
        while (keys.count > root.count)
            keys.remove(keys.count - 1);
        while (keys.count < root.count)
            keys.append({});
    }

    onCountChanged: sync()
    Component.onCompleted: sync()

    ListModel {
        id: keys
    }

    Repeater {
        model: keys

        Item {
            id: key

            property real drop: 0

            width: root.cell || (root.asterisks ? asterisk.implicitWidth : root.dot)
            height: Math.max(root.dot, asterisk.implicitHeight)
            transform: Translate {
                y: key.drop
            }

            Component.onCompleted: if (Settings.passwordMotion === "drop" && !Theme.reduceMotion)
                landing.start()

            // From a little above, overshooting the line and settling on it.
            ParallelAnimation {
                id: landing

                NumberAnimation { target: key; property: "drop"; from: -root.dot * 1.5; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                NumberAnimation { target: key; property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
            }

            Rectangle {
                anchors.centerIn: parent
                visible: !root.asterisks
                width: root.dot
                height: root.dot
                radius: root.dot / 2
                color: root.color
            }

            // Inter's own asterisk rides at the capitals' height.
            Text {
                id: asterisk

                anchors.centerIn: parent
                visible: root.asterisks
                text: "\u{f06c4}" // nf-md-asterisk
                color: root.color
                font.family: Theme.glyphFont
                font.pixelSize: Math.round(root.dot * 1.5)
            }
        }
    }
}
