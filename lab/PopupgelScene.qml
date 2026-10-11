import QtQuick

// Round two of the popover: B, and B with gel in it (lab/PopupColumn.qml).
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
            model: [["B", "B · scale (round one)"], ["G1", "G1 · height runs past, settles"], ["G2", "G2 · bottom sags, springs back"], ["G3", "G3 · two springs, height looser"]]

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
