import QtQuick
import qs
import qs.components

// The workspace mark as glass that bends the icons under it, two ways and
// two strengths each, all switching workspaces on the same beat.
//
//   A   a bead: as the mark sets off it swells into clear glass taller than
//       the pill, magnifying a little and pulling hard round its rim, runs
//       stretched by its speed, and settles back into the capsule at rest
//   B   the mark as it is (FlowMark: the head springs, the tail pours after
//       it), drawn as glass over the pill and its icons rather than a fill
//
// The pill, its icons and the wallpaper are drawn once (`world`) and taken
// as a texture, which both kinds of mark are glass over.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    readonly property var icons: [
        ["/usr/share/icons/hicolor/128x128/apps/firefox.png"],
        ["/usr/share/pixmaps/kitty.png", "/usr/share/icons/hicolor/512x512/apps/obsidian.png"],
        ["/usr/share/icons/hicolor/256x256/apps/discord.png"],
        ["/usr/share/pixmaps/steam.png"],
        ["/usr/share/pixmaps/kitty.png"]
    ]
    readonly property int iconSize: 18
    readonly property int pad: Theme.pillPad
    readonly property int gap: Theme.workspaceGap
    readonly property var groupX: {
        const xs = [];
        let x = pad;
        for (const g of icons) {
            xs.push(x);
            x += groupW(g.length) + gap;
        }
        return xs;
    }
    readonly property real pillW: groupX[icons.length - 1] + groupW(icons[icons.length - 1].length) + pad
    readonly property real pillX: 230
    readonly property int rowH: 62
    readonly property int slabTop: 16

    function groupW(n) {
        return n * iconSize + (n - 1) * Theme.appIconGap;
    }
    function slotLeft(i) {
        return groupX[i] - pad + Theme.markInset;
    }
    function slotRight(i) {
        return groupX[i] + groupW(icons[i].length) + pad - Theme.markInset;
    }

    // Which workspace is on, on a loop that has short hops and long ones.
    readonly property var path: [0, 1, 2, 4, 3, 0, 4, 1]
    property int step: 0
    readonly property int current: path[step]
    Timer {
        running: true
        repeat: true
        interval: 1150
        onTriggered: scene.step = (scene.step + 1) % scene.path.length
    }

    // --- what the glass is over -------------------------------------------
    Item {
        id: world

        anchors.fill: parent

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: scene.backdrop.sourceItem
        }

        Repeater {
            model: 4

            Item {
                required property int index

                x: scene.pillX
                y: index * scene.rowH + scene.slabTop - Theme.barInset
                width: scene.pillW
                height: Theme.barHeight + 2 * Theme.barInset

                Liquid {
                    anchors.fill: parent
                    backdrop: scene.backdrop
                    box0: Qt.vector4d(0, Theme.barInset, width, Theme.barHeight)
                }

                Repeater {
                    model: scene.icons

                    Row {
                        required property var modelData
                        required property int index

                        x: scene.groupX[index]
                        y: Theme.barInset + (Theme.barHeight - scene.iconSize) / 2
                        spacing: Theme.appIconGap

                        Repeater {
                            model: parent.modelData

                            Image {
                                required property string modelData
                                width: scene.iconSize
                                height: scene.iconSize
                                sourceSize.width: 64
                                source: "file://" + modelData
                                smooth: true
                                mipmap: true
                            }
                        }
                    }
                }
            }
        }
    }

    ShaderEffectSource {
        id: worldTex

        property real glassWeight: 1
        anchors.fill: parent
        sourceItem: world
        live: true
        visible: false
    }

    // --- A: the bead --------------------------------------------------------
    Bead { row: 0; over: 7; zoom: 1.12; title: "A1 · bead, 7px over the pill" }
    Bead { row: 1; over: 4; zoom: 1.06; title: "A2 · bead, 4px over" }

    // --- B: the mark as it is, as glass ----------------------------------
    Flow { row: 2; bend: 4; bendDepth: 5; tint: 0.2; title: "B1 · today's mark, glass" }
    Flow { row: 3; bend: 7; bendDepth: 6; tint: 0.14; title: "B2 · stronger lens" }

    component Bead: ShaderEffect {
        id: bead

        required property int row
        required property real over
        required property real zoom
        required property string title

        y: row * scene.rowH
        width: scene.width
        height: scene.rowH

        // The mark's motion: the head on a spring, the tail eased after it,
        // the rest width eased to the workspace's, and `clear` up while it
        // runs and down once it has landed.
        readonly property real targetMid: scene.pillX + (scene.slotLeft(scene.current) + scene.slotRight(scene.current)) / 2
        readonly property real targetW: scene.slotRight(scene.current) - scene.slotLeft(scene.current)
        property real head: targetMid
        property real vel: 0
        property real tail: targetMid
        property real w: targetW
        property real clear: 0
        property bool moving: false
        onTargetMidChanged: moving = true

        FrameAnimation {
            running: true
            onTriggered: {
                const dt = Math.min(frameTime, 0.05);
                const k = 170, c = 2 * Math.sqrt(k) * 0.72;
                bead.vel += (k * (bead.targetMid - bead.head) - c * bead.vel) * dt;
                bead.head += bead.vel * dt;
                bead.tail += (bead.head - bead.tail) * (1 - Math.exp(-dt / 0.07));
                bead.w += (bead.targetW - bead.w) * (1 - Math.exp(-dt / 0.08));
                if (bead.moving && Math.abs(bead.targetMid - bead.head) < 0.5 && Math.abs(bead.vel) < 8)
                    bead.moving = false;
                bead.clear += ((bead.moving ? 1 : 0) - bead.clear) * (1 - Math.exp(-dt / (bead.moving ? 0.06 : 0.14)));
            }
        }

        readonly property real thick: Theme.barHeight - Theme.pillBorder - 2 * Theme.markInset
        readonly property real tall: thick + 2 * over
        readonly property real stretch: Math.abs(head - tail)
        readonly property real h: thick + (tall - thick) * clear - Math.min(3, stretch * 0.06) * clear
        readonly property real bw: w + (Math.max(w + 8, tall * 1.3) - w) * clear
        readonly property real cy: scene.slabTop + Theme.barHeight / 2

        property var source: ShaderEffectSource {
            sourceItem: world
            sourceRect: Qt.rect(0, bead.y, bead.width, bead.height)
            live: true
        }
        readonly property size size: Qt.size(width, height)
        readonly property vector4d box: Qt.vector4d(Math.min(head, tail) - bw / 2, cy - h / 2, stretch + bw, h)
        readonly property real bend: 1.5 + 10.5 * clear
        readonly property real depth: 0.5
        readonly property real steep: 1.6
        readonly property real dispersion: Theme.glassDispersion
        readonly property real restTint: 0.16
        readonly property real beadTint: 0.03

        fragmentShader: Qt.resolvedUrl("mark.frag.qsb")

        Tag {
            x: 10
            y: scene.slabTop + (Theme.barHeight - height) / 2
            text: bead.title
        }
    }

    component Flow: Item {
        id: flow

        required property int row
        required property real bend
        required property real bendDepth
        required property real tint
        required property string title

        y: row * scene.rowH

        FlowMark {
            id: mark

            x: scene.pillX
            y: scene.slabTop - Theme.barInset
            width: scene.pillW
            height: Theme.barHeight + 2 * Theme.barInset
            slabY: Theme.barInset
            slabHeight: Theme.barHeight
            wallLeft: Theme.pillBorder
            wallRight: scene.pillW - Theme.pillBorder
            atFirst: scene.current === 0
            atLast: scene.current === scene.icons.length - 1
            wantLeft: scene.slotLeft(scene.current)
            wantRight: scene.slotRight(scene.current)
            Component.onCompleted: Qt.callLater(() => mark.placed = true)

            backdrop: worldTex
            bend: flow.bend
            bendDepth: flow.bendDepth
            tint: flow.tint
            saturation: 1
            soften: 0.5
        }

        Tag {
            x: 10
            y: scene.slabTop + (Theme.barHeight - height) / 2
            text: flow.title
        }
    }
}
