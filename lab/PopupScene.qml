import QtQuick
import QtQuick.Effects
import qs
import qs.components

// A popover opening and closing under its pill, four ways. A is what the bar
// does now. The popup's window starts under the pill (Popup.qml keeps it off
// the pill for the pointer's sake), so every one of these grows from the
// pill's foot rather than from inside it.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property bool open: false

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 600 }
        PropertyAction { target: scene; property: "open"; value: true }
        PauseAnimation { duration: 1600 }
        PropertyAction { target: scene; property: "open"; value: false }
        PauseAnimation { duration: 900 }
    }

    Row {
        Proto { variant: "A"; title: "A · now: fade + 6px slide" }
        Proto { variant: "B"; title: "B · scale from the item" }
        Proto { variant: "C"; title: "C · buds out of a capsule" }
        Proto { variant: "D"; title: "D · drips, then spreads" }
    }

    component Proto: Item {
        id: col

        required property string variant
        required property string title

        width: 300
        height: scene.height

        readonly property int step: 38
        readonly property int pad: 15
        readonly property int iconBox: 22
        readonly property real pillW: pad * 2 + step * 2 + iconBox
        readonly property real pillX: (width - pillW) / 2
        readonly property real pillY: 10
        readonly property int room: 6
        // The middle icon opens the popup, and the popup centres on it.
        readonly property real ax: width / 2

        // The open box.
        readonly property real fw: 236
        readonly property real fh: 196
        readonly property real fy: pillY + Theme.barHeight + Theme.popupGap

        // What is drawn now: the box's size (centred under the item, hung
        // from fy), its corner, how lit and how visible it is, how far it
        // has slid, how big it is, and its contents' fade and blur.
        property real bw: fw
        property real bh: fh
        property real br: Theme.popupRadius
        property real lit: 0
        property real seen: 0
        property real slide: 0
        property real grow: 1
        property real ink: 0
        property real smear: 0

        Component.onCompleted: shut()
        function shut() {
            seen = 0;
            ink = 0;
            if (variant === "A") {
                slide = -6;
            } else if (variant === "B") {
                grow = 0.86;
            } else if (variant === "C") {
                bw = 46;
                bh = 26;
                br = 13;
                lit = 0.3;
                smear = 1;
            } else {
                bw = 14;
                bh = 14;
                br = 7;
                smear = 1;
            }
        }

        Connections {
            target: scene
            function onOpenChanged() {
                const a = {
                    A: [openA, closeA],
                    B: [openB, closeB],
                    C: [openC, closeC],
                    D: [openD, closeD]
                }[col.variant];
                a[scene.open ? 1 : 0].stop();
                a[scene.open ? 0 : 1].start();
            }
        }

        // A: the shell's Popup today.
        ParallelAnimation {
            id: openA
            NumberAnimation { target: col; property: "seen"; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0.2, 1, 1, 1] }
            NumberAnimation { target: col; property: "ink"; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0.2, 1, 1, 1] }
            NumberAnimation { target: col; property: "slide"; to: 0; duration: 280; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            id: closeA
            NumberAnimation { target: col; properties: "seen,ink"; to: 0; duration: 140; easing.type: Easing.InOutQuad }
            NumberAnimation { target: col; property: "slide"; to: -6; duration: 140; easing.type: Easing.InQuad }
        }

        // B: the whole box out of the item, running a little past.
        ParallelAnimation {
            id: openB
            NumberAnimation { target: col; properties: "seen,ink"; to: 1; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: col; property: "grow"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        }
        ParallelAnimation {
            id: closeB
            NumberAnimation { target: col; properties: "seen,ink"; to: 0; duration: 160; easing.type: Easing.InQuad }
            NumberAnimation { target: col; property: "grow"; to: 0.9; duration: 160; easing.type: Easing.InCubic }
        }

        // C: a capsule the size of the item comes out lit, opens sideways
        // then down, and the contents come up sharp as it lands. Back the
        // same way: contents smear out first, then it gathers into the
        // capsule and goes.
        ParallelAnimation {
            id: openC
            NumberAnimation { target: col; property: "seen"; to: 1; duration: 80 }
            NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
            SequentialAnimation {
                PauseAnimation { duration: 50 }
                NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
            NumberAnimation { target: col; property: "br"; to: Theme.popupRadius; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: col; property: "lit"; to: 0; duration: 420; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                ParallelAnimation {
                    NumberAnimation { target: col; property: "ink"; to: 1; duration: 200; easing.type: Easing.OutQuad }
                    NumberAnimation { target: col; property: "smear"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                }
            }
        }
        ParallelAnimation {
            id: closeC
            NumberAnimation { target: col; property: "ink"; to: 0; duration: 110; easing.type: Easing.InQuad }
            NumberAnimation { target: col; property: "smear"; to: 1; duration: 130; easing.type: Easing.InQuad }
            SequentialAnimation {
                PauseAnimation { duration: 40 }
                ParallelAnimation {
                    NumberAnimation { target: col; property: "bh"; to: 26; duration: 220; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: col; property: "bw"; to: 46; duration: 250; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: col; property: "br"; to: 13; duration: 220; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: col; property: "lit"; to: 0.3; duration: 220 }
                }
                NumberAnimation { target: col; property: "seen"; to: 0; duration: 90 }
            }
        }

        // D: a bead falls out of the item, stretches down narrow, then
        // spreads out to the box and wobbles still. Back: narrows, rises
        // into a bead, gone.
        SequentialAnimation {
            id: openD
            ParallelAnimation {
                NumberAnimation { target: col; property: "seen"; to: 1; duration: 60 }
                NumberAnimation { target: col; property: "bh"; to: 70; duration: 130; easing.type: Easing.OutQuad }
                NumberAnimation { target: col; property: "bw"; to: 22; duration: 130; easing.type: Easing.OutQuad }
                NumberAnimation { target: col; property: "br"; to: 11; duration: 130 }
            }
            ParallelAnimation {
                NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                NumberAnimation { target: col; property: "br"; to: Theme.popupRadius; duration: 300; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    PauseAnimation { duration: 140 }
                    ParallelAnimation {
                        NumberAnimation { target: col; property: "ink"; to: 1; duration: 200; easing.type: Easing.OutQuad }
                        NumberAnimation { target: col; property: "smear"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
        SequentialAnimation {
            id: closeD
            ParallelAnimation {
                NumberAnimation { target: col; property: "ink"; to: 0; duration: 90; easing.type: Easing.InQuad }
                NumberAnimation { target: col; property: "smear"; to: 1; duration: 110 }
                NumberAnimation { target: col; property: "bw"; to: 22; duration: 200; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "br"; to: 11; duration: 200 }
            }
            ParallelAnimation {
                NumberAnimation { target: col; property: "bh"; to: 14; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bw"; to: 14; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "br"; to: 7; duration: 150 }
            }
            NumberAnimation { target: col; property: "seen"; to: 0; duration: 70 }
        }

        // --- the pill -------------------------------------------------------
        LabGlass {
            x: col.pillX - col.room
            y: col.pillY - col.room
            width: col.pillW + 2 * col.room
            height: Theme.barHeight + 2 * col.room
            backdrop: scene.backdrop
            box0: Qt.vector4d(col.room, col.room, col.pillW, Theme.barHeight)
            rimFrom: col.room
            rimTo: col.room + Theme.barHeight
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

        // --- the popover ----------------------------------------------------
        Item {
            id: drawn

            width: col.width
            height: col.height
            opacity: col.seen
            transform: [
                Scale {
                    origin.x: col.ax
                    origin.y: col.fy
                    xScale: col.grow
                    yScale: col.grow
                },
                Translate {
                    y: col.slide
                }
            ]

            // The frost fills the stage so that it samples the blur where it
            // stands; only the box is drawn.
            ShaderEffect {
                x: -col.x
                y: -col.y
                width: scene.width
                height: scene.height

                property var blurred: scene.blurred
                readonly property size size: Qt.size(width, height)
                readonly property vector4d box: Qt.vector4d(col.x + col.ax - col.bw / 2, col.y + col.fy, col.bw, col.bh)
                readonly property real radius: col.br
                readonly property vector4d fill: Qt.vector4d(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, Theme.popupBg.a)
                readonly property real lit: col.lit

                fragmentShader: Qt.resolvedUrl("frost.frag.qsb")
            }

            Rim {
                x: col.ax - col.bw / 2
                y: col.fy
                width: col.bw
                height: col.bh
                radius: col.br
            }

            Item {
                x: col.ax - col.bw / 2
                y: col.fy
                width: col.bw
                height: col.bh
                clip: true

                Column {
                    x: (col.bw - col.fw) / 2 + 12
                    y: 12
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
            down: false
        }
    }
}
