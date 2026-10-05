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

    readonly property string icon: on ? Theme.glyph.nightOn : Theme.glyph.nightOff
    // The panel is dimmed to 0 whenever night mode goes on, so a dark screen is
    // what the mode looks like from outside; say that rather than "Brightness 0%".
    // Scrolling to 0 by hand is not the mode, so key this off the flag, not the level.
    readonly property string tooltip: on ? "Night mode on" : `Brightness ${brightness}%`

    function toggle() {
        Quickshell.execDetached([Paths.script("display.sh"), "toggle"]);
    }

    function nudge(up) {
        Quickshell.execDetached([Paths.script("display.sh"), up ? "up" : "down"]);
    }

    // The popup's slider. display.sh only steps, so a level goes to it as the
    // step from wherever the last one left the panel. A drag asks for far
    // more levels than DDC can take — each setvcp is a good fraction of a
    // second — so one run at a time, and whatever was asked for last goes
    // next. The ones in between were never going to be seen anyway.
    //
    // `brightness` follows the drag rather than the cache while that is going
    // on: read mid-drag, the cache holds a level the slider has already left,
    // and the knob would jump back to it.
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
        onExited: root.push()
    }

    function setBrightness(value) {
        root.wanted = Math.round(Math.max(0, Math.min(100, value)));
        root.brightness = root.wanted;
        root.push();
    }

    function push() {
        if (initialLevel.running || setter.running || root.wanted < 0)
            return;
        const step = root.wanted - root.committed;
        root.wanted = -1;
        if (step === 0)
            return;
        setter.command = [Paths.script("display.sh"), step > 0 ? "up" : "down", String(Math.abs(step))];
        setter.running = true;
    }

    Process {
        id: setter
        onExited: function (code) {
            // Reconcile the actual result before calculating another relative step.
            level.reload();
            level.waitForJob();
            if (code !== 0) {
                console.warn("Could not set display brightness:", code);
                root.wanted = -1;
            }
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
        onLoaded: root.on = true
        onLoadFailed: root.on = false
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
