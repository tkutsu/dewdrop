import QtQuick

// A thicker caret that fades while its text field is active and visible.
Rectangle {
    id: root

    required property TextInput textInput

    width: 2
    color: "#dddddd"
    visible: textInput.cursorVisible && !textInput.readOnly

    SequentialAnimation on opacity {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 1
            to: 0
            duration: 1000
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            from: 0
            to: 1
            duration: 1000
            easing.type: Easing.InOutSine
        }
    }
}
