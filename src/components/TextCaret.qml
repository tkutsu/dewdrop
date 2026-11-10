import QtQuick
import qs.src.core

// The text cursor of every field, in the shape and animation picked in
// Settings. It holds still and solid while the cursor is moving, so typing and
// deleting never animate it.
Rectangle {
    id: root

    // Shared by TextInput fields and TextEdit editors.
    required property var textInput

    readonly property bool block: Settings.caretShape === "block"
    // What a block covers and redraws inverted: nothing on a space, a line end
    // or the end of the text, which take an average character's width.
    readonly property string covered: {
        const code = root.textInput.text.codePointAt(root.textInput.cursorPosition);
        const character = code === undefined ? "" : String.fromCodePoint(code);
        return character.trim();
    }

    readonly property bool idle: visible && !moving.running

    width: !block ? 2 : Math.ceil(covered ? metrics.advanceWidth(covered) : metrics.averageCharacterWidth)
    color: "#dddddd"
    visible: textInput.cursorVisible && !textInput.readOnly

    onXChanged: moving.restart()
    onYChanged: moving.restart()

    Timer {
        id: moving
        interval: 500
    }

    FontMetrics {
        id: metrics
        font: root.textInput.font
    }

    Text {
        visible: root.block
        text: root.covered
        textFormat: Text.PlainText
        font: root.textInput.font
        color: Theme.solid
    }

    // A one-second cycle of quick fades with short holds, as in VS Code's phase.
    SequentialAnimation on opacity {
        id: phase

        running: root.idle && Settings.caretAnimation === "phase"
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

    // Hard on and off, at the toolkits' usual half second.
    SequentialAnimation on opacity {
        id: blink

        running: root.idle && Settings.caretAnimation === "blink"
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1

        PropertyAction { value: 1 }
        PauseAnimation { duration: 500 }
        PropertyAction { value: 0 }
        PauseAnimation { duration: 500 }
    }
}
