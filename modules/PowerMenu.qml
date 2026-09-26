import QtQuick
import QtQuick.Effects
import qs
import qs.components
import qs.services

// The power menu, as a row of buttons.
//
// rofi drew this as a list because a list is all rofi draws. Here it is five
// tiles on one strip: hover or arrow to one, click or Enter to take it. The
// three irreversible ones (shut down, reboot, log out) still ask first, the
// way rofi-power.sh's `confirmations` did — the strip swaps to a yes/no pair
// rather than opening a second menu on top of the first.
//
// The screen-sized surface under it, the keyboard grab and the click-to-exit
// are OverlayWindow's, which the launcher is drawn on too.
OverlayWindow {
    id: root

    name: "powermenu"
    shown: Power.shown
    onDismissed: Power.shown = false

    // --- geometry ------------------------------------------------------------
    readonly property int tileSize: 88
    readonly property int tileRadius: 12
    readonly property int tileGap: 8
    readonly property int stripPad: 16

    // --- state ---------------------------------------------------------------
    // The action awaiting a yes/no, or null when the strip is showing the
    // normal five.
    property var pending: null
    property int index: 0

    // Where the pointer was when it last actually moved, and whether it has
    // moved at all since the strip last changed what it is showing.
    //
    // A tile that appears under a stationary pointer is handed a hover event
    // by Qt, and that is exactly what a confirmation is: tile 0 is "shut
    // down", and the "yes" replacing it is built under the cursor that just
    // clicked. Selecting on that would walk the selection off "cancel" and
    // undo the one thing the confirm strip is for. Same trap, and the same
    // answer, as the launcher's list — see modules/LauncherMenu.qml.
    property point pointer: Qt.point(-1, -1)
    property bool pointerLive: false

    // Swapping between the five and a confirmation is the moment that has to
    // forget where the pointer was.
    onEntriesChanged: root.pointerLive = false

    // One model for both states, so the row does not care which it is in. The
    // confirm pair carries the action's own glyph on the yes button, which is
    // what tells you at a glance what you are agreeing to.
    readonly property var entries: pending ? [
        {
            label: "yes, " + pending.label,
            glyph: pending.glyph,
            accept: true
        },
        {
            label: "cancel",
            glyph: Theme.glyph.powerCancel,
            accept: false
        }
    ] : Power.actions

    function choose(i) {
        const entry = entries[i];
        if (!entry)
            return;

        if (root.pending) {
            if (entry.accept)
                Power.run(root.pending.arg);
            else
                root.back();
            return;
        }

        if (entry.confirm) {
            root.pending = entry;
            // Land on "cancel", not on the thing that wipes the session.
            root.index = 1;
            return;
        }

        Power.run(entry.arg);
    }

    // Escape and the cancel button share this: out of a confirmation, back to
    // the five; out of the five, gone.
    function back() {
        if (root.pending) {
            // -1 when the launcher armed something the menu does not list,
            // which would leave the strip with nothing selected.
            root.index = Math.max(0, Power.actions.indexOf(root.pending));
            root.pending = null;
        } else {
            Power.shown = false;
        }
    }

    // What the menu is opening as. Normally nothing, and it comes up showing
    // its five; the launcher can set Power.armed instead and have it come up
    // on the confirm pair. Taken rather than read, so the next open is a fresh
    // one either way — a menu that came back up still asking "shut down?"
    // would be answering a question from the last time it was open.
    function adopt(): void {
        root.pending = Power.armed;
        Power.armed = null;
        // Land on "cancel" when the menu opens already asking, the same way
        // choose() does when the asking started here. Arriving from the
        // launcher is the one path that skipped choose(), and it was landing
        // on "yes" — so typing "reboot" and pressing Enter twice rebooted,
        // which is the confirm doing the opposite of its job.
        root.index = root.pending ? 1 : 0;
    }

    // Two ways in, because the window is not always new. Usually it is built
    // when the menu opens, and by then Power.shown has already changed — the
    // Connections below does not exist yet to hear it, so a fresh window has
    // to ask on its own.
    Component.onCompleted: root.adopt()

    // And a reopen inside the fold-away reuses the window it built last time
    // (see services/Power.qml), which is the case Component.onCompleted cannot
    // see because it already ran.
    Connections {
        target: Power

        function onShownChanged() {
            if (Power.shown)
                root.adopt();
        }
    }

    // Keyboard lives on an Item rather than on the window: the window has no
    // focus of its own to give away.
    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (event) {
            switch (event.key) {
            case Qt.Key_Escape:
                root.back();
                break;
            case Qt.Key_Left:
            case Qt.Key_H:
                root.index = (root.index - 1 + root.entries.length) % root.entries.length;
                break;
            case Qt.Key_Right:
            case Qt.Key_L:
            case Qt.Key_Tab:
                root.index = (root.index + 1) % root.entries.length;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.choose(root.index);
                break;
            default:
                // 1-5 go straight to a tile. Only while the five are showing:
                // a number is no way to answer "are you sure".
                if (!root.pending && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    const n = event.key - Qt.Key_1;
                    if (n < root.entries.length) {
                        root.index = n;
                        root.choose(n);
                    }
                }
                return;
            }
            event.accepted = true;
        }

        RectangularShadow {
            anchors.fill: strip
            visible: strip.height > 0
            offset.y: Theme.shadowY
            radius: strip.radius
            blur: Theme.shadowBlur
            color: Theme.shadow
        }

        Rectangle {
            id: strip

            anchors.centerIn: parent
            // Same fill and outline as a bar pill, and for the same reason: the
            // 0.5 alpha is what keeps the compositor blurring behind it.
            color: Theme.popupBg
            radius: root.tileRadius + root.stripPad / 2

            Rim {
                anchors.fill: parent
                radius: strip.radius
                z: 1
            }

            width: body.implicitWidth + root.stripPad * 2
            // Zero while closed, which is the whole of the open and close
            // animation: the strip is centred, so a height that grows from
            // nothing grows away from the centre line in both directions at
            // once. Rectangle caps its radius at half the shorter side, so on
            // the way through it draws as a thinning bar rather than as a
            // rectangle with corners too big for it.
            height: root.opened ? body.implicitHeight + root.stripPad * 2 : 0
            // The tiles keep their own size through all of that and get cut off
            // by the strip's edges, so the row is wiped in from its middle
            // rather than squashed into the gap.
            clip: true

            // The two states are different sizes; grow between them rather
            // than cutting, so it reads as the same strip asking a question.
            Behavior on width {
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.OutCubic
                }
            }

            // Both the reveal and a change of state come through here. Same
            // easing either way: the strip settles into its height rather than
            // arriving at it.
            //
            // Deliberately height alone and not a fade as well: the strip's 0.5
            // alpha is only just over the 0.3 the compositor's blur rule
            // ignores, so anything that takes its opacity down drops the blur
            // out from behind it partway through, which is a far louder event
            // than the fade it was meant to soften.
            Behavior on height {
                NumberAnimation {
                    duration: Theme.revealMs
                    easing.type: Easing.OutCubic
                }
            }

            // The strip is not "off the menu": clicking its padding should do
            // nothing, not dismiss. Only the screen around it closes.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: body

                anchors.centerIn: parent
                spacing: 10

                // Only while asking. The five speak for themselves.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.pending !== null
                    text: root.pending ? root.pending.label.toLowerCase() + "?" : ""
                    color: Theme.fg
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.popupTextSize
                    font.weight: Theme.bodyWeight
                }

                // The row and the selection behind it. The selection cannot
                // live inside the Row — a Row positions every child it has —
                // so both sit in an item sized to the row.
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: row.implicitWidth
                    implicitHeight: row.implicitHeight

                    // One rectangle for the whole strip rather than one per
                    // tile: it slides to whichever tile you are on, so the
                    // selection reads as a thing being moved instead of five
                    // outlines taking turns appearing. Every tile is the same
                    // width, so the target is just arithmetic.
                    Rectangle {
                        id: selection

                        x: root.index * (root.tileSize + root.tileGap)
                        width: root.tileSize
                        height: root.tileSize
                        radius: root.tileRadius
                        // Solid black against the strip's half-black, with the
                        // outline stopping that from reading as a hole when the
                        // wallpaper behind is dark. See Theme's menu* colours.
                        color: Theme.selection

                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.fadeMs
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Row {
                        id: row

                        spacing: root.tileGap

                        Repeater {
                            model: root.entries

                            delegate: Item {
                                id: tile

                                required property int index
                                required property var modelData

                                readonly property bool current: root.index === tile.index

                                width: root.tileSize
                                height: root.tileSize

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    // Full strength on every tile, selected or
                                    // not — the menu palette dims a label but
                                    // never its icon.
                                    Glyph {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        implicitHeight: 38
                                        text: tile.modelData.glyph
                                        fontSize: 30
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        // rofi lowercased every row it drew.
                                        text: tile.modelData.label.toLowerCase()
                                        // The menu text/selection pair, rather
                                        // than the bar's idle dimming. It
                                        // brightens over the same span the
                                        // selection takes to arrive, so the two
                                        // are one movement.
                                        color: tile.current ? Theme.menuSelectionText : Theme.menuText
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.labelSize
                                        font.weight: Theme.bodyWeight

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Theme.fadeMs
                                            }
                                        }
                                    }
                                }

                                // rofi's hover-select: the pointer moves the
                                // selection rather than acting on its own —
                                // and only when it has really moved. See
                                // root.pointer for the case that forces it.
                                //
                                // A MouseArea rather than the handler pair it
                                // replaces, because a real move is the thing
                                // being asked about and that is what
                                // positionChanged reports.
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.ArrowCursor

                                    onPositionChanged: function (mouse) {
                                        const p = mapToItem(null, mouse.x, mouse.y);
                                        if (!root.pointerLive) {
                                            root.pointer = p;
                                            root.pointerLive = true;
                                            return;
                                        }
                                        if (Math.abs(p.x - root.pointer.x) < 1 && Math.abs(p.y - root.pointer.y) < 1)
                                            return;
                                        root.pointer = p;
                                        root.index = tile.index;
                                    }

                                    onClicked: root.choose(tile.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
