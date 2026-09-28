import QtQuick
import Quickshell
import Quickshell.Widgets
import qs

// A tray item's DBus menu. Styled off the launcher rather than the old GTK
// menu it replaced: same half-black panel, the same grey fill and white left
// rule on the row you are on, and the same hairline for a separator, so the
// two menus on this desktop read as one thing.
// Submenus open as their own popup anchored to the row that owns them.
Popup {
    id: root

    property QsMenuHandle handle
    signal dismissed

    // A menu drops whole, as the Mac's do; only a popover grows.
    grows: false

    // Whether the pointer is anywhere in this tree, rather than on this
    // surface alone. A row keeps its submenu open while the pointer is
    // "near", and near has to reach all the way down: reading only the
    // submenu's own surface meant that stepping from it into a submenu of
    // its own counted as leaving, and the branch closed under the pointer.
    readonly property bool treeHovered: {
        if (root.hovered)
            return true;
        for (let i = 0; i < body.children.length; i++)
            if (body.children[i].submenuHovered === true)
                return true;
        return false;
    }

    // Rows run the width of the menu, so the only side padding is the hairline
    // they must not paint over — a child is drawn above the panel's border, and
    // a hovered row that reached the edge would break the outline along itself.
    // Top and bottom clear the rounded corners for the same reason.
    radius: Theme.menuRadius
    // The system's menu metrics: rows 22 high, the fill under the pointer
    // inset from the box on every side, and the same inset again between the
    // fill and the label.
    hPadding: Theme.selectionInset
    vPadding: Theme.selectionInset
    readonly property int rowHeight: 22

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    Column {
        id: body

        // A row is as wide as its own label, so the short ones would draw a
        // highlight that stops short of the popup edge while the popup itself
        // is as wide as the longest. The widest row sets the width and the
        // rest stretch to it; read off implicitWidth rather than width, which
        // is what this feeds, or the two chase each other.
        readonly property real rowWidth: {
            let w = 0;
            for (let i = 0; i < body.children.length; i++)
                w = Math.max(w, body.children[i].implicitWidth);
            return w;
        }

        // What the app sent, less the separators that would draw nothing:
        // one after another (blueman sends two in a row), or one at either
        // end. Each of those is an empty row the height of a gap, which reads
        // as a row that failed to load rather than as a gap.
        readonly property var entries: {
            const all = [...opener.children.values];
            const kept = [];
            for (const e of all) {
                if (e.isSeparator && (kept.length === 0 || kept[kept.length - 1].isSeparator))
                    continue;
                kept.push(e);
            }
            while (kept.length > 0 && kept[kept.length - 1].isSeparator)
                kept.pop();
            return kept;
        }

        Repeater {
            model: ScriptModel {
                values: body.entries
            }

            delegate: Item {
                id: row

                required property QsMenuEntry modelData

                // pad is the air on each side of a row's text, and half of it
                // is the air above and below: a menu row is a target to point
                // at rather than something to read around, and the tighter
                // pair is what keeps a long app menu to a column instead of a
                // page. A separator gets the vertical pair and no text.
                readonly property int pad: Theme.selectionInset + 4

                // Whether the pointer is on this row or inside the submenu it
                // opened. A submenu is its own surface, so reaching for one
                // means leaving the row that owns it — and the Loader below
                // used to be bound straight to the row's own hover, which took
                // the submenu away at the moment the pointer arrived at it.
                //
                // It is also what lights the row: a parent whose submenu you
                // are inside should stay marked as the way you came.
                readonly property bool pointerNear: hover.hovered || row.submenuHovered

                // Held open by a handler rather than bound, so that reading
                // the submenu's own hover to decide whether the submenu exists
                // is a sequence of events rather than a binding on itself.
                property bool submenuOpen: false

                readonly property bool submenuHovered: submenu.item ? submenu.item.treeHovered === true : false

                onPointerNearChanged: {
                    if (row.pointerNear) {
                        submenuLeave.stop();
                        if (row.modelData.hasChildren)
                            row.submenuOpen = true;
                    } else {
                        submenuLeave.restart();
                    }
                }

                Timer {
                    id: submenuLeave

                    // Long enough to cross the seam into the submenu, short
                    // enough that it still closes on the way out.
                    interval: 150
                    onTriggered: if (!row.pointerNear)
                        row.submenuOpen = false
                }

                // Everything drawn across the row, in order: the icon and its
                // gap when there is one, the label, and room for the chevron
                // on a row that opens a submenu. Leaving the icon out put the
                // chevron on top of the label's last letters.
                implicitWidth: Math.max(120, label.x + label.implicitWidth + row.pad + (row.modelData.hasChildren ? 12 : 0))
                width: Math.max(implicitWidth, body.rowWidth)
                height: row.modelData.isSeparator ? Theme.selectionInset * 2 : root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    visible: !row.modelData.isSeparator
                    radius: Theme.selectionRadius
                    color: row.pointerNear ? Theme.selection : "transparent"
                }

                // Full width, the same way the launcher's rule under the query
                // is: a line that stops short of both edges reads as a dash
                // sitting in the menu rather than as a divider across it.
                Rectangle {
                    anchors.centerIn: parent
                    visible: row.modelData.isSeparator
                    width: parent.width + Theme.selectionInset * 2
                    height: Theme.pillBorder
                    color: Theme.stroke
                }

                IconImage {
                    id: art
                    anchors.verticalCenter: parent.verticalCenter
                    x: row.pad
                    implicitSize: Theme.popupGlyphSize
                    visible: row.modelData.icon !== ""
                    source: row.modelData.icon
                }

                PopupText {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    x: art.visible ? row.pad + art.implicitSize + 4 : row.pad
                    visible: !row.modelData.isSeparator
                    text: {
                        // Check and radio items carry their state in the text,
                        // the way the GTK menu drew a mark beside them.
                        const mark = row.modelData.buttonType === QsMenuButtonType.None ? "" : (row.modelData.checkState === Qt.Checked ? "● " : "○ ");
                        return mark + row.modelData.text;
                    }
                    color: row.pointerNear ? Theme.menuSelectionText : Theme.menuText
                    opacity: row.modelData.enabled ? 1 : 0.4
                }

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: row.pad
                    visible: row.modelData.hasChildren
                    text: "›"
                }

                HoverHandler {
                    id: hover
                    enabled: !row.modelData.isSeparator && row.modelData.enabled
                }

                TapHandler {
                    enabled: !row.modelData.isSeparator && row.modelData.enabled
                    onTapped: {
                        // A row with a submenu opens it, as it does on hover;
                        // a click is how you ask for it when the hover did not
                        // register, and it is what every other menu does.
                        if (row.modelData.hasChildren) {
                            row.submenuOpen = true;
                            return;
                        }
                        row.modelData.triggered();
                        root.dismissed();
                    }
                }

                // Loaded by URL rather than by name: QML rejects a component
                // that instantiates itself, and a submenu is the same thing one
                // level down.
                Loader {
                    id: submenu

                    active: row.modelData.hasChildren && row.submenuOpen
                    source: Qt.resolvedUrl("MenuPopup.qml")

                    onLoaded: {
                        item.anchorItem = row;
                        item.handle = row.modelData;
                        // Back by the shadow's room, so the submenu's box and
                        // not its window starts level with the row.
                        item.anchor.rect = Qt.rect(-item.shadowSide, -item.shadowTop, row.width, row.height);
                        item.anchor.edges = Edges.Right | Edges.Top;
                        item.anchor.gravity = Edges.Right | Edges.Bottom;
                        // Popup's default slides a popup along X to stay on
                        // screen, which for a submenu beside a menu at the
                        // right edge means sliding it back over its parent.
                        // Flip it to the other side instead, and let it slide
                        // vertically, since the anchoring row can be anywhere.
                        item.anchor.adjustment = PopupAdjustment.FlipX | PopupAdjustment.SlideY;
                        item.dismissed.connect(root.dismissed);
                        item.visible = true;
                    }
                }
            }
        }
    }
}
