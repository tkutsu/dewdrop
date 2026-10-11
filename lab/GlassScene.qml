import QtQuick
import qs
import qs.components

// Side-by-side prototypes using the bar's production shader. The scripted
// presses share one clock so their depth and spread can be compared directly.
Item {
    id: scene
    required property Item backdrop
    required property Item blurred
    property real dent: 0
    property bool down: false

    SequentialAnimation {
        running: true; loops: Animation.Infinite
        PauseAnimation { duration: 850 }
        PropertyAction { target: scene; property: "down"; value: true }
        NumberAnimation { target: scene; property: "dent"; to: 1; duration: 55; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 130 }
        PropertyAction { target: scene; property: "down"; value: false }
        NumberAnimation { target: scene; property: "dent"; to: 0; duration: 310; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
        PauseAnimation { duration: 1200 }
    }

    Repeater {
        model: [
            {title: "S1  Soft diagonal", detail: "Broad, quiet highlights", sheen: Qt.vector4d(-0.60, -0.80, 0.18, 0.10), press: "P1  Cushion", spread: 160, depth: 0.07},
            {title: "S2  Wide satin", detail: "Widest and faintest", sheen: Qt.vector4d(-0.707, -0.707, 0.10, 0.075), press: "P2  Fabric", spread: 115, depth: 0.18},
            {title: "S3  Steep diagonal", detail: "More vertical light", sheen: Qt.vector4d(-0.42, -0.907, 0.24, 0.09), press: "P3  Deep fabric", spread: 150, depth: 0.24}
        ]
        delegate: Item {
            id: col
            required property var modelData
            required property int index
            x: index * 360
            width: 360; height: scene.height
            Tag { x: 24; y: 18; text: col.modelData.title }
            Tag { x: 24; y: 45; text: col.modelData.detail }

            // At actual bar size, plus a large copy to inspect the corners.
            Liquid {
                x: 18; y: 80; width: 324; height: 42
                backdrop: scene.backdrop; takesPress: false
                box0: Qt.vector4d(6, 6, 312, 30)
                rimFrom: 6; rimTo: 36
                sheen: col.modelData.sheen
            }
            Text {
                x: 24; y: 86; width: 312; height: 30
                text: "Sun 11 Oct     14:10"; color: Theme.fg
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                font.family: Settings.font; font.pixelSize: Theme.textSize
            }
            Liquid {
                x: 18; y: 137; width: 324; height: 66
                backdrop: null; takesPress: false
                fill: Qt.vector4d(0.06, 0.075, 0.08, 1)
                lineWidth: 1.8
                box0: Qt.vector4d(6, 6, 312, 54)
                rimFrom: 6; rimTo: 60
                sheen: col.modelData.sheen
            }
            Tag { x: 24; y: 229; text: col.modelData.press }
            Liquid {
                id: pressedGlass
                x: 18; y: 270; width: 324; height: 42
                backdrop: scene.backdrop; takesPress: false
                box0: Qt.vector4d(6, 6, 312, 30)
                rimFrom: 6; rimTo: 36
                sheen: Qt.vector4d(-0.60, -0.80, 0.18, 0.10)
                deform: Qt.vector4d(119, 21, col.modelData.spread, scene.dent * col.modelData.depth)
            }
            Row {
                id: icons
                x: 52; y: 276; spacing: 38
                Repeater {
                    model: [Theme.glyph.wallpaper, Theme.glyph.satty, Theme.glyph.clipboard, Theme.glyph.web, Theme.glyph.folder]
                    Glyph { required property string modelData; text: modelData; height: 30 }
                }
            }
            Cursor { x: 137; y: 306; visible: scene.down }
            Tag { x: 24; y: 338; text: "55 ms in, 310 ms to settle" }
        }
    }
}
