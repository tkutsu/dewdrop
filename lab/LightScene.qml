import QtQuick
import qs
import qs.components

// The pointer's light on the glass (reel 10), kept quiet: it comes up only as
// the pointer nears a pill, trails it on a soft spring, and goes when it
// leaves. The top row has none, to compare against.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    // Where the pointer is, in a row's own pixels.
    property real px: 200
    property real py: 15

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        ParallelAnimation {
            NumberAnimation { target: scene; property: "px"; to: 300; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 14; duration: 500 }
        }
        NumberAnimation { target: scene; property: "px"; to: 470; duration: 1600; easing.type: Easing.InOutSine }
        ParallelAnimation {
            NumberAnimation { target: scene; property: "px"; to: 560; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 24; duration: 700; easing.type: Easing.InOutSine }
        }
        NumberAnimation { target: scene; property: "px"; to: 650; duration: 500; easing.type: Easing.InSine }
        PauseAnimation { duration: 400 }
        NumberAnimation { target: scene; property: "px"; to: 380; duration: 1200; easing.type: Easing.InOutSine }
        ParallelAnimation {
            NumberAnimation { target: scene; property: "px"; to: 200; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { target: scene; property: "py"; to: 15; duration: 900 }
        }
        PauseAnimation { duration: 300 }
    }

    Column {
        x: 24
        y: 40
        spacing: 32

        LightRow { mode: 0; title: "none (today)" }
        LightRow { mode: 1; title: "1 · rim nearest the pointer" }
        LightRow { mode: 2; title: "2 · rim facing the pointer" }
        LightRow { mode: 3; title: "3 · a sheen under it" }
    }

    component LightRow: Item {
        id: row

        required property int mode
        required property string title

        width: 660
        height: Theme.barHeight

        Tag {
            anchors.verticalCenter: parent.verticalCenter
            text: row.title
        }

        Lit {
            x: 280
            width: 190
            Text {
                anchors.centerIn: parent
                text: "Sun 11 Oct     01:20"
                color: Theme.fg
                font.family: Settings.font
                font.pixelSize: Theme.textSize
            }
        }

        Lit {
            x: 478
            width: 128
            Row {
                anchors.centerIn: parent
                spacing: 16
                Repeater {
                    model: [Theme.glyph.wallpaper, Theme.glyph.satty, Theme.glyph.clipboard]
                    Glyph {
                        required property string modelData
                        text: modelData
                    }
                }
            }
        }

        Cursor {
            x: scene.px
            y: scene.py
        }
    }

    // A pill whose glass takes the pointer's light.
    component Lit: Item {
        id: pill

        default property alias content: inside.data
        readonly property int room: 6
        readonly property int mode: parent.mode

        height: Theme.barHeight

        // How near the pointer is: 1 on the pill, nothing 60px off it.
        readonly property real near: {
            const dx = Math.max(x - scene.px, 0, scene.px - (x + width));
            const dy = Math.max(-scene.py, 0, scene.py - height);
            return Math.max(0, 1 - Math.hypot(dx, dy) / 60);
        }
        property real strength: near
        Behavior on strength {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutQuad
            }
        }
        // The light trails the pointer.
        property real lx: scene.px - x
        property real ly: scene.py
        Behavior on lx {
            SpringAnimation {
                spring: 3
                damping: 0.6
            }
        }
        Behavior on ly {
            SpringAnimation {
                spring: 3
                damping: 0.6
            }
        }

        LabGlass {
            x: -pill.room
            y: -pill.room
            width: pill.width + 2 * pill.room
            height: pill.height + 2 * pill.room
            backdrop: scene.backdrop
            box0: Qt.vector4d(pill.room, pill.room, pill.width, pill.height)
            rimFrom: pill.room
            rimTo: pill.room + pill.height
            light: Qt.vector4d(pill.room + pill.lx, pill.room + pill.ly, pill.mode > 0 ? pill.strength : 0, pill.mode)
        }

        Item {
            id: inside
            anchors.fill: parent
        }
    }
}
