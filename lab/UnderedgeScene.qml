import QtQuick
import QtQuick.Effects
import qs
import qs.components

// A popup's list scrolling on under its header (reel 7), four ways, on one
// scroll down and back. S0 is the soft fade the branch has now.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property real scroll: 0

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 500 }
        NumberAnimation { target: scene; property: "scroll"; to: 1; duration: 2200; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: scene; property: "scroll"; to: 0; duration: 1800; easing.type: Easing.InOutSine }
    }

    Row {
        UnderColumn { mode: 0; title: "S0 · fade (now)" }
        UnderColumn { mode: 1; title: "S1 · under, blurred" }
        UnderColumn { mode: 2; title: "S2 · under, blurred, bent" }
        UnderColumn { mode: 3; title: "S3 · S2 under a glass band" }
    }

    component UnderColumn: Item {
        id: col

        required property int mode
        required property string title

        width: 300
        height: scene.height

        readonly property rect box: Qt.rect(20, 16, 260, 236)
        readonly property int header: 40
        readonly property int pad: 10

        // The popup's frost.
        ShaderEffect {
            x: -col.x
            width: scene.width
            height: scene.height

            property var blurred: scene.blurred
            readonly property size size: Qt.size(width, height)
            readonly property vector4d box: Qt.vector4d(col.x + col.box.x, col.box.y, col.box.width, col.box.height)
            readonly property real radius: Theme.popupRadius
            readonly property vector4d fill: Qt.vector4d(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, Theme.popupBg.a)
            readonly property real lit: 0

            fragmentShader: Qt.resolvedUrl("frost.frag.qsb")
        }

        Rim {
            x: col.box.x
            y: col.box.y
            width: col.box.width
            height: col.box.height
            radius: Theme.popupRadius
        }

        // The list's viewport: under the header too, except in S0, where it
        // starts below it and fades at its edges as the branch does now.
        Item {
            id: viewport

            x: col.box.x + col.pad
            y: col.mode === 0 ? col.box.y + col.header : col.box.y + 4
            width: col.box.width - 2 * col.pad
            height: col.box.y + col.box.height - 4 - y
            clip: true
            layer.enabled: col.mode === 0
            layer.effect: ShaderEffect {
                readonly property real span: height
                readonly property real fadeTop: Math.min(Theme.scrollEdge, scene.scroll * 200)
                readonly property real fadeBottom: Math.min(Theme.scrollEdge, (1 - scene.scroll) * 200)
                fragmentShader: Qt.resolvedUrl("../shaders/edge.frag.qsb")
            }

            Column {
                id: cards

                // The rows start below the header in every mode, so the list
                // at rest is the same list.
                y: (col.mode === 0 ? 0 : col.header - 4) - scene.scroll * 200
                width: parent.width
                spacing: 6

                Repeater {
                    model: [["Messages", "Maya: Just got back from Thailand", "#34c759"], ["Mail", "Your order has shipped", "#0a84ff"], ["Calendar", "Standup in 10 minutes", "#ff453a"], ["Music", "Now playing: Bohren & der Club of Gore", "#ff2d55"], ["Updates", "12 packages can be upgraded", "#ff9f0a"], ["Messages", "Lunch tomorrow?", "#34c759"], ["Mail", "Invoice 2026-10", "#0a84ff"], ["Weather", "Rain from 4 pm", "#64d2ff"]]

                    Rectangle {
                        required property var modelData
                        width: cards.width
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
                }
            }
        }

        // What runs under the header: the list as drawn, and blurred.
        ShaderEffectSource {
            id: sharp
            sourceItem: viewport
            hideSource: col.mode > 0
            visible: false
        }
        MultiEffect {
            id: blur
            visible: false
            width: viewport.width
            height: viewport.height
            source: sharp
            blurEnabled: true
            blur: 1
            blurMax: 28
            autoPaddingEnabled: false
        }
        ShaderEffectSource {
            id: blurredList
            sourceItem: blur
            visible: false
            live: true
        }

        ShaderEffect {
            visible: col.mode > 0
            x: viewport.x
            y: viewport.y
            width: viewport.width
            height: viewport.height

            property var sharp: sharp
            property var blurred: blurredList
            readonly property size size: Qt.size(width, height)
            readonly property real edge: col.header - 4
            readonly property real soft: 6
            readonly property real bend: col.mode >= 2 ? 14 : 0
            readonly property real reach: 20
            readonly property real steep: 2
            readonly property real through: 0.65
            readonly property vector4d band: col.mode === 3 ? Qt.vector4d(0.04, 0.04, 0.04, 0.12) : Qt.vector4d(0, 0, 0, 0)
            readonly property real lit: col.mode === 3 ? 0.12 : 0

            fragmentShader: Qt.resolvedUrl("under.frag.qsb")
        }

        // The header, over everything.
        Item {
            x: col.box.x + col.pad
            y: col.box.y
            width: col.box.width - 2 * col.pad
            height: col.header

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Theme.label
                font.family: Settings.font
                font.pixelSize: Theme.textSize
                font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                height: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, 0.08)
                Rim {
                    anchors.fill: parent
                    radius: parent.radius
                }
                Text {
                    anchors.centerIn: parent
                    text: "clear"
                    color: Theme.label
                    font.family: Settings.font
                    font.pixelSize: 12
                }
            }
        }

        Tag {
            anchors.horizontalCenter: parent.horizontalCenter
            y: col.height - height - 8
            text: col.title
        }
    }
}
