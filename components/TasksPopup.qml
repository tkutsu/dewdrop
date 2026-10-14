import QtQuick
import qs
import qs.components
import qs.services

// Google's lists are sections; tasks keep their manual order and wrap to fit.
// A hold folds the rows to one line so a drop can choose a section or parent.
Popup {
    id: root

    readonly property int bodyWidth: 300
    readonly property int rowHeight: 28
    readonly property int gutter: 16
    readonly property int dayWidth: 46
    readonly property int actionsWidth: 24
    property var editing: null
    property string draft: ""
    readonly property var rows: Tasks.rows
    property real compact: reorder.showing ? 1 : 0
    Behavior on compact { NumberAnimation { duration: Theme.revealMs; easing.type: Easing.OutCubic } }
    onCompactChanged: if (reorder.dragging) {
        list.forceLayout();
        const row = list.itemAtIndex(reorder.from);
        if (row) list.contentY = row.y - reorder.holdTop;
        reorder.updateTarget();
    }

    onRequestedVisibleChanged: if (!requestedVisible) {
        root.cancelEdit();
        Tasks.commit();
    }

    Connections {
        target: Tasks
        function onCommitted() {
            if (Tasks.tasks.length === 0) OpenPopup.close(root.anchorItem);
        }
    }

    function dotColour(task) {
        switch (Tasks.urgency(task)) {
        case "late": return Theme.taskLate;
        case "now": return Theme.taskToday;
        case "soon": return Theme.taskSoon;
        }
        return Theme.taskUndated;
    }

    function beginEdit(task) {
        if (Tasks.writing || reorder.showing) return;
        root.editing = task;
        root.draft = task.title + (task.notes ? "\n" + task.notes : "");
        root.setKey(null);
        Qt.callLater(() => {
            list.forceLayout();
            const index = root.rows.findIndex(r => r.kind !== "header" && r.id === task.id);
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
        if (root.editing && Tasks.edit(root.editing, root.draft)) root.cancelEdit();
    }

    // Translate a flat landing slot into Google's sibling coordinates.
    function moveRow(from, to) {
        const held = reorder.queue[from];
        if (!held || from === to) return;
        // A downward landing is after its target; a header always means
        // the first task in that section. Descendants travel with a parent.
        const boundary = to + (to > from || reorder.queue[to]?.kind === "header" ? 1 : 0);
        const before = reorder.queue.slice(0, boundary).filter((r, i) => i !== from && r.parent !== held.id);
        const header = before.filter(r => r.kind === "header").pop();
        const listId = header?.listId ?? held.listId;
        const previous = before.filter(r => r.kind === "task" && r.listId === listId).pop();
        Tasks.move(held, { list: listId, parent: "", previous: previous?.id ?? "" });
    }

    PopupHeader {
        width: root.bodyWidth
        title: "Tasks"
        addable: Tasks.loaded
        onAdd: Launcher.openWith(Launcher.taskPrefix)
        ReconnectButton {}
        RetryButton { service: Tasks }
    }

    PopupText {
        width: root.bodyWidth
        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        visible: Tasks.loaded && Tasks.trouble !== "" && Tasks.trouble !== Google.reconnect
        text: Tasks.trouble
        color: Theme.warn
        font.pixelSize: Theme.footnoteSize
        wrapMode: Text.WordWrap
    }

    PopupText {
        width: root.bodyWidth
        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        visible: !Tasks.loaded || root.rows.length === 0
        text: !Tasks.loaded ? (Tasks.trouble || "Connecting…") : "Nothing on the list"
        color: Theme.label2
        wrapMode: Text.WordWrap
    }

    ListView {
        id: list
        width: root.bodyWidth
        height: Math.min(contentHeight, 320, (root.screen?.height ?? 800) * 0.6)
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
        model: reorder.showing ? reorder.queue : root.rows

        ListReorder {
            id: reorder
            view: list
            model: root.rows
            heldModel: Tasks.dragRows
            rowHeight: root.rowHeight
            rightGuard: root.actionsWidth
            allowSingle: true
            enabled: !root.editing && Tasks.writing === 0
            canLift: index => root.rows[index].kind !== "header"
            canHold: index => !Tasks.isCrossed(root.rows[index])
            canNest: (from, onto) => {
                const a = queue[from], b = queue[onto];
                return a.id !== b.id && b.kind === "task" && !a.children?.length
                    && !a.assignmentInfo && !b.assignmentInfo && !Tasks.isCrossed(b);
            }
            onMoved: (from, to) => root.moveRow(from, to)
            onNested: (from, onto) => {
                const target = queue[onto];
                const children = target.children ?? [];
                Tasks.move(queue[from], { list: target.listId, parent: target.id, previous: children.length ? children[children.length - 1].id : "" });
            }
            onClicked: index => Tasks.complete(queue[index])
            lifted: Component {
                Item {
                    Rectangle {
                        x: 5; anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: root.dotColour(reorder.queue[reorder.from])
                    }
                    PopupText {
                        x: root.gutter; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - Theme.popupInset
                        text: reorder.queue[reorder.from]?.title ?? ""
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
            readonly property bool crossed: !header && Tasks.isCrossed(modelData)
            readonly property bool editing: !header && root.editing?.id === modelData.id
            readonly property int indent: modelData.kind === "subtask" ? root.gutter : 0
            readonly property var keyEdit: header ? null : () => root.beginEdit(modelData)
            readonly property string dayText: {
                if (header) return "";
                const children = (modelData.children ?? []).filter(t => !Tasks.isCrossed(t));
                if (children.length) return children.length + " left";
                const day = Tasks.dayOf(modelData);
                return day === "" || day === Tasks.today || day === Tasks.tomorrow ? "" : Tasks.sayDay(day);
            }
            name: header ? "" : (crossed ? "Reopen " : "Complete ") + modelData.title
            acceptsTap: false
            width: list.width
            readonly property real fullHeight: header ? root.rowHeight : editing ? Math.max(root.rowHeight, editor.contentHeight + 10)
                : Math.max(root.rowHeight, label.implicitHeight + (modelData.notes ? notes.implicitHeight + 2 : 0) + 8)
            height: fullHeight + (root.rowHeight - fullHeight) * root.compact
            clip: root.compact > 0
            opacity: reorder.showing && index === reorder.from ? 0 : crossed ? 0.4 : 1
            onTapped: if (!header && !editing) Tasks.complete(modelData)
            transform: Translate {
                y: reorder.shift(row.index)
                Behavior on y { enabled: reorder.showing; NumberAnimation { duration: Theme.revealMs; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }

            function focusEditor() { editor.forceActiveFocus(); root.keyInput = editor; }

            Rectangle {
                anchors.fill: parent
                radius: Theme.selectionRadius
                color: Theme.selectionStrong
                visible: reorder.dragging && reorder.onto === row.index
            }
            Rectangle {
                visible: !row.header && !row.editing
                x: row.indent + 5; y: 11
                width: 6; height: 6; radius: 3
                color: root.dotColour(row.modelData)
            }
            PopupText {
                id: label
                visible: !row.editing
                x: row.indent + root.gutter; y: 4
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
                x: label.x; y: label.y + label.implicitHeight + 2
                width: parent.width - x - root.actionsWidth - Theme.popupInset
                text: row.modelData.notes ?? ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.footnoteSize
                font.strikeout: row.crossed
                color: Theme.label2
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            PopupText {
                anchors.right: actions.left
                anchors.rightMargin: 2
                y: 5; width: row.dayText ? root.dayWidth : 0
                visible: !row.editing
                text: row.dayText
                font.pixelSize: Theme.footnoteSize
                horizontalAlignment: Text.AlignRight
                color: Tasks.urgency(row.modelData) === "late" ? Theme.warn : Theme.label2
                elide: Text.ElideRight
            }
            PopupButton {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: Theme.popupInset
                y: 3; width: root.actionsWidth; height: 22
                visible: !row.header && !row.editing && !reorder.showing && row.hovered
                glyph: Theme.glyph.edit
                name: "Edit " + row.modelData.title
                live: Tasks.writing === 0
                onTapped: root.beginEdit(row.modelData)
            }
            TextEdit {
                id: editor
                objectName: "taskEditor"
                visible: row.editing
                x: root.gutter; y: 4
                width: parent.width - x - Theme.popupInset
                height: Math.max(root.rowHeight - 8, contentHeight)
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
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                        root.saveEdit();
                        event.accepted = true;
                    }
                }
            }
        }
    }
}
