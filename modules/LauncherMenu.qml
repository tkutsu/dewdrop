import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The launcher box: a query line over a list of matches, one lowercase name
// per row with its icon out at the right edge, and the selected row a rounded
// fill.
//
// The screen-sized surface under it, the keyboard grab and the click-to-exit
// are OverlayWindow's, which the power menu is drawn on too.
OverlayWindow {
    id: root

    name: "launcher"
    shown: Launcher.shown
    inputItem: box
    onDismissed: Launcher.hide()

    // Empty searches disclose history only after an explicit browse request.
    property bool frecencyOpen: false
    readonly property bool expanded: Launcher.query.length > 0 || root.frecencyOpen
    readonly property int compactHeight: root.boxPad * 2 + root.inputHeight
    property real elevation: root.expanded ? 1 : 0
    property real rowsReveal: 0
    property bool rowsReady: false
    readonly property int rowStaggerMs: 32
    readonly property int rowRevealMs: 100 + (root.visibleRows - 1) * root.rowStaggerMs

    Behavior on elevation {
        enabled: !Theme.reduceMotion
        NumberAnimation { duration: root.expanded ? 200 : 150; easing.type: Easing.OutCubic }
    }
    // Start explicitly: a launcher created with a mode has no binding change.
    function animateRows() {
        if (!root.rowsReady)
            return;
        rowEntrance.stop();
        if (Theme.reduceMotion) {
            root.rowsReveal = root.expanded ? 1 : 0;
            return;
        }
        rowEntrance.to = root.expanded ? 1 : 0;
        rowEntrance.duration = root.expanded ? root.rowRevealMs : 150;
        rowEntrance.start();
    }
    onExpandedChanged: root.animateRows()
    Component.onCompleted: {
        root.rowsReady = true;
        root.animateRows();
    }
    NumberAnimation {
        id: rowEntrance
        target: root
        property: "rowsReveal"
        easing.type: Easing.Linear
    }

    function browse() {
        root.frecencyOpen = true;
        input.forceActiveFocus();
    }

    function toggleList() {
        if (root.expanded) {
            root.frecencyOpen = false;
            input.adopt("");
        } else {
            root.browse();
        }
    }

    // Keep the action separate from the result so typing never loses focus.
    property string selectedAction: "activate"
    readonly property var rowActions: {
        const row = Launcher.selected;
        if (Launcher.mailMode)
            return [
                { key: "activate", label: "open in gmail", live: row?.kind === "mail" },
                { key: "mail-fold", label: Launcher.mailOpen ? "back to list" : "read", live: row?.kind === "mail" },
                { key: "play", label: "new mail", live: true }
            ];
        if (!row || row.kind === "note")
            return [];
        if (row.kind === "path")
            return [
                { key: "activate", label: "open", live: true },
                { key: "play", label: "show in folder", live: true },
                { key: "copy-path", label: "copy path", live: true },
                { key: "complete-path", label: "complete path", live: true }
            ];
        if (row.kind === "clip")
            return [
                { key: "activate", label: "copy", live: true },
                { key: "forget", label: "delete", live: true }
            ];
        if (row.kind === "music-start")
            return [{ key: "activate", label: "start music", live: true }];
        if (row.kind === "music-queue")
            return [];
        if (row.kind.startsWith("music-")) {
            const actions = [
                { key: "activate", label: "queue", live: true },
                { key: "play", label: "play", live: true }
            ];
            if (row.kind === "music-artist" || row.kind === "music-album")
                actions.push({ key: "music-fold", label: LauncherMusic.open[row.key] ? "collapse" : "expand", live: true });
            else if (row.indent)
                actions.push({ key: "music-fold", label: "collapse", live: true });
            return actions;
        }
        const labels = { calc: "copy answer", window: "focus", task: "complete", "task-add": "add task", "timer-add": "add timer", desktop: "run", power: row.action?.label, bluetooth: row.connect ? "connect" : "disconnect" };
        const label = row.kind === "timer" ? (row.entry.running ? "pause" : "resume") : labels[row.kind] ?? "open";
        return [{ key: "activate", label, live: row.ok !== false }];
    }
    readonly property int actionIndex: Math.max(0, root.rowActions.findIndex(action => action.key === root.selectedAction))

    // Home and End cycle through available actions without moving the caret.
    function moveAction(dir) {
        const count = root.rowActions.length;
        for (let step = 1; step <= count; step++) {
            const at = (root.actionIndex + dir * step + count) % count;
            if (root.rowActions[at].live) {
                root.selectedAction = root.rowActions[at].key;
                return;
            }
        }
    }

    // Buttons and Enter share the same dispatch; the older shortcuts still work.
    function runAction(at) {
        const action = root.rowActions[at];
        if (!action?.live)
            return;
        root.selectedAction = action.key;
        switch (action.key) {
        case "mail-fold":
            Launcher.mailFold();
            break;
        case "music-fold":
            LauncherMusic.fold();
            break;
        case "copy-path":
            Launcher.copyRow(Launcher.index);
            break;
        case "complete-path":
            root.completePath();
            break;
        case "forget":
            Launcher.forget(Launcher.index);
            break;
        default:
            Launcher.activate(Launcher.index, action.key === "play" ? "play" : "queue");
        }
        input.forceActiveFocus();
    }

    function completePath() {
        const row = Launcher.selected;
        if (row?.kind === "path")
            input.adopt(Launcher.tildeHome(row.path) + (row.dir ? "/" : ""));
    }

    function accept(ctrl) {
        if (!root.expanded && !input.text.trim())
            root.browse();
        else if (!ctrl && root.rowActions.length)
            root.runAction(root.actionIndex);
        else
            Launcher.activate(Launcher.index, ctrl ? "play" : "queue");
    }

    // The sides follow the sampled Spotlight width curve; contents never scale.
    property real widthRatio: 1012 / 960
    property real contentAlpha: 0
    property real exitBlur: 0
    readonly property real extraWidth: root.boxWidth * (root.widthRatio - 1)
    readonly property bool presenting: root.opened || root.contentAlpha > 0

    onOpenedChanged: {
        entrance.stop();
        dismissal.stop();
        if (Theme.reduceMotion) {
            root.widthRatio = 1;
            root.contentAlpha = root.opened ? 1 : 0;
            root.exitBlur = 0;
        } else if (root.opened) {
            entrance.start();
        } else {
            dismissal.start();
        }
    }

    ParallelAnimation {
        id: entrance
        SequentialAnimation {
            PauseAnimation { duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 976 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 955 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 948 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 950 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 954 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 958 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 1; duration: 33 }
            PauseAnimation { duration: 69 }
        }
        NumberAnimation { target: root; property: "contentAlpha"; to: 1; duration: 67 }
        NumberAnimation { target: root; property: "exitBlur"; to: 0; duration: 67 }
    }

    ParallelAnimation {
        id: dismissal
        NumberAnimation { target: root; property: "widthRatio"; to: 1.03; duration: Launcher.dismissMs; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "contentAlpha"; to: 0; duration: Launcher.dismissMs; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "exitBlur"; to: 1; duration: Launcher.dismissMs; easing.type: Easing.InCubic }
    }

    Connections {
        target: Launcher
        function onShownChanged() {
            if (Launcher.shown) {
                root.frecencyOpen = false;
                root.selectedAction = "activate";
                box.bodyHeight = Qt.binding(() => box.restHeight);
                list.model = Qt.binding(() => Launcher.results);
                input.adopt(Launcher.query);
                list.pointerLive = false;
            } else {
                // Launching re-ranks frecency, so keep the departing rows intact.
                box.bodyHeight = box.restHeight;
                list.model = Launcher.results.slice();
            }
        }
    }

    // --- geometry ------------------------------------------------------------
    // What Spotlight is: 680 of window body over a 28 row pitch, measured off
    // Apple's Big Sur screenshot (Alfred, Raycast and Sol are all 560–750).
    // Wide enough for the engine hint line, which wants 447. Everything below
    // is derived, so this is the only number to turn.
    readonly property int boxWidth: 680
    readonly property int rowHeight: 28
    // As deep as the list goes before it stops being a glance and starts
    // being a scroll. maxResults still ranks well past this,
    // so the rest is reachable by arrowing down.
    readonly property int visibleRows: 12
    readonly property bool unreadList: Launcher.shown && Launcher.mailMode && !Launcher.classification.text && !Launcher.mailOpen
    readonly property int boxPad: 12
    // The right-hand slot every row ends in: an app icon, or the "%y" badge
    // that says which engine Enter would use.
    readonly property int slotWidth: 24
    // How far a row is set in per level of the music mode's tree. Wide enough
    // to be read as a step rather than a misalignment, narrow enough that a
    // track two levels down still has most of the line for its title.
    readonly property int indentStep: 16
    // The query line, and the air above and below its rule.
    readonly property int inputHeight: Theme.queryTextSize + 12
    readonly property int contentGap: 8
    readonly property int actionHeight: 20
    // The preview panel / mode grows on the right, and the air between it and
    // the list. Roughly a third of the body, which is about what Spotlight
    // gives its own preview, set in the same 12 of air as everything else in
    // the box. See components/FilePreview.qml.
    readonly property int panelWidth: 220
    readonly property int panelGap: boxPad

    // Whether the box is showing one. Bound to the mode rather than to the
    // selected row having a picture in it: a panel that came and went as the
    // selection moved between a photograph and a text file would resize the
    // box under every arrow key. Music mode holds it open for exactly the same
    // reason — a playlist row has no sleeve, and the box must not shut by 232
    // pixels because you arrowed past one.
    readonly property bool previewing: Launcher.pathMode || Launcher.musicMode

    // The box at its tallest, with the list full. This places the box; it does
    // not size it. The top edge is pinned where a full box would have been
    // centred, so every shorter one keeps its query line on that same line.
    readonly property int fullHeight: boxPad * 2 + inputHeight + actionHeight + contentGap * 3 + Theme.pillBorder + visibleRows * rowHeight

    // +1 for the keys that go down, -1 for the ones that go up, 0 for the
    // rest. Readline's pair and vim's are in here, since both are muscle
    // memory somewhere on this machine — with Ctrl only, because bare they
    // are letters being typed.
    function stepOf(key, ctrl) {
        switch (key) {
        case Qt.Key_Down:
        case Qt.Key_Tab:
        case Qt.Key_PageDown:
            return 1;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
        case Qt.Key_PageUp:
            return -1;
        case Qt.Key_N:
        case Qt.Key_J:
            return ctrl ? 1 : 0;
        case Qt.Key_P:
        case Qt.Key_K:
            return ctrl ? -1 : 0;
        }
        return 0;
    }

    // Tab opens and shuts a mail in mail mode and moves the selection
    // elsewhere. Music trees toggle with Right at the end of the query.
    // Page keys page the file under the / list, in music mode step a level
    // of the tree, and elsewhere move the selection a screenful.
    function step(key, dir) {
        if (!root.expanded) {
            if (dir > 0)
                root.browse();
            return;
        }
        if (!Launcher.query.length && root.frecencyOpen && dir < 0 && Launcher.index === 0) {
            root.frecencyOpen = false;
            return;
        }
        const tab = key === Qt.Key_Tab || key === Qt.Key_Backtab;
        const page = key === Qt.Key_PageDown || key === Qt.Key_PageUp;
        // Reading a mail, every step is the reader's: Tab back to the list,
        // the arrows a row's height of text, the page keys a screenful.
        if (Launcher.mailOpen) {
            if (tab)
                Launcher.mailFold();
            else
                reader.scroll(dir * (page ? reader.height - root.rowHeight : root.rowHeight));
            return;
        }
        if (Launcher.mailMode && tab) {
            Launcher.mailFold();
            return;
        }
        if (Launcher.musicMode && page) {
            LauncherMusic.skip(dir);
            return;
        }
        // With no preview to page, the page keys move a screenful down the
        // list, stopping at either end rather than wrapping like the arrows.
        if (page && preview.item) {
            preview.item.scroll(dir);
            return;
        }
        const to = page ? Math.max(0, Math.min(Launcher.results.length - 1, Launcher.index + dir * root.visibleRows)) : Launcher.index + dir;
        if (dir > 0)
            root.loadUnreadMore(to);
        if (page)
            Launcher.index = to;
        else
            Launcher.move(dir);
    }

    // Fetch another screenful near the end of bare @, including a wheel
    // step when the initial rows fit the viewport and cannot scroll yet.
    function loadUnreadMore(lastVisible) {
        if (!root.unreadList || lastVisible < list.count - 3 || Email.loading || Email.morePending || Email.threads.length >= Email.total)
            return;
        Email.loadMore(Math.min(Email.total, Email.threads.length + root.visibleRows));
    }

    // A changed query resets selection without gliding through replaced rows.
    property bool settling: false

    // Keeping the selected row on screen, and scrolling no further than it
    // takes to get it there. Written out rather than left to the view: the
    // highlight below is placed rather than followed, and a view with nothing
    // to track lets the selection walk off the bottom edge. Never above the
    // top edge, never below the bottom one, otherwise wherever the list is.
    //
    function keepSelectionVisible() {
        const top = Launcher.index * root.rowHeight;
        const floor = top + root.rowHeight - list.height;
        const max = Math.max(0, list.contentHeight - list.height);
        const y = Math.max(0, Math.min(max, Math.max(floor, Math.min(top, list.contentY))));
        scrollTo.stop();
        if (y === list.contentY)
            return;
        if (root.settling || Theme.reduceMotion) {
            list.contentY = y;
            return;
        }
        scrollTo.to = y;
        scrollTo.start();
    }

    // On its own rather than a Behavior on contentY: that property is also
    // what a flick writes to, frame by frame, and an animation sitting on it
    // would be fighting the pointer for the list.
    NumberAnimation {
        id: scrollTo

        target: list
        property: "contentY"
        duration: Theme.selectMs
        easing.type: Easing.OutCubic
    }

    // How bright the screen is under where the box will be, preview panel and
    // all, for the frost (Theme.frostOver). The window is the screen, so its
    // pixels are the screen's. A window reused inside its own fold-away keeps
    // the reading it has, since it is over the same screen.
    BackdropProbe {
        id: under

        screen: root.screen
        area: Qt.rect(Math.round((root.width - root.boxWidth) / 2), Math.round((root.height - root.fullHeight) / 2), root.boxWidth + root.panelGap + root.panelWidth, root.fullHeight)
        active: true
    }

    // The box's shadow, as a sibling rather than a child: the box clips its
    // children to itself, and a shadow is everything outside the box.
    RectangularShadow {
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        visible: root.presenting && box.height > 0
        opacity: root.contentAlpha
        offset.y: 5 + 11 * root.elevation
        radius: box.radius
        blur: 20 + 28 * root.elevation
        color: Qt.rgba(0, 0, 0, 0.19)
    }

    RectangularShadow {
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        visible: root.presenting && box.height > 0
        opacity: root.contentAlpha
        offset.y: 3
        radius: box.radius
        blur: 9
        color: Qt.rgba(0, 0, 0, 0.14)
    }

    Rectangle {
        id: box

        // What the box would be if it were open and settled: exactly its
        // contents. Instant, so it is a measurement rather than a motion.
        //
        // With a panel open there is a floor under that: a two-row list would
        // otherwise leave the preview a 220x30 slot to put a photograph in,
        // and a square is the least a picture can be shown in and still be
        // one.
        readonly property int restHeight: root.expanded ? Math.max(content.implicitHeight, root.previewing ? root.panelWidth : 0) + root.boxPad * 2 : root.compactHeight

        // And what it is actually drawn at, trailing that measurement: the list
        // gaining a row pushes the bottom edge down to it rather than landing
        // there, so the box reads as a drawer the results are filling. It is a
        // independent of the width spring, so typing only moves the lower edge.
        property real bodyHeight: box.restHeight

        Behavior on bodyHeight {
            enabled: !Theme.reduceMotion
            NumberAnimation {
                duration: root.expanded ? 200 : 150
                easing.type: Easing.OutCubic
            }
        }

        // Query height and baseline stay fixed while both sides move about center.
        y: Math.round((root.height - root.fullHeight) / 2)
        // Preview modes still extend rightward from the settled query position.
        property real bodyWidth: root.boxWidth + (root.previewing ? root.panelGap + root.panelWidth : 0)

        Behavior on bodyWidth {
            enabled: !Theme.reduceMotion
            NumberAnimation {
                duration: Theme.revealMs
                easing.type: Easing.OutCubic
            }
        }

        x: Math.round((root.width - root.boxWidth - root.extraWidth) / 2)
        width: Math.round(box.bodyWidth + root.extraWidth)
        height: Math.round(box.bodyHeight)
        visible: root.presenting
        clip: true
        // The popups' frost, at an alpha held over the 0.3 that keeps the
        // compositor blurring behind it, and thickened over a bright screen.
        // Ease in a new backdrop reading without fading below the blur floor.
        color: Theme.frostOver(under.luma)

        Behavior on color {
            ColorAnimation {
                duration: Theme.revealMs
            }
        }
        radius: Theme.popupRadius

        // Its edge, above everything drawn inside it so that no row's fill
        // can paint over it.
        Rim {
            anchors.fill: parent
            radius: box.radius
            z: 10
        }

        // Defocus the departing glass, then fade only in the final frames so
        // the compositor's blur cutoff does not interrupt most of the exit.
        layer.enabled: root.exitBlur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 16
            blur: root.exitBlur
            autoPaddingEnabled: false
            opacity: 1 - Math.max(0, (root.exitBlur - 0.4) / 0.6)
        }

        // The box is not "off the launcher": clicking its padding should do
        // nothing, not dismiss. Only the screen around it closes.
        MouseArea {
            anchors.fill: parent
        }

        // Text follows the left edge at its native size; glass alpha keeps blur.
        Column {
            id: content

            x: root.boxPad
            y: root.boxPad
            // The list's width rather than the box's, which are no longer the
            // same thing: what the box grew for the panel is not the list's
            // to lay out in.
            width: Math.round(root.boxWidth + root.extraWidth) - root.boxPad * 2
            opacity: root.contentAlpha
            spacing: root.contentGap

            // Keep scrolling text clipped to the area beside the fixed icon.
            Item {
                width: parent.width
                height: root.inputHeight

                RollingGlyph {
                    id: searchIcon
                    x: 2
                    y: 1
                    height: root.inputHeight
                    width: 20
                    text: Launcher.queryIcon
                    animate: Launcher.shown
                    fontSize: 20
                    color: Theme.label2
                }

                TextInput {
                    id: input
                    Accessible.name: "Launcher query"

                    x: 30
                    width: parent.width - x
                    height: root.inputHeight
                    color: Theme.fg
                    selectionColor: Theme.textSelection
                    selectedTextColor: Theme.fg
                    cursorDelegate: TextCaret { textInput: input }
                    selectByMouse: true
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.queryTextSize
                    font.weight: Theme.bodyWeight
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    // Fade off-screen text, stopping before the active caret.
                    readonly property real leftFade: input.edgeFade(true)
                    readonly property real rightFade: input.edgeFade(false)
                    function edgeFade(left) {
                        if (input.cursorPosition < 0 || input.contentWidth <= input.width - input.leftPadding - input.rightPadding)
                            return 0;
                        const caret = input.cursorRectangle;
                        const boundary = input.positionToRectangle(left ? 0 : input.length).x;
                        const hidden = left ? boundary < input.leftPadding - 0.5 : boundary > input.width - input.rightPadding + 0.5;
                        return hidden ? Math.min(16, Math.max(0, left ? caret.x - 2 : input.width - caret.x - caret.width - 2)) : 0;
                    }
                    layer.enabled: input.leftFade > 0 || input.rightFade > 0
                    layer.effect: ShaderEffect {
                        readonly property real span: width
                        readonly property real fadeLeft: input.leftFade
                        readonly property real fadeRight: input.rightFade
                        fragmentShader: Qt.resolvedUrl("../shaders/query-edge.frag.qsb")
                    }

                    Text {
                        id: placeholder
                        x: input.leftPadding + 1
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text.length === 0
                        text: "Search"
                        color: Theme.label2
                        font: input.font
                    }

                    // What the mode prefixes do, inside the field and
                    // against its right edge, in the quietest step of the label
                    // scale. It stays while the mode it describes does (see
                    // Launcher.hint), in the room the query is not using, and
                    // gives way as the query reaches it — it is a reference, and
                    // never the thing being read.
                    Item {
                        id: hint

                        readonly property string text: Launcher.prefixHint
                        readonly property int clearance: 24
                        readonly property real room: input.width - (placeholder.visible ? placeholder.implicitWidth : input.contentWidth) - input.leftPadding - hint.clearance

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: modeHints.implicitWidth
                        width: Math.min(hint.implicitWidth, hint.room)
                        height: root.inputHeight
                        clip: true
                        // Gone rather than squeezed to a few letters and an
                        // ellipsis: past a certain point a hint is only noise.
                        visible: Launcher.query.length === 0 && hint.text !== "" && hint.room >= hint.implicitWidth

                        Row {
                            id: modeHints
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Repeater {
                                model: Launcher.modes
                                Row {
                                    required property var modelData
                                    spacing: 2
                                    height: root.inputHeight
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.prefix
                                        color: Theme.label3
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.popupTextSize
                                        font.bold: true
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.hint
                                        color: Theme.label3
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.captionSize
                                    }
                                }
                            }
                        }


                    }

                    focus: true

                    // Every way the query arrives from outside the field: the box
                    // being built, a reopen inside the fold-away reusing it (the
                    // root's onShownChanged), and a mode switched on a box that is
                    // already open.
                    function adopt(text) {
                        input.text = text;
                        input.cursorPosition = input.text.length;
                        input.forceActiveFocus();
                    }

                    // Adopts whatever mode the box was opened in. Normally that is
                    // nothing at all; Launcher.openWith puts a prefix there before
                    // the window exists, and this is what makes the field show it
                    // rather than looking empty while the list underneath is
                    // already in that mode.
                    Component.onCompleted: input.adopt(Launcher.query)

                    // Switching modes on a box that is already open — the bar's
                    // popups do this, and so does the second of the two keybinds
                    // while the first one's box is up.
                    Connections {
                        target: Launcher

                        function onQueryReplaced(text) {
                            input.adopt(text);
                        }
                    }

                    onTextChanged: {
                        root.selectedAction = "activate";
                        root.settling = true;
                        Launcher.query = input.text;
                        root.settling = false;
                    }

                    // Keys handlers run before TextInput's own, so the navigation
                    // keys are ours and everything else still types.
                    Keys.onPressed: function (event) {
                        // Use the platform's editing shortcuts before launcher navigation.
                        // With nothing selected in the line, copy the file's path.
                        if (event.matches(StandardKey.Copy)) {
                            if (input.selectedText)
                                input.copy();
                            else
                                Launcher.copyRow(Launcher.index);
                            event.accepted = true;
                            return;
                        }
                        if (event.matches(StandardKey.Paste)) {
                            input.paste();
                            event.accepted = true;
                            return;
                        }
                        if (event.matches(StandardKey.Cut)) {
                            input.cut();
                            event.accepted = true;
                            return;
                        }
                        if (event.matches(StandardKey.SelectAll)) {
                            input.selectAll();
                            event.accepted = true;
                            return;
                        }
                        const ctrl = event.modifiers & Qt.ControlModifier;

                        switch (event.key) {
                        case Qt.Key_Escape:
                            if (input.text.length)
                                input.adopt("");
                            else if (root.frecencyOpen)
                                root.frecencyOpen = false;
                            else
                                Launcher.hide();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.accept(ctrl);
                            break;
                        case Qt.Key_Home:
                        case Qt.Key_End:
                            if (event.modifiers !== Qt.NoModifier || !root.rowActions.length)
                                return;
                            root.moveAction(event.key === Qt.Key_Home ? -1 : 1);
                            break;
                        // Drop the row rather than act on it. Only the clipboard
                        // has anything to drop; elsewhere this does nothing, and
                        // plain Delete still edits the query.
                        case Qt.Key_Delete:
                            if (!ctrl)
                                return;
                            Launcher.forget(Launcher.index);
                            break;
                        // Right at the end toggles the selected music tree.
                        // In file mode it completes the line to the
                        // selected file, the way a shell's Tab does. Written with
                        // its "~", so the query stays in the files mode, and a
                        // directory ends in "/" ready for the next name. Anywhere
                        // short of the end it is the cursor's, as ever.
                        case Qt.Key_Right:
                            if (input.cursorPosition < input.text.length)
                                return;
                            if (Launcher.musicMode) {
                                LauncherMusic.fold();
                                break;
                            }
                            const row = Launcher.selected;
                            if (!Launcher.pathMode || row?.kind !== "path")
                                return;
                            root.completePath();
                            break;
                        default:
                            // Everything else this takes is a step one way or the
                            // other, and each key's mirror does the same in the
                            // other direction — so the direction is read once and
                            // the pair is handled as one. Anything that is not a
                            // step is the TextInput's.
                            const dir = root.stepOf(event.key, ctrl);
                            if (!dir)
                                return;
                            root.step(event.key, dir);
                        }
                        event.accepted = true;
                    }
                }
            }

            Item {
                id: actionBar
                width: parent.width
                height: root.actionHeight
                visible: root.expanded && root.rowActions.length > 0

                Row {
                    id: actionButtons
                    spacing: 6

                    Repeater {
                        model: root.rowActions

                        PopupButton {
                            required property var modelData
                            required property int index
                            label: modelData.label
                            live: modelData.live
                            framed: true
                            chosen: root.actionIndex === index
                            onTapped: root.runAction(index)
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.rowActions.filter(action => action.live).length > 1
                    text: "Home / End"
                    color: Theme.label3
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.footnoteSize
                }
            }

            // The rule under the query, and only while there is a list under
            // it to rule off. An empty box — nothing typed yet, or a query
            // nothing matched — would otherwise end in a line drawn across
            // nothing. A Column gives an invisible child neither height nor
            // spacing, so this takes the gap it was sitting in with it.
            Rectangle {
                id: divider
                // Out past the padding to both edges of the box: a rule is a
                // line drawn across something, and one that stops short of the
                // sides reads as another item in the column rather than as the
                // division between the query and the answers. A Column sets
                // its children's y and leaves their x alone, which is what
                // makes this possible from inside one.
                x: -root.boxPad
                width: parent.width + root.boxPad * 2
                height: Theme.pillBorder
                visible: list.count > 0
                // Keep its layout slot while folding, without painting in compact mode.
                opacity: root.expanded ? 1 : 0
                color: Theme.stroke
            }

            ListView {
                id: list

                // In the accessibility tree as a list to scroll, half a view a step.

                Accessible.role: Accessible.List

                Accessible.name: "Results"
                Accessible.ignored: !root.expanded
                enabled: root.expanded

                Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)

                Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

                // Out to both edges of the box, less the hairline of border
                // on the right. The white rule down the selected row is the
                // row's own left edge and sits on the box's; the far end has
                // nothing to say and simply runs to the outline — up to it,
                // not over it, or the selected row would be the one row with
                // no right-hand edge to it. The rows put the padding back for
                // their own contents.
                x: -root.boxPad
                width: parent.width + root.boxPad * 2 - Theme.pillBorder
                // Short lists draw short, rather than leaving the box padded
                // out with empty rows the way a fixed height would.
                height: Math.min(count, root.visibleRows) * root.rowHeight
                readonly property real selectedY: (list.highlightItem?.y ?? Launcher.index * root.rowHeight) - list.contentY
                readonly property real topFadeReach: selectedY < Theme.scrollEdge && selectedY + root.rowHeight > 0 ? 0 : Theme.scrollEdge
                readonly property real bottomFadeReach: selectedY + root.rowHeight > height - Theme.scrollEdge && selectedY < height ? 0 : Theme.scrollEdge
                clip: true
                layer.enabled: contentHeight > height
                layer.effect: ScrollEdges {
                    id: listEdges
                    view: list
                    // Keep the selected row solid at either viewport edge.
                    topReach: list.topFadeReach
                    bottomReach: list.bottomFadeReach
                }
                model: Launcher.results

                // Where the pointer was when it last actually moved, in scene
                // coordinates, and whether it has moved at all since the box
                // opened. Both belong to the list rather than to a row: rows
                // are delegates and the one holding this would be recycled.
                property point pointer: Qt.point(-1, -1)
                property bool pointerLive: false

                // The selection lives on the service, so the keyboard and the
                // pointer are both moving the same thing.
                //
                // Told rather than only bound. The model is a plain array and
                // is replaced wholesale on every keystroke, and a ListView
                // resets its own currentIndex when that happens — which goes
                // unseen almost always, because the keystroke that rebuilt the
                // list also moved the selection and the binding put it
                // straight back. There is one case where the list changes and
                // the selection does not: opening the rest of an artist's
                // records. There the grey fill was left on the artist while
                // the selected row, its colour and the sleeve panel had all
                // moved five rows down to the first record revealed.
                //
                // So both events re-tell it, and neither a selection that
                // moves nor a list that changes under a still one can leave
                // the view and the service disagreeing.
                currentIndex: Launcher.index

                Connections {
                    target: Launcher

                    function onIndexChanged() {
                        list.currentIndex = Launcher.index;
                        root.keepSelectionVisible();
                    }
                }

                // Where the list was scrolled to before the last rebuild.
                // Replacing a plain-array model empties the view first and
                // the scroll goes with the rows, so this is recorded only
                // while there are rows: the drop to nothing is not a
                // position anyone chose.
                property real keptY: 0
                property int keptCount: 0

                onContentYChanged: {
                    if (list.count > 0)
                        list.keptY = list.contentY;
                    if (list.contentY > 0)
                        root.loadUnreadMore(Math.ceil((list.contentY + list.height) / root.rowHeight));
                }

                // Every rebuild, whether a keystroke or the list changing
                // under a selection that did not move — a timer removed, an
                // answer landing, a record expanded. Without this the
                // list came back at the top however far down it had been,
                // and the highlight flew back down to a row it had never
                // left. The scroll is put back where it was and the selected
                // row is then brought in only as far as it has to come, which
                // when toggling a tree is nowhere: opening only adds rows below the
                // selection and shutting in place only takes them away.
                //
                // forceLayout first, or the rows are made on the next polish
                // and contentHeight, which the scroll is clamped against, is
                // still the old list's. Not while the box is leaving: the
                // exit swaps in a frozen copy of the rows, and that is not a
                // list to scroll.
                onModelChanged: {
                    if (!Launcher.shown)
                        return;
                    list.currentIndex = Launcher.index;
                    list.forceLayout();
                    const grew = list.count > list.keptCount;
                    list.keptCount = list.count;
                    list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), list.keptY));
                    // New unread rows retain the viewport even when wheel
                    // scrolling left the selected row above it.
                    if (!root.unreadList || !grew)
                        root.keepSelectionVisible();
                }

                // The selection belongs to the view, not to the row. A row
                // can only be selected or not, so a fill drawn by the delegate
                // can only appear and disappear — while one the view owns is a
                // single object that slides from row to row instead of
                // blinking between them.
                //
                // Placed from the service's index rather than followed to the
                // view's own current item. A plain array replaced wholesale
                // puts the highlight back at the top of the content before
                // the selection is restored underneath it, and the way back
                // is animated — so every tree toggle in music mode had the grey bar
                // set off from the first row of the library and fly down the
                // whole list to the row it had never actually left. contentY
                // is reset by the same rebuild and put back in onModelChanged
                // above; this is the other half of that.
                //
                // Every row is the same height, so there is nothing to size
                // to either — which is just as well, because a resize
                // animation on a list that reflows under every keystroke
                // would be a shape changing for no reason.
                highlightFollowsCurrentItem: false
                // The selected row, as the system draws it: a rounded fill
                // held in from the box's edges rather than running out to
                // them, and nothing else marking it.
                highlight: Rectangle {
                    x: Theme.selectionInset
                    width: list.width - Theme.selectionInset * 2
                    height: root.rowHeight
                    y: Launcher.index * root.rowHeight
                    visible: list.count > 0
                    radius: Theme.selectionRadius
                    color: Theme.selection

                    // Glide for navigation, but reset immediately while typing.
                    Behavior on y {
                        enabled: !root.settling && !Theme.reduceMotion

                        NumberAnimation {
                            duration: 80
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                // Nothing here scrolls with momentum; a flick that overshoots
                // the ends just looks like the list came loose.
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool current: Launcher.index === row.index
                    readonly property real enterProgress: Theme.reduceMotion ? 1 : Math.max(0, Math.min(1, (root.rowsReveal * root.rowRevealMs - Math.min(row.index, root.visibleRows - 1) * root.rowStaggerMs) / 100))

                    width: ListView.view.width
                    height: root.rowHeight
                    // The fill is the view's `highlight` above; all that marks
                    // the selected row here is the colour of its text.
                    color: "transparent"
                    opacity: row.enterProgress
                    transform: Translate { y: 6 * (1 - row.enterProgress) }

                    Text {
                        id: title

                        anchors {
                            left: parent.left
                            // The box's padding and the row's own, because the
                            // row itself no longer has any: a title still
                            // starts where it always did — and then however
                            // deep in the music mode's tree this row sits,
                            // which is nothing at all in every other mode.
                            leftMargin: root.boxPad + Theme.pillPad + (row.modelData.indent ?? 0) * root.indentStep
                            verticalCenter: parent.verticalCenter
                        }
                        // Never more than half the row, so a long name cannot
                        // squeeze the subtitle out entirely — the subtitle is
                        // the only thing separating two files both called
                        // config.json. A row with no subtitle has nothing to
                        // protect and gets the line, which is what a clipboard
                        // entry needs.
                        // Half the row is the right reserve when the subtitle
                        // is a path and both halves are competing for it. A row
                        // whose subtitle is a short, fixed thing — a date, a
                        // word — can say so and take the rest, which is what a
                        // task written as a sentence to yourself needs.
                        width: Math.min(implicitWidth, row.width * (row.modelData.titleShare ?? (row.modelData.subtitle ? 0.55 : 0.88)))
                        // An app name is the launcher's to style, so it is
                        // lowercased. A calculated answer, a
                        // command and a copied line are not — they are text
                        // that came from somewhere else and has to come back
                        // out the way it went in.
                        // A timer's title counts down, so it is read live
                        // here rather than carried in the row: a row that
                        // changed every second would rebuild the list every
                        // second. See Launcher.timerResults.
                        text: {
                            const d = row.modelData;
                            const t = d.kind === "timer" ? Timers.describe(d.entry) : d.title;
                            return d.raw ? t : t.toLowerCase();
                        }
                        color: row.current ? Theme.menuSelectionText : Theme.menuText
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.labelSize
                        font.weight: Theme.bodyWeight
                        elide: Text.ElideRight

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.fadeMs
                            }
                        }
                    }

                    // Where the row came from, on the same line rather than
                    // under the title: app rows have nothing to put here, and a
                    // second line would make every row taller for the sake of
                    // the two modes that do.
                    //
                    // Elided from the left and pushed right, because the end of
                    // a path is the part that identifies it — ".../hypr/configs"
                    // says more than "/home/kutsui/.config/...".
                    Text {
                        anchors {
                            left: title.right
                            leftMargin: 8
                            right: slot.left
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        visible: text !== ""
                        text: row.modelData.subtitle ?? ""
                        color: Theme.menuText
                        // Under the title even on the row you are on: it is
                        // context, not the thing you picked. Further under it
                        // on a row the history has never seen — see `dim` in
                        // services/Launcher.qml.
                        opacity: row.modelData.dim ? 0.4 : 0.6
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.captionSize
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }

                    Item {
                        id: slot

                        anchors {
                            right: parent.right
                            // What the row took off the right, less the
                            // border it stops short of: an icon sits the same
                            // distance from the edge of the box as a title
                            // does from the other one.
                            rightMargin: root.boxPad + Theme.pillPad - Theme.pillBorder
                            verticalCenter: parent.verticalCenter
                        }
                        width: root.slotWidth
                        height: root.slotWidth
                        // Let the queue control take its click before the result row.
                        z: 1

                        // Same treatment as a taskbar icon (AppIcon.qml): ask
                        // for the name, and fall back to a glyph if nothing
                        // answers. A .desktop file can name an icon no theme on
                        // the machine carries, and a fallback passed to
                        // iconPath is only another name that can miss in turn —
                        // when it does, the row is left with a hole in it.
                        //
                        // themis answers every name the current menu asks for.
                        // This is the net for the one that eventually does not.
                        IconImage {
                            id: icon

                            anchors.centerIn: parent
                            implicitSize: Theme.iconSize
                            source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            // Only Ready counts: a name that resolves to nothing
                            // leaves the image blank rather than erroring, which
                            // would hide the fallback.
                            // Keyed on having an icon name rather than on the
                            // row's kind, so app rows and path rows both land
                            // here without the slot having to know which.
                            visible: !!row.modelData.icon && status === Image.Ready
                        }

                        // Two jobs, because they draw the same thing. A row
                        // can name a glyph outright — the power commands, a
                        // detected domain, a clipboard entry, none of which
                        // has an icon in any theme — and a row that named an
                        // icon nothing answered to falls back to one.
                        Glyph {
                            anchors.centerIn: parent
                            visible: !!row.modelData.glyph || (!!row.modelData.icon && !icon.visible)
                            text: row.modelData.glyph ?? Theme.glyph.window
                            fontSize: Theme.iconSize
                            implicitHeight: Theme.iconSize
                        }

                        // Engine rows have no icon; the key you would be using
                        // goes here instead, so "%" then "y" shows you
                        // landing on YouTube as you type it.
                        Text {
                            anchors.centerIn: parent
                            visible: !!row.modelData.badge
                            text: row.modelData.badge ?? ""
                            color: Theme.fg
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.captionSize
                            font.weight: Font.Bold
                        }

                        ClickArea {
                            id: queueControl
                            anchors.fill: parent
                            visible: row.modelData.kind === "music-queue" && !!row.modelData.glyph
                            enabled: Mpd.connected
                            cursorShape: Qt.PointingHandCursor
                            name: (row.modelData.glyph === Theme.glyph.paused ? "Pause " : "Play ") + row.modelData.title
                            actions: ({ [Qt.LeftButton]: () => Launcher.activate(row.index) })
                        }
                    }

                    // Hover selects: the pointer moves the selection
                    // rather than acting on its own. Emphatically only when it
                    // moves.
                    //
                    // positionChanged also fires when the list moves under a
                    // pointer that is sitting still — a different delegate
                    // arrives beneath the cursor and Qt hands it a move event.
                    // The keyboard then loses every reorder to wherever the
                    // mouse happens to be parked: typing ".au" reset the
                    // selection to 0 and this put it straight back on row 5,
                    // so Enter opened ChatGPT instead of the AUR. The box
                    // opening under the pointer did the same thing.
                    //
                    // So: compare against the last position the pointer was
                    // really at. Scene coordinates, not the row's own, because
                    // the row is the thing that moved. And nothing counts
                    // until the pointer has moved once since the box opened,
                    // or opening under a stationary cursor would still steal
                    // row 0.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        Accessible.role: Accessible.Button
                        Accessible.name: row.modelData.title || row.modelData.subtitle || "Launcher result"
                        Accessible.ignored: row.modelData.kind === "note"
                        Accessible.onPressAction: if (enabled && visible)
                            Launcher.activate(row.index)

                        onPositionChanged: function (mouse) {
                            const p = mapToItem(null, mouse.x, mouse.y);
                            if (!list.pointerLive) {
                                list.pointer = p;
                                list.pointerLive = true;
                                return;
                            }
                            if (Math.abs(p.x - list.pointer.x) < 1 && Math.abs(p.y - list.pointer.y) < 1)
                                return;
                            list.pointer = p;
                            Launcher.selectAt(row.index);
                        }

                        onClicked: Launcher.activate(row.index)

                        onWheel: function (wheel) {
                            if (wheel.angleDelta.y < 0 || wheel.pixelDelta.y < 0)
                                root.loadUnreadMore(Math.ceil((list.contentY + list.height) / root.rowHeight));
                            wheel.accepted = false;
                        }
                    }
                }
            }

            // The mail Tab opened, under its own row: the text in one piece,
            // wrapped to the box and scrolled by the keys that otherwise move
            // the selection. As tall as the text, and at most what the rest of
            // a full list would have been, so reading never grows the box past
            // its usual size. Only while one is open (see Launcher.mailOpen).
            Flickable {
                id: reader
                // In the accessibility tree as a list to scroll, half a view a step.
                Accessible.role: Accessible.List
                Accessible.name: "Mail reader"
                Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
                Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

                function scroll(by) {
                    reader.contentY = Math.max(0, Math.min(reader.contentHeight - reader.height, reader.contentY + by));
                }

                visible: Launcher.mailOpen !== null
                width: parent.width
                height: Math.min(reader.contentHeight, (root.visibleRows - 1) * root.rowHeight - root.contentGap)
                contentHeight: body.implicitHeight + root.contentGap
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                layer.enabled: contentHeight > height
                layer.effect: ScrollEdges {
                    view: reader
                }

                Text {
                    id: body

                    // Set in where a row's title is, so the text starts under
                    // the subject rather than out at the box's edge.
                    x: Theme.pillPad
                    width: reader.width - Theme.pillPad * 2
                    text: Launcher.mailText || "reading…"
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    lineHeight: 1.25
                    color: Theme.menuText
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.labelSize
                    // A new mail starts at its top.
                    onTextChanged: reader.contentY = 0
                }
            }
        }

        // The panel slot, out in the width the box grew for it. One place for
        // the two panels rather than the same geometry written on each: the
        // two modes that grow one never do it at the same time.
        //
        // It shares the query's fixed baseline and content fade.
        Item {
            x: Math.round(root.boxWidth + root.extraWidth) - root.boxPad + root.panelGap
            opacity: root.contentAlpha
            y: content.y
            width: root.panelWidth
            height: Math.round(box.bodyHeight) - root.boxPad * 2

            // Built only in / mode, and kept past it for as long as the box
            // is still wider than the list: it is left where it is and the
            // box's own clip takes it away, so leaving / mode closes over the
            // panel at the speed the box closes rather than blinking it out
            // first.
            Loader {
                id: preview

                anchors.fill: parent
                active: Launcher.pathMode || (!Launcher.musicMode && box.bodyWidth > root.boxWidth)

                sourceComponent: FilePreview {
                    // Files only. A directory has no picture in it, and its
                    // row is a place to go rather than a thing to look at.
                    path: Launcher.pathMode && Launcher.selected && Launcher.selected.kind === "path" && !Launcher.selected.dir ? Launcher.selected.path : ""
                }
            }

            // The other panel. Its own component rather than a mode inside
            // FilePreview, which shells out to a thumbnailer because a path
            // can be any kind of file at all — where this is always a picture
            // already sitting in the folder with the music.
            //
            // Built only in # mode. It has always blinked out on leaving it
            // rather than being clipped away, so there is no fold-away to
            // keep it for.
            Loader {
                anchors.fill: parent
                active: Launcher.musicMode

                sourceComponent: CoverArt {
                    dir: LauncherMusic.coverDir
                    // The row's own two lines, which the panel has the width
                    // to wrap and the row does not.
                    title: Launcher.selected ? Launcher.selected.title : ""
                    subtitle: Launcher.selected ? (Launcher.selected.subtitle ?? "") : ""
                    glyph: Launcher.selected ? (Launcher.selected.glyph ?? "") : ""
                }
            }
        }
    }
}
