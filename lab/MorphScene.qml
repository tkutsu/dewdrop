import QtQuick
import QtQuick.Effects
import qs
import qs.components

// The music pill turning into its popover rather than opening one (the
// morph reel), three ways, opening and closing on the same beat:
//
//   M1  pour: the pill stays; the popover pours out from under it through
//       a neck that pinches off as it lands
//   M2  island: the pill itself grows, in place, into the popover, the way
//       the Dynamic Island opens; its own contents blur out as the
//       popover's blur in
//   M3  reel: the pill squeezes into a drop where it was clicked, and the
//       drop falls and swells, bell first, into the popover below the bar
//
// All one piece of glass (lab/morph.frag): clear where it is the pill,
// frost where it is the popover.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property bool open: false
    SequentialAnimation {
        running: true
        loops: Animation.Infinite
        PauseAnimation { duration: 500 }
        PropertyAction { target: scene; property: "open"; value: true }
        PauseAnimation { duration: 1700 }
        PropertyAction { target: scene; property: "open"; value: false }
        PauseAnimation { duration: 1000 }
    }

    Row {
        Column3 { variant: "M1"; title: "M1 · pour" }
        Column3 { variant: "M2"; title: "M2 · island" }
        Column3 { variant: "M3"; title: "M3 · reel" }
    }

    component Column3: Item {
        id: col

        required property string variant
        required property string title

        width: 340
        height: scene.height

        // The pill, at rest.
        readonly property real pw: 196
        readonly property real ph: Theme.barHeight
        readonly property real px: (width - pw) / 2
        readonly property real py: 10
        // The popover, open.
        readonly property real fw: 272
        readonly property real fh: 150
        readonly property real fx: (width - fw) / 2
        readonly property real fy: variant === "M2" ? py : py + ph + Theme.popupGap + 4
        readonly property real fr: 14

        // What is drawn now.
        property real pillW: pw
        property real pillX: px
        property real bx: px
        property real by: py
        property real bw: 0
        property real bh: 0
        property real br: fr
        property real join: 0
        property real bell: 0
        property real frost: 0
        property real pillInk: 1
        property real panelInk: 0

        function rest() {
            pillW = pw; pillX = px; bw = 0; bh = 0; join = 0; bell = 0; frost = 0; pillInk = 1; panelInk = 0;
        }
        Component.onCompleted: rest()

        Connections {
            target: scene
            function onOpenChanged() {
                for (const a of [openM1, closeM1, openM2, closeM2, openM3, closeM3])
                    a.stop();
                const run = { M1: [openM1, closeM1], M2: [openM2, closeM2], M3: [openM3, closeM3] }[col.variant];
                run[scene.open ? 0 : 1].start();
            }
        }

        // --- M1: pour ----------------------------------------------------
        SequentialAnimation {
            id: openM1
            ScriptAction { script: { col.bx = col.px + col.pw / 2 - 30; col.by = col.py + col.ph - 16; col.bw = 60; col.bh = 16; col.br = 8; col.join = 14; } }
            ParallelAnimation {
                NumberAnimation { target: col; property: "by"; to: col.fy; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: col; property: "bx"; to: col.fx; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                NumberAnimation { target: col; property: "br"; to: col.fr; duration: 200 }
                SequentialAnimation {
                    PauseAnimation { duration: 170 }
                    NumberAnimation { target: col; property: "join"; to: 0; duration: 200; easing.type: Easing.InQuad }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 150 }
                    NumberAnimation { target: col; property: "panelInk"; to: 1; duration: 260; easing.type: Easing.OutQuad }
                }
            }
        }
        SequentialAnimation {
            id: closeM1
            NumberAnimation { target: col; property: "panelInk"; to: 0; duration: 90 }
            ParallelAnimation {
                NumberAnimation { target: col; property: "join"; to: 14; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: col; property: "by"; to: col.py + col.ph - 16; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bx"; to: col.px + col.pw / 2 - 30; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bw"; to: 60; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bh"; to: 16; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "br"; to: 8; duration: 240 }
            }
            ScriptAction { script: col.rest() }
        }

        // --- M2: island ----------------------------------------------------
        SequentialAnimation {
            id: openM2
            ScriptAction { script: { col.bx = col.px; col.by = col.py; col.bw = col.pw; col.bh = col.ph; col.br = col.ph / 2; col.pillW = 0; } }
            ParallelAnimation {
                NumberAnimation { target: col; property: "pillInk"; to: 0; duration: 120 }
                NumberAnimation { target: col; property: "bx"; to: col.fx; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                NumberAnimation { target: col; property: "br"; to: col.fr; duration: 260; easing.type: Easing.OutQuad }
                NumberAnimation { target: col; property: "frost"; to: 1; duration: 260 }
                SequentialAnimation {
                    PauseAnimation { duration: 170 }
                    NumberAnimation { target: col; property: "panelInk"; to: 1; duration: 260; easing.type: Easing.OutQuad }
                }
            }
        }
        SequentialAnimation {
            id: closeM2
            NumberAnimation { target: col; property: "panelInk"; to: 0; duration: 90 }
            ParallelAnimation {
                NumberAnimation { target: col; property: "bx"; to: col.px; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: col; property: "bw"; to: col.pw; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: col; property: "bh"; to: col.ph; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: col; property: "br"; to: col.ph / 2; duration: 260 }
                NumberAnimation { target: col; property: "frost"; to: 0; duration: 260 }
                SequentialAnimation {
                    PauseAnimation { duration: 160 }
                    NumberAnimation { target: col; property: "pillInk"; to: 1; duration: 160 }
                }
            }
            ScriptAction { script: col.rest() }
        }

        // --- M3: reel ------------------------------------------------------
        SequentialAnimation {
            id: openM3
            ParallelAnimation {
                NumberAnimation { target: col; property: "pillInk"; to: 0; duration: 100 }
                NumberAnimation { target: col; property: "pillW"; to: 40; duration: 150; easing.type: Easing.InOutCubic }
                NumberAnimation { target: col; property: "pillX"; to: col.px + col.pw / 2 - 20; duration: 150; easing.type: Easing.InOutCubic }
            }
            ScriptAction { script: { col.bx = col.px + col.pw / 2 - 20; col.by = col.py; col.bw = 40; col.bh = col.ph; col.br = col.ph / 2; col.pillW = 0; col.bell = 0.7; } }
            ParallelAnimation {
                NumberAnimation { target: col; property: "by"; to: col.fy; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: col; property: "bh"; to: col.fh; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                NumberAnimation { target: col; property: "bx"; to: col.fx; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                NumberAnimation { target: col; property: "bw"; to: col.fw; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                NumberAnimation { target: col; property: "br"; to: col.fr; duration: 260 }
                NumberAnimation { target: col; property: "bell"; to: 0; duration: 300; easing.type: Easing.OutQuad }
                NumberAnimation { target: col; property: "frost"; to: 1; duration: 220 }
                SequentialAnimation {
                    PauseAnimation { duration: 160 }
                    NumberAnimation { target: col; property: "panelInk"; to: 1; duration: 260; easing.type: Easing.OutQuad }
                }
            }
        }
        SequentialAnimation {
            id: closeM3
            NumberAnimation { target: col; property: "panelInk"; to: 0; duration: 90 }
            ParallelAnimation {
                NumberAnimation { target: col; property: "by"; to: col.py; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bh"; to: col.ph; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bx"; to: col.px + col.pw / 2 - 20; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "bw"; to: 40; duration: 240; easing.type: Easing.InCubic }
                NumberAnimation { target: col; property: "br"; to: col.ph / 2; duration: 240 }
                NumberAnimation { target: col; property: "bell"; to: 0.5; duration: 240 }
                NumberAnimation { target: col; property: "frost"; to: 0; duration: 240 }
            }
            ScriptAction { script: { col.pillW = 40; col.pillX = col.px + col.pw / 2 - 20; col.bw = 0; col.bell = 0; } }
            ParallelAnimation {
                NumberAnimation { target: col; property: "pillW"; to: col.pw; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: col; property: "pillX"; to: col.px; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                SequentialAnimation {
                    PauseAnimation { duration: 100 }
                    NumberAnimation { target: col; property: "pillInk"; to: 1; duration: 160 }
                }
            }
            ScriptAction { script: col.rest() }
        }

        // --- drawing ---------------------------------------------------------
        ShaderEffect {
            anchors.fill: parent

            property var backdrop: scene.backdrop
            property var blurred: scene.blurred
            readonly property size size: Qt.size(width, height)
            readonly property point origin: Qt.point(col.x, 0)
            readonly property size stage: Qt.size(scene.backdrop.width, scene.backdrop.height)
            readonly property vector4d pill: Qt.vector4d(col.pillX, col.py, col.pillW, col.ph)
            readonly property vector4d panel: Qt.vector4d(col.bx, col.by, col.bw, col.bh)
            readonly property real panelRadius: col.br
            readonly property real join: col.join
            readonly property real bell: col.bell
            readonly property real frost: col.frost
            readonly property real frostFrom: col.variant === "M1" ? col.py + col.ph + 2 : 1e5
            readonly property vector4d clearTint: Qt.vector4d(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, Theme.glassTint)
            readonly property vector4d frostTint: Qt.vector4d(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, Theme.popupBg.a)
            readonly property vector4d rimTop: Qt.vector4d(Theme.pillRimTop.r, Theme.pillRimTop.g, Theme.pillRimTop.b, Theme.pillRimTop.a)
            readonly property vector4d rimBottom: Qt.vector4d(Theme.rimBottom.r, Theme.rimBottom.g, Theme.rimBottom.b, Theme.rimBottom.a)
            readonly property real bend: 8

            fragmentShader: Qt.resolvedUrl("morph.frag.qsb")
        }

        // The pill's contents: the controls and the song, blurred as they go.
        Item {
            id: pillContent
            x: col.px
            y: col.py
            width: col.pw
            height: col.ph
            visible: false

            Row {
                anchors.centerIn: parent
                spacing: 10
                Glyph { text: Theme.glyph.mediaPrev; anchors.verticalCenter: parent.verticalCenter }
                Glyph { text: Theme.glyph.playing; anchors.verticalCenter: parent.verticalCenter }
                PopupText { text: "Bohren & der Club of Gore"; font.pixelSize: Theme.captionSize + 1; anchors.verticalCenter: parent.verticalCenter }
                Glyph { text: Theme.glyph.mediaNext; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        MultiEffect {
            source: pillContent
            x: pillContent.x
            y: pillContent.y
            width: pillContent.width
            height: pillContent.height
            opacity: col.pillInk
            blurEnabled: true
            blur: 1 - col.pillInk
            blurMax: 24
            scale: 0.9 + 0.1 * col.pillInk
        }

        // The popover's contents.
        Item {
            id: panelContent
            x: col.fx
            y: col.fy
            width: col.fw
            height: col.fh
            visible: false

            Row {
                x: 14
                y: 14
                spacing: 12
                Rectangle {
                    width: 64
                    height: 64
                    radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#3a4a6a" }
                        GradientStop { position: 1; color: "#111522" }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    PopupText { text: "Prowler"; font.weight: Font.DemiBold }
                    PopupText { text: "Bohren & der Club of Gore"; color: Theme.label2; font.pixelSize: Theme.captionSize }
                }
            }
            Rectangle {
                x: 14
                y: 92
                width: col.fw - 28
                height: 4
                radius: 2
                color: Theme.sliderTrack
                Rectangle { width: parent.width * 0.4; height: parent.height; radius: 2; color: Theme.fg }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 110
                spacing: 34
                Glyph { text: Theme.glyph.mediaPrev }
                Glyph { text: Theme.glyph.playing }
                Glyph { text: Theme.glyph.mediaNext }
            }
        }
        MultiEffect {
            source: panelContent
            x: panelContent.x
            y: panelContent.y
            width: panelContent.width
            height: panelContent.height
            opacity: col.panelInk
            blurEnabled: true
            blur: 1 - col.panelInk
            blurMax: 32
            scale: 0.94 + 0.06 * col.panelInk
            transformOrigin: Item.Top
        }

        Tag {
            x: 10
            y: col.height - 34
            text: col.title
        }
    }
}
