import QtQuick
import qs

// Separate entries, each saved on Enter or focus loss after validation.
Item {
    id: root

    property var setting: null
    property bool syncing: false
    property bool closing: false
    readonly property var saved: root.setting?.get() ?? []
    implicitWidth: 400
    implicitHeight: body.implicitHeight

    onSavedChanged: root.sync()
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        root.closing = true;
        for (let i = 0; i < entries.count; i++)
            if (entries.get(i).draft !== entries.get(i).value)
                root.commit(i);
    }

    ListModel { id: entries }

    function values(): var {
        const out = [];
        for (let i = 0; i < entries.count; i++)
            if (entries.get(i).value !== "")
                out.push(entries.get(i).value);
        return out;
    }

    // Preserve the active editor when our own save comes back through Settings.
    function sync(): void {
        if (JSON.stringify(root.saved) === JSON.stringify(root.values()))
            return;
        root.syncing = true;
        entries.clear();
        for (const value of root.saved)
            entries.append({ value: String(value), draft: String(value), message: "" });
        root.syncing = false;
    }

    function commit(index: int): bool {
        if (index < 0 || index >= entries.count)
            return false;
        const value = entries.get(index).draft.trim();
        let message = value === "" ? "Enter a value or remove this entry." : (root.setting?.validate?.(value) ?? "");
        for (let i = 0; !message && i < entries.count; i++)
            if (i !== index && entries.get(i).value === value)
                message = "This entry is already in the list.";
        entries.setProperty(index, "message", message);
        if (message)
            return false;
        const changed = value !== entries.get(index).value;
        entries.setProperty(index, "value", value);
        entries.setProperty(index, "draft", value);
        if (changed)
            root.setting.set(root.values());
        return true;
    }

    function add(): void {
        let index = -1;
        for (let i = 0; i < entries.count; i++)
            if (entries.get(i).value === "")
                index = i;
        if (index < 0) {
            index = entries.count;
            entries.append({ value: "", draft: "", message: "" });
        }
        Qt.callLater(() => rows.itemAt(index)?.input.forceActiveFocus());
    }

    function remove(index: int): void {
        const changed = entries.get(index).value !== "";
        entries.remove(index);
        if (changed)
            root.setting.set(root.values());
    }

    Column {
        id: body
        width: root.width
        spacing: 6

        Repeater {
            id: rows
            model: entries

            delegate: Column {
                id: entry

                required property int index
                required property string value
                required property string draft
                required property string message
                property bool removing: false
                property alias input: input
                width: root.width
                spacing: 3

                onDraftChanged: if (input.text !== entry.draft)
                    input.text = entry.draft

                SettingField {
                    width: parent.width - 32
                    implicitHeight: 26
                    visible: !!root.setting?.setTitle && entry.value !== ""
                    setting: ({
                        title: "Feed Title " + (entry.index + 1),
                        placeholder: "Feed title (optional)",
                        get: () => root.setting?.getTitle?.(entry.value) ?? "",
                        set: title => root.setting?.setTitle?.(entry.value, title)
                    })
                }

                Row {
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        width: parent.width - removeButton.width - parent.spacing
                        height: 26
                        radius: Theme.selectionRadius + 2
                        color: Theme.well
                        border.width: Theme.pillBorder
                        border.color: entry.message ? Theme.warn : input.activeFocus ? Theme.outline : "transparent"

                        TextInput {
                            id: input

                            Accessible.name: (root.setting?.title ?? "Entry") + " " + (entry.index + 1)
                            Accessible.description: entry.message
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            activeFocusOnTab: true
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Theme.fg
                            selectionColor: Theme.textSelection
                            selectedTextColor: Theme.fg
                            cursorDelegate: TextCaret { textInput: input }
                            selectByMouse: true
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.captionSize
                            Component.onCompleted: text = entry.draft
                            onTextEdited: entries.setProperty(entry.index, "draft", text)
                            onEditingFinished: if (!entry.removing && !root.syncing && !root.closing)
                                root.commit(entry.index)

                            Keys.onEscapePressed: function (event) {
                                event.accepted = entry.draft !== entry.value || entry.value === "" || entry.message !== "";
                                if (entry.value === "") {
                                    entry.removing = true;
                                    root.remove(entry.index);
                                } else {
                                    entries.setProperty(entry.index, "draft", entry.value);
                                    entries.setProperty(entry.index, "message", "");
                                }
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

                    PopupButton {
                        id: removeButton

                        anchors.verticalCenter: parent.verticalCenter
                        framed: true
                        glyph: Theme.glyph.minus
                        name: "Remove " + (root.setting?.title ?? "Entry") + " " + (entry.index + 1)
                        activeFocusOnTab: true
                        lit: activeFocus
                        onTapped: {
                            entry.removing = true;
                            forceActiveFocus();
                            root.remove(entry.index);
                        }
                        Keys.onSpacePressed: tapped()
                        Keys.onReturnPressed: tapped()
                    }
                }

                PopupText {
                    width: parent.width - 26
                    visible: entry.message !== ""
                    text: entry.message
                    color: Theme.warn
                    font.pixelSize: Theme.footnoteSize
                    wrapMode: Text.Wrap
                }
            }
        }

        PopupButton {
            framed: true
            label: "Add"
            glyph: Theme.glyph.plus
            name: "Add " + (root.setting?.title ?? "Entry")
            activeFocusOnTab: true
            lit: activeFocus
            onTapped: root.add()
            Keys.onSpacePressed: tapped()
            Keys.onReturnPressed: tapped()
        }
    }
}
