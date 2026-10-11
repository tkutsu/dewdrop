import QtQuick
import qs
import qs.components

// The real Popup, opening (G2), scrolling its list under its header
// (ScrollUnder) and closing, anchored to a pill in the lab's window. The lab
// borrows the bar's layer name for this scene (Lab.qml), so Hyprland blurs
// behind the popup as it does behind the bar's.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 400 }
        ScriptAction { script: { pop.requestedVisible = true; pop.visible = true; } }
        PauseAnimation { duration: 900 }
        NumberAnimation { target: list; property: "contentY"; to: 220; duration: 1600; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 300 }
        NumberAnimation { target: list; property: "contentY"; to: 0; duration: 1200; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 300 }
        ScriptAction { script: pop.requestedVisible = false }
        PauseAnimation { duration: 160 }
        ScriptAction { script: pop.visible = false }
        PauseAnimation { duration: 700 }
    }

    Item {
        x: (scene.width - 128) / 2
        y: 10
        width: 128
        height: Theme.barHeight + 2 * Theme.barInset

        Pill {
            side: Pill.Side.Centre
            backdrop: scene.backdrop

            BarItem { Glyph { text: Theme.glyph.wallpaper } }
            BarItem {
                id: anchor
                Glyph { text: Theme.glyph.clipboard }
            }
            BarItem { Glyph { text: Theme.glyph.web } }
        }
    }

    Popup {
        id: pop

        anchorItem: anchor
        visible: false
        spacing: 6

        PopupHeader {
            width: 280
            z: 1
            title: "Notifications"
        }

        ListView {
            id: list

            width: 280
            height: 200
            clip: true
            interactive: false
            spacing: 6
            model: [["Messages", "Maya: Just got back from Thailand", "#34c759"], ["Mail", "Your order has shipped", "#0a84ff"], ["Calendar", "Standup in 10 minutes", "#ff453a"], ["Music", "Now playing: Bohren & der Club of Gore", "#ff2d55"], ["Updates", "12 packages can be upgraded", "#ff9f0a"], ["Messages", "Lunch tomorrow?", "#34c759"], ["Mail", "Invoice 2026-10", "#0a84ff"], ["Weather", "Rain from 4 pm", "#64d2ff"]]

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 44
                radius: Theme.selectionRadius + 2
                color: Qt.rgba(1, 1, 1, 0.07)

                Rectangle {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 6
                    color: modelData[2]
                }
                Column {
                    x: 44
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: modelData[0]
                        color: Theme.label
                        font.family: Settings.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: modelData[1]
                        color: Theme.label2
                        font.family: Settings.font
                        font.pixelSize: 12
                    }
                }
            }

            ScrollUnder {
                parent: list
                view: list
                box: pop.chromeItem
            }
        }
    }
}
