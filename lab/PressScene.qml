import QtQuick
import qs
import qs.components

// Press feedback, four ways, on one script: a held press, a quick double
// tap, a short press. A is what the bar does now.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    // Which icon the pointer is over, fractional on the way, and whether it
    // is held.
    property real at: 1
    property bool down: false

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 400 }
        NumberAnimation { target: scene; property: "at"; to: 2; duration: 420; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 160 }
        PropertyAction { target: scene; property: "down"; value: true }
        PauseAnimation { duration: 800 }
        PropertyAction { target: scene; property: "down"; value: false }
        PauseAnimation { duration: 600 }
        NumberAnimation { target: scene; property: "at"; to: 3; duration: 340; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 140 }
        PropertyAction { target: scene; property: "down"; value: true }
        PauseAnimation { duration: 100 }
        PropertyAction { target: scene; property: "down"; value: false }
        PauseAnimation { duration: 130 }
        PropertyAction { target: scene; property: "down"; value: true }
        PauseAnimation { duration: 100 }
        PropertyAction { target: scene; property: "down"; value: false }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: scene; property: "at"; to: 0; duration: 520; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 140 }
        PropertyAction { target: scene; property: "down"; value: true }
        PauseAnimation { duration: 380 }
        PropertyAction { target: scene; property: "down"; value: false }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: scene; property: "at"; to: 1; duration: 400; easing.type: Easing.InOutCubic }
    }

    Column {
        x: 24
        y: 26
        spacing: 24

        PressRow { variant: "A"; title: "A · now: a pixel's dip" }
        PressRow { variant: "B"; title: "B · light from the contact" }
        PressRow { variant: "C" ; title: "C · a bead of glass inside" }
        PressRow { variant: "D"; title: "D · light, and the pill swells" }
    }

    component PressRow: Item {
        id: row

        required property string variant
        required property string title

        readonly property var icons: [Theme.glyph.wallpaper, Theme.glyph.satty, Theme.glyph.clipboard, Theme.glyph.web, Theme.glyph.folder]
        readonly property int step: 38
        readonly property int iconBox: 22
        readonly property int pad: 15
        readonly property real pillX: 330
        readonly property real pillW: pad * 2 + step * (icons.length - 1) + iconBox
        // Room round the slab for the glass to swell into.
        readonly property int room: 6
        function centre(i) {
            return pad + iconBox / 2 + i * step;
        }
        readonly property real contactX: centre(scene.at)

        // The icon the press landed on, kept after release so it settles
        // where it was pressed even as the pointer moves on.
        property int held: -1
        Connections {
            target: scene
            function onDownChanged() {
                if (scene.down)
                    row.held = Math.round(scene.at);
            }
        }

        // How lit the glass is: on at once, off slowly.
        property real lit: scene.down ? 1 : 0
        Behavior on lit {
            NumberAnimation {
                duration: scene.down ? 80 : 450
                easing.type: scene.down ? Easing.OutQuad : Easing.OutCubic
            }
        }
        // How far the press has pushed into it, on a spring that runs past
        // on the way back.
        property real pop: scene.down ? 1 : 0
        Behavior on pop {
            SpringAnimation {
                spring: 5
                damping: 0.26
                epsilon: 0.002
            }
        }

        width: 600
        height: Theme.barHeight

        Tag {
            anchors.verticalCenter: parent.verticalCenter
            text: row.title
        }

        LabGlass {
            x: row.pillX - row.room
            y: -row.room
            width: row.pillW + 2 * row.room
            height: Theme.barHeight + 2 * row.room
            backdrop: scene.backdrop
            box0: Qt.vector4d(row.room, row.room, row.pillW, Theme.barHeight)
            rimFrom: row.room
            rimTo: row.room + Theme.barHeight
            press: row.variant === "B" || row.variant === "D"
                ? Qt.vector4d(row.room + row.centre(row.held), row.room + Theme.barHeight / 2 + 4, 24, row.lit)
                : row.variant === "C" ? Qt.vector4d(row.room + row.centre(row.held), row.room + Theme.barHeight / 2, 18, row.lit * 0.35)
                : Qt.vector4d(0, 0, 1, 0)
            bulge0: row.variant === "D"
                ? Qt.vector4d(row.room + row.centre(row.held) - 20, row.room - 3 * row.pop, 40, Theme.barHeight + 6 * row.pop)
                : Qt.vector4d(0, 0, 0, 0)
        }

        // C: a lighter piece of glass under the icon, out from the contact.
        Rectangle {
            visible: row.variant === "C" && opacity > 0
            x: row.pillX + row.centre(row.held) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: Theme.barHeight - 8
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.1 + 0.08 * row.lit)
            scale: 0.5 + 0.5 * row.pop
            opacity: row.lit

            Rim {
                anchors.fill: parent
                radius: parent.radius
                topColor: Theme.markRimTop
            }
        }

        Repeater {
            model: row.icons

            Glyph {
                required property int index
                required property string modelData

                readonly property bool pressed: index === row.held
                x: row.pillX + row.centre(index) - width / 2
                y: (Theme.barHeight - height) / 2 + (row.variant === "A" && pressed && scene.down ? Theme.pressDip : 0)
                text: modelData
                color: pressed && row.variant !== "A" ? Qt.rgba(1, 1, 1, 0.85 + 0.15 * row.lit) : Theme.fg
                scale: !pressed || row.variant === "A" ? 1 : 1 + (row.variant === "D" ? 0.1 : row.variant === "B" ? 0.08 : 0.05) * row.pop
            }
        }

        Cursor {
            x: row.pillX + row.contactX - 1
            y: Theme.barHeight / 2 + 2
            down: scene.down
        }
    }
}
