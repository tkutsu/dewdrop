import QtQuick
import qs
import qs.components

// A slider's knob turning into a bead of glass while it is held (reel 4),
// three ways, on one script: take hold, drag right, drag left, let go.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property real value: 0.3
    property bool down: false

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 500 }
        PropertyAction { target: scene; property: "down"; value: true }
        PauseAnimation { duration: 350 }
        NumberAnimation { target: scene; property: "value"; to: 0.8; duration: 750; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 300 }
        NumberAnimation { target: scene; property: "value"; to: 0.3; duration: 950; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 350 }
        PropertyAction { target: scene; property: "down"; value: false }
        PauseAnimation { duration: 800 }
    }

    // The sound popup's frost, standing still.
    ShaderEffect {
        anchors.fill: parent

        property var blurred: scene.blurred
        readonly property size size: Qt.size(width, height)
        readonly property vector4d box: Qt.vector4d(20, 20, scene.width - 40, scene.height - 40)
        readonly property real radius: Theme.popupRadius
        readonly property vector4d fill: Qt.vector4d(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, Theme.popupBg.a)
        readonly property real lit: 0

        fragmentShader: Qt.resolvedUrl("frost.frag.qsb")
    }

    Rim {
        x: 20
        y: 20
        width: scene.width - 40
        height: scene.height - 40
        radius: Theme.popupRadius
    }

    Column {
        x: 40
        y: 40
        spacing: 22

        BeadRow { variant: "A"; title: "A · capsule lens" }
        BeadRow { variant: "B"; title: "B · round magnifier" }
        BeadRow { variant: "C"; title: "C · liquid: stretches with the drag" }
    }

    component BeadRow: Column {
        id: row

        required property string variant
        required property string title

        spacing: 6

        Text {
            text: row.title
            color: Theme.label2
            font.family: Settings.font
            font.pixelSize: 12
        }

        Item {
            id: slider

            // The real Slider's size; the item is taller so the bead has
            // room to stand above and below the track.
            readonly property int trackHeight: 4
            readonly property int knob: 12
            width: 300
            height: 32

            readonly property real cx: Math.max(knob / 2, Math.min(width - knob / 2, scene.value * width))

            // How big the bead is when held, and how it bends.
            readonly property size held: row.variant === "B" ? Qt.size(22, 22) : Qt.size(34, 20)
            readonly property real bend: row.variant === "B" ? 3 : 4
            readonly property real magnify: row.variant === "B" ? 2.2 : 1.6

            // How fast the knob is going, in pixels a second, eased so that
            // the stretch follows the drag without shivering.
            property real speed: 0
            property real last: scene.value
            FrameAnimation {
                running: row.variant === "C"
                onTriggered: {
                    const v = (scene.value - slider.last) * slider.width / Math.max(frameTime, 0.001);
                    slider.last = scene.value;
                    slider.speed += (v - slider.speed) * 0.3;
                }
            }
            readonly property real stretch: row.variant === "C" && scene.down ? Math.min(16, Math.abs(speed) * 0.03) : 0

            property real bw: scene.down ? held.width + stretch : knob
            property real bh: scene.down ? held.height - stretch * 0.35 : knob
            Behavior on bw {
                SpringAnimation {
                    spring: 6
                    damping: row.variant === "C" ? 0.22 : 0.4
                    epsilon: 0.05
                }
            }
            Behavior on bh {
                SpringAnimation {
                    spring: 6
                    damping: row.variant === "C" ? 0.22 : 0.4
                    epsilon: 0.05
                }
            }
            property real clear: scene.down ? 1 : 0
            Behavior on clear {
                NumberAnimation {
                    duration: scene.down ? 140 : 200
                    easing.type: Easing.OutQuad
                }
            }

            // The track alone, for the shader to draw through the bead.
            Item {
                id: track

                anchors.fill: parent

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: slider.trackHeight
                    radius: height / 2
                    color: Theme.sliderTrack

                    Item {
                        width: parent.width * scene.value
                        height: parent.height
                        clip: true

                        Rectangle {
                            width: slider.width
                            height: parent.height
                            radius: height / 2
                            color: Theme.fg
                        }
                    }
                }
            }

            ShaderEffectSource {
                id: trackTexture

                sourceItem: track
                hideSource: true
                visible: false
            }

            ShaderEffect {
                anchors.fill: parent

                property var source: trackTexture
                readonly property size size: Qt.size(width, height)
                readonly property vector4d bead: Qt.vector4d(slider.cx - slider.bw / 2, (height - slider.bh) / 2, slider.bw, slider.bh)
                readonly property real clear: slider.clear
                readonly property real bend: slider.bend
                readonly property real magnify: 1 + (slider.magnify - 1) * slider.clear
                readonly property real dispersion: Theme.glassDispersion
                readonly property vector4d knob: Qt.vector4d(Theme.fg.r, Theme.fg.g, Theme.fg.b, Theme.fg.a)
                readonly property vector4d knobEdge: Qt.vector4d(Theme.knobEdge.r, Theme.knobEdge.g, Theme.knobEdge.b, Theme.knobEdge.a)

                fragmentShader: Qt.resolvedUrl("bead.frag.qsb")
            }

            Cursor {
                x: slider.cx + 3
                y: slider.height / 2 + 3
                down: scene.down
            }
        }
    }
}
