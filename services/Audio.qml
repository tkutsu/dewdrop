pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs

// Output device state for the bar.
//
// Volume, mute and the active sink come straight from PipeWire, so they update
// without a poll and without a subprocess per change — that is the bulk of what
// taskbar-audio.sh was paying for.
//
// What PipeWire does not expose through Quickshell is *port availability*, and
// that is the whole point of the old script: an analog jack with nothing in it
// should read as disconnected rather than as "speakers". So one long-lived
// `pactl subscribe` supplies the events and a one-shot `pactl list sinks`
// answers the port question, only when something about a sink actually moved —
// not on every volume tick, which is what the shell version did.
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volume: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property string description: sink?.description || "Audio output"

    // Bluetooth sinks have no jack to detect, and being connected is the whole
    // point of them, so they skip the availability check entirely.
    readonly property bool bluetooth: (sink?.properties?.["device.api"] ?? "") === "bluez5"

    property bool portAvailable: false

    readonly property bool connected: !!sink && sink.name !== "auto_null" && (bluetooth || portAvailable)
    // 0% is silent either way, so it is dimmed like muted.
    readonly property bool silent: muted || volume <= 0

    // The level as how far its waves have lit, and the same speaker whatever
    // it is playing through: which output is on is the popup's to say. It
    // used to be a headphones or a loudspeaker glyph for those ports, which
    // named the device and threw the level away.
    readonly property string icon: connected ? level(volume, muted) : Theme.glyph.audioOff

    // The same speaker for anything with a volume: the popup's rows for each
    // app draw theirs with it too, and so does the music popup. 0% is the
    // empty speaker, and each step after it is a sixth of the way to 100;
    // anything boosted past 100 is the last.
    function level(percent: int, isMuted: bool): string {
        if (isMuted)
            return Theme.glyph.muted;
        const steps = Theme.glyph.vol;
        const last = steps.length - 1;
        return steps[Math.max(0, Math.min(last, Math.ceil(percent * last / 100)))];
    }

    // Everything the machine could play through, for the popup to choose
    // between: what pavucontrol's output tab was opened for.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSink).sort((a, b) => (a.description || a.name).localeCompare(b.description || b.name))

    // Every app playing right now, each with its own volume. Picked by type
    // rather than by media.class, which like the rest of `properties` stays
    // empty until a node is tracked. A playing app counts as a sink here
    // (it is Audio | Stream | Sink), so `isSink` does not tell playback
    // from capture; the type does.
    readonly property var outStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream && n.audio)

    // The ones not paused. A browser keeps a stream open for every tab that
    // has made a sound, playing or not, and pipewire-pulse marks the idle
    // ones corked. Only these get a row; the popup still tracks all of
    // `outStreams`, or a stream's properties would empty out the moment it
    // was hidden and it could never read as playing again.
    readonly property var streams: outStreams.filter(n => String(n.properties?.["pulse.corked"]) !== "true")

    function appName(node): string {
        const props = node.properties ?? {};
        return props["application.name"] || node.description || node.name;
    }

    function toggleMute(): void {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function setDefault(node): void {
        Pipewire.preferredDefaultAudioSink = node;
    }

    // The name of the sink when there is one, whether or not anything is
    // plugged into it: an unplugged jack is still the output the machine would
    // use. (This was written as a conditional that returned `description` from
    // both of its branches.)
    readonly property string tooltip: sink ? description : "No audio output"

    // One notch of the wheel, up or down. Through volumecontrol.sh rather than
    // setVolume: the script owns the step-snapping and the media keys call it
    // too, so there is one definition of what a step is.
    function step(up) {
        Quickshell.execDetached([Paths.script("volumecontrol.sh"), up ? "--inc" : "--dec"]);
    }

    // The same step for one app's stream, which the script cannot reach (it
    // only speaks to the default sink): up or down to the next multiple of
    // five, unmuting on the way as the script does.
    function stepNode(node, up: bool): void {
        const audio = node?.audio;
        if (!audio)
            return;
        const percent = Math.round(audio.volume * 100);
        const next = up ? (Math.floor(percent / 5) + 1) * 5 : Math.floor((percent - 1) / 5) * 5;
        audio.muted = false;
        audio.volume = Math.max(0, Math.min(100, next)) / 100;
    }

    function setVolume(fraction) {
        if (sink?.audio)
            sink.audio.volume = Math.max(0, Math.min(1, fraction));
    }

    // Keep the sink's bindings alive; without this `audio` and `description`
    // stay empty. Only the default one: nothing here reads any of the others.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    onSinkChanged: probe.reload()

    Process {
        id: probe
        command: ["pactl", "--format=json", "list", "sinks"]

        // A burst of pactl events can land while the probe is already out. The
        // debounce collapses those into one reload() that then finds `running`
        // still true and drops it, leaving the port state stale until some
        // unrelated sink event comes along — which, for a jack that was just
        // plugged in, is the one event that mattered. Remember the miss instead
        // and go again on the way out.
        property bool stale: false

        function reload() {
            if (running)
                stale = true;
            else
                running = true;
        }

        onExited: {
            if (stale) {
                stale = false;
                running = true;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const name = root.sink?.name;
                if (!name)
                    return;
                let sinks;
                try {
                    sinks = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const entry = sinks.find(s => s.name === name);
                const port = entry?.ports?.find(p => p.name === entry.active_port);
                // Ports without jack detection (S/PDIF) report "unknown" and so
                // read as disconnected, which is what we want here: the analog
                // outs are the ones actually in use on this box.
                root.portAvailable = port?.availability === "available";
            }
        }
    }

    // The event feed. pactl fires a burst per change, so the reload is debounced
    // rather than run once per line.
    Process {
        id: subscription
        running: true
        command: ["pactl", "subscribe"]
        onExited: subscriptionRetry.restart()
        // A hot reload destroys this object but leaves the subprocess running,
        // reparented to init, and pulse only accepts so many clients before it
        // starts refusing them — at which point the bar loses the sink and
        // every volume command fails. Hand it back on the way out.
        Component.onDestruction: running = false

        stdout: SplitParser {
            onRead: function (line) {
                if (/ on (sink|server|card) /.test(line))
                    debounce.restart();
            }
        }
    }

    Timer {
        id: debounce
        interval: 50
        onTriggered: probe.reload()
    }

    Timer {
        id: subscriptionRetry
        interval: 1000
        onTriggered: {
            subscription.running = true;
            probe.reload();
        }
    }

    Component.onCompleted: probe.reload()
}
