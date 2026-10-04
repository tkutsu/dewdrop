import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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

    // Empty on the other pills; the right pill fixes its unkeyed ends in place.
    property var order: []
    property bool dragging: false
    readonly property bool animating: dragging || row.children.some(item => item.animating === true)
    onAnimatingChanged: Tooltips.setMoving(root, animating)
    Component.onDestruction: Tooltips.setMoving(root, false)
    property Item dragSource: null
    property point dragPoint: Qt.point(0, 0)

    function arrange(): void {
        if (order.length === 0)
            return;
        for (const item of row.children) {
            const index = order.indexOf(item.settingsKey);
            item.Layout.row = 0;
            item.Layout.column = index >= 0 ? index + 1 : item === row.children[0] ? 0 : order.length + 1;
        }
    }

    onOrderChanged: arrange()
    Component.onCompleted: {
        arrange();
        Tooltips.setMoving(root, animating);
    }

    readonly property var _movable: shown.filter(item => order.includes(item.settingsKey))
    readonly property bool dragValid: root.visible && dragSource !== null && dragSource.here && dragSource.visible
    // Later, not here: clearing dragSource now re-evaluates dragValid inside its own change.
    onDragValidChanged: if (dragging && !dragValid) Qt.callLater(root.cancelInvalidDrag)

    function cancelInvalidDrag(): void {
        if (dragging && !dragValid)
            cancelDrag();
    }

    function moduleAt(point): Item {
        if (!root.contains(point))
            return null;
        for (const item of root._movable)
            if (item.contains(item.mapFromItem(root, point)))
                return item;
        return null;
    }

    // Compare against the remaining modules so either side of the source is a no-op.
    function beforeAt(point): Item {
        for (const item of root._movable) {
            if (item === root.dragSource)
                continue;
            const middle = item.mapToItem(root, item.width / 2, 0).x;
            if (point.x < middle)
                return item;
        }
        return null;
    }

    readonly property Item dropBefore: dragging ? beforeAt(dragPoint) : null
    // A drop just before the module that already follows the source leaves it where it is.
    readonly property bool dropMoves: dragging
        && dropBefore !== (_movable[_movable.indexOf(dragSource) + 1] ?? null)

    function cancelDrag(): void {
        dragging = false;
        dragSource = null;
    }

    // Resolve the drop from current geometry, including a drawer still settling.
    // A null point is a drag that ended without a release, which cancels.
    function finishDrag(point): void {
        if (dragging && dragValid && point !== null && root.contains(point))
            RightPillOrder.move(dragSource.settingsKey, beforeAt(point)?.settingsKey ?? null,
                root._movable.map(item => item.settingsKey));
        cancelDrag();
    }

    // Where on the bar this pill sits. It anchors itself from this rather than
    // being placed by the bar, so the one thing that decides whether the pill
    // backs onto a screen edge is also the thing that puts it there — the two
    // cannot drift apart.
    property int side: Pill.Side.Centre

    readonly property int moduleGap: Theme.gap + (side === Pill.Side.Right ? 3 : 0)

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

    // Whether the pill draws its own slab. Not for the ones around the clock,
    // whose glass is drawn for all of them at once by the bar (Liquid.qml) so
    // that they can flow into each other; those keep only their contents, and
    // fade them by `contentOpacity` as the glass under them runs away.
    property bool drawsSlab: true
    property real contentOpacity: 1

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

    // The outline as a single line around the pill, starting from the left and
    // going clockwise. Its measurements, in the slab's own coordinates: the
    // stroke is centred on the path it follows, so the path is half a stroke
    // inside the slab and the line's outer edge lands exactly on the pill's.
    // Half a pixel further out than the stroke's own half-width would put it.
    // A rounded rectangle is drawn with its edge antialiased over the pixel
    // outside itself, and that fringe is the pill's dark grey: sitting the
    // line exactly on the edge leaves a hairline of pill showing around the
    // outside of it. Half a pixel of bleed covers the fringe and costs no
    // height — it is inside the margin the pill already claims.
    readonly property real trackBleed: 0.5
    readonly property real trackInset: root.trackWidth / 2 - trackBleed
    // Except along the foot, where the bar's surface ends on the slab's edge
    // and anything past it is cut: the bleed there was cut with it, and left
    // the line a pixel wide along the bottom and half again that along the
    // top. There is no fringe for it to cover at a cut edge, so the line
    // stands wholly inside instead.
    readonly property real trackFootInset: root.trackWidth / 2
    // The slab's own corner, brought in by the path's insets so the line
    // stays concentric with the edge it stands inside: by the mean of the two,
    // top and foot, which on fully round ends is the circle through both.
    // Read from the constant rather than from the height: the two agree only
    // while the pills are fully round, and the ends are where they would come
    // apart — a squarer slab with a lozenge drawn round it. Clamped to the
    // half height Qt clamps the slab's own radius to, so neither can outrun it.
    readonly property real trackRadius: Math.min(Theme.pillRadius, slab.height / 2) - (trackInset + trackFootInset) / 2
    readonly property real trackMiddle: (trackInset + slab.height - trackFootInset) / 2
    // The four straight edges and the four corners, which between them are one
    // circle. Fully round ends take the two vertical edges to nothing and
    // leave a line up each side of length zero.
    readonly property real trackLength: 2 * (slab.width - 2 * trackInset - 2 * trackRadius) + 2 * (slab.height - trackInset - trackFootInset - 2 * trackRadius) + 2 * Math.PI * trackRadius

    // How fast `progress` runs on its own, per second, while whatever it
    // measures is running; 0 while it stands still. The owner only says where
    // it is once a second, and the pill carries the line on in between, so it
    // creeps round rather than stepping a pixel at a time.
    property real rate: 0

    // How much of that line is lit. Not a Behavior: the elapsed time arrives
    // once a second, and a one-second Behavior restarted every second never
    // finishes — the bar redrew at the monitor's refresh rate for as long as
    // anything played (4.6% CPU against 0.2%, measured), re-stroking the dash
    // pattern every frame. Moved on by `creep` instead, a quarter of a pixel
    // at a time: under what the eye can call a step, and a few redraws a
    // second rather than a hundred and twenty.
    property real lit: root.trackLength * Math.max(0, Math.min(1, root.progress + root.drift))

    // How far the line has been carried past the last `progress`, capped at a
    // second's worth so that a late update stalls it rather than overshoots.
    property real drift: 0
    property real since: 0

    function settle() {
        root.since = Date.now();
        root.drift = 0;
    }

    onProgressChanged: settle()
    // And from a pause, which would otherwise count the whole of it as time
    // the line should have been moving.
    onRateChanged: settle()

    Timer {
        id: creep

        readonly property real pxPerSecond: Math.abs(root.rate) * root.trackLength

        interval: pxPerSecond > 0 ? Math.max(16, Math.min(1000, 250 / pxPerSecond)) : 1000
        repeat: true
        running: root.visible && root.rate !== 0 && root.progress >= 0 && track.opacity > 0
        onTriggered: root.drift = root.rate * Math.min(1, (Date.now() - root.since) / 1000)
    }

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

    anchors {
        top: parent.top
        left: root.side === Pill.Side.Left ? parent.left : undefined
        leftMargin: root.side === Pill.Side.Left ? root.edgeOffset : 0
        right: root.side === Pill.Side.Right ? parent.right : undefined
        rightMargin: root.side === Pill.Side.Right ? root.edgeOffset : 0
        horizontalCenter: root.side === Pill.Side.Centre ? parent.horizontalCenter : undefined
        // What the centre anchor would have to be off by for centreOn to land
        // where the pill's own middle was going to.
        horizontalCenterOffset: root.centreOn ? Math.round(root.width / 2 - root.centreOnX) : 0
    }

    implicitWidth: row.implicitWidth
    // A margin's worth of claim on each side of the slab. The bottom one hangs
    // off the end of the layer surface and is never clicked — it is here so the
    // slab stays centred in the pill and everything inside goes on centring
    // itself without knowing any of this happened.
    implicitHeight: Theme.barHeight + Theme.barInset * 2

    // The wallpaper, for the slab to be clear glass over it rather than a
    // tint (Liquid.backdrop). Null leaves it the tint.
    property Image backdrop: null

    // The slab as one colour: the wallpaper under this pill as the glass
    // shows it, or the tint over the wallpaper's average before the strip has
    // been read and on a flat colour. For what has to be drawn solid on it
    // (Theme.badgeBg).
    readonly property color surface: backdrop?.columns?.length ? Theme.glassOver(backdrop.average(x + slab.x, x + slab.x + slab.width)) : Theme.mix(Theme.backdrop, Theme.tint, Theme.barBg.a)

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
        // from above like every other surface the shell draws.
        Liquid {
            anchors.fill: parent
            backdrop: root.backdrop
            box0: Qt.vector4d(0, 0, width, height)
            rimFrom: 0
            rimTo: height
        }
    }

    // The pill's outline, lit from the left and travelling clockwise as the
    // track plays: a position read off the thing that is playing rather than
    // off a bar somewhere else, and it costs the bar no room — the line is the
    // pill's own edge, inside its own height.
    //
    // One stroke along a path, dashed so that the first dash is everything
    // played and the gap is everything left. Drawn as a line rather than as a
    // shape revealed by a clip, so it goes round the ends the way a line
    // around a pill has to, instead of filling in from both edges at once.
    //
    // And shaded as the rims are, with the light from above: bright along the
    // top and faint along the foot. A stroke cannot take a gradient, so the
    // line is drawn into a layer and the shading is laid over that
    // (shaders/track.frag). A pixel of
    // room all round, because the line bleeds half a pixel past the slab and a
    // layer keeps only what is inside its item.
    Item {
        id: track

        readonly property int room: 1

        x: slab.x - room
        y: slab.y - room
        width: slab.width + 2 * room
        height: slab.height + 2 * room
        visible: root.progress >= 0 && opacity > 0
        opacity: root.trackOpacity

        layer.enabled: visible
        layer.effect: ShaderEffect {
            property real foot: Theme.pillTrackFoot

            fragmentShader: Qt.resolvedUrl("../shaders/track.frag.qsb")
        }

        // What is still to play: the whole line again, faint, under the part
        // that has played. The light goes on after the two are laid together,
        // so where they overlap the played line covers this one rather than
        // adding to it. A ring on the same edges as the stroke: out by the
        // bleed but for the foot, and as wide as the line.
        Rim {
            x: track.room - root.trackBleed
            y: track.room - root.trackBleed
            width: slab.width + 2 * root.trackBleed
            height: slab.height + root.trackBleed
            radius: root.trackRadius + root.trackWidth / 2
            lineWidth: root.trackWidth
            topColor: Qt.rgba(root.trackColor.r, root.trackColor.g, root.trackColor.b, Theme.pillTrackRest)
            bottomColor: topColor
        }

        Shape {
            x: track.room
            y: track.room
            width: slab.width
            height: slab.height
            visible: root.lit > 0
            // The curve renderer, because this is a line on a curve and the
            // triangulated one leaves steps on the ends.
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.trackColor
                strokeWidth: root.trackWidth
                fillColor: "transparent"
                // Rounded tips stay smooth as the line thickens on hover.
                capStyle: ShapePath.RoundCap
                strokeStyle: root.lit >= root.trackLength ? ShapePath.SolidLine : ShapePath.DashLine
                // In multiples of the stroke width, which is what a dash pattern
                // is measured in. Never zero: a zero-length gap is not a dash
                // pattern Qt will draw.
                dashPattern: [Math.max(0.001, root.lit / root.trackWidth), Math.max(0.001, (root.trackLength - root.lit) / root.trackWidth)]

                // Nine o'clock, and clockwise from there: up the left edge and
                // round its corner, along the top, down the right edge, back along
                // the bottom and up to where it started. Four corners with a
                // straight between each pair, which at a fully round end is a
                // straight of no length and the same two semicircles as before.
                startX: root.trackInset
                startY: root.trackMiddle

                PathLine {
                    x: root.trackInset
                    y: root.trackInset + root.trackRadius
                }
                PathArc {
                    x: root.trackInset + root.trackRadius
                    y: root.trackInset
                    radiusX: root.trackRadius
                    radiusY: root.trackRadius
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: slab.width - root.trackInset - root.trackRadius
                    y: root.trackInset
                }
                PathArc {
                    x: slab.width - root.trackInset
                    y: root.trackInset + root.trackRadius
                    radiusX: root.trackRadius
                    radiusY: root.trackRadius
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: slab.width - root.trackInset
                    y: slab.height - root.trackFootInset - root.trackRadius
                }
                PathArc {
                    x: slab.width - root.trackInset - root.trackRadius
                    y: slab.height - root.trackFootInset
                    radiusX: root.trackRadius
                    radiusY: root.trackRadius
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.trackInset + root.trackRadius
                    y: slab.height - root.trackFootInset
                }
                PathArc {
                    x: root.trackInset
                    y: slab.height - root.trackFootInset - root.trackRadius
                    radiusX: root.trackRadius
                    radiusY: root.trackRadius
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.trackInset
                    y: root.trackMiddle
                }
            }
        }
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
    GridLayout {
        id: row
        anchors.fill: parent
        columnSpacing: 0
        opacity: root.contentOpacity
        onChildrenChanged: root.arrange()
    }

    // An ancestor handler observes child MouseAreas without swallowing their clicks.
    DragHandler {
        id: reorder
        target: null
        enabled: root.order.length > 0
        // Turning a handler off drops its grab without saying so.
        onEnabledChanged: if (!enabled) root.cancelDrag()
        acceptedButtons: Qt.LeftButton
        grabPermissions: root.moduleAt(centroid.pressPosition) !== null
            ? PointerHandler.CanTakeOverFromItems : PointerHandler.TakeOverForbidden
        onActiveChanged: {
            if (!active)
                return;
            root.dragSource = root.moduleAt(centroid.pressPosition);
            if (root.dragSource === null)
                return;
            root.dragPoint = centroid.position;
            root.dragging = true;
            OpenPopup.dismiss();
        }
        onCentroidChanged: if (active && root.dragging) root.dragPoint = centroid.position
        // Every end of the drag comes through here, released or not. Only a
        // release drops; centroid is reset by then, but the point keeps its place.
        onGrabChanged: (transition, point) => {
            const ends = [PointerDevice.UngrabExclusive, PointerDevice.CancelGrabExclusive, PointerDevice.OverrideGrabExclusive];
            if (!ends.includes(transition))
                return;
            const released = transition === PointerDevice.UngrabExclusive && point.state === EventPoint.Released;
            root.finishDrag(released ? root.mapFromItem(null, point.scenePosition) : null);
        }
    }

    // Between the modules either side of the drop, splitting any margin they overlap by.
    DropLine {
        target: {
            if (!root.dropMoves || !root.contains(root.dragPoint))
                return NaN;
            const items = root._movable.filter(item => item !== root.dragSource);
            const next = root.dropBefore;
            const previous = items[(next ? items.indexOf(next) : items.length) - 1];
            const left = previous?.mapToItem(root, previous.width, 0).x;
            const right = next?.mapToItem(root, 0, 0).x;
            return ((left ?? right) + (right ?? left)) / 2;
        }
    }

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
