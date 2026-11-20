import QtQuick
import qs.src.core

// What a Mac's text fields do with the mouse beyond typing: a right click
// opens Cut, Copy, Paste and Select All at the pointer (EditMenu), and a
// selection can be picked up and dropped somewhere else in its field.
// Goes inside the field: `TextMenu {}`.
//
// Read-only text gets only Copy and Select All, and a password field only
// Paste and Select All: what it holds is never read back out of it.
Item {
    id: root

    readonly property Item field: parent
    readonly property bool editable: !root.field.readOnly
    // A password field, while its text is hidden (a TextEdit has no echoMode).
    readonly property bool secret: root.field.echoMode !== undefined && root.field.echoMode !== TextInput.Normal
    // Whether the selection can be dragged somewhere else.
    readonly property bool movable: root.editable && !root.secret
    readonly property bool hasSelection: root.field.selectionStart !== root.field.selectionEnd
    readonly property alias hovered: hover.hovered
    // The box drawn round the field (`TextMenu { frame: box }`). Its padding
    // belongs to the field, as a Mac field's bezel does: the I-beam over it,
    // and a click there puts the caret at the nearest character.
    property Item frame: null

    anchors.fill: parent

    property bool open: false
    // Where the right click was, which the menu hangs from.
    property point at

    onVisibleChanged: if (!root.visible)
        root.close(false)

    // Put the menu away. `back` gives the focus back to the field, after a
    // choice or Escape; a click that went somewhere else leaves it there.
    function close(back: bool): void {
        if (!root.open)
            return;
        if (back && root.field.activeFocusOnPress)
            root.field.forceActiveFocus();
        root.open = false;
    }

    // The selection stays the menu's for as long as it is up. Focus can leave
    // the field once the pointer is on the menu's window, and a field drops a
    // selection that is not persistent when it loses focus, so it is made
    // persistent until the menu goes. If the focus went to something else in
    // the window meanwhile, the selection goes then, as it would have.
    property bool persistent: false
    onOpenChanged: {
        const f = root.field;
        if (root.open) {
            root.persistent = f.persistentSelection;
            f.persistentSelection = true;
            root.forwardedBefore = Array.from(f.Keys.forwardTo);
            f.Keys.forwardTo = [root];
            return;
        }
        f.Keys.forwardTo = root.forwardedBefore;
        f.persistentSelection = root.persistent;
        if (!root.persistent && !f.activeFocus && root.Window.active)
            f.deselect();
    }

    // Keys typed while the menu is up are the menu's: the arrows, Return and
    // Escape drive it, and the rest go nowhere. A bar popup's keys come to its
    // menu through the bar (Popup.qml) and never reach the field; where they
    // come straight to the field (the launcher, settings, the password panel),
    // the field hands them over.
    // Set in onOpenChanged: a Binding hands forwardTo a list of nulls.
    property var forwardedBefore: []
    Keys.onPressed: event => {
        event.accepted = true;
        menu.item?.key(event);
    }

    // The menu's rows, in order, with a hairline ("") between the groups.
    readonly property var rows: root.secret ? ["Paste", "", "Select All"]
        : root.editable ? ["Cut", "Copy", "Paste", "", "Select All"]
        : ["Copy", "", "Select All"]

    function can(row: string): bool {
        switch (row) {
        case "Cut":
            return root.hasSelection && root.editable;
        case "Copy":
            return root.hasSelection;
        case "Paste":
            return root.editable;
        case "Select All":
            return root.field.length > 0;
        default:
            return false;
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
    // Paste lands where you clicked. On a menu that is already up, it moves
    // the menu there.
    function openAt(x: real, y: real): void {
        const f = root.field;
        if (!root.onSelection(x, y))
            f.cursorPosition = f.positionAt(x, y);
        if (f.activeFocusOnPress)
            f.forceActiveFocus();
        menu.item?.setKey(null);
        root.at = Qt.point(x, y);
        root.open = true;
    }

    // --- A right press held across the menu --------------------------------
    // As on the Mac: press, drag onto a row and let go there to choose it.
    // Let go elsewhere after moving and the menu goes; let go where it was
    // pressed and it stays up, as after a click. Nothing counts until the
    // pointer has moved: the window the press just opened may not be placed
    // yet, and its rows would answer from wherever it was made.
    property bool tracking: false
    property point trackedFrom

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

    // The move is a remove and an insert, so whatever watches the text sees
    // it once without the text moved; the searches it feeds wait before they
    // run (Launcher, Weather), so only the moved text is looked up.
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

    function moved(from: point, x: real, y: real): bool {
        return Math.hypot(x - from.x, y - from.y) >= Qt.styleHints.startDragDistance;
    }

    HoverHandler {
        id: hover
        // An arrow over text that can be picked up, as on the Mac.
        cursorShape: root.dragging || root.movable && root.onSelection(hover.point.position.x, hover.point.position.y)
            ? Qt.ArrowCursor : Qt.IBeamCursor
    }

    HoverHandler {
        parent: root.frame ?? root
        enabled: root.frame !== null
        cursorShape: Qt.IBeamCursor
    }

    TapHandler {
        parent: root.frame ?? root
        enabled: root.frame !== null && root.field.activeFocusOnPress
        onTapped: point => {
            const f = root.field;
            const at = point.position;
            // Whatever else sits in the box (a switcher) keeps its own clicks.
            const hit = root.frame.childAt(at.x, at.y);
            if (hit && hit !== f)
                return;
            const p = f.mapFromItem(root.frame, at.x, at.y);
            f.forceActiveFocus();
            f.cursorPosition = f.positionAt(p.x, p.y);
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // A list the field is in would take a drag for a scroll.
        preventStealing: root.holding || root.tracking

        // Every other press is the field's own: selecting by dragging, a
        // double click on a word.
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.openAt(mouse.x, mouse.y);
                root.tracking = true;
                root.trackedFrom = Qt.point(mouse.x, mouse.y);
                return;
            }
            // A click on the field puts an open menu away, and does nothing
            // else, as a click outside a menu does.
            if (root.open) {
                root.close(true);
                return;
            }
            mouse.accepted = root.movable && !(mouse.modifiers & Qt.ShiftModifier) && root.onSelection(mouse.x, mouse.y);
            if (!mouse.accepted)
                return;
            root.holding = true;
            root.pressedAt = Qt.point(mouse.x, mouse.y);
            if (root.field.activeFocusOnPress)
                root.field.forceActiveFocus();
        }
        onPositionChanged: mouse => {
            if (root.tracking) {
                if (root.moved(root.trackedFrom, mouse.x, mouse.y))
                    menu.item?.track(root.mapToGlobal(mouse.x, mouse.y));
                return;
            }
            if (!root.holding || !root.dragging && !root.moved(root.pressedAt, mouse.x, mouse.y))
                return;
            root.dragging = true;
            const f = root.field;
            const p = root.contains(Qt.point(mouse.x, mouse.y)) ? f.positionAt(mouse.x, mouse.y) : -1;
            root.dropAt = p >= f.selectionStart && p <= f.selectionEnd ? -1 : p;
        }
        onReleased: mouse => {
            if (root.tracking) {
                root.tracking = false;
                if (!root.moved(root.trackedFrom, mouse.x, mouse.y))
                    return;
                if (!(menu.item?.release(root.mapToGlobal(mouse.x, mouse.y)) ?? false))
                    root.close(true);
                return;
            }
            if (root.dragging)
                root.drop();
            else if (root.holding)
                root.field.cursorPosition = root.field.positionAt(mouse.x, mouse.y);
            root.letGo();
        }
        onCanceled: {
            root.tracking = false;
            if (menu.item)
                menu.item.tracked = null;
            root.letGo();
        }
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
