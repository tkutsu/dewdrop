import QtQuick

// A thicker caret with short fades and idle pauses while its field is visible.
Rectangle {
    id: root

    // Shared by TextInput fields and TextEdit editors.
    required property var textInput

    width: 2
    color: "#dddddd"
    visible: textInput.cursorVisible && !textInput.readOnly

    SequentialAnimation on opacity {
        running: root.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1

        PropertyAction { value: 1 }
        PauseAnimation { duration: 800 }
        NumberAnimation {
            from: 1
            to: 0
            duration: 200
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 300 }
        NumberAnimation {
            from: 0
            to: 1
            duration: 200
            easing.type: Easing.InOutSine
        }
    }
}
