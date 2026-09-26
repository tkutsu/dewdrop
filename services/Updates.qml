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
    readonly property bool loading: checkOfficial.running || checkAur.running

    function refresh() {
        for (const p of [checkOfficial, checkAur, countOfficial, countAur])
            if (!p.running)
                p.running = true;
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

        command: ["checkupdates"]
        stdout: StdioCollector {
            onStreamFinished: checkOfficial.out = text
        }

        onExited: function (exitCode) {
            if (exitCode !== 0 && exitCode !== 2)
                return;
            root.officialList = root.lines(checkOfficial.out);
            root.official = root.officialList.length;
            root.loaded = true;
        }
    }

    // yay is the looser of the two: `-Qua` exits 1 both for "no AUR updates"
    // and for an RPC call that did not land, so the pair cannot be told apart
    // here the way checkupdates' can. Anything past those two codes is still
    // worth refusing — and the official half, which is the bulk of the count,
    // is guarded properly.
    Process {
        id: checkAur

        property string out: ""

        command: ["yay", "-Qua"]
        stdout: StdioCollector {
            onStreamFinished: checkAur.out = text
        }

        onExited: function (exitCode) {
            if (exitCode !== 0 && exitCode !== 1)
                return;
            root.aurList = root.lines(checkAur.out);
            root.aur = root.aurList.length;
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

    Timer {
        interval: 6 * 60 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
