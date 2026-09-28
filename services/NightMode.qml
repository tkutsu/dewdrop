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
            if (!isNaN(value))
                root.brightness = value;
        }
    }
}
