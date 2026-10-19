import QtQuick
import qs

// Reveal a long title at a steady speed, pausing at both ends for reading.
Item {
    id: root

    default property alias content: line.data
    property string text: ""
    property real contentWidth: 0
    property real maxWidth: 0
    property bool hovered: false
    property bool active: (Settings.scrollMusicTitles || root.hovered) && !Theme.reduceMotion
    property bool paused: false
    readonly property real overflow: Math.max(0, contentWidth - width)
    readonly property bool overflowing: visible && width > 0 && overflow > 0
    readonly property bool scrolling: active && !paused && overflowing
    property real offset: 0
    // Extra travel lets a contracting media pill draw text behind its icon.
    property real travel: 0
    // Pausing motion still leaves overflowing text clipped at the edges.
    readonly property real leftFade: overflowing ? Math.min(16, width / 2, offset + travel) : 0
    readonly property real rightFade: overflowing ? Math.max(0, Math.min(16, width / 2, overflow - offset - travel)) : 0

    implicitWidth: maxWidth > 0 ? Math.min(contentWidth, maxWidth) : contentWidth
    clip: true

    // Fade the title into the glass only where text extends past an edge.
    layer.enabled: root.leftFade > 0 || root.rightFade > 0
    layer.effect: ShaderEffect {
        readonly property real span: width
        readonly property real fadeLeft: root.leftFade
        readonly property real fadeRight: root.rightFade
        fragmentShader: Qt.resolvedUrl("../shaders/query-edge.frag.qsb")
    }

    // Track, width and visibility changes start with the beginning in view.
    function restart() {
        motion.stop();
        root.offset = 0;
        if (root.scrolling)
            motion.start();
    }

    onTextChanged: restart()
    onOverflowChanged: restart()
    onScrollingChanged: restart()
    Component.onCompleted: restart()

    Item {
        id: line
        x: -root.offset - root.travel
        width: root.contentWidth
        height: root.height
    }

    SequentialAnimation {
        id: motion
        loops: Animation.Infinite
        // Hover reveals the hidden text immediately; automatic scrolling waits for reading.
        PauseAnimation { duration: root.hovered ? 0 : 2000 }
        NumberAnimation {
            target: root
            property: "offset"
            to: root.overflow
            duration: Math.ceil(root.overflow / 22 * 1000)
        }
        PauseAnimation { duration: 2000 }
        NumberAnimation {
            target: root
            property: "offset"
            to: 0
            duration: Math.ceil(root.overflow / 22 * 1000)
        }
    }
}
