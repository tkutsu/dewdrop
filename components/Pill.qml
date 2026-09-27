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

    // Where on the bar this pill sits. It anchors itself from this rather than
    // being placed by the bar, so the one thing that decides whether the pill
    // backs onto a screen edge is also the thing that puts it there — the two
    // cannot drift apart.
    property int side: Pill.Side.Centre

    // How far along the bar is in filling the gaps between the pills with the
    // pill colour and drawing one strip for all three: 0 while we draw our own
    // slab, 1 once the bar's fill has taken it over entirely. Fading out of the
    // way rather than staying put because two 0.5-alpha blacks stacked make a
    // darker pill on a lighter strip, which is the seam the fill exists to
    // remove. Nothing else changes — same size, same padding, same margin
    // claimed for clicks — so nothing moves as it goes.
    property real mergeProgress: 0

    // How far short of its side the pill stops. Zero for the three that back
    // onto a screen edge or the centre line; the ones either side of the clock
    // float clear of their edge, which is also what stops them claiming a
    // margin they no longer reach — the edge is another pill's, and so is the
    // hit area out to it.
    // Fractional while the pill it is measured off is folding, so the two move
    // together rather than this one trailing by a pixel at a time.
    property real edgeOffset: 0

    // Trim off the padding at the pill's inner end — the one that faces the
    // rest of the bar rather than a screen edge. The right pill opens on the
    // volume glyph, whose ink already carries more air on its left than the
    // other glyphs do, so `pillPad` reads wide there. Taking it off the pad
    // rather than shifting the glyph pulls the pill's edge in instead of
    // moving anything inside it.
    property int innerPadTrim: 0

    // How far through whatever the pill is carrying, 0..1, or -1 for the pills
    // that are carrying nothing that runs — which is all of them but one.
    property real progress: -1

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
    readonly property real trackInset: Theme.pillTrack / 2 - trackBleed
    // The slab's own corner, brought in by the same inset as the rest of the
    // path so the line stays concentric with the edge it stands inside. Read
    // from the constant rather than from the height: the two agree only while
    // the pills are fully round, and the ends are where they would come apart
    // — a squarer slab with a lozenge drawn round it. Clamped to the half
    // height Qt clamps the slab's own radius to, so neither can outrun it.
    readonly property real trackRadius: Math.min(Theme.pillRadius, slab.height / 2) - trackInset
    readonly property real trackMiddle: slab.height / 2
    // The four straight edges and the four corners, which between them are one
    // circle. Fully round ends take the two vertical edges to nothing and
    // leave a line up each side of length zero.
    readonly property real trackLength: 2 * (slab.width - 2 * trackInset - 2 * trackRadius) + 2 * (slab.height - 2 * trackInset - 2 * trackRadius) + 2 * Math.PI * trackRadius

    // How much of that line is lit. Set rather than animated: the elapsed time
    // arrives once a second with about a pixel to cross, and a one-second
    // Behavior restarted every second never finishes — the bar redrew at the
    // monitor's refresh rate for as long as anything played (4.6% CPU against
    // 0.2%, measured), re-stroking the dash pattern every frame. A pixel a
    // second reads as moving either way.
    property real lit: root.trackLength * Math.max(0, Math.min(1, root.progress))

    // Whether a pill at offset zero is against the screen edge. Not for one
    // placed on a stage beside the clock (see Bar.qml): its offset passes
    // through zero on the way under the clock, and claiming the margin for
    // that one frame put its width into its offset and its offset into its
    // width — a loop that held the bar for half a second at every arrival.
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
    implicitHeight: Theme.barHeight + Theme.barMargin * 2

    Rectangle {
        id: slab

        anchors {
            fill: parent
            topMargin: Theme.barMargin
            bottomMargin: Theme.barMargin
            leftMargin: root.atLeftEdge ? Theme.barMargin : 0
            rightMargin: root.atRightEdge ? Theme.barMargin : 0
        }
        radius: Theme.pillRadius
        color: Qt.rgba(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, Theme.barBg.a * (1 - root.mergeProgress))

        // The pill's edge, lit from above like every other surface the shell
        // draws. Goes with the fill once the pills merge: a strip has no ends
        // for a rim to run round.
        Rim {
            anchors.fill: parent
            radius: Theme.pillRadius
            topColor: Theme.pillRimTop
            opacity: 1 - root.mergeProgress
            visible: opacity > 0
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
    Shape {
        x: slab.x
        y: slab.y
        width: slab.width
        height: slab.height
        visible: root.progress >= 0 && root.lit > 0
        // Goes with the outline it stands in for: once the pills have merged
        // into one strip there are no ends for a line to run between.
        opacity: 1 - root.mergeProgress
        // The curve renderer, because this is a line on a curve and the
        // triangulated one leaves steps on the ends.
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Theme.fg
            strokeWidth: Theme.pillTrack
            fillColor: "transparent"
            // Square ends, so the lit part stops exactly where the track has
            // got to rather than half a stroke past it.
            capStyle: ShapePath.FlatCap
            strokeStyle: root.lit >= root.trackLength ? ShapePath.SolidLine : ShapePath.DashLine
            // In multiples of the stroke width, which is what a dash pattern
            // is measured in. Never zero: a zero-length gap is not a dash
            // pattern Qt will draw.
            dashPattern: [Math.max(0.001, root.lit / Theme.pillTrack), Math.max(0.001, (root.trackLength - root.lit) / Theme.pillTrack)]

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
                y: slab.height - root.trackInset - root.trackRadius
            }
            PathArc {
                x: slab.width - root.trackInset - root.trackRadius
                y: slab.height - root.trackInset
                radiusX: root.trackRadius
                radiusY: root.trackRadius
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.trackInset + root.trackRadius
                y: slab.height - root.trackInset
            }
            PathArc {
                x: root.trackInset
                y: slab.height - root.trackInset - root.trackRadius
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

    // No spacing of the row's own: each module brings the gap in front of it
    // (BarItem.lead), which is what lets a module folding into the right
    // pill's drawer take its gap with it. A row's spacing is fixed for every
    // visible item, and cancelling it with a negative margin does not work —
    // RowLayout clamps a cell at zero width, so a folding module kept its
    // whole gap until its width outgrew it, and the pill jumped by a gap per
    // module at the start of the fold and again at the end.
    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 0
    }

    // The first module has nothing in front of it to keep a gap from.
    Binding {
        target: root._shown[0] ?? null
        property: "lead"
        value: false
    }

    // The modules at the ends carry the pill's padding rather than the pill
    // insetting its row: BarItem's padLeft/padRight widen a module's hit area
    // by exactly what they inset its content, so the padding and the margin
    // beyond it click through to the module they belong to. A module that hides
    // itself hands its end to the next one along.
    readonly property var _shown: {
        const shown = [];
        for (const child of row.children)
            if (child.visible)
                shown.push(child);
        return shown;
    }

    Binding {
        target: root._shown[0] ?? null
        property: "padLeft"
        value: root.atLeftEdge ? Theme.pillPad + Theme.barMargin : Theme.pillPad - root.innerPadTrim
    }

    Binding {
        target: root._shown[root._shown.length - 1] ?? null
        property: "padRight"
        value: root.atRightEdge ? Theme.pillPad + Theme.barMargin : Theme.pillPad - root.innerPadTrim
    }
}
