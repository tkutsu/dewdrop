import QtQuick
import qs
import qs.components

// A slider's knob turning into a bead of glass while it is held (reel 4).
// B: a round bead, bent hard round its rim and nearly true in the middle, at
// three strengths. C: the same bead with a tail that trails it like gel, on
// three springs. One script for all, changing speed on purpose: a slow drag,
// a fast one, a stop, a flick back, a slow drift, let go.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property real value: 0.3
    property bool down: false

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 400 }
        PropertyAction { target: scene; property: "down"; value: true }
        PauseAnimation { duration: 250 }
        NumberAnimation { target: scene; property: "value"; to: 0.45; duration: 700 }
        NumberAnimation { target: scene; property: "value"; to: 0.85; duration: 300; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 450 }
        NumberAnimation { target: scene; property: "value"; to: 0.5; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: scene; property: "value"; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 400 }
        PropertyAction { target: scene; property: "down"; value: false }
        PauseAnimation { duration: 700 }
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
        y: 34
        spacing: 12

        BeadRow { title: "B1 · rim pulls in 11px"; bend: 11; depth: 0.4; steep: 1.5 }
        BeadRow { title: "B2 · rim pulls in 15px: the track curls round the rim"; bend: 15; depth: 0.5; steep: 1.8 }
        BeadRow { title: "B3 · rim pulls in 20px"; bend: 20; depth: 0.6; steep: 2.2 }
        BeadRow { title: "C1 · gel tail, firm"; trails: true; spring: 9; damping: 0.6; tailShare: 0.75; reach: 10 }
        BeadRow { title: "C2 · gel tail, soft, the head thins as it pulls"; trails: true; spring: 5; damping: 0.45; tailShare: 0.6; thins: true; reach: 16 }
        BeadRow { title: "C3 · gel tail, wobbly: runs past and back on a stop"; trails: true; spring: 4; damping: 0.22; tailShare: 0.8; reach: 14 }
    }

    component BeadRow: Column {
        id: row

        required property string title
        // B2's lens unless a row says otherwise.
        property real bend: 15
        property real depth: 0.5
        property real steep: 1.8
        property bool trails: false
        property real spring: 6
        property real damping: 0.4
        property real tailShare: 1
        property bool thins: false
        // The longest the tail gets, in pixels: it eases towards this rather
        // than stopping at it, so a faster drag always pulls it a little more.
        property real reach: 14

        spacing: 4

        Text {
            text: row.title
            color: Theme.label2
            font.family: Settings.font
            font.pixelSize: 12
        }

        Item {
            id: slider

            // The real Slider's track and knob; the item is taller so the
            // bead has room above and below the track.
            readonly property int trackHeight: 4
            readonly property int knob: 12
            readonly property real bead: 22
            width: 300
            height: 32

            readonly property real cx: Math.max(knob / 2, Math.min(width - knob / 2, scene.value * width))

            // The head's radius: the knob's at rest, the bead's when held,
            // on a spring that runs a little past.
            property real r: scene.down ? bead / 2 : knob / 2
            Behavior on r {
                SpringAnimation {
                    spring: 6
                    damping: 0.4
                    epsilon: 0.02
                }
            }
            // The tail: where the head was a moment ago, on a spring, so it
            // trails further the faster the head goes and catches up when it
            // stops.
            property real tailX: cx
            Behavior on tailX {
                enabled: row.trails
                SpringAnimation {
                    spring: row.spring
                    damping: row.damping
                    epsilon: 0.05
                }
            }
            // How far the tail trails, eased into its reach.
            readonly property real lag: row.reach * Math.tanh((tailX - cx) / row.reach)
            readonly property real pull: Math.abs(lag)
            readonly property real headR: r * (row.thins ? 1 - 0.18 * Math.min(1, pull / bead) : 1)
            readonly property real tailR: row.trails ? Math.min(headR, r * row.tailShare + (r - r * row.tailShare) * Math.max(0, 1 - pull / 6)) : headR

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
                readonly property vector4d head: Qt.vector4d(slider.cx, height / 2, slider.headR, 0)
                readonly property vector4d tail: Qt.vector4d(slider.cx + slider.lag, height / 2, slider.tailR, 0)
                readonly property real clear: slider.clear
                readonly property real bend: row.bend * slider.clear
                readonly property real depth: row.depth
                readonly property real steep: row.steep
                readonly property real magnify: 1
                readonly property real dispersion: Theme.glassDispersion
                readonly property vector4d knob: Qt.vector4d(Theme.fg.r, Theme.fg.g, Theme.fg.b, Theme.fg.a)
                readonly property vector4d knobEdge: Qt.vector4d(Theme.knobEdge.r, Theme.knobEdge.g, Theme.knobEdge.b, Theme.knobEdge.a)

                fragmentShader: Qt.resolvedUrl("bead.frag.qsb")
            }

            Cursor {
                x: slider.cx + 3
                y: slider.height / 2 + 4
                down: scene.down
            }
        }
    }
}
