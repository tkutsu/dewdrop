import QtQuick
import Quickshell
import qs
import qs.components
import qs.services

// Google task lists keep their manual order and wrap to fit.
// A hold folds the rows to one line so a drop can choose a task list or parent.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWideWidth
    // The same air above the first line and below the last, however many
    // lines a task wraps to; a one-line row is one line plus that air.
    readonly property int rowPad: 4
    readonly property FontMetrics caption: FontMetrics {
        font.family: Theme.bodyFont
        font.pixelSize: Theme.captionSize
    }
    readonly property int lineHeight: Math.ceil(root.caption.height)
    readonly property int rowHeight: root.lineHeight + root.rowPad * 2
    readonly property int gutter: 16
    readonly property int dotLeft: 5
    readonly property int indentThreshold: 24
    readonly property int dayWidth: 46
    // The header's plus is 20 wide at the right edge; the row buttons sit
    // under it.
    readonly property int actionsWidth: 20
    property var editing: null
    property string draft: ""
    readonly property var rows: Tasks.rows
    readonly property var dropDestination: reorder.showing
        ? root.destination(reorder.from, reorder.to, reorder.horizontalOffset) : null
    readonly property int dragIndent: root.dropDestination?.parent ? root.gutter : 0
    property real compact: reorder.showing ? 1 : 0
    Behavior on compact {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }
    onCompactChanged: if (reorder.dragging) {
        list.forceLayout();
        const row = list.itemAtIndex(reorder.from);
        if (row) list.contentY = row.y - reorder.holdTop;
        reorder.updateTarget();
    }

    onRequestedVisibleChanged: if (!requestedVisible) {
        // Outside clicks and popup browsing must not discard a changed draft.
        if (root.editing && root.draft !== root.editText(root.editing)) root.saveEdit();
        else root.cancelEdit();
        Tasks.commit();
    }

    Connections {
        target: Tasks
        function onCommitted() {
            if (Tasks.tasks.length === 0) OpenPopup.close(root.anchorItem);
        }
    }

    function editText(task) {
        if (task.kind === "header") return task.title;
        return task.title + (task.notes ? "\n" + task.notes : "");
    }

    function beginEdit(task) {
        if (reorder.showing) return;
        if (root.editing && (root.editing.id !== task.id || root.editing.kind !== task.kind)) {
            root.saveEdit();
            if (root.editing) return;
        }
        root.editing = task;
        root.draft = root.editText(task);
        root.setKey(null);
        Qt.callLater(() => {
            list.forceLayout();
            const index = root.rows.findIndex(r => (r.kind === "header") === (task.kind === "header") && r.id === task.id);
            list.positionViewAtIndex(index, ListView.Contain);
            Qt.callLater(() => list.itemAtIndex(index)?.focusEditor());
        });
    }

    function cancelEdit() {
        root.keyInput = null;
        root.editing = null;
        root.draft = "";
    }

    function saveEdit() {
        if (!root.editing) return;
        const saved = root.editing.kind === "header"
            ? Tasks.renameList(root.editing.id, root.draft) : Tasks.edit(root.editing, root.draft);
        if (saved) root.cancelEdit();
    }

    // Vertical motion picks the slot; horizontal motion chooses its depth.
    function destination(from, to, offsetX) {
        const held = reorder.rows[from];
        if (!held || held.kind === "header") return null;
        // Upward gaps precede the target; downward gaps follow it. Excluding
        // the held family keeps a parent from landing after its own children.
        const boundary = to + (to > from ? 1 : 0);
        const remaining = reorder.rows.filter(r => r.id !== held.id && r.parent !== held.id);
        const before = reorder.rows.slice(0, boundary).filter(r => r.id !== held.id && r.parent !== held.id);
        const header = before.filter(r => r.kind === "header").pop();
        const listId = header?.listId ?? Tasks.lists[0]?.id ?? held.listId;
        const prior = before[before.length - 1];
        const next = remaining[before.length];
        // Keep an existing child in its family unless dragged left to promote.
        let parent = held.parent && listId === held.listId
            && (prior?.id === held.parent || prior?.parent === held.parent || next?.parent === held.parent) ? held.parent : "";
        if (offsetX <= -root.indentThreshold) parent = "";
        if (offsetX >= root.indentThreshold) {
            // A slot among children joins their parent: nesting stays one level.
            const candidate = prior?.parent
                ? reorder.rows.find(r => r.id === prior.parent && r.listId === listId) : prior;
            const canIndent = candidate?.kind === "task" && candidate.listId === listId
                && !held.children?.length && !held.assignmentInfo && !candidate.assignmentInfo
                && !Tasks.isCrossed(candidate);
            parent = canIndent ? candidate.id : "";
        }
        const previous = before.filter(r => r.kind !== "header" && r.listId === listId && (r.parent || "") === parent).pop();
        return { list: listId, parent: parent, previous: previous?.id ?? "" };
    }

    // A sideways-only gesture can change depth without changing the slot.
    function moveRow(from, to, offsetX) {
        const held = reorder.rows[from];
        const target = root.destination(from, to, offsetX);
        if (!target || (from === to && target.list === held.listId && target.parent === (held.parent || ""))) return;
        Tasks.move(held, target);
    }

    PopupHeader {
        width: root.bodyWidth
        title: "Tasks"
        addable: Tasks.loaded
        onAdd: Launcher.openWith(Launcher.taskPrefix)
        ReconnectButton {}
        RetryButton { service: Tasks }

        // There is no Google Tasks app here, so the page (as the bar's right
        // click opens it).
        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            name: "Open Google Tasks"
            onTapped: {
                OpenPopup.dismiss();
                Quickshell.execDetached(["xdg-open", "https://tasks.google.com/"]);
            }
        }
    }

    PopupNote {
        width: root.bodyWidth
        visible: Tasks.loaded && Tasks.trouble !== "" && Tasks.trouble !== Google.reconnect
        text: Tasks.trouble
        warn: true
        font.pixelSize: Theme.footnoteSize
    }

    PopupNote {
        width: root.bodyWidth
        visible: Tasks.pending.length > 0
        text: "Waiting to save…"
        font.pixelSize: Theme.footnoteSize
    }

    PopupNote {
        width: root.bodyWidth
        visible: !Tasks.loaded || Tasks.tasks.length === 0
        text: !Tasks.loaded ? (Tasks.trouble || "Connecting…") : "No tasks"
    }

    ListView {
        id: list
        width: root.bodyWidth
        // Compaction changes content height, but the pointer's coordinate system
        // must stay fixed until the held row has landed.
        height: reorder.showing ? reorder.holdHeight : Math.min(contentHeight, 320, (root.screen?.height ?? 800) * 0.6)
        clip: true
        interactive: !reorder.showing && !root.editing && contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        SmoothScroll { view: list }
        layer.enabled: contentHeight > height
        layer.effect: ScrollEdges { view: list }
        Accessible.role: Accessible.List
        Accessible.name: "Tasks"
        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)
        model: reorder.showing ? reorder.rows : root.rows

        ListReorder {
            id: reorder
            view: list
            model: root.rows
            heldModel: Tasks.dragRows
            rowHeight: root.rowHeight
            rightGuard: root.actionsWidth
            allowSingle: true
            enabled: !root.editing
            canLift: index => root.rows[index].kind !== "header"
            canHold: index => !Tasks.isCrossed(root.rows[index])
            onMoved: (from, to) => root.moveRow(from, to, reorder.horizontalOffset)
            onClicked: index => Tasks.complete(rows[index])
            lifted: Component {
                Item {
                    Rectangle {
                        x: root.dotLeft + root.dragIndent
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: Tasks.dotColour(reorder.rows[reorder.from])
                    }
                    PopupText {
                        x: root.gutter + root.dragIndent
                        y: root.rowPad
                        width: parent.width - x - Theme.popupInset
                        text: reorder.rows[reorder.from]?.title ?? ""
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }
                }
            }
        }

        delegate: PopupRow {
            id: row
            required property var modelData
            required property int index
            readonly property bool header: modelData.kind === "header"
            readonly property bool sub: modelData.kind === "subtask"
            // A family is threaded by a line down from the parent's dot,
            // past its numbered children.
            readonly property bool threaded: !reorder.showing && (sub || root.rows[index + 1]?.kind === "subtask")
            readonly property bool lastChild: sub && root.rows[index + 1]?.kind !== "subtask"
            readonly property bool crossed: !header && Tasks.isCrossed(modelData)
            readonly property bool editing: root.editing?.id === modelData.id && (root.editing.kind === "header") === header
            readonly property int indent: sub ? root.gutter : 0
            readonly property var keyEdit: () => root.beginEdit(modelData)
            readonly property string dayText: {
                if (header) return "";
                const day = Tasks.dayOf(modelData);
                return day === "" || day === Tasks.today || day === Tasks.tomorrow ? "" : Tasks.sayDay(day);
            }
            // A list name is renamed by its edit button, so the header itself
            // neither lights nor takes a press.
            name: header ? "" : (crossed ? "Reopen " : "Complete ") + modelData.title
            acceptsTap: false
            width: list.width
            readonly property real fullHeight: editing ? Math.max(root.rowHeight, editor.contentHeight + root.rowPad * 2) : header ? root.rowHeight
                : Math.max(root.rowHeight, label.implicitHeight + (modelData.notes ? notes.implicitHeight + 2 : 0) + root.rowPad * 2)
            height: fullHeight + (root.rowHeight - fullHeight) * root.compact
            clip: root.compact > 0
            opacity: reorder.showing && index === reorder.from ? 0 : crossed ? 0.4 : 1
            onTapped: if (!editing && !reorder.showing) Tasks.complete(modelData)
            transform: Translate {
                y: reorder.shift(row.index)
                Behavior on y {
                    enabled: reorder.showing
                    NumberAnimation {
                        duration: Theme.revealMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }

            // The bar forwards keys while the editor keeps mouse selection.
            function focusEditor() {
                editor.forceActiveFocus();
                root.keyInput = editor;
            }

            Rectangle {
                visible: row.threaded && !(row.editing && !row.sub)
                x: root.gutter / 2 - 0.5
                y: row.sub ? 0 : dot.y + dot.height / 2 + 6
                width: 1
                height: (row.lastChild ? root.rowPad + root.lineHeight : row.height) - y
                color: Theme.label3
            }
            Rectangle {
                id: dot
                visible: !row.header && !row.sub && !row.editing
                // Hang off the first line's x-height, even when the title wraps.
                x: row.indent + (root.gutter - width) / 2
                anchors.baseline: label.baseline
                anchors.baselineOffset: -(metrics.xHeight + height) / 2 - 1
                width: row.hovered ? 8 : 6
                height: width
                radius: width / 2
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.selectMs
                        easing.type: Easing.OutCubic
                    }
                }
                color: Tasks.dotColour(row.modelData)
            }
            PopupText {
                visible: row.sub && !row.editing
                x: row.indent
                anchors.baseline: label.baseline
                width: root.gutter - 4
                text: row.modelData.number + "."
                font.pixelSize: Theme.captionSize
                horizontalAlignment: Text.AlignRight
                color: Tasks.urgency(row.modelData) === "none" ? Theme.label2 : Tasks.dotColour(row.modelData)
            }
            PopupText {
                id: label
                FontMetrics {
                    id: metrics
                    font: label.font
                }
                visible: !row.editing
                x: row.header ? root.dotLeft : row.indent + root.gutter
                y: root.rowPad
                width: parent.width - x - root.actionsWidth - (row.dayText ? root.dayWidth : 0) - Theme.popupInset
                text: row.modelData.title
                textFormat: Text.PlainText
                font.pixelSize: Theme.captionSize
                font.strikeout: row.crossed
                color: row.header ? Theme.label2 : Theme.fg
                wrapMode: root.compact >= 1 ? Text.NoWrap : Text.WordWrap
                elide: root.compact >= 1 ? Text.ElideRight : Text.ElideNone
            }
            PopupText {
                id: notes
                visible: !row.header && !row.editing && !reorder.showing && text !== ""
                x: label.x
                y: label.y + label.implicitHeight + 2
                width: parent.width - x - root.actionsWidth - Theme.popupInset
                text: row.modelData.notes ?? ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.footnoteSize
                font.strikeout: row.crossed
                color: Theme.label2
                // All of it: a note is the rest of what the task says.
                wrapMode: Text.WordWrap
            }
            PopupText {
                anchors.right: actions.left
                anchors.rightMargin: 2
                anchors.baseline: label.baseline
                width: row.dayText ? root.dayWidth : 0
                visible: !row.editing
                text: row.dayText
                font.pixelSize: Theme.footnoteSize
                horizontalAlignment: Text.AlignRight
                color: Tasks.urgency(row.modelData) === "late" ? Theme.warn : Theme.label2
                elide: Text.ElideRight
            }
            // One button in one place: edit under the pointer, and copy once
            // editing, for what the editor holds now, saved or not.
            PopupButton {
                id: actions
                anchors.right: parent.right
                // Centred on the first line, however far the task wraps.
                y: Math.round(root.rowPad + (root.lineHeight - height) / 2)
                width: root.actionsWidth
                height: 22
                // A list name being edited has no copy button.
                visible: !reorder.showing && (row.editing ? !row.header : row.hovered)
                glyph: row.editing ? Theme.glyph.copy : Theme.glyph.edit
                name: (row.editing ? "Copy " : row.header ? "Rename task list " : "Edit ") + row.modelData.title
                onTapped: row.editing ? Launcher.copy(root.draft) : root.beginEdit(row.modelData)
            }
            TextEdit {
                id: editor
                objectName: "taskEditor"
                Accessible.name: row.header ? "Task list name" : "Task title and notes"
                visible: row.editing
                x: row.header ? root.dotLeft : row.indent + root.gutter
                y: root.rowPad
                // Clear of the copy button; a list name has none.
                width: parent.width - x - (row.header ? 0 : root.actionsWidth) - Theme.popupInset
                height: Math.max(root.lineHeight, contentHeight)
                text: row.editing ? root.draft : ""
                textFormat: TextEdit.PlainText
                color: Theme.fg
                selectionColor: Theme.selectionStrong
                selectedTextColor: Theme.fg
                font.family: Theme.bodyFont
                font.pixelSize: Theme.captionSize
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                onTextChanged: if (row.editing) root.draft = text
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.cancelEdit();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (row.header || !(event.modifiers & Qt.ShiftModifier))) {
                        root.saveEdit();
                        event.accepted = true;
                    }
                }
            }
        }
    }
}
