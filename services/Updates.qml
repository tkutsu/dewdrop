pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Pending package updates. The counts can only come from checkupdates/yay, but
// the 6-hour cycle, the counting and the tooltip are no longer a shell script —
// and nothing pipes through `wc -l` any more.
Singleton {
    id: root

    property int official: 0
    property int aur: 0
    property int officialTotal: 0
    property int aurTotal: 0
    // checkupdates already prints "name old -> new" per line; keeping the lines
    // costs nothing and turns the tooltip into something worth reading.
    property var officialList: []
    property var aurList: []

    readonly property int pending: official + aur
    readonly property string icon: Theme.glyph.update
    // Held at 99 rather than spilling into "99+": the badge is for noticing
    // there is a pile, not for counting it.
    readonly property string label: pending === 0 ? "" : String(Math.min(pending, 99))

    // Nothing has come back yet, or the check is out again: the module dims
    // for both, the way the mail and tasks modules do, so a count of zero
    // is not mistaken for an up-to-date machine.
    property bool loaded: false
    property int checksRemaining: 0
    property string officialTrouble: ""
    property string aurTrouble: ""
    readonly property string trouble: [officialTrouble, aurTrouble].filter(s => s !== "").join(" · ")
    readonly property bool loading: checksRemaining > 0 || checkOfficial.running || checkAur.running
    readonly property bool polling: Settings.moduleOn("updater")
    property bool refreshQueued: false

    onLoadingChanged: if (!root.loading && root.refreshQueued) Qt.callLater(root.flushRefresh)

    function flushRefresh(): void {
        if (root.loading || !root.refreshQueued)
            return;
        root.refreshQueued = false;
        if (root.polling)
            root.refresh();
    }

    onPollingChanged: if (root.polling)
        root.refresh()

    Retry {
        id: recovery
        active: root.polling && !root.loading
        onTriggered: root.refresh()
    }

    function refresh() {
        if (root.loading) {
            root.refreshQueued = true;
            return;
        }
        recovery.cancel();
        root.checksRemaining = 2;
        for (const p of [checkOfficial, checkAur, countOfficial, countAur])
            if (!p.running)
                p.running = true;
    }

    function retryNow(): void {
        recovery.retryNow();
    }

    // Only transport failures are retried; a broken tool still needs fixing.
    function failedCheck(source: string, exitCode: int, stderr: string): string {
        if (exitCode === 124 || /could not resolve|connection|network|timed? out|timeout|temporary failure|TLS|SSL|failed to synchronize|failed to download|error.*(?:request|download)|RPC.*(?:failed|error)/i.test(stderr))
            recovery.schedule();
        return `${source} check failed${exitCode === 124 ? " (timed out)" : ""}`;
    }

    function finishCheck(): void {
        root.checksRemaining--;
        if (root.checksRemaining === 0 && root.trouble === "")
            recovery.reset();
    }

    function lines(text) {
        return text.split("\n").filter(l => l.trim() !== "");
    }

    // checkupdates keeps 2 for "nothing to do" and 1 for a failure it could
    // not work around — most often a database sync with no network behind it.
    // Both come back with nothing on stdout, so the exit code is the only
    // thing that tells them apart, and without it a failed check reads as a
    // clean machine: the badge clears and the icon says up to date.
    //
    // The collector runs before the exit is known (checked against this
    // build), so the text is held and committed once the code is in.
    Process {
        id: checkOfficial

        property string out: ""
        property string err: ""

        command: ["timeout", "90s", "checkupdates"]
        stdout: StdioCollector {
            onStreamFinished: checkOfficial.out = text
        }
        stderr: StdioCollector {
            onStreamFinished: checkOfficial.err = text
        }

        onExited: function (exitCode) {
            if (exitCode !== 0 && exitCode !== 2) {
                root.officialTrouble = root.failedCheck("Official update", exitCode, checkOfficial.err);
            } else {
                root.officialTrouble = "";
                root.officialList = root.lines(checkOfficial.out);
                root.official = root.officialList.length;
                root.loaded = true;
            }
            root.finishCheck();
        }
    }

    // yay uses 1 both for no updates and a failed RPC. Its stderr distinguishes
    // the failed call, which must preserve the previous count and retry.
    Process {
        id: checkAur

        property string out: ""
        property string err: ""

        command: ["timeout", "90s", "yay", "-Qua"]
        stdout: StdioCollector {
            onStreamFinished: checkAur.out = text
        }
        stderr: StdioCollector {
            onStreamFinished: checkAur.err = text
        }

        onExited: function (exitCode) {
            if (exitCode !== 0 && (exitCode !== 1 || checkAur.err.trim() !== "")) {
                root.aurTrouble = root.failedCheck("AUR update", exitCode, checkAur.err);
            } else {
                root.aurTrouble = "";
                root.aurList = root.lines(checkAur.out);
                root.aur = root.aurList.length;
            }
            root.finishCheck();
        }
    }

    Process {
        id: countOfficial
        command: ["pacman", "-Qnq"]
        stdout: StdioCollector {
            onStreamFinished: root.officialTotal = root.lines(text).length
        }
    }

    Process {
        id: countAur
        command: ["pacman", "-Qmq"]
        stdout: StdioCollector {
            onStreamFinished: root.aurTotal = root.lines(text).length
        }
    }

    // So a finished upgrade can say so instead of the bar carrying a stale
    // count until the next six-hourly check:  qs ipc call updates refresh
    IpcHandler {
        target: "updates"

        function refresh(): void {
            root.refresh();
        }
    }

    Connections {
        target: WallClock
        function onWokeUp(): void {
            if (root.polling)
                root.refresh();
        }
    }

    // External pacman/yay transactions also invalidate the installed counts.
    FileView {
        path: "/var/log/pacman.log"
        watchChanges: root.polling
        printErrors: false
        onFileChanged: {
            reload();
            packageChange.restart();
        }
    }

    Timer {
        id: packageChange
        interval: 2000
        onTriggered: if (root.polling) root.refresh()
    }

    Timer {
        interval: 6 * 60 * 60 * 1000
        running: root.polling && !root.loading && !recovery.pending
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: if (root.polling)
        root.refresh()
}
