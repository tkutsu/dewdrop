import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs

// One of the bar's three islands: a row of modules on its own rounded slab.
// The bar draws nothing itself, so this is what the wallpaper is read against
// and what the compositor blurs behind.
//
// A pill is bigger than the slab it draws. It claims the margin around it —
// above, below, and out to the screen edge on the side it backs onto — and
// hands that margin to the modules at its ends as padding, which is what makes
// the corner of the screen a click on the first workspace again. Nothing is
// laid out against the slab, only centred in the pill, so claiming the margin
// moves nothing.
Item {
    id: root

    enum Side {
        Left,
        Centre,
        Right
    }

    default property alias content: row.data
    readonly property alias moduleHost: row
    // The glass alone, for the workspace mark to bend (GlassMark).
    readonly property Item slabItem: slab

    // Ordered pills keep unkeyed controls at their ends.
    property var order: []
    property var leadingOrder: []
    property var orderController: RightPillOrder
    property Item reorderPeer: null
    property var transferableKeys: []
    property var lockedKeys: []
    signal moduleReceived(string key)
    readonly property var modules: row.children.filter(item => item.settingsKey)
    property alias dragging: reorder.dragging
    readonly property bool reorderPressed: reorder.pressSource !== null
    readonly property bool animating: dragging || centreMove.running || row.children.some(item => item.animating === true)
    onAnimatingChanged: Tooltips.setMoving(root, animating)
    Component.onDestruction: Tooltips.setMoving(root, false)
    property alias dragSource: reorder.dragSource
    readonly property bool dropMoves: reorder.dropMoves

    function arrange(): void {
        if (order.length === 0)
            return;
        const leading = row.children.filter(item => !item.settingsKey && (item.leadingControl || item === row.children[0]));
        leading.sort((a, b) => {
            const first = leadingOrder.indexOf(a);
            const second = leadingOrder.indexOf(b);
            return (first < 0 ? leadingOrder.length : first) - (second < 0 ? leadingOrder.length : second);
        });
        for (let i = 0; i < row.children.length; i++) {
            const item = row.children[i];
            const index = order.indexOf(item.settingsKey);
            item.Layout.row = 0;
            item.Layout.column = index >= 0 ? leading.length + index
                : leading.includes(item) ? leading.indexOf(item) : leading.length + order.length + i;
        }
    }

    onOrderChanged: arrange()
    onLeadingOrderChanged: arrange()
    Component.onCompleted: {
        arrange();
        Tooltips.setMoving(root, animating);
    }

    // Where on the bar this pill sits. It anchors itself from this rather than
    // being placed by the bar, so the one thing that decides whether the pill
    // backs onto a screen edge is also the thing that puts it there — the two
    // cannot drift apart.
    property int side: Pill.Side.Centre

    property int moduleGap: Theme.gap + (side === Pill.Side.Right ? 3 : 0)

    // How far short of its side the pill stops. Zero for the three that back
    // onto a screen edge or the centre line; the ones either side of the clock
    // float clear of their edge, which is also what stops them claiming a
    // margin they no longer reach — the edge is another pill's, and so is the
    // hit area out to it.
    // Fractional while the pill it is measured off is folding, so the two move
    // together rather than this one trailing by a pixel at a time.
    property real edgeOffset: 0

    // How far through whatever the pill is carrying, 0..1, or -1 for the pills
    // that are carrying nothing that runs — which is all of them but one.
    property real progress: -1

    // How much of that outline is showing, 0..1, for a pill that goes away:
    // the line is the brightest thing on it, and one that slid under the
    // clock at full strength read as the last of the pill to leave.
    property real trackOpacity: 1

    // The colour of that line: white, or whatever colour the thing it
    // measures has of its own (the music pill's sleeve).
    property color trackColor: Theme.fg

    // Keep the path and its faint remainder aligned as the line thickens.
    property real trackWidth: Theme.pillTrack
    property Item trackSlab: slab

    // Whether the pill draws its own slab. Not for the ones around the clock,
    // whose glass is drawn for all of them at once by the bar (Liquid.qml) so
    // that they can flow into each other; those keep only their contents, and
    // fade them by `contentOpacity` as the glass under them runs away.
    property bool drawsSlab: true
    property real contentOpacity: 1
    property real contentScale: 1
    property real contentZoom: 1
    property real contentBlur: 0
    property real contentShiftX: 0
    property real contentSink: 0
    property bool interactive: true
    enabled: interactive && contentOpacity > 0.01

    // How far the glass runs on past the pill's inner end, in pixels: the
    // right pill's drawer springing past its own width as it opens, or past
    // shut as it closes, which is below zero (BarItem.overrun).
    //
    // The modules go with it, each by its share of the way from the far end:
    // the one at the inner end rides the glass's end, and the gaps behind it
    // open out evenly as the glass runs past and close up as it is squeezed
    // in, then settle back. Drawn only (BarItem.shift): the layout keeps its
    // places, so nothing rounds to a pixel or reflows while it happens.
    property real stretch: 0

    onStretchChanged: {
        const shown = root.shown;
        if (shown.length === 0)
            return;
        const left = root.side === Pill.Side.Left;
        const dir = left ? 1 : -1;
        const from = item => left ? item.x : row.width - item.x - item.width;
        const span = from(left ? shown[shown.length - 1] : shown[0]);
        for (const item of row.children)
            if ("shift" in item)
                item.shift = item.visible && span > 0 ? dir * stretch * from(item) / span : 0;
    }

    property real rate: 0
    property bool trackReady: true
    property alias trackReveal: track.trackReveal
    readonly property real trackRadius: track.trackRadius
    readonly property real trackLength: track.trackLength
    readonly property real lit: track.lit

    // Whether a pill at offset zero is against the screen edge. Not for one
    // placed beside the clock (see Bar.qml): those are never against an
    // edge, and when they used to slide under the clock their offset passed
    // through zero on the way, and claiming the margin for that one frame put
    // its width into its offset and its offset into its width — a loop that
    // held the bar for half a second at every arrival.
    property bool edges: true
    readonly property bool atLeftEdge: edges && side === Pill.Side.Left && edgeOffset === 0
    readonly property bool atRightEdge: edges && side === Pill.Side.Right && edgeOffset === 0

    // Something inside the pill to put on the centre line instead of the pill
    // itself. A centred pill whose contents change width slides half that width
    // every time they do; naming the one part of it that never changes width
    // pins that part and lets the rest grow either side of it.
    property Item centreOn: null

    // Where that thing is, in the pill's own coordinates. Walked up the parent
    // chain rather than handed to mapToItem, which is a function call and so
    // would leave the binding with nothing to re-run on: every step here reads
    // an x off an item, and those are what the layout moves.
    readonly property real centreOnX: {
        if (!centreOn)
            return 0;
        let x = centreOn.width / 2;
        for (let item = centreOn; item && item !== root; item = item.parent)
            x += item.x;
        return x;
    }

    // A point in this pill, including a gap with no item of its own.
    property real centreAt: centreOn ? centreOnX : width / 2
    // A merge displaces the contents immediately; the same centring motion
    // that compensates for a leading media slot brings the whole pill back.
    property real centreShift: 0
    property bool animatePosition: false
    property bool _positionReady: false
    // Window sizing and service replies settle before ordinary position changes animate.
    Timer {
        interval: Theme.startMs
        running: true
        onTriggered: root._positionReady = true
    }
    // Animate between whole-pixel left edges; fractional frames keep the motion smooth.
    property real _centreLeft: parent ? Math.round(parent.width / 2 - centreAt - centreShift) : 0
    Behavior on _centreLeft {
        enabled: root.animatePosition && root._positionReady && !Theme.reduceMotion
        NumberAnimation {
            id: centreMove
            duration: Theme.foldMs
            easing.type: Easing.InOutCubic
        }
    }

    anchors {
        // Our left edge already chooses the grid. Qt's centre rounding would
        // shift it by half a pixel whenever the pill's width changes parity.
        alignWhenCentered: false
        top: parent.top
        left: root.side === Pill.Side.Left ? parent.left : undefined
        leftMargin: root.side === Pill.Side.Left ? root.edgeOffset : 0
        right: root.side === Pill.Side.Right ? parent.right : undefined
        rightMargin: root.side === Pill.Side.Right ? root.edgeOffset : 0
        horizontalCenter: root.side === Pill.Side.Centre ? parent.horizontalCenter : undefined
        // Compensate for width changes immediately while the left edge travels.
        horizontalCenterOffset: root._centreLeft + root.centreShift + root.width / 2 - (root.parent?.width ?? 0) / 2
    }

    implicitWidth: row.implicitWidth
    // A margin's worth of claim on each side of the slab. The bottom one hangs
    // off the end of the layer surface and is never clicked — it is here so the
    // slab stays centred in the pill and everything inside goes on centring
    // itself without knowing any of this happened.
    implicitHeight: Theme.barHeight + Theme.barInset * 2

    // The wallpaper, for the slab to be clear glass over it rather than a
    // tint (Liquid.backdrop). Null leaves it the tint.
    property Item backdrop: null

    // The slab as one colour: the wallpaper under this pill as the glass
    // shows it, or the tint over the wallpaper's average before the strip has
    // been read and on a flat colour. For what has to be drawn solid on it
    // (Theme.badgeBg).
    readonly property color surface: backdrop?.sampled ? Theme.glassOver(backdrop.average(x + slab.x, x + slab.x + slab.width)) : Theme.mix(Theme.backdrop, Theme.tint, Theme.barBg.a)

    // Where the glass is in the bar, stretch and all, for a bar that draws
    // this pill's glass itself while something pours out of it
    // (Bar.qml, the recording pill).
    readonly property rect slabRect: Qt.rect(root.x + slab.x, root.y + slab.y, slab.width, slab.height)

    Item {
        id: slab

        anchors {
            fill: parent
            topMargin: Theme.barInset
            bottomMargin: Theme.barInset
            leftMargin: (root.atLeftEdge ? Theme.barMargin : 0) - (root.side === Pill.Side.Right ? root.stretch : 0)
            rightMargin: (root.atRightEdge ? Theme.barMargin : 0) - (root.side === Pill.Side.Left ? root.stretch : 0)
        }
        visible: root.drawsSlab

        // The same glass as the clock's, one box of it, with the edge lit
        // from above like every other surface the shell draws. Out past the
        // slab by the bar's inset all round, for a press to swell it into.
        Liquid {
            anchors.fill: parent
            anchors.margins: -Theme.barInset
            backdrop: root.backdrop
            box0: Qt.vector4d(Theme.barInset, Theme.barInset, slab.width, slab.height)
            rimFrom: Theme.barInset
            rimTo: Theme.barInset + slab.height
        }
    }

    ProgressTrack {
        id: track
        slab: root.trackSlab
        progress: root.progress
        rate: root.rate
        trackOpacity: root.trackOpacity
        trackColor: root.trackColor
        trackWidth: root.trackWidth
        trackReady: root.trackReady
    }

    // No spacing of the row's own: each module carries half the gap to its
    // neighbours as padding, so folding takes that padding with it. A row's
    // spacing is fixed for every visible item, and cancelling it with a
    // negative margin does not work —
    // the layout clamps a cell at zero width, so a folding module kept its
    // whole gap until its width outgrew it, and the pill jumped by a gap per
    // module at the start of the fold and again at the end.
    // A grid of one row rather than a RowLayout: its columns (arrange) put
    // the right pill's modules in their saved order without recreating them.
    // The bar's selection mode (OpenPopup.selected) marks its item here in
    // the workspaces' glass (FlowMark), over the slab and under the contents,
    // and keeps it marked while the keys are down in its popup, the way a
    // menu bar title stays lit while its menu is open. It flows from item to
    // item along the pill with its ends on springs, so it stretches to each
    // one's width and settles there. It does not cross the air into another
    // pill: it fades out here and comes up there.
    FlowMark {
        id: keyMark

        // The selected item, when it is in this pill and does not mark the
        // selection itself (a workspace moves the workspace mark).
        readonly property Item target: {
            if (OpenPopup.selected?.marksSelection)
                return null;
            for (let p = OpenPopup.selected; p; p = p.parent)
                if (p === root)
                    return OpenPopup.selected;
            return null;
        }
        readonly property Item box: target?.keyBox ?? target
        // Where its box is along the pill, read through every parent so the
        // mark follows the item as the pill's contents move (the drawer).
        readonly property real boxMid: {
            if (!box)
                return 0;
            let x = box.x + box.width / 2;
            for (let p = box.parent; p && p !== root; p = p.parent)
                x += p.x;
            return x;
        }
        readonly property real half: box ? Math.max(box.width + Theme.gap, Theme.keyMarkWidth) / 2 : 0
        // The item the mark was last sent to: one that moves or changes
        // width under it is followed, not flowed to.
        property Item placedOn: null

        function retarget(): void {
            if (!keyMark.target)
                return;
            keyMark.resizing = keyMark.target === keyMark.placedOn;
            keyMark.placedOn = keyMark.target;
            // On the item at either end of the pill, the mark runs out to
            // the end and rounds with it, the way the workspace mark does on
            // the first and last workspace, rather than stopping short of
            // the pill's round end or pressing against it.
            const left = keyMark.boxMid - keyMark.half;
            const right = keyMark.boxMid + keyMark.half;
            keyMark.wantLeft = left < slab.x + Theme.pillPad ? keyMark.wallLeft : left;
            keyMark.wantRight = right > slab.x + slab.width - Theme.pillPad ? keyMark.wallRight : right;
        }

        onBoxMidChanged: Qt.callLater(keyMark.retarget)
        onHalfChanged: Qt.callLater(keyMark.retarget)
        onWallLeftChanged: Qt.callLater(keyMark.retarget)
        onWallRightChanged: Qt.callLater(keyMark.retarget)

        spring: Theme.keyMarkSpring
        damping: Theme.keyMarkDamping

        width: root.width
        height: root.height
        slabY: slab.y
        slabHeight: slab.height
        // The pill's ends are walls wherever the item is, as far in as the
        // mark keeps from its top and bottom.
        atFirst: true
        atLast: true
        wallLeft: slab.x + Theme.pillBorder + Theme.markInset
        wallRight: slab.x + slab.width - Theme.pillBorder - Theme.markInset
        resetWhenHidden: true
        opacity: target ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }
    }

    GridLayout {
        id: row
        anchors.fill: parent
        columnSpacing: 0
        opacity: root.contentOpacity
        // Render only the ink into the effect; the glass and track are siblings.
        layer.enabled: root.contentBlur > 0 && opacity > 0 && !Theme.reduceMotion
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 8
            blur: root.contentBlur
        }
        transform: [
            Scale {
                origin.x: row.width / 2
                origin.y: row.height / 2
                xScale: root.contentScale * root.contentZoom
                yScale: root.contentZoom
            },
            Translate { x: root.contentShiftX; y: root.contentSink }
        ]
        onChildrenChanged: root.arrange()
    }

    PillReorder { id: reorder; pill: root }

    // The first and last modules have no neighbour on their outer side.
    Binding {
        target: root.shown[0] ?? null
        property: "lead"
        value: false
    }

    Binding {
        target: root.shown[root.shown.length - 1] ?? null
        property: "trail"
        value: false
    }

    // The modules at the ends carry the pill's padding rather than the pill
    // insetting its row: BarItem's padLeft/padRight widen a module's hit area
    // by exactly what they inset its content, so the padding and the margin
    // beyond it click through to the module they belong to. A module that hides
    // itself hands its end to the next one along.
    readonly property var shown: {
        const shown = [];
        for (const child of row.children)
            if (child.visible)
                shown.push(child);
        return root.order.length > 0 ? shown.sort((a, b) => a.Layout.column - b.Layout.column) : shown;
    }

    Binding {
        target: root.shown[0] ?? null
        property: "padLeft"
        value: root.atLeftEdge ? Theme.pillPad + Theme.barMargin : Theme.pillPad
    }

    Binding {
        target: root.shown[root.shown.length - 1] ?? null
        property: "padRight"
        value: root.atRightEdge ? Theme.pillPad + Theme.barMargin : Theme.pillPad
    }
}
