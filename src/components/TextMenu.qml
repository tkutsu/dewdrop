import QtQuick
import qs.src.core

// What a Mac's text fields do with the mouse beyond typing: a right click
// opens Cut, Copy, Paste and Select All at the pointer (EditMenu), and a
// selection can be picked up and dropped somewhere else in its field.
// Read-only text offers only Copy and Select All. Goes inside the field:
// `TextMenu {}`.
Item {
    id: root

    readonly property Item field: parent
    readonly property bool editable: !root.field.readOnly
    readonly property bool hasSelection: root.field.selectionStart !== root.field.selectionEnd
    readonly property alias hovered: hover.hovered

    anchors.fill: parent

    property bool open: false
    // Where the right click was, which the menu hangs from.
    property point at

    onVisibleChanged: if (!root.visible)
        root.open = false

    // The menu's rows, in order, with a hairline ("") between the groups.
    readonly property var rows: root.editable ? ["Cut", "Copy", "Paste", "", "Select All"] : ["Copy", "", "Select All"]

    function can(row: string): bool {
        switch (row) {
        case "Cut":
        case "Copy":
            return root.hasSelection;
        case "Select All":
            return root.field.length > 0;
        default:
            return true;
        }
    }

    function act(row: string): void {
        switch (row) {
        case "Cut":
            root.field.cut();
            break;
        case "Copy":
            root.field.copy();
            break;
        case "Paste":
            root.field.paste();
            break;
        case "Select All":
            root.field.selectAll();
            break;
        }
    }

    // Whether a point is on the selected text, rather than merely nearest to
    // it: positionAt answers with the closest cursor even past a line's end,
    // so the edge positions also have to be on the inner side of the point.
    function onSelection(x: real, y: real): bool {
        if (!root.hasSelection)
            return false;
        const f = root.field;
        const p = f.positionAt(x, y);
        if (p < f.selectionStart || p > f.selectionEnd)
            return false;
        const r = f.positionToRectangle(p);
        if (y < r.y || y >= r.y + r.height)
            return false;
        return (p !== f.selectionStart || x >= r.x) && (p !== f.selectionEnd || x <= r.x);
    }

    // A right click away from the selection puts the cursor there first, so
    // Paste lands where you clicked.
    function openAt(x: real, y: real): void {
        const f = root.field;
        if (!root.onSelection(x, y))
            f.cursorPosition = f.positionAt(x, y);
        if (f.activeFocusOnPress)
            f.forceActiveFocus();
        root.at = Qt.point(x, y);
        root.open = true;
    }

    // --- Dragging a selection ----------------------------------------------
    // A press on the selection holds it; moving past the drag distance picks
    // it up, and the release drops it at the insertion point shown. Without a
    // move it was a click, and puts the cursor there as a click always has.
    property bool holding: false
    property bool dragging: false
    property point pressedAt
    // Where the text would land, or -1: off the field, or inside the text
    // being moved, where dropping changes nothing.
    property int dropAt: -1

    function drop(): void {
        const f = root.field;
        const start = f.selectionStart, end = f.selectionEnd, to = root.dropAt;
        if (to < 0)
            return;
        // getText rather than selectedText: a TextEdit's selectedText writes
        // line breaks as paragraph separators.
        const moved = f.getText(start, end);
        const at = to > end ? to - (end - start) : to;
        f.remove(start, end);
        f.insert(at, moved);
        f.select(at, at + moved.length);
    }

    function letGo(): void {
        root.holding = false;
        root.dragging = false;
        root.dropAt = -1;
    }

    HoverHandler {
        id: hover
        // An arrow over text that can be picked up, as on the Mac.
        cursorShape: root.dragging || root.editable && root.onSelection(hover.point.position.x, hover.point.position.y)
            ? Qt.ArrowCursor : Qt.IBeamCursor
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Every other press is the field's own: selecting by dragging, a
        // double click on a word, a link in read-only text.
        onPressed: mouse => {
            // A press anywhere on the field puts an open menu away, and
            // does nothing else, as a click outside a menu does.
            if (root.open) {
                root.open = false;
                return;
            }
            if (mouse.button === Qt.RightButton) {
                root.openAt(mouse.x, mouse.y);
                return;
            }
            mouse.accepted = root.editable && !(mouse.modifiers & Qt.ShiftModifier) && root.onSelection(mouse.x, mouse.y);
            if (!mouse.accepted)
                return;
            root.holding = true;
            root.pressedAt = Qt.point(mouse.x, mouse.y);
            if (root.field.activeFocusOnPress)
                root.field.forceActiveFocus();
        }
        onPositionChanged: mouse => {
            if (!root.holding)
                return;
            if (!root.dragging && Math.hypot(mouse.x - root.pressedAt.x, mouse.y - root.pressedAt.y) < Qt.styleHints.startDragDistance)
                return;
            root.dragging = true;
            const f = root.field;
            const p = root.contains(Qt.point(mouse.x, mouse.y)) ? f.positionAt(mouse.x, mouse.y) : -1;
            root.dropAt = p >= f.selectionStart && p <= f.selectionEnd ? -1 : p;
        }
        onReleased: mouse => {
            if (root.dragging)
                root.drop();
            else if (root.holding)
                root.field.cursorPosition = root.field.positionAt(mouse.x, mouse.y);
            root.letGo();
        }
        onCanceled: root.letGo()
    }

    // The insertion point a drop would use, while the field's own cursor
    // stays with the selection.
    Rectangle {
        readonly property rect spot: root.dropAt >= 0 ? root.field.positionToRectangle(root.dropAt) : Qt.rect(0, 0, 0, 0)
        visible: root.dropAt >= 0
        x: Math.round(spot.x)
        y: spot.y
        width: 2
        height: spot.height
        color: Theme.fg
    }

    // Built on the first right click and taken down once its fade is over;
    // loaded by URL, so until then a field costs only the handlers above.
    Linger {
        id: lifetime
        shown: root.open
        hold: menu.item?.exitMs ?? 160
        onActiveChanged: {
            if (lifetime.active)
                menu.setSource(Qt.resolvedUrl("EditMenu.qml"), { owner: root });
            else
                menu.source = "";
        }
    }

    Loader {
        id: menu
    }
}
