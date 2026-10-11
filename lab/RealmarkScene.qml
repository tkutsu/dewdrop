import QtQuick
import qs
import qs.components

// The real thing: a Pill of mock workspaces whose mark is a real FlowMark,
// drawn by a real BeadMark over a strip as tall as the bar's window, the way
// Bar.qml has it. The workspaces step on a script, as MarkScene's do.
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
    readonly property int gap: Theme.workspaceGap
    function groupW(n) {
        return n * iconSize + (n - 1) * Theme.appIconGap;
    }
    readonly property var groupX: {
        const xs = [];
        let x = 0;
        for (const g of icons) {
            xs.push(x);
            x += groupW(g.length) + gap;
        }
        return xs;
    }

    readonly property var path: [0, 1, 2, 4, 3, 0, 4, 1]
    property int step: 0
    readonly property int current: path[step]
    Timer {
        running: true
        repeat: true
        interval: 1150
        onTriggered: scene.step = (scene.step + 1) % scene.path.length
    }

    // The bar's window, as tall as Bar.stripHeight.
    Item {
        id: win
        y: 20
        width: scene.width
        height: Theme.barHeight + 2 * Theme.barInset

        Item {
            x: 40
            width: pill.implicitWidth
            height: parent.height

            Pill {
                id: pill
                side: Pill.Side.Centre
                backdrop: scene.backdrop

                BarItem {
                    Item {
                        id: strip
                        implicitWidth: scene.groupX[scene.icons.length - 1] + scene.groupW(scene.icons[scene.icons.length - 1].length)
                        implicitHeight: Theme.barHeight

                        FlowMark {
                            id: mark
                            opacity: 0
                            x: -Theme.pillPad
                            width: strip.width + Theme.pillPad * 2
                            height: strip.height
                            slabY: Theme.pillTop(strip.height)
                            slabHeight: Theme.barHeight
                            atFirst: scene.current === 0
                            atLast: scene.current === scene.icons.length - 1
                            wallLeft: Theme.pillBorder
                            wallRight: strip.width + Theme.pillPad * 2 - Theme.pillBorder
                            wantLeft: scene.groupX[scene.current] + inset
                            wantRight: scene.groupX[scene.current] + scene.groupW(scene.icons[scene.current].length) + Theme.pillPad * 2 - inset
                            Component.onCompleted: Qt.callLater(() => mark.placed = true)
                        }

                        Repeater {
                            model: scene.icons

                            Row {
                                required property var modelData
                                required property int index
                                x: scene.groupX[index]
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.appIconGap

                                Repeater {
                                    model: parent.modelData
                                    Image {
                                        required property string modelData
                                        width: scene.iconSize
                                        height: scene.iconSize
                                        sourceSize.width: 64
                                        source: "file://" + modelData
                                        mipmap: true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        BeadMark {
            anchors.fill: parent
            mark: mark
            pillItem: pill.parent
            wallpaperItem: scene.backdrop
        }
    }
}
