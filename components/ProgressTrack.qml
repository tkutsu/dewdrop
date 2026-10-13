import QtQuick
import qs

// A capsule progress outline, updated by distance travelled rather than per frame.
ShaderEffect {
    id: root
    required property Item slab
    property real progress: -1
    property real trackOpacity: 1
    property color trackColor: Theme.fg
    property real trackWidth: Theme.pillTrack

    // Clockwise distance along the middle of the track, for its progress clock.
    readonly property real trackRadius: Math.min(slab.width, slab.height) / 2 - trackWidth / 2
    readonly property real trackLength: 2 * Math.abs(slab.width - slab.height) + 2 * Math.PI * trackRadius

    // How fast `progress` runs on its own, per second, while whatever it
    // measures is running; 0 while it stands still. The owner only says where
    // it is once a second, and the pill carries the line on in between, so it
    // creeps round rather than stepping a pixel at a time.
    property real rate: 0

    // How much of that line is lit. Not a Behavior: the elapsed time arrives
    // once a second, and a one-second Behavior restarted every second never
    // finishes — the bar redrew at the monitor's refresh rate for as long as
    // anything played (4.6% CPU against 0.2%, measured), re-stroking the dash
    // pattern every frame. Moved on by `creep` instead, a quarter of a pixel
    // at a time: under what the eye can call a step, and a few redraws a
    // second rather than a hundred and twenty.
    property real lit: root.trackLength * Math.max(0, Math.min(1, root.progress + root.drift))

    // How far the line has been carried past the last `progress`, capped at a
    // second's worth so that a late update stalls it rather than overshoots.
    property real drift: 0
    property real since: 0

    function settle() {
        root.since = Date.now();
        root.drift = 0;
    }

    onProgressChanged: settle()
    // And from a pause, which would otherwise count the whole of it as time
    // the line should have been moving.
    onRateChanged: settle()

    Timer {
        id: creep

        readonly property real pxPerSecond: Math.abs(root.rate) * root.trackLength

        interval: pxPerSecond > 0 ? Math.max(16, Math.min(1000, 250 / pxPerSecond)) : 1000
        repeat: true
        running: root.visible && root.rate !== 0 && root.progress >= 0 && root.opacity > 0
        onTriggered: root.drift = root.rate * Math.min(1, (Date.now() - root.since) / 1000)
    }

    // Tracks wait for the glass to settle; disappear immediately when it moves.
    property bool trackReady: true
    property real trackReveal: 0
    onTrackReadyChanged: {
        trackFade.stop();
        if (trackReady && !Theme.reduceMotion) {
            trackReveal = 0;
            trackFade.start();
        }
        else
            trackReveal = trackReady ? 1 : 0;
    }
    NumberAnimation {
        id: trackFade
        target: root; property: "trackReveal"; to: 1
        duration: 240; easing.type: Easing.InOutCubic
    }

    // Use the glass's rounded-box distance directly, avoiding a second curve renderer.
    readonly property int room: 1
    x: slab.x - room
    y: slab.y - room
    width: slab.width + 2 * room
    height: slab.height + 2 * room
    visible: root.progress >= 0 && opacity > 0
    opacity: root.trackOpacity * root.trackReveal
    property size size: Qt.size(width, height)
    property size slabSize: Qt.size(slab.width, slab.height)
    property real lineWidth: root.trackWidth
    property real played: root.lit / Math.max(root.trackLength, 1)
    property color ink: root.trackColor
    property real rest: Theme.pillTrackRest
    property real foot: Theme.pillTrackFoot
    fragmentShader: Qt.resolvedUrl("../shaders/track.frag.qsb")

    Component.onCompleted: root.trackReveal = root.trackReady ? 1 : 0
}
