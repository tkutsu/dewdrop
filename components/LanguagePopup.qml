import QtQuick
import qs
import qs.services

// The keyboard layouts to switch between, the one in use ticked, and what the
// bar calls each at the right edge — the input menu the Mac hangs off its
// menu bar.
Popup {
    id: root

    readonly property int bodyWidth: 220

    spacing: 6

    PopupHeader {
        width: root.bodyWidth
        title: "Keyboard"
    }

    Column {
        Repeater {
            model: Keyboard.layouts

            delegate: ChoiceRow {
                id: row

                required property var modelData
                required property int index

                width: root.bodyWidth
                text: modelData.name
                current: row.index === Keyboard.index
                onTapped: Keyboard.select(row.index)

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.short
                    color: Theme.label2
                    font.pixelSize: Theme.captionSize
                }
            }
        }
    }
}
