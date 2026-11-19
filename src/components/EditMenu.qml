import QtQuick
import Quickshell
import qs.src.core

// The menu a right click on a text field opens (TextMenu), hung from the
// pointer, in the rows every menu here has (MenuRow) on the frosted panel.
Popup {
    id: root

    required property Item owner

    anchorItem: root.owner
    // Shown for as long as it is loaded; the fade is requestedVisible's.
    visible: true
    requestedVisible: root.owner.open
    // Up where it was asked for, the way a context menu appears, rather
    // than growing out of the field.
    grows: false
    spacing: 0
    radius: Theme.menuRadius
    hPadding: Theme.selectionInset
    vPadding: Theme.selectionInset
    bottomPadding: vPadding
    // Escape: back to typing in the field.
    closeKey: () => root.owner.close(true)

    // Its rows' left edge at the pointer: back by the shadow's room and the
    // padding, so the box and not its window lands there. A second right
    // click moves it.
    anchor.rect: Qt.rect(root.owner.at.x - root.shadowSide - root.hPadding, root.owner.at.y - root.shadowTop, 1, 1)
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY

    // Put away with the window the field is in, before it can go out from
    // under the menu.
    readonly property bool hostOpen: root.owner.QsWindow.window?.opened ?? true
    onHostOpenChanged: if (!root.hostOpen)
        root.owner.close(false)

    // A click anywhere but the menu or its field puts the menu away; a press
    // on the field is the field's (TextMenu).
    OutsideClick {
        enabled: root.owner.open
        inside: root.hovered || root.owner.hovered
        onReleased: root.owner.close(false)
    }

    // The row that was chosen, while it blinks.
    property Item chosen: null

    // The row under a right press dragged across the menu, which the field
    // reports (TextMenu): the compositor keeps the pointer on the surface the
    // press went down on, so until it is let go the menu never hears it.
    property Item tracked: null

    // The row that can be chosen under a point on the screen, or null.
    function rowAt(global: point): Item {
        for (let i = 0; i < list.children.length; i++) {
            const row = list.children[i];
            if (typeof row.choose !== "function" || !row.enabled)
                continue;
            const p = row.mapFromGlobal(global.x, global.y);
            if (p.x >= 0 && p.y >= 0 && p.x < row.width && p.y < row.height)
                return row;
        }
        return null;
    }

    function track(global: point): void {
        root.tracked = root.rowAt(global);
    }

    // The right press let go: chooses the row under it. Whether there was one.
    function release(global: point): bool {
        const row = root.rowAt(global);
        root.tracked = null;
        if (row)
            row.activate();
        return row !== null;
    }

    Column {
        id: list

        // As wide as the widest row; read off implicitWidth, which width does
        // not feed, or the two would chase each other.
        readonly property real rowWidth: {
            let w = 0;
            for (let i = 0; i < list.children.length; i++)
                w = Math.max(w, list.children[i].implicitWidth);
            return w;
        }

        Repeater {
            model: root.owner.rows

            delegate: MenuRow {
                id: row

                required property string modelData

                text: row.modelData
                separator: row.modelData === ""
                enabled: !row.separator && root.owner.can(row.modelData)
                hot: root.keyItem ? row.keyed : root.owner.tracking ? root.tracked === row : rowHover.hovered
                frozen: root.chosen !== null
                width: list.rowWidth

                Accessible.onPressAction: row.activate()

                function activate(): void {
                    if (row.choose())
                        root.chosen = row;
                }
                onPicked: {
                    root.owner.act(row.modelData);
                    root.owner.close(true);
                }

                // Popup.qml's keys: the arrows move between rows, Return
                // chooses one.
                property bool keyed: false
                readonly property var keyPress: row.enabled ? row.activate : null

                HoverHandler {
                    id: rowHover
                }

                TapHandler {
                    enabled: root.chosen === null
                    onTapped: row.activate()
                }
            }
        }
    }
}
