pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core

// The caffeine switch, one for the session so every bar's cup agrees. Each bar
// holds its own inhibitor bound to it (modules/IdleInhibit.qml): an inhibitor
// needs a window, and a bar's own follows that bar through hotplug and reload.
//
// It holds the screen until turned off, or for `minutes` from when it was
// turned on: the end is a moment (`until`), so it keeps through a restart.
Singleton {
    id: root

    // Off once the end has passed, even before the file says so: a turn that
    // ran out while the bar was down must not bring the cup back for a tick.
    readonly property bool active: stored.active && !(stored.until > 0 && stored.until <= root.now)
    // How long a turn on lasts, 0 for until turned off.
    readonly property alias minutes: stored.minutes
    // When it turns off, to follow "until": "14:30", or "tomorrow at 14:30"
    // once a turn reaches past midnight, so a day's hold does not read as now.
    readonly property string endsAt: {
        if (!root.active || stored.until <= 0)
            return "";
        const end = new Date(stored.until * 1000);
        const today = new Date(root.now * 1000);
        if (end.toDateString() === today.toDateString())
            return Settings.sayTime(end);
        today.setDate(today.getDate() + 1);
        const day = end.toDateString() === today.toDateString() ? "tomorrow" : Qt.formatDate(end, "ddd d MMM");
        return `${day} at ${Settings.sayTime(end)}`;
    }

    // Seconds since the epoch, moved on by the check below.
    property real now: Date.now() / 1000

    function turn(on: bool): void {
        root.now = Date.now() / 1000;
        stored.until = on && stored.minutes > 0 ? Math.round(root.now) + stored.minutes * 60 : 0;
        stored.active = on;
    }

    function toggle(): void {
        root.turn(!root.active);
    }

    // A new length while on counts from this moment.
    function choose(minutes: int): void {
        stored.minutes = minutes;
        if (root.active)
            root.turn(true);
    }

    // For the keybind (SUPER+J): the cup sits in the drawer while caffeine is
    // off, so the mouse way in is two clicks deep.
    //   qs ipc call caffeine toggle
    IpcHandler {
        target: "caffeine"

        function toggle(): void {
            root.toggle();
        }
    }

    // Checked against the wall clock, not counted down: a Qt timer stands
    // still while the machine sleeps, and the end should not move with it.
    Timer {
        interval: 5000
        repeat: true
        running: stored.active && stored.until > 0
        onTriggered: {
            root.now = Date.now() / 1000;
            if (!root.active)
                root.turn(false);
        }
    }

    // Kept on disk, so it comes back as it was after a reload or a restart.
    // Read before the first bar asks, so the cup never leaves the bar and
    // comes back, and the screen is never let go in between.
    Component.onCompleted: file.text()

    FileView {
        id: file

        path: Paths.state("caffeine.json")
        blockLoading: true
        printErrors: false
        onAdapterUpdated: file.writeAdapter()

        JsonAdapter {
            id: stored

            property bool active: false
            property int minutes: 0
            property real until: 0
        }
    }
}
