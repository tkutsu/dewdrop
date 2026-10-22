import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services

// A fixed song envelope with independent bass, mid and treble reactions.
Scope {
    id: root

    property bool active: false
    property bool playing: false
    readonly property var samples: root.filePath ? WaveformCache.samples : []
    readonly property var reactions: root.filePath ? WaveformCache.reactions : []
    property real position: Mpd.playbackElapsed
    property real bass: 0
    property real mid: 0
    property real treble: 0
    readonly property string filePath: Mpd.musicDir && Mpd.file && !Mpd.file.includes("://") ? Mpd.musicDir + Mpd.file : ""
    readonly property string wanted: active ? filePath : ""
    readonly property string loaded: root.filePath ? WaveformCache.loaded : ""

    NumberAnimation {
        id: settlePulse
        target: root
        properties: "bass,mid,treble"
        to: 0
        duration: Theme.reduceMotion ? 0 : Theme.fadeMs
        easing.type: Easing.OutQuad
    }

    // Keep one decoder at a time; the singleton retains the last completed song.
    function sync(): void {
        if (decode.processId > 0) {
            if (decode.target !== root.wanted)
                decode.running = false;
        } else if (root.wanted && root.wanted !== root.loaded) {
            decode.target = root.wanted;
            decode.running = true;
        }
    }

    onFilePathChanged: {
        settlePulse.stop();
        root.bass = root.mid = root.treble = 0;
        root.position = Mpd.playbackElapsed;
    }
    onWantedChanged: sync()
    onPlayingChanged: {
        settlePulse.stop();
        root.position = Mpd.playbackElapsed;
        if (!root.playing)
            settlePulse.restart();
    }
    Component.onCompleted: sync()
    Component.onDestruction: decode.running = false

    FrameAnimation {
        running: root.playing && root.loaded === root.filePath && root.reactions.length > 0 && WaveformCache.step > 0
        onTriggered: {
            root.position = Mpd.playbackElapsed + (Date.now() - Mpd.playbackSampledAt) / 1000;
            const at = Math.max(0, root.position / WaveformCache.step);
            const index = Math.floor(at);
            const a = root.reactions[index] ?? [0, 0, 0];
            const b = root.reactions[index + 1] ?? [0, 0, 0];
            const blend = at - index;
            root.bass = a[0] + (b[0] - a[0]) * blend;
            root.mid = a[1] + (b[1] - a[1]) * blend;
            root.treble = a[2] + (b[2] - a[2]) * blend;
        }
    }

    Process {
        id: decode
        property string target: ""
        command: ["python3", "-I", Quickshell.shellPath("scripts/music-waveform.py"), target]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.wanted !== decode.target)
                    return;
                try {
                    const result = JSON.parse(text);
                    if (Array.isArray(result.bars) && result.bars.length === 256 && result.bars.every(value => Number.isFinite(value) && value >= 0 && value <= 1)
                            && Number.isFinite(result.step) && result.step > 0
                            && Array.isArray(result.reactions) && result.reactions.length > 0
                            && result.reactions.every(frame => Array.isArray(frame) && frame.length === 3
                                && frame.every(value => Number.isFinite(value) && value >= 0 && value <= 1))) {
                        WaveformCache.samples = result.bars;
                        WaveformCache.reactions = result.reactions;
                        WaveformCache.step = result.step;
                        WaveformCache.loaded = decode.target;
                    }
                } catch (_) {}
            }
        }
        onExited: if (root.wanted && root.wanted !== target)
            Qt.callLater(root.sync)
    }
}
