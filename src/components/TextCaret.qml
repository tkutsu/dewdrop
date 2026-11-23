import QtQuick

// The text cursor of every field: a line that phases while it rests. It holds
// still and solid while the cursor is moving, so typing and deleting never
// animate it.
Rectangle {
    id: root

    // Shared by TextInput fields and TextEdit editors.
    required property var textInput

    readonly property bool idle: visible && !moving.running

    width: 2
    color: "#dddddd"
    visible: textInput.cursorVisible && !textInput.readOnly

    onXChanged: moving.restart()
    onYChanged: moving.restart()

    Timer {
        id: moving
        interval: 500
    }

    // A one-second cycle of quick fades with short holds, as in VS Code's phase.
    SequentialAnimation on opacity {
        running: root.idle
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1

        PauseAnimation { duration: 100 }
        NumberAnimation {
            from: 1
            to: 0
            duration: 350
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 100 }
        NumberAnimation {
            from: 0
            to: 1
            duration: 350
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 100 }
    }
}
