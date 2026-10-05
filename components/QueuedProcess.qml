import QtQuick
import Quickshell.Io

// A process run for a query as it stands, at most one at a time, a beat after
// the query stops moving. qalc, fd, the thumbnailer and cliphist's kin are all
// this shape, and the shape is easy to get subtly wrong — see the notes on
// pump() — so it lives once here.
//
// Set `want` to what the query asks for and bind `command` to `arg`, which is
// what the run in progress was for. Every answer arrives as result(arg, text),
// tagged with its own `arg`, so one that lands after the query has moved on is
// simply not matched by whoever reads it rather than shown against the wrong
// input.
//
// A query that moves while a run is in flight must not mean two of them at
// once, and killing the running one is not the answer: Process.running = false
// sends a signal and returns, so the next start would race the death of the
// last. The new run is queued behind the old one instead, and everything this
// is used for finishes in tens of milliseconds, so the queue is never more than
// one deep.
Process {
    id: root

    // What the query asks for. "" asks for nothing and stops the clock.
    property string want: ""
    // What the run in progress, or the last one, was for.
    property string arg: ""
    // How long `want` has to hold still before it is acted on.
    property int interval: 60
    property bool cancelled: false

    signal result(string arg, string text)

    // Held as a property rather than a child: a Process has no default
    // property to put one in.
    readonly property Timer debounce: Timer {
        interval: root.interval
        onTriggered: root.pump()
    }

    onWantChanged: {
        if (root.want)
            root.debounce.restart();
        else {
            root.debounce.stop();
            if (root.running)
                root.cancelled = true;
            else
                root.arg = "";
        }
    }

    // Only the debounce calls this. An exiting run that finds newer work
    // waiting restarts the clock rather than starting that work itself —
    // otherwise the debounce would only ever hold back the first run, and
    // every one after it would launch the moment the last exited. Typing
    // steadily would then mean a process per exit for as long as you typed,
    // which is the thing a debounce is there to stop.
    function pump(): void {
        if (root.running || root.want === root.arg)
            return;
        root.arg = root.want;
        root.cancelled = false;
        if (root.arg)
            root.running = true;
    }

    // For a box that is closing: a clock that outlived it would spawn its
    // process against a query nobody is looking at any more. Clearing `want`
    // also means the run in flight, if any, finds nothing queued behind it.
    function cancel(): void {
        root.want = "";
        root.debounce.stop();
        if (root.running)
            root.cancelled = true;
        else
            root.arg = "";
    }

    onExited: {
        // Keep arg intact until its stdout is collected, then forget that run.
        if (root.cancelled) {
            root.arg = "";
            root.cancelled = false;
        }
        if (root.want && root.want !== root.arg)
            root.debounce.restart();
    }

    stdout: StdioCollector {
        onStreamFinished: root.result(root.arg, text)
    }
}
