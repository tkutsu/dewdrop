import QtQuick
import qs

// Reveal a long title at a steady speed, pausing at both ends for reading.
Item {
    id: root

    default property alias content: line.data
    property string text: ""
    property real contentWidth: 0
    property real maxWidth: 0
    property bool active: Settings.scrollMusicTitles && !Theme.reduceMotion
    readonly property real overflow: Math.max(0, contentWidth - width)
    readonly property bool scrolling: active && visible && width > 0 && overflow > 0
    property real offset: 0
    readonly property real leftFade: scrolling ? Math.min(16, width / 2, offset) : 0
    readonly property real rightFade: scrolling ? Math.min(16, width / 2, overflow - offset) : 0

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
        x: -root.offset
        width: root.contentWidth
        height: root.height
    }

    SequentialAnimation {
        id: motion
        loops: Animation.Infinite
        PauseAnimation { duration: 2000 }
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
