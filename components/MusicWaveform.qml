import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services

// A fixed song envelope, with pulses timed to detected audio onsets.
Scope {
    id: root

    property bool active: false
    property bool playing: false
    readonly property var samples: root.filePath ? WaveformCache.samples : []
    readonly property var beats: root.filePath ? WaveformCache.beats : []
    property real position: Mpd.playbackElapsed
    property real pulse: 0
    readonly property string filePath: Mpd.file && !Mpd.file.includes("://") ? Mpd.musicDir + Mpd.file : ""
    readonly property string wanted: active ? filePath : ""
    readonly property string loaded: root.filePath ? WaveformCache.loaded : ""

    NumberAnimation {
        id: settlePulse
        target: root
        property: "pulse"
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
        if (root.loaded === root.filePath)
            settlePulse.stop();
        else
            settlePulse.restart();
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
        running: root.playing && root.loaded === root.filePath && root.samples.length > 0 && root.beats.length > 0
        onTriggered: {
            root.position = Mpd.playbackElapsed + (Date.now() - Mpd.playbackSampledAt) / 1000;
            let low = 0, high = root.beats.length;
            while (low < high) {
                const mid = (low + high) >> 1;
                if (root.beats[mid] <= root.position)
                    low = mid + 1;
                else
                    high = mid;
            }
            const age = low ? root.position - root.beats[low - 1] : 1;
            root.pulse = age < 0.35 ? 1.8 * (1 - Math.exp(-age / 0.02)) * Math.exp(-age / 0.12) : 0;
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
                            && Array.isArray(result.beats) && result.beats.every(value => Number.isFinite(value) && value >= 0)) {
                        WaveformCache.samples = result.bars;
                        WaveformCache.beats = result.beats;
                        WaveformCache.loaded = decode.target;
                    }
                } catch (_) {}
            }
        }
        onExited: if (root.wanted && root.wanted !== target)
            Qt.callLater(root.sync)
    }
}
