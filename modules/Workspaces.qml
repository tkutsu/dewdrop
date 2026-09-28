import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components

// hyprland/workspaces with a taskbar: the workspace number followed by one icon
// per *app* on it, badged with a count when that app has more than one window
// there. Clicking a badged icon walks through that app's windows.
BarItem {
    id: root

    // workspace-taskbar ignore-list
    readonly property var ignored: [/^steam_app.*/, /^gamescope$/]

    // Which windows are shouting. Hyprland flags the workspace, but it flags
    // the window too, so the bar can point at the app that wants you rather
    // than at the room it is in. Gathered once for the whole strip instead of
    // per workspace: every workspace would otherwise walk the same list.
    readonly property var urgentAddresses: Hyprland.toplevels.values.filter(t => t.urgent).map(t => t.address)

    function anyUrgent(addresses) {
        return addresses.some(a => root.urgentAddresses.includes(a));
    }

    // The Hyprland dispatcher speaks Lua here (hyprland.lua drives this setup),
    // which is why these read as function calls rather than bare dispatchers.
    onScrollUp: Hyprland.dispatch('hl.dsp.focus({ workspace = "e-1" })')
    onScrollDown: Hyprland.dispatch('hl.dsp.focus({ workspace = "e+1" })')

    // One strip rather than a run of loose workspaces, because the selection is
    // drawn across it rather than by each workspace for itself.
    Item {
        id: strip

        Layout.fillHeight: true
        implicitWidth: buttons.implicitWidth

        // The workspace the mark is under. Asking the buttons which of them is
        // active keeps the mark out of the delegate, which is the whole point:
        // one mark that moves, rather than one per workspace fading in and out.
        readonly property Item selected: {
            for (const child of buttons.children)
                if (child.active === true)
                    return child;
            return null;
        }

        // The focused workspace sits on a rounded fill, the way the open item
        // on the system's menu bar does: a lighter slab inside the pill,
        // holding the letter and its icons. It was a rule under the group
        // before that, which is a tab's idiom rather than a menu bar's.
        // Urgency is not its business — the icon of the app that wants you
        // bounces for that, wherever on the strip it is, rather than only on
        // the workspace in front of you.
        //
        // Measured off the pill's top edge, not the strip's: the strip reaches
        // past the slab into the margin the pill claims for clicks (see
        // Theme.pillTop). Sideways it takes the pill's own padding back, less
        // the inset, so its ends sit inside the pill's ends by the same air
        // it keeps off the top and bottom.
        //
        // The move is the state change, and it moves the way a drop does along
        // a surface: the mark's front end runs ahead to the workspace you are
        // on, stretching it out of the one you left, then its back end lets go
        // and is drawn along after it. Two slabs of glass, the head and the
        // tail, joined by a neck that thins the further apart they are, all
        // one surface (Liquid, the same glass the pills beside the clock are).
        // The glass reaches a pad past either end of the strip, because the
        // mark does.
        Liquid {
            id: mark

            readonly property int inset: Theme.markInset
            readonly property real slabTop: Theme.pillTop(strip.height) + inset
            readonly property real thickness: Theme.barHeight - inset * 2

            // Where the mark belongs, in this item's pixels.
            readonly property real wantLeft: strip.selected ? strip.selected.x + inset : 0
            readonly property real wantRight: strip.selected ? strip.selected.x + strip.selected.width + Theme.pillPad * 2 - inset : 0

            // Each end runs from wherever it was to where the mark belongs,
            // on a clock of its own, so a switch made mid-run picks up both
            // ends where they are rather than snapping them together first.
            property bool placed: false
            property real toLeft
            property real toRight
            property real headFromLeft
            property real headFromRight
            property real tailFromLeft
            property real tailFromRight
            property real head: 1
            property real tail: 1

            readonly property real headLeft: headFromLeft + (toLeft - headFromLeft) * head
            readonly property real headRight: headFromRight + (toRight - headFromRight) * head
            readonly property real tailLeft: tailFromLeft + (toLeft - tailFromLeft) * tail
            readonly property real tailRight: tailFromRight + (toRight - tailFromRight) * tail

            readonly property real headMid: (headLeft + headRight) / 2
            readonly property real tailMid: (tailLeft + tailRight) / 2
            readonly property real apart: Math.abs(headMid - tailMid)
            // Full thickness while the ends overlap, down to 40% of it once
            // they are three thicknesses apart: a neighbour's mark only
            // stretches, a long way off it pours through a thread.
            readonly property real neck: thickness * (1 - 0.6 * Math.min(1, apart / (thickness * 3)))

            function follow() {
                if (!strip.selected)
                    return;
                if (!placed) {
                    placed = true;
                    headFromLeft = tailFromLeft = toLeft = wantLeft;
                    headFromRight = tailFromRight = toRight = wantRight;
                    return;
                }
                const hl = headLeft, hr = headRight, tl = tailLeft, tr = tailRight;
                headFromLeft = hl;
                headFromRight = hr;
                tailFromLeft = tl;
                tailFromRight = tr;
                toLeft = wantLeft;
                toRight = wantRight;
                head = 0;
                tail = 0;
                flow.restart();
            }

            onWantLeftChanged: follow()
            onWantRightChanged: follow()

            visible: strip.selected !== null
            x: -Theme.pillPad
            width: strip.width + Theme.pillPad * 2
            height: strip.height

            box0: Qt.vector4d(tailLeft, slabTop, tailRight - tailLeft, thickness)
            box1: Qt.vector4d(headLeft, slabTop, headRight - headLeft, thickness)
            box2: Qt.vector4d(Math.min(headMid, tailMid), slabTop + (thickness - neck) / 2, apart, neck)

            // At rest the head lies on the tail, and a reach would swell the
            // two into something fatter than either; it comes up only as they
            // part.
            reach: Theme.pillSpread * Math.min(1, apart / thickness)
            lineWidth: 0
            // The strong step, not a popup row's hover: on a pill this thin
            // over a bright wallpaper, the row fill was barely there.
            fill: Qt.vector4d(Theme.selectionStrong.r, Theme.selectionStrong.g, Theme.selectionStrong.b, Theme.selectionStrong.a)
            rimFrom: slabTop
            rimTo: slabTop + thickness

            ParallelAnimation {
                id: flow

                NumberAnimation {
                    target: mark
                    property: "head"
                    from: 0
                    to: 1
                    duration: Theme.markMs * 0.6
                    easing.type: Easing.OutCubic
                }

                SequentialAnimation {
                    PauseAnimation {
                        duration: Theme.markMs * 0.2
                    }

                    NumberAnimation {
                        target: mark
                        property: "tail"
                        from: 0
                        to: 1
                        duration: Theme.markMs * 0.8
                        easing.type: Easing.InOutCubic
                    }
                }
            }
        }

        RowLayout {
            id: buttons

            anchors.fill: parent
            spacing: Theme.gap

            Repeater {
                model: ScriptModel {
                    // "sort-by-number": true
                    values: [...Hyprland.workspaces.values].sort((a, b) => a.id - b.id)
                }

                delegate: Item {
                    id: button

                    required property var modelData
                    required property int index
                    readonly property bool active: Hyprland.focusedWorkspace?.id === modelData.id

                    // Greek letters for the ten workspaces of a number row. The
                    // tenth is named "0" here, which is where κ goes; anything
                    // named something else keeps its name.
                    readonly property string letter: {
                        const name = modelData.name;
                        if (!/^[0-9]$/.test(name))
                            return "";
                        const index = name === "0" ? 9 : Number(name) - 1;
                        return Theme.workspaceLetters[index];
                    }

                    // One entry per window class, in the order the classes first appear,
                    // so an app does not jump along the row as its windows come and go.
                    readonly property var apps: {
                        const byClass = {};
                        const order = [];
                        for (const toplevel of Hyprland.toplevels.values) {
                            if (toplevel.workspace?.id !== modelData.id)
                                continue;
                            // A window that opened since the last `hyprctl clients`
                            // refresh has an empty lastIpcObject, and every one of those
                            // used to pile into a single classless group under the
                            // fallback glyph. The Wayland app id arrives with the window
                            // itself, so it covers the gap until the IPC object catches
                            // up.
                            const cls = toplevel.lastIpcObject?.class || toplevel.wayland?.appId || "";
                            if (root.ignored.some(re => re.test(cls)))
                                continue;
                            if (!byClass[cls]) {
                                byClass[cls] = {
                                    windowClass: cls,
                                    addresses: []
                                };
                                order.push(cls);
                            }
                            byClass[cls].addresses.push(toplevel.address);
                        }
                        return order.map(cls => byClass[cls]);
                    }

                    // The count badges are made of what they sit on: the pill's
                    // fill on a workspace you are not on, the mark's on the one
                    // you are, and the compositor blurs behind either. They turn
                    // with the mark — in as its head arrives, back out as its
                    // tail lets go.
                    property real lit: button.active ? 1 : 0

                    Behavior on lit {
                        NumberAnimation {
                            duration: button.active ? Theme.markMs * 0.6 : Theme.markMs
                            easing.type: button.active ? Easing.OutCubic : Easing.InOutCubic
                        }
                    }

                    readonly property color badgeFill: {
                        const from = Theme.barBg, to = Theme.markBg, t = button.lit;
                        return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, from.a + (to.a - from.a) * t);
                    }

                    Layout.fillHeight: true
                    implicitWidth: row.implicitWidth

                    MouseArea {
                        id: press
                        anchors.fill: parent
                        // The strip's left padding belongs to the first workspace, not
                        // to the strip: an item may reach past its parent as long as
                        // nothing in the chain clips, and that is what turns the corner
                        // of the screen into a click on workspace one.
                        anchors.leftMargin: button.index === 0 ? -root.padLeft : 0
                        onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = "${button.modelData.name}" })`)
                    }

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        height: parent.height
                        spacing: Theme.appIconGap

                        BarText {
                            Layout.fillHeight: true
                            text: button.letter || button.modelData.name
                            // A letter stays at one weight: the mark says which
                            // workspace is yours, and a letter that went bold
                            // would widen the mark as it arrived.
                            fontSize: Theme.workspaceTextSize
                            weight: button.letter ? Theme.bodyWeight : (button.active ? Font.DemiBold : Theme.bodyWeight)
                            color: Theme.fg

                            transform: Translate { y: letterBounce.offset + (press.pressed ? Theme.pressDip : 0) }
                        }

                        // The fallback, and only that. Urgency belongs on the
                        // icon of the app that wants you, so the letter moves
                        // just when the workspace is shouting and no icon on it
                        // has owned up — an ignored window, or one Hyprland
                        // flagged by workspace without flagging the window.
                        // Otherwise a shouting app would move twice over.
                        Bounce {
                            id: letterBounce
                            running: button.modelData.urgent && !button.apps.some(a => root.anyUrgent(a.addresses))
                        }

                        Repeater {
                            // Keyed by class, so a window opening or closing
                            // anywhere on the desktop touches only the icon it
                            // belongs to. The array itself is new on every
                            // change, and a Repeater handed the array rebuilt
                            // every icon on every workspace each time: a new
                            // desktop entry lookup and a new image load per
                            // icon, for a window that was not theirs.
                            model: ScriptModel {
                                values: button.apps
                                objectProp: "windowClass"
                            }

                            delegate: AppIcon {
                                id: app

                                required property var modelData
                                required property int index

                                Layout.alignment: Qt.AlignVCenter
                                windowClass: modelData.windowClass
                                count: modelData.addresses.length
                                urgent: root.anyUrgent(modelData.addresses)
                                pressed: tap.pressed
                                badgeFill: button.badgeFill

                                MouseArea {
                                    id: tap
                                    anchors.fill: parent

                                    // Focusing a window switches workspace as a side
                                    // effect. Where an icon stands for several windows,
                                    // each click moves on to the next of them, so a
                                    // badged icon is a way through the whole group.
                                    onClicked: {
                                        const addresses = app.modelData.addresses;
                                        const current = Hyprland.activeToplevel?.address;
                                        const at = addresses.indexOf(current);
                                        const next = addresses[(at + 1) % addresses.length];
                                        Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${next}" })`);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
