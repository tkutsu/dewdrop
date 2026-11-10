import QtQuick
import qs.src.core

// A line of text, saved on Enter, focus loss or settings closure.
// Escape puts back what was there, and with nothing to put back is left to
// whatever holds the field (the settings window closes on it).
Rectangle {
    id: root

    property var setting: null
    property bool edited: false
    // Why the typed text was refused. SettingRow shows it; the draft stays put
    // to be corrected, and is never saved.
    property string trouble: ""

    implicitWidth: root.setting?.fieldWidth ?? 160
    implicitHeight: 22
    radius: Theme.selectionRadius + 2
    color: Theme.well
    border.width: Theme.pillBorder
    border.color: root.trouble ? Theme.warn : input.activeFocus ? Theme.outline : "transparent"

    // The settings window's keys (SettingsMenu.qml) hand it the typing.
    function keyFocus(): void {
        input.forceActiveFocus();
        input.selectAll();
    }

    function problem(text: string): string {
        return root.setting.validate?.(text) ?? "";
    }

    Component.onDestruction: if (root.edited && root.setting && input.text !== input.stored && !root.problem(input.text))
        root.setting.set(input.text)

    TextInput {
        id: input
        Accessible.name: root.setting?.title ?? ""

        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.fg
        selectionColor: Theme.textSelection
        selectedTextColor: Theme.fg
        cursorDelegate: TextCaret { textInput: input }
        selectByMouse: true
        font.family: Theme.bodyFont
        font.pixelSize: Theme.captionSize
        font.features: Theme.figures

        // Kept to the stored value until it is being edited.
        readonly property string stored: String(root.setting?.get() ?? "")
        onStoredChanged: if (!activeFocus)
            text = stored
        Component.onCompleted: text = stored

        onTextEdited: {
            root.edited = true;
            root.trouble = "";
        }
        onEditingFinished: {
            if (text !== stored) {
                root.trouble = root.problem(text);
                if (!root.trouble)
                    root.setting.set(text);
            }
            root.edited = false;
        }

        Keys.onEscapePressed: function (event) {
            event.accepted = text !== stored;
            root.edited = false;
            root.trouble = "";
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
