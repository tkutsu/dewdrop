import QtQuick
import QtQuick.Effects
import qs
import qs.components

// One pill and the popover its middle item opens, moving the way `variant`
// says. The bar's window may draw a little way below the pill (the pill's
// bulge); the popup's window starts popupGap under the pill and draws nothing
// above that (clipTop), as the real windows do.
//
//   B   scale out of the item (round one)
//   G1  B, and the height runs past and settles like gel
//   G2  B, and the bottom edge sags and springs back
//   G3  B on two springs, the height looser than the width
//   G4  G1's shape on springs: the width settles, the height runs past once
//   E1  the pill bulges, drops a dew, the dew falls and blooms into the box
//   E2  the pill bulges and pours: the dew spreads into the box while joined
//   E3  the dew falls further and splashes: squashes, then spreads up and out
//   E4  E1 smaller and slower, no overshoot
Item {
    id: col

    required property string variant
    required property string title
    required property Item backdrop
    required property Item blurred
    required property bool open
    // The stage, for the frost to sample the blur where it stands.
    required property Item stage

    width: 300
    height: stage.height

    readonly property int step: 38
    readonly property int pad: 15
    readonly property int iconBox: 22
    readonly property real pillW: pad * 2 + step * 2 + iconBox
    readonly property real pillX: (width - pillW) / 2
    readonly property real pillY: 10
    readonly property real pillBottom: pillY + Theme.barHeight
    readonly property int roomUp: 6
    readonly property int roomDown: 14
    readonly property real ax: width / 2
    readonly property real fw: 236
    readonly property real fh: 196
    readonly property real fy: pillBottom + Theme.popupGap

    // What is drawn: the box (centred on the item, top at by), its corner,
    // the dew, how far they reach for each other, the sag, light, whole
    // visibility, scale, contents' fade and blur, and the pill's bulge.
    property real bw: 0
    property real bh: 0
    property real by: fy
    property real br: Theme.popupRadius
    property real dropY: fy
    property real dropR: 0
    property real join: 10
    property real sag: 0
    property real lit: 0
    property real seen: 0
    property real xs: 1
    property real ys: 1
    property real ink: 0
    property real smear: 0
    // The pill's bulge under the item, on a gel spring.
    property real bulge: 0
    Behavior on bulge {
        SpringAnimation {
            spring: 6
            damping: 0.28
            epsilon: 0.02
        }
    }
    // G3's springs; off for everyone else, and off while a value is set
    // to start from.
    property bool springs: false
    Behavior on xs {
        enabled: col.springs
        SpringAnimation { spring: col.variant === "G4" ? 5 : 5.5; damping: col.variant === "G4" ? 0.6 : 0.38; epsilon: 0.001 }
    }
    Behavior on ys {
        enabled: col.springs
        SpringAnimation { spring: col.variant === "G4" ? 5 : 5.5; damping: col.variant === "G4" ? 0.34 : 0.2; epsilon: 0.001 }
    }

    readonly property bool scales: variant === "B" || variant.startsWith("G")

    Component.onCompleted: shut()
    function shut() {
        springs = false;
        seen = 0;
        ink = 0;
        smear = 0;
        sag = 0;
        lit = 0;
        if (scales) {
            bw = fw;
            bh = fh;
            by = fy;
            xs = ys = 0.86;
        } else {
            bw = 0;
            bh = 0;
            dropR = 0;
        }
    }

    onOpenChanged: {
        for (const a of [openB, closeB, openG1, closeG1, openG2, closeG2, closeG3, openE1, openE2, openE3, openE4, closeE1, closeE2, closeE3, closeE4])
            a.stop();
        if (open) {
            if (variant === "B") openB.start();
            else if (variant === "G1") openG1.start();
            else if (variant === "G2") openG2.start();
            else if (variant === "G3" || variant === "G4") {
                springs = false;
                xs = ys = 0.86;
                springs = true;
                seen = 1;
                ink = 1;
                xs = 1;
                ys = 1;
            } else if (variant === "E1") openE1.start();
            else if (variant === "E2") openE2.start();
            else if (variant === "E3") openE3.start();
            else openE4.start();
        } else {
            if (variant === "B") closeB.start();
            else if (variant === "G1") closeG1.start();
            else if (variant === "G2") closeG2.start();
            else if (variant === "G3" || variant === "G4") closeG3.start();
            else if (variant === "E1") closeE1.start();
            else if (variant === "E2") closeE2.start();
            else if (variant === "E3") closeE3.start();
            else closeE4.start();
        }
    }

    // --- B and the gels ------------------------------------------------------
    ParallelAnimation {
        id: openB
        NumberAnimation { target: col; properties: "seen,ink"; to: 1; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: col; properties: "xs,ys"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    }
    ParallelAnimation {
        id: closeB
        NumberAnimation { target: col; properties: "seen,ink"; to: 0; duration: 160; easing.type: Easing.InQuad }
        NumberAnimation { target: col; properties: "xs,ys"; to: 0.9; duration: 160; easing.type: Easing.InCubic }
    }
    ParallelAnimation {
        id: openG1
        NumberAnimation { target: col; properties: "seen,ink"; to: 1; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: col; property: "xs"; to: 1; duration: 280; easing.type: Easing.OutCubic }
        SequentialAnimation {
            NumberAnimation { target: col; property: "ys"; to: 1.06; duration: 190; easing.type: Easing.OutQuad }
            NumberAnimation { target: col; property: "ys"; to: 0.985; duration: 170; easing.type: Easing.InOutQuad }
            NumberAnimation { target: col; property: "ys"; to: 1; duration: 190; easing.type: Easing.InOutQuad }
        }
    }
    SequentialAnimation {
        id: closeG1
        NumberAnimation { target: col; property: "ys"; to: 1.025; duration: 70; easing.type: Easing.OutQuad }
        ParallelAnimation {
            NumberAnimation { target: col; properties: "seen,ink"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: col; properties: "xs,ys"; to: 0.9; duration: 140; easing.type: Easing.InCubic }
        }
    }
    ParallelAnimation {
        id: openG2
        NumberAnimation { target: col; properties: "seen,ink"; to: 1; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: col; properties: "xs,ys"; to: 1; duration: 250; easing.type: Easing.OutCubic }
        SequentialAnimation {
            NumberAnimation { target: col; property: "sag"; to: 9; duration: 180; easing.type: Easing.OutQuad }
            NumberAnimation { target: col; property: "sag"; to: -3; duration: 170; easing.type: Easing.InOutSine }
            NumberAnimation { target: col; property: "sag"; to: 0; duration: 210; easing.type: Easing.InOutSine }
        }
    }
    SequentialAnimation {
        id: closeG2
        NumberAnimation { target: col; property: "sag"; to: 4; duration: 80; easing.type: Easing.OutQuad }
        ParallelAnimation {
            NumberAnimation { target: col; properties: "seen,ink"; to: 0; duration: 140; easing.type: Easing.InQuad }
            NumberAnimation { target: col; properties: "xs,ys"; to: 0.92; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "sag"; to: 0; duration: 140 }
        }
    }
    SequentialAnimation {
        id: closeG3
        PropertyAction { target: col; property: "springs"; value: false }
        ParallelAnimation {
            NumberAnimation { target: col; properties: "seen,ink"; to: 0; duration: 150; easing.type: Easing.InQuad }
            NumberAnimation { target: col; properties: "xs,ys"; to: 0.9; duration: 150; easing.type: Easing.InCubic }
        }
    }

    // --- the dews --------------------------------------------------------------
    // A box that starts as the drop, for the dew to bloom into.
    function boxAtDrop() {
        bw = dropR * 2;
        bh = dropR * 2;
        by = dropY - dropR;
        br = dropR;
    }

    SequentialAnimation {
        id: openE1
        PropertyAction { target: col; property: "bulge"; value: 7 }
        PauseAnimation { duration: 90 }
        PropertyAction { target: col; property: "seen"; value: 1 }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 4 }
        PropertyAction { target: col; property: "smear"; value: 1 }
        NumberAnimation { target: col; property: "dropR"; to: 6; duration: 80; easing.type: Easing.OutQuad }
        PropertyAction { target: col; property: "bulge"; value: 0 }
        NumberAnimation { target: col; property: "dropY"; to: col.fy + 18; duration: 150; easing.type: Easing.InQuad }
        ScriptAction { script: col.boxAtDrop() }
        ParallelAnimation {
            NumberAnimation { target: col; property: "by"; to: col.fy; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
            NumberAnimation { target: col; property: "br"; to: Theme.popupRadius; duration: 200 }
            NumberAnimation { target: col; property: "dropR"; to: 0; duration: 200 }
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                ParallelAnimation {
                    NumberAnimation { target: col; property: "ink"; to: 1; duration: 200 }
                    NumberAnimation { target: col; property: "smear"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    SequentialAnimation {
        id: closeE1
        ParallelAnimation {
            NumberAnimation { target: col; property: "ink"; to: 0; duration: 90 }
            NumberAnimation { target: col; property: "smear"; to: 1; duration: 110 }
        }
        ParallelAnimation {
            NumberAnimation { target: col; property: "bw"; to: 12; duration: 210; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "bh"; to: 12; duration: 210; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "by"; to: col.fy + 12; duration: 210; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "br"; to: 6; duration: 210 }
        }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 18 }
        PropertyAction { target: col; property: "dropR"; value: 6 }
        PropertyAction { target: col; property: "bw"; value: 0 }
        NumberAnimation { target: col; property: "dropY"; to: col.fy + 2; duration: 140; easing.type: Easing.InQuad }
        PropertyAction { target: col; property: "bulge"; value: 6 }
        NumberAnimation { target: col; property: "dropR"; to: 0; duration: 70 }
        PropertyAction { target: col; property: "seen"; value: 0 }
        PropertyAction { target: col; property: "bulge"; value: 0 }
    }

    SequentialAnimation {
        id: openE2
        PropertyAction { target: col; property: "bulge"; value: 7 }
        PauseAnimation { duration: 80 }
        PropertyAction { target: col; property: "seen"; value: 1 }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 5 }
        PropertyAction { target: col; property: "smear"; value: 1 }
        PropertyAction { target: col; property: "join"; value: 12 }
        NumberAnimation { target: col; property: "dropR"; to: 7; duration: 90; easing.type: Easing.OutQuad }
        PropertyAction { target: col; property: "by"; value: col.fy }
        PropertyAction { target: col; property: "bw"; value: 14 }
        PropertyAction { target: col; property: "bh"; value: 10 }
        PropertyAction { target: col; property: "br"; value: 5 }
        ParallelAnimation {
            NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            SequentialAnimation {
                PauseAnimation { duration: 40 }
                NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 380; easing.type: Easing.OutCubic }
            }
            NumberAnimation { target: col; property: "br"; to: Theme.popupRadius; duration: 200 }
            NumberAnimation { target: col; property: "dropR"; to: 0; duration: 250 }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                PropertyAction { target: col; property: "bulge"; value: 0 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 180 }
                ParallelAnimation {
                    NumberAnimation { target: col; property: "ink"; to: 1; duration: 200 }
                    NumberAnimation { target: col; property: "smear"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    SequentialAnimation {
        id: closeE2
        ParallelAnimation {
            NumberAnimation { target: col; property: "ink"; to: 0; duration: 90 }
            NumberAnimation { target: col; property: "smear"; to: 1; duration: 110 }
        }
        PropertyAction { target: col; property: "bulge"; value: 6 }
        ParallelAnimation {
            NumberAnimation { target: col; property: "bh"; to: 10; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "bw"; to: 14; duration: 230; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "br"; to: 5; duration: 200 }
            NumberAnimation { target: col; property: "dropR"; to: 7; duration: 150 }
        }
        PropertyAction { target: col; property: "bw"; value: 0 }
        NumberAnimation { target: col; property: "dropR"; to: 0; duration: 100; easing.type: Easing.InQuad }
        PropertyAction { target: col; property: "seen"; value: 0 }
        PropertyAction { target: col; property: "bulge"; value: 0 }
    }

    SequentialAnimation {
        id: openE3
        PropertyAction { target: col; property: "bulge"; value: 7 }
        PauseAnimation { duration: 80 }
        PropertyAction { target: col; property: "seen"; value: 1 }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 4 }
        PropertyAction { target: col; property: "smear"; value: 1 }
        NumberAnimation { target: col; property: "dropR"; to: 6; duration: 80; easing.type: Easing.OutQuad }
        PropertyAction { target: col; property: "bulge"; value: 0 }
        NumberAnimation { target: col; property: "dropY"; to: col.fy + 36; duration: 200; easing.type: Easing.InQuad }
        // It lands and squashes.
        PropertyAction { target: col; property: "by"; value: col.fy + 36 }
        PropertyAction { target: col; property: "bw"; value: 12 }
        PropertyAction { target: col; property: "bh"; value: 12 }
        PropertyAction { target: col; property: "br"; value: 6 }
        PropertyAction { target: col; property: "dropR"; value: 0 }
        ParallelAnimation {
            NumberAnimation { target: col; property: "bw"; to: 64; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: col; property: "bh"; to: 8; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: col; property: "by"; to: col.fy + 40; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: col; property: "br"; to: 4; duration: 70 }
        }
        // And spreads up and out into the box.
        ParallelAnimation {
            NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            NumberAnimation { target: col; property: "by"; to: col.fy; duration: 280; easing.type: Easing.OutCubic }
            NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 330; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
            NumberAnimation { target: col; property: "br"; to: Theme.popupRadius; duration: 200 }
            SequentialAnimation {
                PauseAnimation { duration: 160 }
                ParallelAnimation {
                    NumberAnimation { target: col; property: "ink"; to: 1; duration: 200 }
                    NumberAnimation { target: col; property: "smear"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    SequentialAnimation {
        id: closeE3
        ParallelAnimation {
            NumberAnimation { target: col; property: "ink"; to: 0; duration: 90 }
            NumberAnimation { target: col; property: "smear"; to: 1; duration: 110 }
        }
        ParallelAnimation {
            NumberAnimation { target: col; property: "bw"; to: 12; duration: 220; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "bh"; to: 12; duration: 220; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "by"; to: col.fy + 30; duration: 220; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "br"; to: 6; duration: 220 }
        }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 36 }
        PropertyAction { target: col; property: "dropR"; value: 6 }
        PropertyAction { target: col; property: "bw"; value: 0 }
        NumberAnimation { target: col; property: "dropY"; to: col.fy + 2; duration: 180; easing.type: Easing.InQuad }
        PropertyAction { target: col; property: "bulge"; value: 6 }
        NumberAnimation { target: col; property: "dropR"; to: 0; duration: 70 }
        PropertyAction { target: col; property: "seen"; value: 0 }
        PropertyAction { target: col; property: "bulge"; value: 0 }
    }

    SequentialAnimation {
        id: openE4
        PropertyAction { target: col; property: "bulge"; value: 4 }
        PauseAnimation { duration: 110 }
        PropertyAction { target: col; property: "seen"; value: 1 }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 2 }
        PropertyAction { target: col; property: "smear"; value: 1 }
        NumberAnimation { target: col; property: "dropR"; to: 4; duration: 110; easing.type: Easing.OutQuad }
        PropertyAction { target: col; property: "bulge"; value: 0 }
        NumberAnimation { target: col; property: "dropY"; to: col.fy + 20; duration: 220; easing.type: Easing.InOutSine }
        ScriptAction { script: col.boxAtDrop() }
        ParallelAnimation {
            NumberAnimation { target: col; property: "by"; to: col.fy; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 400; easing.type: Easing.OutCubic }
            NumberAnimation { target: col; property: "br"; to: Theme.popupRadius; duration: 240 }
            NumberAnimation { target: col; property: "dropR"; to: 0; duration: 240 }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                ParallelAnimation {
                    NumberAnimation { target: col; property: "ink"; to: 1; duration: 220 }
                    NumberAnimation { target: col; property: "smear"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    SequentialAnimation {
        id: closeE4
        ParallelAnimation {
            NumberAnimation { target: col; property: "ink"; to: 0; duration: 100 }
            NumberAnimation { target: col; property: "smear"; to: 1; duration: 120 }
        }
        ParallelAnimation {
            NumberAnimation { target: col; property: "bw"; to: 8; duration: 240; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "bh"; to: 8; duration: 240; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "by"; to: col.fy + 16; duration: 240; easing.type: Easing.InCubic }
            NumberAnimation { target: col; property: "br"; to: 4; duration: 240 }
        }
        PropertyAction { target: col; property: "dropY"; value: col.fy + 20 }
        PropertyAction { target: col; property: "dropR"; value: 4 }
        PropertyAction { target: col; property: "bw"; value: 0 }
        NumberAnimation { target: col; property: "dropY"; to: col.fy + 1; duration: 200; easing.type: Easing.InOutSine }
        PropertyAction { target: col; property: "bulge"; value: 4 }
        NumberAnimation { target: col; property: "dropR"; to: 0; duration: 90 }
        PropertyAction { target: col; property: "seen"; value: 0 }
        PropertyAction { target: col; property: "bulge"; value: 0 }
    }

    // --- the pill ----------------------------------------------------------------
    LabGlass {
        x: col.pillX - col.roomUp
        y: col.pillY - col.roomUp
        width: col.pillW + 2 * col.roomUp
        height: Theme.barHeight + col.roomUp + col.roomDown
        backdrop: col.backdrop
        box0: Qt.vector4d(col.roomUp, col.roomUp, col.pillW, Theme.barHeight)
        rimFrom: col.roomUp
        rimTo: col.roomUp + Theme.barHeight
        bulge0: col.bulge > 0.05
            ? Qt.vector4d(col.roomUp + col.ax - col.pillX - 13, col.roomUp, 26, Theme.barHeight + col.bulge)
            : Qt.vector4d(0, 0, 0, 0)
    }

    Repeater {
        model: [Theme.glyph.wallpaper, Theme.glyph.satty, Theme.glyph.clipboard]

        Glyph {
            required property int index
            required property string modelData
            x: col.pillX + col.pad + col.iconBox / 2 + index * col.step - width / 2
            y: col.pillY + (Theme.barHeight - height) / 2
            text: modelData
        }
    }

    // --- the popover ---------------------------------------------------------------
    Item {
        width: col.width
        height: col.height
        opacity: col.seen
        transform: Scale {
            origin.x: col.ax
            origin.y: col.fy
            xScale: col.xs
            yScale: col.ys
        }

        ShaderEffect {
            x: -col.x
            y: -col.y
            width: col.stage.width
            height: col.stage.height

            property var blurred: col.blurred
            readonly property size size: Qt.size(width, height)
            readonly property vector4d box: Qt.vector4d(col.x + col.ax - col.bw / 2, col.y + col.by, col.bw, col.bh)
            readonly property real radius: col.br
            readonly property vector4d drop: Qt.vector4d(col.x + col.ax, col.y + col.dropY, col.dropR, 0)
            readonly property real join: col.join
            readonly property real sag: col.sag
            readonly property real clipTop: col.y + col.fy
            readonly property vector4d fill: Qt.vector4d(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, Theme.popupBg.a)
            readonly property real lit: col.lit

            fragmentShader: Qt.resolvedUrl("dew.frag.qsb")
        }

        Item {
            x: col.ax - col.bw / 2
            y: col.by
            width: col.bw
            height: col.bh + Math.max(0, col.sag)
            clip: true

            Column {
                x: (col.bw - col.fw) / 2 + 12
                y: col.fy - col.by + 12 + col.sag * 0.4
                width: col.fw - 24
                spacing: 12
                opacity: col.ink
                layer.enabled: col.smear > 0.01
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: col.smear
                    blurMax: 24
                }

                Text {
                    text: "Sound"
                    color: Theme.label
                    font.family: Settings.font
                    font.pixelSize: Theme.textSize
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: ["Speakers", "Headphones", "HDMI"]

                    Row {
                        required property int index
                        required property string modelData
                        spacing: 10

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: index === 0 ? Theme.label : Theme.label3
                        }
                        Text {
                            text: modelData
                            color: index === 0 ? Theme.label : Theme.label2
                            font.family: Settings.font
                            font.pixelSize: Theme.textSize
                        }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.stroke
                }
                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.sliderTrack

                    Rectangle {
                        width: parent.width * 0.62
                        height: 4
                        radius: 2
                        color: Theme.fg
                    }
                }
                Text {
                    text: "Sound settings…"
                    color: Theme.label2
                    font.family: Settings.font
                    font.pixelSize: Theme.textSize
                }
            }
        }
    }

    Tag {
        anchors.horizontalCenter: parent.horizontalCenter
        y: col.height - height - 10
        text: col.title
    }

    Cursor {
        x: col.ax + 2
        y: col.pillY + Theme.barHeight / 2 + 2
    }
}
