import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components

// One group per workspace, ordered by number, with one icon per app.
// Groups expand in place; individual windows can be dragged to another workspace.
BarItem {
    id: root

    property string expandedClass: ""
    property int expandedWorkspace: -1
    property var expandedWorkspaceObject: null
    property bool dragging: false
    property Item dragSource: null
    property string dragAddress: ""
    property var dragWorkspace: null
    property int dragWorkspaceId: -1
    property point dragPoint: Qt.point(0, 0)

    function collapse(): void {
        expandedWorkspace = -1;
        expandedClass = "";
        expandedWorkspaceObject = null;
    }

    function windowClass(toplevel): string {
        return toplevel.lastIpcObject?.class || toplevel.wayland?.appId || "";
    }

    readonly property bool expansionValid: expandedWorkspaceObject !== null
        && expandedWorkspaceObject.id === expandedWorkspace
        && Hyprland.workspaces.values.includes(expandedWorkspaceObject)
        && Hyprland.toplevels.values.filter(t => t.workspace?.id === expandedWorkspace
            && root.windowClass(t) === expandedClass).length > 1
    onExpansionValidChanged: if (!expansionValid) Qt.callLater(root.collapseInvalidExpansion)

    function collapseInvalidExpansion(): void {
        if (!expansionValid)
            collapse();
    }

    readonly property bool dragValid: dragSource !== null && dragWorkspace !== null
        && dragWorkspace.id === dragWorkspaceId
        && Hyprland.toplevels.values.some(t => t.address === dragAddress && t.workspace === dragWorkspace)
    onDragValidChanged: if (dragging && !dragValid) root.cancelDrag()

    function cancelDrag(): void {
        dragging = false;
        dragSource = null;
        dragAddress = "";
        dragWorkspace = null;
        dragWorkspaceId = -1;
    }

    // Hit only workspace bodies, with the first one's screen-edge padding included.
    function workspaceAt(point) {
        const local = root.mapFromItem(strip, point.x, point.y);
        const pillY = Theme.pillTop(root.height);
        if (local.x < 0 || local.x >= root.width || local.y < pillY || local.y >= pillY + Theme.barHeight)
            return null;
        for (let i = 0; i < workspaces.count; i++) {
            const button = workspaces.itemAt(i);
            if (button && point.x >= button.x - (i === 0 ? root.padLeft : 0)
                && point.x < button.x + button.width)
                return button.modelData;
        }
        return null;
    }

    readonly property var dropWorkspace: dragging ? root.workspaceAt(dragPoint) : null
    readonly property int dropWorkspaceId: dropWorkspace && dropWorkspace !== dragWorkspace ? dropWorkspace.id : -1

    // Capture the ID at release; membership follows the workspace object through compaction.
    function finishDrag(point): void {
        const destination = root.workspaceAt(point);
        const id = destination?.id;
        const address = dragAddress;
        const valid = dragging && dragValid && destination !== dragWorkspace
            && Number.isInteger(id) && id > 0 && /^[0-9a-fA-F]+$/.test(address);
        cancelDrag();
        if (!valid)
            return;
        Hyprland.dispatch(`move_windows(${id}, {"0x${address}"})`);
    }

    HoverHandler {
        id: stripHover
        // Include the strip's pill padding when deciding whether a click was outside.
        parent: root
    }

    Connections {
        target: Hyprland
        enabled: root.expandedWorkspace !== -1

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data === "click" && !stripHover.hovered)
                root.collapse();
        }
    }

    onClicked: root.collapse()

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

    // The Hyprland dispatcher speaks Lua here (hyprland.lua drives this setup),
    // which is why these read as function calls rather than bare dispatchers.
    // Down is the next one: the strip lies across the wheel like a Slider,
    // so it goes the way a slider does rather than the way an icon does.
    onScrollUp: if (!root.dragging) Hyprland.dispatch('workspace_cycle(-1)')
    onScrollDown: if (!root.dragging) Hyprland.dispatch('workspace_cycle(1)')

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
            if (root.dragging)
                return false;
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
        FlowMark {
            id: mark
            held: strip.held
            slabY: Theme.pillTop(strip.height)
            slabHeight: Theme.barHeight
            atFirst: strip.selected !== null && strip.selected.index === 0
            atLast: strip.selected !== null && strip.selected.index === workspaces.count - 1
            wallLeft: wantLeft - inset + Theme.pillBorder
            wallRight: strip.width + Theme.pillPad * 2 - Theme.pillBorder
            visible: hasSelection
            x: -Theme.pillPad
            width: strip.width + Theme.pillPad * 2
            height: strip.height

            readonly property real targetLeft: strip.selected ? strip.selected.x + inset : wantLeft
            readonly property real targetRight: strip.selected ? strip.selected.x + strip.selected.width + Theme.pillPad * 2 - inset : wantRight
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

            // Keep the liquid inside the pill's current rounded rim as both animate.
            layer.enabled: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: markMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

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
                            const cls = root.windowClass(toplevel);
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

                    // Every window of a multi-window app keeps an icon; the ones after the
                    // first are folded to nothing until the group is expanded. The first
                    // keeps its address as key across both states, so a press on it is not
                    // lost to a rebuild, and nothing is created or removed to animate.
                    readonly property var icons: {
                        const result = [];
                        for (const app of button.apps) {
                            const expanded = root.expandedWorkspace === button.modelData.id
                                && root.expandedClass === app.windowClass;
                            app.addresses.forEach((address, i) => {
                                result.push({
                                    key: address,
                                    windowClass: app.windowClass,
                                    addresses: expanded || i > 0 ? [address] : app.addresses,
                                    expanded,
                                    folded: i > 0 && !expanded
                                });
                            });
                        }
                        return result;
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

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: Theme.pillTop(button.height) + Theme.markInset
                        anchors.bottomMargin: Theme.pillTop(button.height) + Theme.markInset
                        radius: Theme.pillRadius - Theme.markInset
                        color: Theme.selectionStrong
                        visible: root.dropWorkspaceId === button.modelData.id
                    }

                    MouseArea {
                        id: press
                        anchors.fill: parent
                        // The strip's left padding belongs to the first workspace, not
                        // to the strip: an item may reach past its parent as long as
                        // nothing in the chain clips, and that is what turns the corner
                        // of the screen into a click on workspace one.
                        anchors.leftMargin: button.index === 0 ? -root.padLeft : 0
                        onPressed: root.collapse()
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
                            // Keyed by address: see `icons`.
                            model: ScriptModel {
                                values: button.icons
                                objectProp: "key"
                            }

                            delegate: AppIcon {
                                id: app

                                required property var modelData
                                required property int index

                                Layout.alignment: Qt.AlignVCenter
                                // How far a folded icon has opened, 0..1: width, gap and
                                // opacity together, the way the strip itself opens.
                                property real reveal: modelData.folded ? 0 : 1

                                Behavior on reveal {
                                    NumberAnimation {
                                        duration: Theme.markMs * 0.6
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                visible: reveal > 0
                                opacity: reveal
                                Layout.preferredWidth: implicitWidth * reveal
                                Layout.leftMargin: -Theme.appIconGap * (1 - reveal)
                                windowClass: modelData.windowClass
                                urgent: root.anyUrgent(modelData.addresses)
                                // Only on the workspace in front of you: Hyprland
                                // keeps the last window as active after you move
                                // to an empty one, and a dot left behind there
                                // would point at a window you are not in.
                                focused: button.active && modelData.addresses.includes(Hyprland.activeToplevel?.address)
                                pressed: tap.pressed && !root.dragging
                                // An app that wants you is not one to stand back.
                                inkOpacity: (app.urgent ? 1 : button.ink) * (root.dragging && root.dragSource === app ? 0.35 : 1)

                                Component.onDestruction: if (root.dragSource === app) root.cancelDrag()

                                // The app's name, the way the Dock labels its
                                // icons.
                                HoverPopup {
                                    anchorItem: app
                                    hovered: tap.containsMouse && !root.dragging
                                    pressed: tap.pressed || root.dragging
                                    text: app.modelData.expanded
                                        ? (Hyprland.toplevels.values.find(t => t.address === app.modelData.key)?.title
                                            || app.entry?.name || app.windowClass)
                                        : (app.entry?.name || app.windowClass)
                                }

                                MouseArea {
                                    id: tap
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    property point pressPoint: Qt.point(0, 0)
                                    property string addressOnPress: ""
                                    property bool suppressClick: false

                                    onPressed: mouse => {
                                        suppressClick = false;
                                        pressPoint = tap.mapToItem(strip, mouse.x, mouse.y);
                                        const addresses = app.modelData.addresses;
                                        addressOnPress = addresses.length === 1 ? addresses[0] : "";
                                        if (addresses.length > 1) {
                                            suppressClick = true;
                                            root.expandedWorkspaceObject = button.modelData;
                                            root.expandedClass = app.windowClass;
                                            root.expandedWorkspace = button.modelData.id;
                                            Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${addresses[0]}" })`);
                                        } else if (!app.modelData.expanded) {
                                            root.collapse();
                                        }
                                    }

                                    onPositionChanged: mouse => {
                                        if (!pressed || addressOnPress === "" || (suppressClick && !root.dragging))
                                            return;
                                        const point = tap.mapToItem(strip, mouse.x, mouse.y);
                                        if (!root.dragging && Math.hypot(point.x - pressPoint.x, point.y - pressPoint.y) >= drag.threshold) {
                                            suppressClick = true;
                                            root.dragSource = app;
                                            root.dragAddress = addressOnPress;
                                            root.dragWorkspace = button.modelData;
                                            root.dragWorkspaceId = button.modelData.id;
                                            root.dragging = true;
                                        }
                                        if (root.dragging && root.dragSource === app) {
                                            root.dragPoint = point;
                                        }
                                    }

                                    onReleased: mouse => {
                                        if (root.dragging && root.dragSource === app)
                                            root.finishDrag(tap.mapToItem(strip, mouse.x, mouse.y));
                                        addressOnPress = "";
                                    }

                                    onCanceled: {
                                        suppressClick = true;
                                        addressOnPress = "";
                                        if (root.dragSource === app)
                                            root.cancelDrag();
                                    }

                                    onClicked: {
                                        if (!suppressClick)
                                            Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${app.modelData.addresses[0]}" })`);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Draw outside the layout so the ghost never changes workspace widths or takes input.
        AppIcon {
            z: 10
            visible: root.dragging
            windowClass: root.dragSource?.windowClass ?? ""
            focused: root.dragSource?.focused ?? false
            x: root.dragPoint.x - width / 2
            y: root.dragPoint.y - height / 2
            width: implicitWidth
            height: Theme.barHeight
        }
    }
}
