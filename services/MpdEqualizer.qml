pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Keep unapplied edits alive while the music popup is closed or MPD reconnects.
Singleton {
    id: root

    readonly property var frequencies: [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var labels: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    // Listening curves, not measurements or corrections for a particular headphone.
    readonly property var presets: [
        {label: "Flat", value: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]},
        {label: "Rock", value: "Rock", gains: [4, 3, 2, 0, -2, -1, 1, 3, 4, 3]},
        {label: "Techno", value: "Techno", gains: [5, 4, 2, 0, -2, 0, 2, 3, 4, 3]},
        {label: "Classical", value: "Classical", gains: [2, 1, 0, 0, -1, -1, 0, 1, 2, 2]},
        {label: "Bass", value: "Bass", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]},
        {label: "Vocals", value: "Vocals", gains: [-2, -2, -1, 0, 1, 3, 4, 2, 0, -1]},
        {label: "Bright", value: "Bright", gains: [0, 0, 0, 0, 0, 1, 2, 3, 4, 4]},
        {label: "Jazz", value: "Jazz", gains: [3, 2, 1, 0, -1, 0, 1, 2, 3, 2]},
        {label: "Headphones", value: "Headphones", gains: [2, 1, 0, -1, -1, 0, 1, 0, -1, -2]}
    ]
    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property var saved: []
    property string fingerprint: ""
    property string error: ""
    property bool ready: false
    property bool legacy: false
    property bool busy: false
    readonly property bool dirty: ready && JSON.stringify(gains) !== JSON.stringify(saved)
    readonly property string preset: presets.find(p => JSON.stringify(p.gains) === JSON.stringify(root.gains))?.value ?? "Custom"

    function load(): void {
        if (root.busy || root.dirty)
            return;
        root.error = "";
        worker.applying = false;
        worker.received = false;
        worker.exited = false;
        root.busy = true;
        worker.running = true;
    }

    function setBand(index: int, gain: real): void {
        if (!root.ready || root.busy)
            return;
        const next = root.gains.slice();
        next[index] = Math.round(Math.max(-12, Math.min(12, gain)) * 2) / 2;
        root.gains = next;
    }

    function choose(name: string): void {
        const selected = root.presets.find(p => p.value === name);
        if (selected && root.ready && !root.busy)
            root.gains = selected.gains.slice();
    }

    function reset(): void {
        if (!root.busy) {
            if (root.saved.length === 10)
                root.gains = root.saved.slice();
            root.error = "";
            root.load();
        }
    }

    function apply(): void {
        if (!root.dirty || root.busy)
            return;
        root.error = "";
        worker.applying = true;
        worker.received = false;
        worker.exited = false;
        root.busy = true;
        worker.running = true;
    }

    Process {
        id: worker
        property bool applying: false
        property bool received: false
        property bool exited: false
        function finish(): void {
            if (received && exited)
                root.busy = false;
        }
        command: ["python3", "-I", Quickshell.shellPath("scripts/mpd-equalizer.py"),
            applying ? "apply" : "read", "--config", Settings.mpdConfig,
            "--socket", Settings.mpdSocket].concat(applying ? ["--gains", JSON.stringify(root.gains), "--fingerprint", root.fingerprint] : [])
        stdout: StdioCollector {
            onStreamFinished: {
                worker.received = true;
                try {
                    const result = JSON.parse(text);
                    if (result.error) {
                        root.error = result.error;
                        if (!worker.applying)
                            root.ready = false;
                    } else {
                        root.error = "";
                        root.gains = result.gains;
                        root.saved = result.gains.slice();
                        root.fingerprint = result.fingerprint;
                        root.legacy = result.legacy;
                        root.ready = true;
                    }
                } catch (e) {
                    root.error = "Could not read equalizer settings.";
                }
                worker.finish();
            }
        }
        onExited: (code, status) => {
            worker.exited = true;
            if (code !== 0 && !root.error)
                root.error = "Could not update the equalizer.";
            worker.finish();
        }
    }
}
