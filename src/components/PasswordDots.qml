import QtQuick
import qs.src.core

// A password shown as a dot for each key it took, each fading in as it rises
// into place. The lock screen and the polkit panel both draw theirs with it.
Row {
    id: root

    property int count: 0
    // Each dot's room, to sit over a field's own hidden characters; 0 packs
    // them `spacing` apart.
    property real cell: 0
    property real dot: 8
    property color color: Theme.fg

    spacing: root.cell ? 0 : 5

    // Added and taken at the end rather than rebuilt from a number, so the
    // dots already shown stay put and only a new one comes in.
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

            property real rise: 0

            width: root.cell || root.dot
            height: root.dot
            transform: Translate {
                y: key.rise
            }

            Component.onCompleted: if (!Theme.reduceMotion)
                arrival.start()

            ParallelAnimation {
                id: arrival

                NumberAnimation { target: key; property: "rise"; from: root.dot * 0.75; to: 0; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: key; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.dot
                height: root.dot
                radius: root.dot / 2
                color: root.color
            }
        }
    }
}
