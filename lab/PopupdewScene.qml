import QtQuick

// Round two of the popover: the pill drops a dew that becomes the box
// (lab/PopupColumn.qml).
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property bool open: false

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 600 }
        PropertyAction { target: scene; property: "open"; value: true }
        PauseAnimation { duration: 1700 }
        PropertyAction { target: scene; property: "open"; value: false }
        PauseAnimation { duration: 1000 }
    }

    Row {
        Repeater {
            model: [["E1", "E1 · dew falls, blooms"], ["E2", "E2 · dew pours while joined"], ["E3", "E3 · dew falls, splashes"], ["E4", "E4 · small slow dew, no bounce"]]

            PopupColumn {
                required property var modelData
                variant: modelData[0]
                title: modelData[1]
                backdrop: scene.backdrop
                blurred: scene.blurred
                stage: scene
                open: scene.open
            }
        }
    }
}
