import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components
import qs.services

// One group per workspace, ordered by number, with one icon per app.
// Groups expand in place; individual windows can be dragged to another workspace.
BarItem {
    id: root

    enabled: WorkspaceSync.settled

    property string expandedClass: ""
    property int expandedWorkspace: -1
    property var expandedWorkspaceObject: null
    property bool dragging: false
    property Item dragSource: null
    property string dragAddress: ""
    property var dragWorkspace: null
    property int dragWorkspaceId: -1
    property point dragPoint: Qt.point(0, 0)
    // True while a group opens or folds. The icons animate their own widths
    // then, and the strip follows them exactly rather than chasing them with
    // its spring, which would leave the pill's end behind (see widthChange).
    property bool folding: false

    // The bar draws GlassMark over the pill; this supplies its geometry
    // and draws the plain selection when transparency is reduced.
    readonly property Item markItem: mark
    property bool drawsMark: true
    contentAnimating: folding || stripResize.running || mark.animating

    Timer {
        id: foldTimer
        interval: Theme.markMs * 0.6
        onTriggered: root.folding = false
    }

    function startFold(): void {
        folding = true;
        foldTimer.restart();
    }

    function expand(workspace, cls: string): void {
        startFold();
        expandedWorkspaceObject = workspace;
        expandedClass = cls;
        expandedWorkspace = workspace.id;
    }

    function collapse(): void {
        if (expandedWorkspace === -1)
            return;
        startFold();
        expandedWorkspace = -1;
        expandedClass = "";
        expandedWorkspaceObject = null;
    }

    Connections {
        target: Settings

        function onGroupWindowsChanged(): void {
            root.collapse();
            root.startFold();
        }
    }

    function windowClass(toplevel): string {
        return toplevel.wayland?.appId || toplevel.lastIpcObject?.class || "";
    }

    // Quickshell can retain old IDs after compaction; stale IPC window counts are unreliable.
    readonly property var liveWorkspaces: [...Hyprland.workspaces.values]
        .filter(w => w.id !== -1 && !w.name.startsWith("special:"))
        .filter(w => w.active || w.lastIpcObject?.ispersistent
            || Hyprland.toplevels.values.some(t => t.workspace?.id === w.id))
        .sort((a, b) => a.id - b.id)
        .map(w => ({ id: w.id, name: w.name, urgent: w.urgent, workspace: w }))

    // While WorkspaceSync settles a renumbering, Quickshell's workspaces and
    // windows disagree with each other, so the strip draws from the last state
    // that was whole: which workspaces there were, which one had focus, and
    // where each window was. Windows that close meanwhile still go at once.
    property var frozen: null
    property var lastWhole: null

    Connections {
        target: WorkspaceSync

        function onSettledChanged(): void {
            if (WorkspaceSync.settled) {
                root.frozen = null;
                return;
            }
            root.cancelDrag();
            if (root.lastWhole !== null) {
                root.frozen = root.lastWhole;
                return;
            }
            const placement = ({});
            for (const t of Hyprland.toplevels.values)
                placement[t.address] = t.workspace?.id;
            root.frozen = {
                workspaces: root.liveWorkspaces,
                focused: Hyprland.focusedWorkspace?.id ?? -1,
                placement: placement
            };
        }
    }

    readonly property var shownWorkspaces: frozen ? frozen.workspaces : liveWorkspaces
    onShownWorkspacesChanged: positionsDirty = true
    readonly property int focusedId: frozen ? frozen.focused : (Hyprland.focusedWorkspace?.id ?? -1)
    onFocusedIdChanged: positionsDirty = true

    function workspaceOf(toplevel) {
        return root.frozen ? root.frozen.placement[toplevel.address] : toplevel.workspace?.id;
    }

    readonly property bool expansionValid: expandedWorkspaceObject !== null
        && (root.frozen !== null || expandedWorkspaceObject.id === expandedWorkspace)
        && root.shownWorkspaces.some(w => w.workspace === expandedWorkspaceObject)
        && Hyprland.toplevels.values.filter(t => root.workspaceOf(t) === expandedWorkspace
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

    function inPill(point): bool {
        const local = root.mapFromItem(strip, point.x, point.y);
        const pillY = Theme.pillTop(root.height);
        return local.x >= 0 && local.x < root.width && local.y >= pillY && local.y < pillY + Theme.barHeight;
    }

    // Hit only workspace bodies, with the first one's screen-edge padding included.
    function buttonAt(point): Item {
        if (!root.inPill(point))
            return null;
        for (let i = 0; i < workspaces.count; i++) {
            const button = workspaces.itemAt(i);
            if (button && point.x >= button.drawnX - (i === 0 ? root.padLeft : 0)
                && point.x < button.drawnX + button.width)
                return button;
        }
        if (newWorkspace.visible && point.x >= newWorkspace.x - Theme.workspaceGap)
            return newWorkspace;
        return null;
    }

    // The number a new workspace takes: compaction keeps them contiguous,
    // so it is the one after the last.
    function nextWorkspaceId(): int {
        return (workspaces.itemAt(workspaces.count - 1)?.workspaceInfo.id ?? 0) + 1;
    }

    // The workspace a release would move the window to, or null.
    readonly property Item dropTarget: {
        const button = dragging ? root.buttonAt(dragPoint) : null;
        return button && button.workspaceInfo?.workspace !== dragWorkspace ? button : null;
    }

    // An empty workspace is one icon's ink wide.
    readonly property int emptyWidth: Math.round(Theme.iconSize * Theme.iconInk)

    // The gap between two workspaces is a drop of its own: the window gets a
    // workspace there, and the ones after it move up a number. Returns the
    // index of the workspace after the gap, or -1. Not offered either side of
    // a workspace the window has to itself, which would come back the same.
    //
    // Hovered, the gap opens an empty workspace (see `opening`) and reaches
    // over it, but not on to where the next workspace has gone: only as far
    // as that workspace will be once the gap closes again. Otherwise leaving
    // the gap to the right would close it and send the workspace you were
    // reaching for back past the pointer.
    function gapAt(point): int {
        if (!root.inPill(point))
            return -1;
        for (let i = 1; i < workspaces.count; i++) {
            const before = workspaces.itemAt(i - 1);
            const after = workspaces.itemAt(i);
            if (!before || !after)
                continue;
            const closed = after.drawnX - after.gapBefore;
            const reach = after.opening * (Math.min(root.emptyWidth, after.width) - 1);
            if (point.x < before.drawnX + before.width || point.x >= closed + reach)
                continue;
            const alone = Hyprland.toplevels.values.filter(t => root.workspaceOf(t) === root.dragWorkspaceId).length === 1;
            const from = root.shownWorkspaces.findIndex(w => w.workspace === root.dragWorkspace);
            return alone && (i === from || i === from + 1) ? -1 : i;
        }
        return -1;
    }

    readonly property int insertAt: dragging ? root.gapAt(dragPoint) : -1
    onInsertAtChanged: root.startFold()

    // Where the drop line stands: in the middle of an opened gap, or between
    // icons where the window will show up in the workspace it lands in.
    readonly property real dropX: {
        const before = workspaces.itemAt(root.insertAt - 1);
        const after = workspaces.itemAt(root.insertAt);
        if (root.insertAt !== -1 && before && after)
            return (before.drawnX + before.width + after.drawnX) / 2;
        return root.dropTarget !== null && root.dragSource !== null
            ? (root.dropTarget.drawnX ?? root.dropTarget.x) + root.dropTarget.slotX(root.dragSource.windowClass, root.dragAddress)
            : NaN;
    }

    // Capture the ID at release; membership follows the workspace object through compaction.
    // A drop in a gap names the workspace after it, which makes way.
    function finishDrag(point): void {
        const gap = root.gapAt(point);
        const between = gap !== -1;
        const button = between ? workspaces.itemAt(gap) : root.buttonAt(point);
        const fresh = button !== null && button === newWorkspace;
        const destination = button?.workspaceInfo?.workspace ?? null;
        const id = fresh ? root.nextWorkspaceId() : destination?.id;
        const address = dragAddress;
        const valid = dragging && dragValid && (fresh || between || destination !== dragWorkspace)
            && Number.isInteger(id) && id > 0 && /^[0-9a-fA-F]+$/.test(address);
        cancelDrag();
        if (!valid)
            return;
        Hyprland.dispatch(between
            ? `insert_window_at(${id}, "0x${address}")`
            : `move_window_to(${id}, "0x${address}")`);
    }

    property bool positionsDirty: true
    // Retain the last consistent placement for workspace ID compaction.
    FrameAnimation {
        id: positionTracker
        running: root.visible && (root.positionsDirty || root.folding || stripResize.running || root.dragging)
        onTriggered: {
            root.positionsDirty = false;
            if (WorkspaceSync.settled) {
                const placement = ({});
                for (const toplevel of Hyprland.toplevels.values)
                    placement[toplevel.address] = toplevel.workspace?.id;
                root.lastWhole = { workspaces: root.shownWorkspaces, focused: root.focusedId, placement };
            }
        }
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
    // Named so the strip is in the accessibility tree as the area the
    // wheel cycles through workspaces on; each workspace is its own button.
    name: "Workspaces"
    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
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

            enabled: root._started && !root.folding
            property bool growing: true
            onTargetValueChanged: growing = targetValue > strip.implicitWidth

            SequentialAnimation {
                id: stripResize
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

        // A workspace that goes takes its slot with it at once, and everything
        // after it would jump left while the pill's end springs in. Instead
        // those workspaces are held out by the width the strip still has to
        // lose, so they close up with the pill's end, on its spring.
        property real closedAt: Infinity
        readonly property real closing: strip.implicitWidth - buttons.implicitWidth

        // Let go once the spring is done, but not the moment it stops: a new
        // target stops and restarts it. A window moved out of a workspace
        // into another gives two at once, one for the workspace that goes
        // and one for the icon that arrives.
        Connections {
            target: stripResize
            function onRunningChanged() {
                if (!stripResize.running)
                    unclose.restart();
            }
        }

        Timer {
            id: unclose
            interval: 50
            onTriggered: if (!stripResize.running) strip.closedAt = Infinity
        }

        // The workspace selection mode is on, if it is on one of these.
        readonly property Item keyed: OpenPopup.selected?.parent === buttons ? OpenPopup.selected : null

        // Where the mark is: the focused workspace, or the one selection
        // mode is on, the way a tab bar's lens follows the keys while the
        // focused workspace keeps its icons lit (button.ink).
        //
        // Read focus directly: delegate active bindings update separately and
        // briefly leave no selection when moving towards an earlier workspace.
        readonly property Item selected: {
            if (strip.keyed)
                return strip.keyed;
            const focused = root.focusedId;
            for (const child of buttons.children)
                if (focused !== -1 && child.workspaceInfo?.id === focused)
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
        // The head runs on a spring, Apple's snappy one for a switch, which
        // all but lands without running past. What overshoot a long run does
        // carry would take it out through the pill's own end, so there the
        // end is a wall the head stops against.
        FlowMark {
            id: mark
            held: strip.held
            // Keep keyboard steps quick; workspace switches take a gentler spring.
            spring: strip.keyed ? Theme.keyMarkSpring : Theme.switchSpring
            damping: strip.keyed ? Theme.keyMarkDamping : Theme.switchDamping
            slabY: Theme.pillTop(strip.height)
            slabHeight: Theme.barHeight
            atFirst: strip.selected !== null && strip.selected.index === 0
            atLast: strip.selected !== null && strip.selected.index === workspaces.count - 1
            wallLeft: Theme.pillBorder
            wallRight: strip.width + Theme.pillPad * 2 - Theme.pillBorder
            visible: hasSelection
            x: -Theme.pillPad
            width: strip.width + Theme.pillPad * 2
            height: strip.height

            // The workspace the mark was last sent to.
            property Item placedOn: null

            readonly property real targetLeft: strip.selected ? strip.selected.drawnX + inset : wantLeft
            readonly property real targetRight: strip.selected ? strip.selected.drawnX + strip.selected.width + Theme.pillPad * 2 - inset : wantRight
            property bool hasSelection: false

            // Focus, delegate removal, and layout can change separately in one update.
            // Retain the drawn destination until all three have settled.
            function retarget(): void {
                mark.hasSelection = strip.selected !== null;
                if (!mark.hasSelection)
                    return;
                // Layout changes update the same destination rather than
                // starting another selection move.
                mark.resizing = strip.selected === mark.placedOn;
                mark.placedOn = strip.selected;
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

            opacity: root.drawsMark ? 1 : 0

            // Keep the liquid inside the pill's current rounded rim as both animate.
            layer.enabled: root.drawsMark
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
            layer.enabled: root.drawsMark

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
                    values: root.shownWorkspaces.map(w => w.id)
                }

                onItemRemoved: (index, item) => {
                    if (!widthChange.enabled)
                        return;
                    strip.closedAt = Math.min(strip.closedAt, item.x);
                    unclose.restart();
                }

                delegate: Item {
                    id: button

                    required property int modelData
                    required property int index
                    readonly property var workspaceInfo: root.shownWorkspaces.find(w => w.id === modelData)
                        ?? ({ id: modelData, urgent: false, workspace: null })
                    readonly property var iconItems: row.children.filter(c => c.icon !== undefined)
                    onIconItemsChanged: root.positionsDirty = true
                    onXChanged: root.positionsDirty = true
                    onDrawnXChanged: root.positionsDirty = true
                    readonly property bool active: root.focusedId === button.workspaceInfo.id

                    // A stop in the bar's selection mode (OpenPopup): Return
                    // goes to the workspace. The workspace mark comes over to
                    // say it is selected (strip.selected), where a mark of the
                    // selection's own would sit on top of it.
                    readonly property bool marksSelection: true

                    function keyPress(): void {
                        if (!WorkspaceSync.settled)
                            return;
                        root.collapse();
                        press.focusWorkspace();
                    }

                    // One entry per window class, in the order the classes first appear,
                    // so an app does not jump along the row as its windows come and go.
                    readonly property var apps: {
                        const byClass = Object.create(null);
                        const order = [];
                        for (const toplevel of Hyprland.toplevels.values) {
                            if (root.workspaceOf(toplevel) !== button.workspaceInfo.id)
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
                    // With Settings.groupWindows off every group stays expanded.
                    readonly property var icons: {
                        const result = [];
                        for (const app of button.apps) {
                            const expanded = (!Settings.groupWindows && app.addresses.length > 1)
                                || (root.expandedWorkspace === button.workspaceInfo.id
                                    && root.expandedClass === app.windowClass);
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

                    // Bring the focused workspace's icons forward with the mark.
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

                    // How far an empty workspace has opened in front of this
                    // one, 0..1, while a window is held over the gap before it
                    // (see root.insertAt). It draws nothing, the way an empty
                    // workspace does; the drop line stands in it.
                    property real opening: root.insertAt === button.index ? 1 : 0

                    Behavior on opening {
                        NumberAnimation {
                            duration: Theme.markMs * 0.6
                            easing.type: Easing.OutCubic
                        }
                    }

                    readonly property int gapBefore: Math.round(button.opening * (root.emptyWidth + Theme.workspaceGap))

                    Layout.fillHeight: true
                    Layout.leftMargin: button.gapBefore
                    implicitWidth: row.implicitWidth

                    // Keep collapse on the strip's original width spring.
                    readonly property real drawnX: x + (x >= strip.closedAt - 0.5 ? strip.closing : 0)
                    transform: Translate { x: button.drawnX - button.x }

                    // A folded app receives the window into its icon; expanded apps preserve window order.
                    function slotX(cls: string, address: string): real {
                        const shown = button.iconItems.filter(app => app.visible && !app.icon.folded);
                        if (shown.length === 0)
                            return row.implicitWidth / 2;
                        shown.sort((a, b) => a.x - b.x);
                        const matching = shown.filter(app => app.windowClass === cls);
                        const expanded = !Settings.groupWindows || (root.expandedWorkspace === button.workspaceInfo.id
                            && root.expandedClass === cls);
                        if (matching.length && !expanded)
                            return matching[0].x + matching[0].width * matching[0].scale / 2;
                        const order = Hyprland.toplevels.values.map(t => t.address);
                        const at = order.indexOf(address);
                        const next = matching.length
                            ? matching.find(app => order.indexOf(app.modelData) > at)
                            : shown.find((app, i) => (i === 0 || shown[i - 1].windowClass !== app.windowClass)
                                && order.indexOf(app.modelData) > at);
                        if (next)
                            return next.x - Theme.appIconGap / 2;
                        const before = matching.length ? matching[matching.length - 1] : shown[shown.length - 1];
                        return before.x + before.width * before.scale + Theme.appIconGap / 2;
                    }

                    MouseArea {
                        id: press
                        anchors.fill: parent
                        // The strip's left padding belongs to the first workspace, not
                        // to the strip: an item may reach past its parent as long as
                        // nothing in the chain clips, and that is what turns the corner
                        // of the screen into a click on workspace one. Between workspaces
                        // each takes half the gap, the way its mark reaches into it, and
                        // the last takes the pill's right padding.
                        anchors.leftMargin: button.index === 0 ? -root.padLeft : -Math.ceil(Theme.workspaceGap / 2)
                        anchors.rightMargin: button.index === workspaces.count - 1 ? -root.padRight : -Math.floor(Theme.workspaceGap / 2)
                        function focusWorkspace(): void {
                            if (!button.active)
                                Hyprland.dispatch(`hl.dsp.focus({ workspace = ${button.workspaceInfo.id} })`);
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: "Workspace " + button.workspaceInfo.id
                        Accessible.onPressAction: if (enabled && visible)
                            button.keyPress()

                        onPressed: root.collapse()
                        onClicked: press.focusWorkspace()
                    }

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        height: parent.height
                        spacing: 0

                        // An empty workspace occupies one icon's ink width without drawing an icon.
                        Item {
                            visible: button.apps.length === 0 && !emptyBounce.running
                            Layout.fillHeight: true
                            implicitWidth: root.emptyWidth
                        }

                        // Urgency from ignored apps still needs a visible signal.
                        BarText {
                            visible: emptyBounce.running
                            Layout.fillHeight: true
                            tightWidth: true
                            text: "\u25cb"
                            fontSize: Theme.textSize
                            color: Theme.fg
                            opacity: emptyBounce.running ? emptyBounce.fade : button.ink

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
                            running: button.workspaceInfo.urgent && !button.apps.some(a => root.anyUrgent(a.addresses))
                        }

                        Repeater {
                            // Keyed by address: see `icons`. The model holds the keys
                            // alone and each icon looks its entry up, because ScriptModel
                            // moves a row without taking the new value: a window dropped
                            // in ahead of a group would leave the old first icon open,
                            // still holding the whole group's addresses.
                            model: ScriptModel {
                                values: button.icons.map(icon => icon.key)
                            }

                            delegate: AppIcon {
                                id: app

                                required property string modelData
                                required property int index

                                // Folded while its row waits to be removed.
                                readonly property var icon: button.icons.find(icon => icon.key === app.modelData)
                                    ?? ({ key: app.modelData, windowClass: "", addresses: [], expanded: false, folded: true })

                                Layout.alignment: Qt.AlignVCenter
                                // How far a folded icon has opened, 0..1: width, gap and
                                // opacity together, the way the strip itself opens.
                                property real reveal: icon.folded ? 0 : 1
                                readonly property int gapWidth: index > 0 ? Theme.appIconGap : 0
                                readonly property int slotWidth: Math.round((implicitWidth + gapWidth) * reveal)

                                // Only for opening and folding: a folded icon that
                                // becomes the group's first, because the first window
                                // closed, takes its place at once.
                                Behavior on reveal {
                                    enabled: root.folding

                                    NumberAnimation {
                                        duration: Theme.markMs * 0.6
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                // The icon keeps its size and scales into a slot that
                                // shrinks under it: shrinking the icon itself would
                                // spill its artwork over the next one, or crop it
                                // and resize its layer every frame while it has a dot.
                                visible: reveal > 0
                                opacity: reveal
                                scale: reveal
                                transformOrigin: Item.Left
                                // Fold the gap into the slot so hiding the icon leaves no final layout jump.
                                Layout.leftMargin: Math.round(gapWidth * reveal)
                                Layout.rightMargin: slotWidth - implicitWidth - Layout.leftMargin
                                windowClass: icon.windowClass
                                // A folded icon's window is already in the first icon's addresses.
                                urgent: !icon.folded && root.anyUrgent(icon.addresses)
                                // Only on the workspace in front of you: Hyprland
                                // keeps the last window as active after you move
                                // to an empty one, and a dot left behind there
                                // would point at a window you are not in.
                                focused: button.active && icon.addresses.includes(Hyprland.activeToplevel?.address)
                                pressed: tap.pressed && !root.dragging
                                // An app that wants you is not one to stand back.
                                inkOpacity: (app.urgent ? 1 : button.ink) * (root.dragging && root.dragSource === app ? 0.35 : 1)

                                onXChanged: root.positionsDirty = true
                                onYChanged: root.positionsDirty = true
                                onIconChanged: root.positionsDirty = true
                                onRevealChanged: root.positionsDirty = true
                                Component.onDestruction: if (root.dragSource === app) root.cancelDrag()

                                // The app's name, the way the Dock labels its
                                // icons.
                                HoverPopup {
                                    id: label
                                    anchorItem: app
                                    hovered: tap.containsMouse && !root.dragging
                                    pressed: tap.pressed || root.dragging
                                    text: app.icon.expanded
                                        ? (Hyprland.toplevels.values.find(t => t.address === app.modelData)?.title
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

                                    function focusWindow(address: string): void {
                                        Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${address}" })`);
                                    }

                                    // The press's half: a bunched app opens out and its
                                    // first window comes forward; anything else folds an
                                    // open bunch away. True when a window is focused
                                    // already, which leaves the click nothing to do.
                                    function pressApp(): bool {
                                        const addresses = app.icon.addresses;
                                        if (addresses.length > 1) {
                                            root.expand(button.workspaceInfo.workspace, app.windowClass);
                                            tap.focusWindow(addresses[0]);
                                            return true;
                                        }
                                        if (!app.icon.expanded)
                                            root.collapse();
                                        return false;
                                    }

                                    Accessible.role: Accessible.Button
                                    Accessible.name: label.text
                                    // Resting on an icon shows its window's title (ClickArea).
                                    Accessible.description: "Pointer: hover"
                                    Accessible.onPressAction: if (enabled && visible && !tap.pressApp())
                                        tap.focusWindow(app.icon.addresses[0])

                                    onPressed: mouse => {
                                        pressPoint = tap.mapToItem(strip, mouse.x, mouse.y);
                                        const addresses = app.icon.addresses;
                                        addressOnPress = addresses.length === 1 ? addresses[0] : "";
                                        suppressClick = tap.pressApp();
                                    }

                                    onPositionChanged: mouse => {
                                        if (!pressed || addressOnPress === "" || (suppressClick && !root.dragging))
                                            return;
                                        const point = tap.mapToItem(strip, mouse.x, mouse.y);
                                        if (!root.dragging && Math.hypot(point.x - pressPoint.x, point.y - pressPoint.y) >= drag.threshold) {
                                            suppressClick = true;
                                            root.dragSource = app;
                                            root.dragAddress = addressOnPress;
                                            root.dragWorkspace = button.workspaceInfo.workspace;
                                            root.dragWorkspaceId = button.workspaceInfo.id;
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

                                    onClicked: if (!suppressClick)
                                        tap.focusWindow(app.icon.addresses[0])
                                }
                            }
                        }
                    }
                }
            }

            // An empty workspace after the last, there only while a window is
            // dragged, so it can be dropped into a workspace of its own. It
            // draws nothing, the way an empty workspace does; the pill opens
            // to make room for it and the drop line marks it. Not offered
            // when the strip already has an empty one to drop on.
            Item {
                id: newWorkspace

                readonly property var modelData: null

                visible: root.dragging && root.shownWorkspaces
                    .every(w => Hyprland.toplevels.values.some(t => root.workspaceOf(t) === w.id))
                Layout.fillHeight: true
                implicitWidth: root.emptyWidth

                function slotX(cls: string, address: string): real {
                    return width / 2;
                }
            }
        }

        // Where the dragged window will land.
        DropLine {
            target: root.dropX
        }

        // The drag preview ends at release; workspace membership draws the moved icon.
        AppIcon {
            id: ghost
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
