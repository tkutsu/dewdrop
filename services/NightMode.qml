pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Night mode and monitor backlight, both over DDC/CI (VCP 0x10).
//
// SUPER+Z runs display.sh too, so the script has to stay whatever the bar does
// — and it, not the bar, owns what a toggle means: hyprsunset temperature,
// ddcutil, the brightness cache, and the one lock that keeps a toggle from
// landing in the middle of a scroll. Reimplementing that here would just give
// it a second definition to drift from.
//
// What does change: the old module re-ran a script every 5 seconds to find out
// what the state was. The flag files are watched instead, so a toggle from
// either the keybind or the bar shows up at once and nothing runs in between.
Singleton {
    id: root


    property bool on: false
    property int brightness: 100
    property bool automatic: false
    property int startMinute: 22 * 60
    property int endMinute: 7 * 60
    property bool restored: false
    property bool flagKnown: false

    readonly property string icon: on ? Theme.glyph.nightOn : Theme.glyph.nightOff
    // The panel is dimmed to 0 whenever night mode goes on, so a dark screen is
    // what the mode looks like from outside; say that rather than "Brightness 0%".
    // Scrolling to 0 by hand is not the mode, so key this off the flag, not the level.
    // On Auto it says what comes next, as Control Center does: "Night mode on
    // until 07:00", "Brightness 80% · night mode off until 22:00". A manual
    // change holds until the next boundary, so that is the end when on and the
    // start when off.
    readonly property string tooltip: (on ? "Night mode on" : `Brightness ${brightness}%`)
        + (!automatic ? "" : on ? ` until ${formatTime(endMinute)}` : ` · night mode off until ${formatTime(startMinute)}`)

    // Off, On or Auto, as the popup's choice shows it. A pick holds while
    // display.sh runs: the flag only moves once the DDC write lands, and until
    // then the choice would light the mode being left.
    property string asked: ""
    readonly property string mode: asked || (automatic ? "auto" : on ? "on" : "off")

    function formatTime(minute) {
        return ("0" + Math.floor(minute / 60)).slice(-2) + ":" + ("0" + minute % 60).slice(-2);
    }

    function parseTime(text) {
        if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(text))
            return -1;
        const parts = text.split(":");
        return Number(parts[0]) * 60 + Number(parts[1]);
    }

    // Compare local times, including ranges that cross midnight. The end is exclusive.
    function scheduledOn(at) {
        const date = new Date(at);
        const minute = date.getHours() * 60 + date.getMinutes();
        return startMinute < endMinute ? minute >= startMinute && minute < endMinute
            : minute >= startMinute || minute < endMinute;
    }

    function setAutomatic(enabled) {
        if (root.automatic === enabled)
            return;
        root.automatic = enabled;
        memory.applied = -1;
        root.resetScheduleRetry();
        root.saveSchedule();
        root.checkSchedule();
    }

    // Auto hands the mode to the schedule. Off and On take it back, and a pick
    // made while the last one is still landing goes next.
    function setMode(mode) {
        root.setAutomatic(mode === "auto");
        root.asked = mode === "auto" || (!chooser.running && root.on === (mode === "on")) ? "" : mode;
        if (root.asked && !chooser.running)
            root.choose();
    }

    function choose() {
        chooser.command = [Paths.script("display.sh"), root.asked === "on" ? "night-on" : "night-off"];
        chooser.running = true;
    }

    Process {
        id: chooser
        onExited: function (code) {
            nightFlag.reload();
            nightFlag.waitForJob();
            if (code === 0 && root.asked && root.on !== (root.asked === "on"))
                return root.choose();
            root.asked = "";
            root.checkSchedule();
        }
    }

    function setSchedule(start, end) {
        const from = root.parseTime(start), to = root.parseTime(end);
        if (from < 0 || to < 0 || from === to)
            return false;
        root.startMinute = from;
        root.endMinute = to;
        root.resetScheduleRetry();
        root.saveSchedule();
        root.checkSchedule();
        return true;
    }

    property var pendingSchedule: []

    // Debounce the whole range here so closing the popup cannot discard an edit.
    function queueSchedule(start, end) {
        root.pendingSchedule = [start, end];
        scheduleSave.restart();
    }

    Timer {
        id: scheduleSave
        interval: 500
        onTriggered: {
            const range = root.pendingSchedule;
            root.pendingSchedule = [];
            if (range[0] !== root.formatTime(root.startMinute) || range[1] !== root.formatTime(root.endMinute))
                root.setSchedule(range[0], range[1]);
        }
    }

    // Only a crossed boundary moves the mode, so SUPER+Z, a scroll or the
    // slider holds until the next start or end instead of being undone on the
    // next tick. The shared clock still catches boundaries skipped in suspend.
    function checkSchedule() {
        if (!root.restored || !root.flagKnown || !root.automatic || modeSetter.running || chooser.running)
            return;
        const due = root.scheduledOn(WallClock.now) ? 1 : 0;
        if (due !== root.pendingMode)
            root.resetScheduleRetry();
        if (due === memory.applied)
            return;
        if (due === Number(root.on)) {
            memory.applied = due;
            root.resetScheduleRetry();
            return;
        }
        if (setter.running || WallClock.now < root.nextScheduleAttempt)
            return;
        root.pendingMode = due;
        modeSetter.command = [Paths.script("display.sh"), due ? "night-on" : "night-off"];
        modeSetter.running = true;
    }

    property int pendingMode: -1
    property int scheduleFailures: 0
    property double nextScheduleAttempt: 0

    // A new schedule boundary or user choice starts a fresh retry sequence.
    function resetScheduleRetry() {
        root.scheduleFailures = 0;
        root.nextScheduleAttempt = 0;
    }

    Connections {
        target: WallClock
        function onNowChanged() { root.checkSchedule(); }
        function onWokeUp() { root.checkSchedule(); }
    }

    Process {
        id: modeSetter
        onExited: function (code) {
            nightFlag.reload();
            nightFlag.waitForJob();
            // A failed boundary backs off from 30 seconds to five minutes;
            // a good run re-checks at once for a boundary it made skip.
            if (code === 0) {
                root.resetScheduleRetry();
                memory.applied = root.pendingMode;
                root.checkSchedule();
            } else {
                root.nextScheduleAttempt = WallClock.now + Math.min(30000 * Math.pow(2, root.scheduleFailures), 5 * 60000);
                root.scheduleFailures = Math.min(root.scheduleFailures + 1, 16);
                console.warn("Could not set scheduled night mode:", code);
            }
        }
    }

    // The mode the schedule last put the screen in (-1 before it has acted).
    // Kept through a hot reload, so saving a config file mid-override does not
    // count as crossing a boundary; a restart enforces the schedule afresh.
    PersistentProperties {
        id: memory

        reloadableId: "nightMode"

        property int applied: -1
    }

    FileView {
        id: scheduleFile
        path: Paths.state("night-mode.json")
        printErrors: false
        onLoaded: {
            const validMinute = value => Number.isInteger(value) && value >= 0 && value < 1440;
            if (validMinute(schedule.startMinute) && validMinute(schedule.endMinute)
                && schedule.startMinute !== schedule.endMinute) {
                root.startMinute = schedule.startMinute;
                root.endMinute = schedule.endMinute;
                root.automatic = schedule.automatic;
            }
            root.restored = true;
            root.checkSchedule();
        }
        onLoadFailed: root.restored = true
        JsonAdapter {
            id: schedule
            property bool automatic: false
            property int startMinute: 22 * 60
            property int endMinute: 7 * 60
        }
    }

    function saveSchedule() {
        if (!root.restored)
            return;
        schedule.automatic = root.automatic;
        schedule.startMinute = root.startMinute;
        schedule.endMinute = root.endMinute;
        scheduleFile.writeAdapter();
    }

    function toggle() {
        Quickshell.execDetached([Paths.script("display.sh"), "toggle"]);
    }

    function nudge(up) {
        root.setBrightness(root.brightness + (up ? 20 : -20));
    }

    // The slider and wheel use `display.sh set`. They ask for far more levels
    // than DDC can take — each setvcp is a good fraction of a second — so one
    // run at a time, and whatever was asked for last goes next. The ones in
    // between were never going to be seen anyway.
    //
    // `brightness` follows the request rather than the cache while that is going
    // on: read mid-drag, the cache holds a level the slider has already left,
    // and the knob would jump back to it. `committed` is the cache's level, for
    // the knob to settle on once the drag is done.
    property int wanted: -1
    property int committed: 100

    // The temporary cache disappears at boot; get queries DDC when it is absent.
    Component.onCompleted: initialLevel.running = true
    Process {
        id: initialLevel
        command: [Paths.script("display.sh"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text);
                if (isNaN(value))
                    return;
                root.committed = value;
                if (root.wanted < 0)
                    root.brightness = root.committed;
            }
        }
    }

    function setBrightness(value) {
        root.wanted = Math.round(Math.max(0, Math.min(100, value)));
        root.brightness = root.wanted;
        root.push();
    }

    function push() {
        if (setter.running || root.wanted < 0)
            return;
        setter.command = [Paths.script("display.sh"), "set", String(root.wanted)];
        root.wanted = -1;
        setter.running = true;
    }

    Process {
        id: setter
        onExited: function (code) {
            if (code !== 0) {
                console.warn("Could not set display brightness:", code);
                root.wanted = -1;
            }
            // The cache moved while this ran, and its change was not let
            // through to the knob; read it now if nothing else is queued.
            level.reload();
            level.waitForJob();
            if (root.wanted < 0)
                root.brightness = root.committed;
            root.push();
        }
    }

    // watchChanges only reports that the file moved; it does not re-read it, so
    // without the reload() the view keeps serving whatever it held at startup
    // and loaded/loadFailed never fire again.
    FileView {
        id: nightFlag
        path: "/tmp/flag-night-mode"
        watchChanges: true
        printErrors: false
        onFileChanged: nightFlag.reload()
        onLoaded: {
            const firstRead = !root.flagKnown;
            root.on = true;
            root.flagKnown = true;
            if (firstRead)
                root.checkSchedule();
        }
        onLoadFailed: {
            const firstRead = !root.flagKnown;
            root.on = false;
            root.flagKnown = true;
            if (firstRead)
                root.checkSchedule();
        }
    }

    FileView {
        id: level
        path: "/tmp/flag-brightness"
        watchChanges: true
        printErrors: false
        onFileChanged: level.reload()
        onLoaded: {
            const value = parseInt(level.text());
            if (isNaN(value))
                return;
            root.committed = value;
            if (!setter.running && root.wanted < 0)
                root.brightness = value;
        }
    }
}
