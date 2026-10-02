import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components

// One group per workspace, ordered by number, with one icon per app.
// Clicking an icon that stands for several windows walks through them.
BarItem {
    id: root

    // workspace-taskbar ignore-list
    readonly property var ignored: [/^gamescope$/]

    // Which windows are shouting. Hyprland flags the workspace, but it flags
    // the window too, so the bar can point at the app that wants you rather
    // than at the room it is in. Gathered once for the whole strip instead of
    // per workspace: every workspace would otherwise walk the same list.
    readonly property var urgentAddresses: Hyprland.toplevels.values.filter(t => t.urgent).map(t => t.address)

    function anyUrgent(addresses) {
        return addresses.some(a => root.urgentAddresses.includes(a));
    }

    // ID compaction needs fresh window associations and monitor focus in Quickshell 0.3.
    function refreshWorkspaceAssociations(): void {
        Hyprland.refreshToplevels();
        Hyprland.refreshMonitors();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "changeworkspaceid")
                Qt.callLater(root.refreshWorkspaceAssociations);
        }
    }

    Connections {
        target: Hyprland.workspaces

        // Association refreshes discover new workspaces with ID -1; resolve those after discovery.
        function onValuesChanged() {
            if (Hyprland.workspaces.values.some(w => w.id === -1))
                Qt.callLater(Hyprland.refreshWorkspaces);
        }
    }

    // The Hyprland dispatcher speaks Lua here (hyprland.lua drives this setup),
    // which is why these read as function calls rather than bare dispatchers.
    // Down is the next one: the strip lies across the wheel like a Slider,
    // so it goes the way a slider does rather than the way an icon does.
    onScrollUp: Hyprland.dispatch('workspace_cycle(-1)')
    onScrollDown: Hyprland.dispatch('workspace_cycle(1)')

    // One strip rather than a run of loose workspaces, because the selection is
    // drawn across it rather than by each workspace for itself.
    Item {
        id: strip

        Layout.fillHeight: true
        implicitWidth: buttons.implicitWidth

        // Use the drawer's spring when workspace groups make the left pill grow or shrink.
        Behavior on implicitWidth {
            id: widthChange

            enabled: root._started
            property bool growing: true
            onTargetValueChanged: growing = targetValue > strip.implicitWidth

            SequentialAnimation {
                PauseAnimation {
                    duration: widthChange.growing ? 0 : 180
                }
                SpringAnimation {
                    spring: widthChange.growing ? Theme.springStiffness : Theme.foldSpring
                    damping: Theme.foldDamping
                    epsilon: 0.1
                }
            }
        }

        // Read focus directly: delegate active bindings update separately and
        // briefly leave no selection when moving towards an earlier workspace.
        readonly property Item selected: {
            const focused = Hyprland.focusedWorkspace?.id;
            for (const child of buttons.children)
                if (focused !== undefined && child.modelData?.id === focused)
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
        // holding its app icons. It was a rule under the group
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

            readonly property real targetLeft: strip.selected ? strip.selected.x + inset : wantLeft
            readonly property real targetRight: strip.selected ? strip.selected.x + strip.selected.width + Theme.pillPad * 2 - inset : wantRight
            property real wantLeft: 0
            property real wantRight: 0
            property bool hasSelection: false

            // Focus, delegate removal, and layout can change separately in one update.
            // Retain the drawn destination until all three have settled.
            function retarget(): void {
                mark.hasSelection = strip.selected !== null;
                if (!mark.hasSelection)
                    return;
                mark.wantLeft = mark.targetLeft;
                mark.wantRight = mark.targetRight;
            }

            onTargetLeftChanged: Qt.callLater(mark.retarget)
            onTargetRightChanged: Qt.callLater(mark.retarget)
            Component.onCompleted: Qt.callLater(mark.retarget)

            Connections {
                target: strip

                function onSelectedChanged() {
                    Qt.callLater(mark.retarget);
                }
            }

            // Each end runs from wherever it is to where the mark belongs, so
            // a switch made mid-run picks both ends up where they are rather
            // than snapping them together first. Not until the mark has been
            // placed once, or it would flow in from the screen's edge.
            property bool placed: false
            onPlacedChanged: if (placed) {
                tailLeft = wantLeft;
                tailRight = wantRight;
                tailProgress = 1;
                roundness = 0;
            }

            // Place once; a delegate disappearing between IPC updates keeps its motion.
            onVisibleChanged: if (visible && !placed)
                Qt.callLater(() => {
                    if (mark.visible)
                        mark.placed = true;
                })

            property real headLeft: wantLeft
            property real headRight: wantRight
            property real tailLeft: wantLeft
            property real tailRight: wantRight
            property point tailStart: Qt.point(wantLeft, wantRight)
            property real tailProgress: 1
            property real roundness: 0

            // A new destination keeps the tail wherever the previous move left it.
            function followTail(): void {
                if (!mark.placed) {
                    mark.tailLeft = mark.wantLeft;
                    mark.tailRight = mark.wantRight;
                    mark.tailProgress = 1;
                    mark.roundness = 0;
                    return;
                }
                mark.tailStart = Qt.point(mark.tailLeft, mark.tailRight);
                mark.tailProgress = 0;
            }

            onWantLeftChanged: followTail()
            onWantRightChanged: followTail()

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
            FrameAnimation {
                running: mark.visible && mark.placed && (mark.tailProgress < 1 || mark.roundness > 0)

                // Distance and the tail's shrinking size accelerate the same cubic flow.
                onTriggered: {
                    const previousMid = mark.tailMid;
                    const distance = mark.apart / (mark.thickness * 4);
                    const shrink = 1 - mark.blobHeight / mark.thickness;
                    const speed = (1 + 0.75 * distance * distance) * (1 + 0.75 * shrink);
                    mark.tailProgress = Math.min(1, mark.tailProgress + frameTime * 1000 * speed / (Theme.markMs * 1.1));
                    const t = Math.max(0, (mark.tailProgress - 0.2) / 0.8);
                    const eased = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
                    const left = mark.tailStart.x + (mark.wantLeft - mark.tailStart.x) * eased;
                    const right = mark.tailStart.y + (mark.wantRight - mark.tailStart.y) * eased;
                    const velocity = mark.tailProgress < 1 && frameTime > 0 ? Math.abs((left + right) / 2 - previousMid) / frameTime : 0;
                    mark.tailLeft = left;
                    mark.tailRight = right;
                    // Ease into a ball as flow speeds up, and back into a pill at rest.
                    const pace = Math.min(1, velocity / (mark.thickness * 24));
                    const round = pace * pace * (3 - 2 * pace);
                    const roundingTime = round > mark.roundness ? 0.025 : 0.05;
                    mark.roundness += (round - mark.roundness) * (1 - Math.exp(-frameTime / roundingTime));
                    if (round === 0 && mark.roundness < 0.001)
                        mark.roundness = 0;
                }
            }

            // The pill's ends, as walls for the head. A pixel short of the
            // slab's edge, so the pill's rim stays in view outside the glass
            // pressed against it. Only at the first and last workspace: in
            // the middle of the strip the overshoot has room to run.
            readonly property bool atFirst: strip.selected !== null && strip.selected.index === 0
            readonly property bool atLast: strip.selected !== null && strip.selected.index === workspaces.count - 1
            readonly property real wallLeft: wantLeft - inset + Theme.pillBorder
            // The pill keeps its old width briefly after an empty workspace leaves.
            readonly property real wallRight: strip.width + Theme.pillPad * 2 - Theme.pillBorder

            // A long jump can overshoot by more than a narrow workspace's width.
            readonly property real frontLeft: Math.min(atFirst ? Math.max(headLeft - lift, wallLeft) : headLeft - lift, atLast ? wallRight : Infinity)
            readonly property real frontRight: Math.max(frontLeft, atLast ? Math.min(headRight + lift, wallRight) : headRight + lift)

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
            readonly property real neck: thickness * (1 - 0.6 * Math.pow(Math.min(1, apart / (thickness * 3)), 2))
            readonly property real tailWidth: tailRight - tailLeft + lift * 2
            readonly property real blobWidth: tailWidth + (neck - tailWidth) * roundness
            readonly property real blobHeight: thickness + (neck - thickness) * roundness

            visible: hasSelection
            x: -Theme.pillPad
            width: strip.width + Theme.pillPad * 2
            height: strip.height

            // Keep the liquid inside the pill's current rounded rim as both animate.
            layer.enabled: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: markMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            box0: Qt.vector4d(tailMid - blobWidth / 2, slabTop + (thickness - blobHeight) / 2, blobWidth, blobHeight)
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

        Item {
            id: markMask

            width: mark.width
            height: mark.height
            visible: false
            layer.enabled: true

            Rectangle {
                // BarItem rounds the pill width; account for that rounding at its left edge.
                x: strip.width + root.padLeft + root.padRight - root.width + Theme.pillBorder
                y: Theme.pillTop(parent.height) + Theme.pillBorder
                width: Math.max(0, root.width - root.padLeft - root.padRight + Theme.pillPad * 2 - Theme.pillBorder * 2)
                height: Theme.barHeight - Theme.pillBorder * 2
                radius: Theme.pillRadius - Theme.pillBorder
                color: "white"
            }
        }

        RowLayout {
            id: buttons

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: implicitWidth
            spacing: Theme.workspaceGap

            Repeater {
                id: workspaces

                model: ScriptModel {
                    // Quickshell can retain old IDs after compaction; stale IPC window counts are unreliable.
                    values: [...Hyprland.workspaces.values]
                        .filter(w => w.active || w.lastIpcObject?.ispersistent
                            || Hyprland.toplevels.values.some(t => t.workspace?.id === w.id))
                        .sort((a, b) => a.id - b.id)
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

                    // The icons of a workspace you are not on stand
                    // a little back, and come forward with the mark.
                    readonly property real ink: Theme.restOpacity + (1 - Theme.restOpacity) * button.lit

                    // Held down on one of the icons. A press on the workspace
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
                        onClicked: {
                            if (!button.active)
                                Hyprland.dispatch(`hl.dsp.focus({ workspace = ${button.modelData.id} })`);
                        }
                    }

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        height: parent.height
                        spacing: Theme.appIconGap

                        // An empty workspace occupies one icon's ink width without drawing an icon.
                        Item {
                            visible: button.apps.length === 0 && !emptyBounce.running
                            Layout.fillHeight: true
                            implicitWidth: Math.round(Theme.iconSize * Theme.iconInk)
                        }

                        // Urgency from ignored apps still needs a visible signal.
                        BarText {
                            visible: emptyBounce.running
                            Layout.fillHeight: true
                            tightWidth: true
                            text: "\u25cb"
                            fontSize: Theme.textSize
                            color: Theme.fg
                            opacity: emptyBounce.running ? 1 : button.ink

                            transform: Translate { y: emptyBounce.offset }
                        }

                        // The fallback, and only that. Urgency belongs on the
                        // icon of the app that wants you, so the marker moves
                        // just when the workspace is shouting and no icon on it
                        // has owned up — an ignored window, or one Hyprland
                        // flagged by workspace without flagging the window.
                        // Otherwise a shouting app would move twice over.
                        Bounce {
                            id: emptyBounce
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
