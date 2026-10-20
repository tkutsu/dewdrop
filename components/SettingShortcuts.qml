import QtQuick
import qs

// Edit each web shortcut as one validated entry, saving on Enter or focus loss.
Item {
    id: root

    property var setting: null
    property bool syncing: false
    property bool closing: false
    readonly property var saved: root.setting?.get() ?? []
    implicitWidth: 400
    implicitHeight: body.implicitHeight

    ListModel { id: entries }

    onSavedChanged: root.sync()
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        root.closing = true;
        for (let i = 0; i < entries.count; i++)
            root.commit(i);
    }

    function values(): var {
        const out = [];
        for (let i = 0; i < entries.count; i++) {
            const row = entries.get(i);
            if (row.value)
                out.push(JSON.parse(row.value));
        }
        return out;
    }

    // Keep draft fields and focus when our own save returns through Settings.
    function sync(): void {
        if (JSON.stringify(root.saved) === JSON.stringify(root.values()))
            return;
        root.syncing = true;
        entries.clear();
        for (const entry of root.saved)
            entries.append({ value: JSON.stringify(entry), name: entry.name, key: entry.key, url: entry.url, message: "" });
        root.syncing = false;
    }

    function commit(index: int): bool {
        if (index < 0 || index >= entries.count)
            return false;
        const row = entries.get(index);
        const value = { key: row.key.trim(), name: row.name.trim(), url: row.url.trim() };
        let message = !value.name ? "Enter a name for this shortcut."
            : value.key && (Array.from(value.key).length !== 1 || /\s/.test(value.key)) ? "Use one character, or leave it blank for the default search."
            : !/^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/.test(value.url) ? "Enter a full http:// or https:// URL."
            : "";
        for (let i = 0; !message && i < entries.count; i++) {
            const saved = entries.get(i).value;
            if (i !== index && saved && JSON.parse(saved).key === value.key)
                message = value.key ? "This character is already in use." : "Only one shortcut can have a blank character.";
        }
        entries.setProperty(index, "message", message);
        if (message)
            return false;
        const serialized = JSON.stringify(value);
        const changed = row.value !== serialized;
        entries.setProperty(index, "value", serialized);
        for (const field of ["key", "name", "url"])
            entries.setProperty(index, field, value[field]);
        if (changed)
            root.setting.set(root.values());
        return true;
    }

    function add(): void {
        let index = -1;
        for (let i = 0; i < entries.count; i++)
            if (!entries.get(i).value)
                index = i;
        if (index < 0) {
            index = entries.count;
            entries.append({ value: "", key: "", name: "", url: "", message: "" });
        }
        Qt.callLater(() => rows.itemAt(index)?.focusFirst());
    }

    function remove(index: int): void {
        const changed = !!entries.get(index).value;
        entries.remove(index);
        if (changed)
            root.setting.set(root.values());
    }

    function restore(index: int): void {
        const row = entries.get(index);
        const value = JSON.parse(row.value);
        for (const field of ["key", "name", "url"])
            entries.setProperty(index, field, value[field]);
        entries.setProperty(index, "message", "");
    }

    Column {
        id: body
        width: root.width
        spacing: 8

        Repeater {
            id: rows
            model: entries

            delegate: Column {
                id: entry

                required property int index
                required property string value
                required property string name
                required property string key
                required property string url
                required property string message
                property bool removing: false
                function focusFirst(): void {
                    fields.itemAt(0)?.input.forceActiveFocus();
                }
                width: root.width
                spacing: 4

                Item {
                    width: parent.width
                    height: fieldsBody.implicitHeight

                    Column {
                        id: fieldsBody
                        width: parent.width - 32
                        spacing: 4

                        Repeater {
                            id: fields
                            model: [
                                { field: "name", label: "Name", placeholder: "Shortcut name" },
                                { field: "key", label: "Character", placeholder: "Blank for default" },
                                { field: "url", label: "URL", placeholder: "https://example.com/search?q=%s" }
                            ]

                            delegate: Row {
                                id: fieldRow
                                required property var modelData
                                readonly property string draft: entry[fieldRow.modelData.field]
                                property alias input: input
                                width: fieldsBody.width
                                spacing: 6

                                onDraftChanged: if (input.text !== draft)
                                    input.text = draft

                                PopupText {
                                    width: 66
                                    height: 26
                                    verticalAlignment: Text.AlignVCenter
                                    text: fieldRow.modelData.label
                                    color: Theme.label2
                                    font.pixelSize: Theme.captionSize
                                }

                                Rectangle {
                                    width: parent.width - 72
                                    height: 26
                                    radius: Theme.selectionRadius + 2
                                    color: Theme.well
                                    border.width: Theme.pillBorder
                                    border.color: entry.message ? Theme.warn : input.activeFocus ? Theme.outline : "transparent"

                                    TextInput {
                                        id: input
                                        Accessible.name: "Web Shortcut " + (entry.index + 1) + " " + fieldRow.modelData.label
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
                                        Component.onCompleted: text = fieldRow.draft
                                        onTextEdited: entries.setProperty(entry.index, fieldRow.modelData.field, text)
                                        onEditingFinished: if (!entry.removing && !root.syncing && !root.closing)
                                            root.commit(entry.index)

                                        Keys.onEscapePressed: function (event) {
                                            event.accepted = entry.message !== "" || !entry.value || JSON.stringify({key: entry.key, name: entry.name, url: entry.url}) !== entry.value;
                                            if (!entry.value) {
                                                entry.removing = true;
                                                root.remove(entry.index);
                                            } else {
                                                root.restore(entry.index);
                                            }
                                        }

                                        PopupText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !input.text
                                            text: fieldRow.modelData.placeholder
                                            color: Theme.label3
                                            font.pixelSize: Theme.captionSize
                                        }
                                    }
                                }
                            }
                        }
                    }

                    PopupButton {
                        x: parent.width - width
                        y: 0
                        framed: true
                        glyph: Theme.glyph.minus
                        name: "Remove Web Shortcut " + (entry.index + 1)
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
                    width: parent.width - 32
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
            name: "Add Web Shortcut"
            activeFocusOnTab: true
            lit: activeFocus
            onTapped: root.add()
            Keys.onSpacePressed: tapped()
            Keys.onReturnPressed: tapped()
        }
    }
}
