import QtQuick
import qs

// A line of text, written when Enter is pressed or the field is left.
// Escape puts back what was there, and with nothing to put back is left to
// whatever holds the field (the settings window closes on it).
Rectangle {
    id: root

    property var setting: null

    implicitWidth: 160
    implicitHeight: 22
    radius: Theme.selectionRadius + 2
    color: Theme.well
    border.width: Theme.pillBorder
    border.color: input.activeFocus ? Theme.outline : "transparent"

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.fg
        selectionColor: Theme.selection
        selectedTextColor: Theme.fg
        selectByMouse: true
        font.family: Theme.bodyFont
        font.pixelSize: Theme.captionSize
        font.features: Theme.figures

        // Kept to the stored value until it is being edited.
        readonly property string stored: String(root.setting?.get() ?? "")
        onStoredChanged: if (!activeFocus)
            text = stored
        Component.onCompleted: text = stored

        onEditingFinished: if (text !== stored)
            root.setting.set(text)

        Keys.onEscapePressed: function (event) {
            event.accepted = text !== stored;
            text = stored;
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            text: root.setting?.placeholder ?? ""
            color: Theme.label3
            font.pixelSize: Theme.captionSize
        }
    }
}
