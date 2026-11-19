import QtQuick
import Quickshell
import qs.src.core

// The menu a right click on a text field opens (TextMenu), hung from the
// pointer. Styled as the tray's menus are (MenuPopup): rows 22 high on the
// frosted panel, the grey fill on the row you are on, a hairline between the
// groups, and a blink on the row chosen before it acts.
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
    closeKey: () => root.owner.open = false

    // Its rows' left edge at the pointer: back by the shadow's room and the
    // padding, so the box and not its window lands there.
    anchor.rect: Qt.rect(root.owner.at.x - root.shadowSide - root.hPadding, root.owner.at.y - root.shadowTop, 1, 1)
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY

    // Put away with the window the field is in, before it can go out from
    // under the menu.
    readonly property bool hostOpen: root.owner.QsWindow.window?.opened ?? true
    onHostOpenChanged: if (!root.hostOpen)
        root.owner.open = false

    // A click anywhere but the menu or its field puts the menu away; a press
    // on the field is the field's (TextMenu).
    OutsideClick {
        enabled: root.owner.open
        inside: root.hovered || root.owner.hovered
        onReleased: root.owner.open = false
    }

    // The row that was clicked, while it blinks.
    property Item chosen: null

    Column {
        id: list

        // As wide as the widest label, and no narrower than the tray's
        // menus. Read off implicitWidth, which width does not feed, or the two
        // would chase each other.
        readonly property real rowWidth: {
            let w = 120;
            for (let i = 0; i < list.children.length; i++)
                w = Math.max(w, list.children[i].implicitWidth);
            return w;
        }

        Repeater {
            model: root.owner.rows

            delegate: Item {
                id: row

                required property string modelData
                readonly property bool rule: row.modelData === ""

                enabled: !row.rule && root.owner.can(row.modelData)
                Accessible.role: Accessible.MenuItem
                Accessible.name: row.modelData
                Accessible.ignored: row.rule
                Accessible.onPressAction: row.choose()

                function choose(): void {
                    if (!row.enabled || root.chosen !== null)
                        return;
                    root.chosen = row;
                    blink.start();
                }

                // Popup.qml's keys: the arrows move between rows, Return
                // chooses one.
                property bool keyed: false
                readonly property var keyPress: row.enabled ? row.choose : null

                property bool blinkOn: true
                readonly property bool lit: root.chosen !== null ? root.chosen === row && row.blinkOn
                    : root.keyItem ? row.keyed : rowHover.hovered

                readonly property int pad: Theme.popupInset
                implicitWidth: row.rule ? 0 : label.implicitWidth + row.pad * 2
                width: list.rowWidth
                height: row.rule ? Theme.selectionInset * 2 : 22

                Rectangle {
                    anchors.fill: parent
                    visible: !row.rule
                    radius: Theme.selectionRadius
                    color: row.lit ? Theme.selection : "transparent"
                }

                PopupSeparator {
                    anchors.centerIn: parent
                    visible: row.rule
                    width: parent.width
                }

                PopupText {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    x: row.pad
                    visible: !row.rule
                    text: row.modelData
                    color: row.lit ? Theme.menuSelectionText : Theme.menuText
                    opacity: row.enabled ? 1 : 0.4
                }

                HoverHandler {
                    id: rowHover
                }

                TapHandler {
                    enabled: root.chosen === null
                    onTapped: row.choose()
                }

                SequentialAnimation {
                    id: blink

                    PropertyAction { target: row; property: "blinkOn"; value: false }
                    PauseAnimation { duration: Theme.blinkMs }
                    PropertyAction { target: row; property: "blinkOn"; value: true }
                    PauseAnimation { duration: Theme.blinkMs }
                    ScriptAction {
                        script: {
                            root.owner.act(row.modelData);
                            root.owner.open = false;
                        }
                    }
                }
            }
        }
    }
}
