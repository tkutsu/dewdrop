import QtQuick
import QtQuick.Effects
import qs
import qs.components
import qs.services

// The power menu, drawn the Mac's way.
//
// Five round buttons on one panel, the way Control Center draws its own, each
// named as the Apple menu names it: hover or arrow to one, click or Enter to
// take it. The three irreversible ones (shut down, restart, log out) still
// ask first, the way rofi-power.sh's `confirmations` did, and they ask it the
// way the Mac does: the panel turns into an alert, with the action's icon,
// the Mac's own question, and Cancel beside the action it would take.
//
// The screen-sized surface under it, the keyboard grab and the click-to-exit
// are OverlayWindow's, which the launcher is drawn on too.
OverlayWindow {
    id: root

    name: "powermenu"
    shown: Power.shown
    onDismissed: Power.shown = false

    // --- geometry ------------------------------------------------------------
    readonly property int discSize: 52
    readonly property int tileWidth: 78
    readonly property int panelPad: 18
    readonly property int buttonWidth: 112
    readonly property int buttonHeight: 28
    readonly property int buttonGap: 8
    // The alert's width: its two buttons and the gap between them. The
    // question wraps inside it.
    readonly property int alertWidth: buttonWidth * 2 + buttonGap
    // Round enough to read as the Mac's panels, and nested round the
    // buttons' capsules: their radius plus the air between them and the edge.
    readonly property int panelRadius: buttonHeight / 2 + panelPad / 2

    // --- state ---------------------------------------------------------------
    // The action awaiting an answer, or null when the panel is showing the
    // normal five.
    property var pending: null
    property int index: 0

    // Where the pointer was when it last actually moved, and whether it has
    // moved at all since the panel last changed what it is showing.
    //
    // A button that appears under a stationary pointer is handed a hover
    // event by Qt, and that is exactly what a confirmation is: the alert's
    // buttons are built under the cursor that just clicked. Selecting on that
    // would walk the selection off "Cancel" and undo the one thing the alert
    // is for. Same trap, and the same answer, as the launcher's list — see
    // modules/LauncherMenu.qml.
    property point pointer: Qt.point(-1, -1)
    property bool pointerLive: false

    // Swapping between the five and an alert is the moment that has to
    // forget where the pointer was.
    onEntriesChanged: root.pointerLive = false

    // One model for both states, so the keys and the pointer do not care
    // which it is in. The alert's pair is in the Mac's order: Cancel first,
    // the action last, named without the ellipsis — the question has been
    // asked.
    readonly property var entries: pending ? [
        {
            name: "Cancel",
            accept: false
        },
        {
            name: pending.name.replace("…", ""),
            accept: true
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
            // Land on Cancel, not on the thing that wipes the session.
            root.index = 0;
            return;
        }

        Power.run(entry.arg);
    }

    // Escape and Cancel share this: out of an alert, back to the five; out
    // of the five, gone.
    function back() {
        if (root.pending) {
            // -1 when the launcher armed something the menu does not list,
            // which would leave the panel with nothing selected.
            root.index = Math.max(0, Power.actions.indexOf(root.pending));
            root.pending = null;
        } else {
            Power.shown = false;
        }
    }

    // What the menu is opening as. Normally nothing, and it comes up showing
    // its five; the launcher can set Power.armed instead and have it come up
    // on the alert. Taken rather than read, so the next open is a fresh one
    // either way — a menu that came back up still asking "shut down?" would
    // be answering a question from the last time it was open.
    function adopt(): void {
        root.pending = Power.armed;
        Power.armed = null;
        // On Cancel when the menu opens already asking, the same way choose()
        // lands there when the asking started here. Arriving from the
        // launcher is the one path that skips choose(), and it once landed on
        // the action — so typing "reboot" and pressing Enter twice rebooted,
        // which is the confirm doing the opposite of its job. Cancel is index
        // 0 in the alert, so both states open on the first entry.
        root.index = 0;
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

    // The pointer's half of the selection, on every button in both states:
    // rofi's hover-select, where the pointer moves the selection rather than
    // acting on its own — and only when it has really moved. See root.pointer
    // for the case that forces it. A MouseArea rather than a HoverHandler,
    // because a real move is the thing being asked about and that is what
    // positionChanged reports.
    component Pick: MouseArea {
        required property int at

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
            root.index = at;
        }

        onClicked: root.choose(at)
    }

    // A round button's face: the Control Center disc, a step brighter and
    // ringed while it is the one Enter would take.
    component Disc: Rectangle {
        id: disc

        property string glyph
        property bool current: false

        width: root.discSize
        height: root.discSize
        radius: width / 2
        color: current ? Theme.selectionStrong : Theme.selection
        border.width: Theme.pillBorder
        border.color: current ? Theme.outline : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.fadeMs
            }
        }

        Glyph {
            anchors.centerIn: parent
            height: disc.height
            text: disc.glyph
            fontSize: 24
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
                // 1-5 go straight to a button. Only while the five are
                // showing: a number is no way to answer "are you sure".
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
            anchors.fill: panel
            visible: panel.height > 0
            offset.y: Theme.shadowY
            radius: panel.radius
            blur: Theme.shadowBlur
            color: Theme.shadow
        }

        Rectangle {
            id: panel

            anchors.centerIn: parent
            // Same fill and outline as a popup, and for the same reason: the
            // alpha is what keeps the compositor blurring behind it.
            color: Theme.popupBg
            radius: root.panelRadius

            Rim {
                anchors.fill: parent
                radius: panel.radius
                z: 1
            }

            width: body.implicitWidth + root.panelPad * 2
            // Zero while closed, which is the whole of the open and close
            // animation: the panel is centred, so a height that grows from
            // nothing grows away from the centre line in both directions at
            // once. Rectangle caps its radius at half the shorter side, so on
            // the way through it draws as a thinning bar rather than as a
            // rectangle with corners too big for it.
            height: root.opened ? body.implicitHeight + root.panelPad * 2 : 0
            // The contents keep their own size through all of that and get
            // cut off by the panel's edges, so they are wiped in from the
            // middle rather than squashed into the gap.
            clip: true

            // The two states are different sizes; grow between them rather
            // than cutting, so it reads as the same panel asking a question.
            Behavior on width {
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.OutCubic
                }
            }

            // Both the reveal and a change of state come through here.
            //
            // Deliberately height alone and not a fade as well: the panel's
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

            // The panel is not "off the menu": clicking its padding should do
            // nothing, not dismiss. Only the screen around it closes.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: body

                anchors.centerIn: parent

                // The five: a disc each, the Apple menu's name under it.
                Row {
                    visible: root.pending === null

                    Repeater {
                        model: Power.actions

                        delegate: Item {
                            id: tile

                            required property int index
                            required property var modelData

                            readonly property bool current: root.pending === null && root.index === tile.index

                            width: root.tileWidth
                            height: column.implicitHeight

                            Column {
                                id: column

                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 8

                                Disc {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    glyph: tile.modelData.glyph
                                    current: tile.current
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.name
                                    // The menu text/selection pair: the name
                                    // brightens over the same span the disc
                                    // does, so the two are one movement.
                                    color: tile.current ? Theme.menuSelectionText : Theme.menuText
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.captionSize
                                    font.weight: Theme.bodyWeight

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.fadeMs
                                        }
                                    }
                                }
                            }

                            Pick {
                                at: tile.index
                            }
                        }
                    }
                }

                // The alert: what it is about, the question, and the answers.
                Column {
                    visible: root.pending !== null
                    spacing: 14

                    Disc {
                        anchors.horizontalCenter: parent.horizontalCenter
                        glyph: root.pending?.glyph ?? ""
                    }

                    Text {
                        width: root.alertWidth
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.pending?.question ?? ""
                        color: Theme.label
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.popupTextSize + 1
                        font.weight: Font.DemiBold
                        lineHeight: 1.1
                    }

                    Row {
                        spacing: root.buttonGap

                        Repeater {
                            model: root.pending ? root.entries : []

                            delegate: Rectangle {
                                id: button

                                required property int index
                                required property var modelData

                                readonly property bool current: root.index === button.index

                                width: root.buttonWidth
                                height: root.buttonHeight
                                radius: height / 2
                                color: current ? Theme.selectionStrong : Theme.selection
                                border.width: Theme.pillBorder
                                border.color: current ? Theme.outline : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.fadeMs
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: button.modelData.name
                                    color: button.current ? Theme.menuSelectionText : Theme.menuText
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.popupTextSize
                                    font.weight: Theme.bodyWeight

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.fadeMs
                                        }
                                    }
                                }

                                Pick {
                                    at: button.index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
