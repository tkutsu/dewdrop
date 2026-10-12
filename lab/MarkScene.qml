import QtQuick
import qs
import qs.components

// Two lens strengths for the spring-driven workspace mark over the pill
// and its icons, switching workspaces on the same beat.
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
            model: 2

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

    Flow { row: 0; bend: 4; bendDepth: 5; tint: 0.2; title: "B1 · today's mark, glass" }
    Flow { row: 1; bend: 7; bendDepth: 6; tint: 0.14; title: "B2 · stronger lens" }

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
