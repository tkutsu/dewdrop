import QtQuick

// A thicker caret that blinks while its text field is active and visible.
Rectangle {
    id: root

    required property TextInput textInput

    width: 2
    color: "#dddddd"
    visible: textInput.cursorVisible && !textInput.readOnly

    SequentialAnimation on opacity {
        running: root.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1

        PropertyAction { value: 1 }
        PauseAnimation { duration: 1000 }
        PropertyAction { value: 0 }
        PauseAnimation { duration: 1000 }
    }
}
