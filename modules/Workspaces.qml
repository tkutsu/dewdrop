import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components

// hyprland/workspaces with a taskbar: the workspace number followed by one icon
// per *app* on it, dotted underneath when it holds the focused window.
// Clicking an icon that stands for several windows walks through them.
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
    onScrollUp: Hyprland.dispatch('hl.dsp.focus({ workspace = "e+1" })')
    onScrollDown: Hyprland.dispatch('hl.dsp.focus({ workspace = "e-1" })')

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

        // A press held on one of the strip's icons. Read off the buttons, the
        // way `selected` is, rather than off a handler of the strip's own,
        // which would have to share the press with the areas that act on it.
        readonly property bool held: {
            for (const child of buttons.children)
                if (child.held === true)
                    return true;
            return false;
        }

        // The focused workspace sits on a rounded fill, the way the open item
        // on the system's menu bar does: a lighter slab inside the pill,
        // holding the number and its icons. It was a rule under the group
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
        // The top is measured from inside the pill's rim. The rim is lit
        // along the top and all but gone along the bottom, so it reads as the
        // pill's edge up there and as more pill down here. An inset of two
        // from the slab's edge on both sides left one dark pixel above the
        // mark and two below it, which looked like the mark riding high.
        //
        // The move is the state change, and it moves the way a drop does along
        // a surface: the mark's front end runs ahead to the workspace you are
        // on, stretching it out of the one you left, then its back end lets go
        // and is drawn along after it. Two slabs of glass, the head and the
        // tail, joined by a neck that thins the further apart they are, all
        // one surface (Liquid, the same glass the pills beside the clock are).
        // The glass reaches a pad past either end of the strip, because the
        // mark does.
        //
        // The head runs on a spring, so it carries a little past the
        // workspace and comes back, and the mark stands a touch long for a
        // moment before it settles, the way a drop's momentum does. At the
        // ends of the strip that would carry it out through the pill's own
        // end, so there the end is a wall: the head stops against it and the
        // rest of the run piles up against it as a bulb (see press).
        Liquid {
            id: mark

            readonly property int inset: Theme.markInset

            // How far the glass has come up off the pill, 0..1: a press held
            // on an icon lifts it a pixel towards the pill's edges and
            // lights it a step, and letting go drops it back on the spring.
            // A pixel, because the bar's surface ends at the pill's foot and
            // the mark cannot swell past it the way a lens on a phone does.
            property real lift: strip.held ? 1 : 0

            Behavior on lift {
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.markDamping
                }
            }

            readonly property real edge: inset - lift
            readonly property real slabTop: Theme.pillTop(strip.height) + Theme.pillBorder + edge
            readonly property real thickness: Theme.barHeight - Theme.pillBorder - edge * 2
            readonly property color tone: Theme.mix(Theme.selectionStrong, Theme.markLifted, lift)

            // Where the mark belongs, in this item's pixels.
            readonly property real wantLeft: strip.selected ? strip.selected.x + inset : 0
            readonly property real wantRight: strip.selected ? strip.selected.x + strip.selected.width + Theme.pillPad * 2 - inset : 0

            // Each end runs from wherever it is to where the mark belongs, so
            // a switch made mid-run picks both ends up where they are rather
            // than snapping them together first. Not until the mark has been
            // placed once, or it would flow in from the screen's edge.
            property bool placed: false
            onVisibleChanged: if (visible)
                Qt.callLater(() => placed = true)

            property real headLeft: wantLeft
            property real headRight: wantRight
            property real tailLeft: wantLeft
            property real tailRight: wantRight

            Behavior on headLeft {
                enabled: mark.placed
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.markDamping
                }
            }
            Behavior on headRight {
                enabled: mark.placed
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.markDamping
                }
            }
            Behavior on tailLeft {
                enabled: mark.placed
                SequentialAnimation {
                    PauseAnimation {
                        duration: Theme.markMs * 0.2
                    }
                    NumberAnimation {
                        duration: Theme.markMs * 0.8
                        easing.type: Easing.InOutCubic
                    }
                }
            }
            Behavior on tailRight {
                enabled: mark.placed
                SequentialAnimation {
                    PauseAnimation {
                        duration: Theme.markMs * 0.2
                    }
                    NumberAnimation {
                        duration: Theme.markMs * 0.8
                        easing.type: Easing.InOutCubic
                    }
                }
            }

            // The pill's ends, as walls for the head. A pixel short of the
            // slab's edge, so the pill's rim stays in view outside the glass
            // pressed against it. Only at the first and last workspace: in
            // the middle of the strip the overshoot has room to run.
            readonly property bool atFirst: strip.selected !== null && strip.selected.index === 0
            readonly property bool atLast: strip.selected !== null && strip.selected.index === workspaces.count - 1
            readonly property real wallLeft: wantLeft - inset + Theme.pillBorder
            readonly property real wallRight: wantRight + inset - Theme.pillBorder

            readonly property real frontLeft: atFirst ? Math.max(headLeft - lift, wallLeft) : headLeft - lift
            readonly property real frontRight: atLast ? Math.min(headRight + lift, wallRight) : headRight + lift

            // How far past a wall the spring would have carried the head, on
            // whichever side it is pressing.
            readonly property real pastLeft: atFirst ? wallLeft - (headLeft - lift) : 0
            readonly property real pastRight: atLast ? headRight + lift - wallRight : 0

            // How hard the head is pressed into the wall, 0..1, eased out so
            // the glass gives quickly at first and then stiffens. It comes
            // out as a bulb of glass against the wall, taller than the rest
            // of the mark, the way a drop run into something piles up where
            // it hit rather than swelling all along.
            readonly property real press: {
                const t = Math.min(1, Math.max(pastLeft, pastRight, 0) / Theme.markPress);
                return 1 - (1 - t) * (1 - t);
            }
            readonly property real bulbEdge: Math.max(0, edge - Theme.markBulge * press)
            readonly property real bulbTop: Theme.pillTop(strip.height) + Theme.pillBorder + bulbEdge
            readonly property real bulbThickness: Theme.barHeight - Theme.pillBorder - bulbEdge * 2
            readonly property real bulbWidth: press > 0 ? bulbThickness * 1.2 : 0
            readonly property real bulbLeft: pastRight > pastLeft ? wallRight - bulbWidth : wallLeft

            readonly property real headMid: (frontLeft + frontRight) / 2
            readonly property real tailMid: (tailLeft + tailRight) / 2
            readonly property real apart: Math.abs(headMid - tailMid)
            // Full thickness while the ends overlap, down to 40% of it once
            // they are three thicknesses apart: a neighbour's mark only
            // stretches, a long way off it pours through a thread.
            readonly property real neck: thickness * (1 - 0.6 * Math.min(1, apart / (thickness * 3)))

            visible: strip.selected !== null
            x: -Theme.pillPad
            width: strip.width + Theme.pillPad * 2
            height: strip.height

            box0: Qt.vector4d(tailLeft - lift, slabTop, tailRight - tailLeft + lift * 2, thickness)
            box1: Qt.vector4d(frontLeft, slabTop, frontRight - frontLeft, thickness)
            box2: Qt.vector4d(Math.min(headMid, tailMid), slabTop + (thickness - neck) / 2, apart, neck)

            // At rest the head lies on the tail, and a reach would swell the
            // two into something fatter than either; it comes up only as they
            // part.
            reach: Theme.pillSpread * Math.min(1, apart / thickness)
            box3: Qt.vector4d(bulbLeft, bulbTop, bulbWidth, bulbThickness)
            // The bulb joins the head with a small reach of its own: enough
            // to round the step between the two, and short enough that the
            // swell a join adds (a quarter of the reach) stays inside the
            // pixel between the wall and the pill's edge.
            reaches: Qt.vector4d(reach, reach, reach, 3 * press)
            // The strong step, not a popup row's hover: on a pill this thin
            // over a bright wallpaper, the row fill was barely there.
            fill: Qt.vector4d(tone.r, tone.g, tone.b, tone.a)
            rimTop: Qt.vector4d(Theme.markRimTop.r, Theme.markRimTop.g, Theme.markRimTop.b, Theme.markRimTop.a)
            // The bulb's band, which is the rest of the mark's or taller when
            // it bulges.
            rimFrom: bulbTop
            rimTo: bulbTop + bulbThickness
        }

        RowLayout {
            id: buttons

            anchors.fill: parent
            spacing: Theme.workspaceGap

            Repeater {
                id: workspaces

                model: ScriptModel {
                    // "sort-by-number": true
                    values: [...Hyprland.workspaces.values].sort((a, b) => a.id - b.id)
                }

                delegate: Item {
                    id: button

                    required property var modelData
                    required property int index
                    readonly property bool active: Hyprland.focusedWorkspace?.id === modelData.id

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

                    // How far the mark has come onto this workspace, 0..1: in
                    // as its head arrives, back out as its tail lets go.
                    property real lit: button.active ? 1 : 0

                    Behavior on lit {
                        NumberAnimation {
                            duration: button.active ? Theme.markMs * 0.6 : Theme.markMs
                            easing.type: button.active ? Easing.OutCubic : Easing.InOutCubic
                        }
                    }

                    // The number and icons of a workspace you are not on stand
                    // a little back, and come forward with the mark.
                    readonly property real ink: Theme.restOpacity + (1 - Theme.restOpacity) * button.lit

                    // Held down on one of the icons. A press on the number
                    // gives no answer of its own: the mark moving over is it.
                    readonly property bool held: {
                        for (const child of row.children)
                            if (child.pressed === true)
                                return true;
                        return false;
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
                        // By id, the way the number row's keys reach it. The tenth
                        // is named "0", and focusing it by name asked for a
                        // workspace 0 that does not exist; back-and-forth then
                        // took that as a second visit and flipped between the
                        // last two.
                        onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${button.modelData.id} })`)
                    }

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        height: parent.height
                        spacing: Theme.appIconGap

                        // The workspace's name, which for the ten on the number row
                        // is the key that reaches it: 0 for the tenth, as on the
                        // keyboard. It stays at one weight, since the mark says
                        // which workspace is yours and a number that went bold
                        // would widen the mark as it arrived. Laid out on its
                        // ink, like the icons beside it: tabular figures give
                        // a 1 as much side bearing as an 8 is wide, which put
                        // the 1 twice as far from its icons as the 2.
                        BarText {
                            Layout.fillHeight: true
                            tightWidth: true
                            text: button.modelData.name.replace(/^special:/, "")
                            fontSize: Theme.workspaceTextSize
                            color: Theme.fg
                            opacity: numberBounce.running ? 1 : button.ink

                            transform: Translate { y: numberBounce.offset }
                        }

                        // The fallback, and only that. Urgency belongs on the
                        // icon of the app that wants you, so the number moves
                        // just when the workspace is shouting and no icon on it
                        // has owned up — an ignored window, or one Hyprland
                        // flagged by workspace without flagging the window.
                        // Otherwise a shouting app would move twice over.
                        Bounce {
                            id: numberBounce
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
                                urgent: root.anyUrgent(modelData.addresses)
                                // Only on the workspace in front of you: Hyprland
                                // keeps the last window as active after you move
                                // to an empty one, and a dot left behind there
                                // would point at a window you are not in.
                                focused: button.active && modelData.addresses.includes(Hyprland.activeToplevel?.address)
                                pressed: tap.pressed
                                // An app that wants you is not one to stand back.
                                inkOpacity: app.urgent ? 1 : button.ink

                                // The app's name, the way the Dock labels its
                                // icons.
                                HoverPopup {
                                    anchorItem: app
                                    hovered: tap.containsMouse
                                    pressed: tap.pressed
                                    text: app.entry?.name || app.windowClass
                                }

                                MouseArea {
                                    id: tap
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    // Focusing a window switches workspace as a side
                                    // effect. Where an icon stands for several windows,
                                    // each click moves on to the next of them, so the
                                    // icon is a way through the whole group.
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
