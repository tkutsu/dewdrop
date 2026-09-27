pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Wallpaper cycling.
//
// taskbar-wallpaper.sh retires with this: the bar was its only caller besides
// the boot-time `restore`, which is now just what this does on startup. Keeping
// both would mean two copies of the same ordering, and of the rule for what
// "the wallpaper on screen" means between runs.
Singleton {
    id: root

    readonly property string dir: Settings.wallpaperDir

    property var files: []

    // --- thumbnails -------------------------------------------------------------
    // What the popup draws for each file: a small copy kept on disk by
    // scripts/wallpaper-thumbs, looked up by path. A file with no entry yet —
    // the first time the folder is seen, or one just dropped into it — is
    // drawn from the original until its thumbnail lands.
    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/quickshell/wallpaper-thumbs"
    property var thumbs: ({})

    function thumbOf(path) {
        return root.thumbs[path] ?? path;
    }

    // Every scan hands over a new array whether the files moved or not, and
    // every scroll notch scans, so the script is only asked when the list
    // itself changed. One that changes mid-run is caught by the next scan.
    property string thumbed: ""

    onFilesChanged: {
        const list = root.files.join("\n");
        if (list === root.thumbed || thumbnail.running)
            return;
        root.thumbed = list;
        thumbnail.exec([Quickshell.shellPath("scripts/wallpaper-thumbs"), root.thumbDir].concat(root.files));
    }

    Process {
        id: thumbnail

        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab > 0)
                        map[line.slice(0, tab)] = line.slice(tab + 1);
                }
                root.thumbs = map;
            }
        }
    }

    // The wallpaper is remembered by path, not by position: the folder is a
    // place the user drops files into, and an index would point at a different
    // image the moment one is added or removed.
    property string current: ""

    // Set while a flat colour is on screen instead of an image, in which case
    // `current` is empty. The two are never both set: a wallpaper is one or the
    // other, and every setter clears the one it is not.
    property string color: ""
    // The last colour there was, kept through an image and across restarts so
    // that going back to a colour is one click rather than mixing it again. It
    // outlives `color`, which is cleared the moment an image goes up.
    property string lastColor: ""
    readonly property string colorPath: Quickshell.env("HOME") + "/.cache/quickshell-wallpaper-color.png"

    // Whether a flat colour drifts with the time of day: warmer towards dusk,
    // darker through the night, itself again by mid-morning — the way a
    // dynamic desktop follows the sun, done to one colour instead of a set of
    // photographs. Remembered with the wallpaper.
    property bool drift: false

    function setDrift(on) {
        root.drift = on;
        root.save();
    }

    // The hour of the day as a fraction, for the drift. Moved on the minute,
    // and only while there is a drifting colour to move — the same rule the
    // clock follows, since nothing here changes faster than that.
    property real hour: root.hourNow()

    function hourNow() {
        const d = new Date();
        return d.getHours() + d.getMinutes() / 60;
    }

    Timer {
        running: root.drift && root.color !== ""
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.hour = root.hourNow()
    }

    // How warm and how dark the colour goes at each hour, as a handful of
    // points to interpolate between rather than a formula: the shape of a day
    // is easier to read off a table than out of trigonometry. Warm is how far
    // towards `dusk` the colour is mixed, dark how far its value comes down,
    // both as fractions of the most either is allowed to go (driftWarm,
    // driftDark). Twenty-four is midnight again, so the table wraps.
    readonly property var driftCurve: [
        [0, 0.6, 1],
        [5, 0.6, 1],
        [7, 0.3, 0.3],
        [9, 0, 0],
        [16, 0, 0],
        [19, 1, 0.3],
        [21, 0.8, 0.8],
        [24, 0.6, 1]
    ]
    readonly property color dusk: "#ff8f4a"
    readonly property real driftWarm: 0.18
    readonly property real driftDark: 0.3

    function drifted(hex, hour) {
        const curve = root.driftCurve;
        let i = 0;
        while (i < curve.length - 2 && curve[i + 1][0] <= hour)
            i++;
        const [h0, w0, d0] = curve[i];
        const [h1, w1, d1] = curve[i + 1];
        const t = (hour - h0) / (h1 - h0);
        const warm = (w0 + (w1 - w0) * t) * root.driftWarm;
        const dark = (d0 + (d1 - d0) * t) * root.driftDark;
        const c = Qt.color(hex);
        const mix = (a, b) => (a + (b - a) * warm) * (1 - dark);
        return Qt.rgba(mix(c.r, root.dusk.r), mix(c.g, root.dusk.g), mix(c.b, root.dusk.b), 1);
    }

    // The colour the backdrop actually draws: the one that was set, or where
    // the day has taken it. Empty while an image is up. hyprpaper is only ever
    // given the colour as set — it is what shows while the shell is down, and
    // re-rendering its PNG once a minute for a drift nobody would see there is
    // a magick run a minute for nothing.
    readonly property string onScreen: {
        if (!root.color)
            return "";
        return root.drift ? String(root.drifted(root.color, root.hour)) : root.color;
    }

    // --- tinting the material --------------------------------------------------
    // Roughly what colour the screen behind the bar is: the flat colour when
    // there is one, else the image boiled down to its average by magick. The
    // pills and popups take their fill from it (Theme.tint), so the material
    // reads as tinted glass over this particular desktop rather than as the
    // same black over any of them.
    property string sampled: ""

    readonly property string behind: root.onScreen || root.sampled

    // The surface colour itself: the hue of what is behind, kept to a near
    // black. Saturation is capped so a vivid wallpaper tints the glass rather
    // than dyeing it, and the lightness is fixed so white labels on it keep
    // exactly the contrast they had on black.
    readonly property color tint: {
        if (!root.behind)
            return "black";
        const c = Qt.color(root.behind);
        return Qt.hsla(Math.max(0, c.hslHue), Math.min(c.hslSaturation, 0.5), 0.08, 1);
    }

    Binding {
        target: Theme
        property: "tint"
        value: root.tint
    }

    onCurrentChanged: {
        root.sampled = "";
        if (root.current)
            sample.exec(["magick", "-define", "jpeg:size=256x256", root.current, "-resize", "64x64!", "-scale", "1x1!", "-format", "#%[hex:p{0,0}]", "info:"]);
    }

    Process {
        id: sample

        stdout: StdioCollector {
            onStreamFinished: {
                const hex = text.trim();
                if (/^#[0-9a-fA-F]{6}/.test(hex))
                    root.sampled = hex.slice(0, 7);
            }
        }
    }

    readonly property int index: files.indexOf(current)
    readonly property string tooltip: color ? `Wallpaper: ${color}` : (files.length ? `Wallpaper: ${index + 1}/${files.length}` : "No wallpapers found")

    // Every entry point rescans first, so a file added a second ago is already
    // in the rotation. `find` over a few dozen images costs nothing next to the
    // hyprpaper preload that follows it.
    function next() {
        rescan(() => step(1));
    }

    function prev() {
        rescan(() => step(-1));
    }

    function random() {
        rescan(_random);
    }

    function step(delta) {
        if (!files.length)
            return;
        // An unknown current (first run, or the file was deleted) starts the
        // walk so that "next" lands on the first wallpaper and "prev" the last.
        const from = index < 0 ? (delta > 0 ? -1 : 0) : index;
        show((from + delta + files.length) % files.length);
    }

    function _random() {
        if (files.length < 2)
            return show(files.length - 1);
        if (index < 0)
            return show(Math.floor(Math.random() * files.length));
        // Rerolling the current wallpaper feels like a no-op, so pick among the
        // others and wrap.
        show((index + 1 + Math.floor(Math.random() * (files.length - 1))) % files.length);
    }

    function show(target) {
        if (target < 0 || target >= files.length)
            return;
        root.color = "";
        root.current = files[target];
        root.save();
        apply(root.current);
    }

    // hyprpaper knows about files, not colours, so the swatch is written out as
    // a one-pixel PNG and set like any other wallpaper. It re-reads the file on
    // every `wallpaper` call, so one fixed path serves every colour — naming
    // the file after the hex would leave a cache entry behind for every notch
    // of a slider drag.
    function setColor(hex) {
        root.current = "";
        root.color = hex;
        root.lastColor = hex;
        root.save();
        debounce.restart();
    }

    // Three lines: what is on screen — a path or a #rrggbb — the colour to
    // come back to, and whether a colour drifts. Each line is only ever added
    // after the last, so a state written before one of them existed still
    // reads.
    function save() {
        state.setText(`${root.color || root.current}\n${root.lastColor}\n${root.drift ? "drift" : ""}\n`);
    }

    function renderColor() {
        render.exec(["magick", "-size", "1x1", "xc:" + root.color, root.colorPath]);
    }

    // A drag emits a value per pixel of travel. Without this each one would be
    // its own magick run racing the last one to write the same file.
    Timer {
        id: debounce
        interval: 60
        onTriggered: root.renderColor()
    }

    Process {
        id: render
        onExited: function (code) {
            if (code === 0)
                root.apply(root.colorPath);
        }
    }

    function apply(path) {
        // `wallpaper` reads the file itself. The `preload` that used to run
        // first — and the `unload unused` that never worked — are both gone:
        // this hyprpaper (0.8.4, checked 2026-09) answers "invalid hyprpaper
        // request" to either, so the preload was a failed process racing the
        // call that was doing the work anyway.
        set.exec(["hyprctl", "hyprpaper", "wallpaper", "," + path]);
    }

    function openFolder() {
        Quickshell.execDetached(Settings.inTerminal(["yazi", root.dir]));
    }

    Process {
        id: set
    }

    FileView {
        id: state
        path: root.dir + "/.current_wallpaper"
        printErrors: false
        // Deliberately not watched: watchChanges only reports that the file
        // moved and never re-reads it (see services/NightMode.qml), and this
        // file's only writer is save() — there is nothing to hear about.
        onLoaded: {
            if (!root.restored) {
                const lines = state.text().split("\n");
                root.adopt((lines[0] ?? "").trim());
                // A colour on screen is also the colour to come back to, which
                // is what carries a state file written before the second line
                // existed.
                const last = (lines[1] ?? "").trim();
                root.lastColor = last || root.color;
                root.drift = (lines[2] ?? "").trim() === "drift";
            }
            root.stateKnown = true;
            root.restore();
        }
        onLoadFailed: {
            root.stateKnown = true;
            root.restore();
        }
    }

    // Recursive: the wallpaper directory sorts images into subfolders, so a
    // flat FolderListModel would see almost none of them.
    Process {
        id: scan
        command: ["find", root.dir, "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", ")"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.files = text.split("\n").filter(l => l !== "").sort();
                const queued = root._pending;
                root._pending = [];
                root.restore();
                for (const action of queued)
                    action();
            }
        }
    }

    // Callbacks waiting on the in-flight scan. A queue rather than a single
    // slot so that three fast scroll notches still move three wallpapers.
    property var _pending: []

    function rescan(then) {
        if (then)
            root._pending = root._pending.concat([then]);
        if (!scan.running)
            scan.running = true;
    }

    // Startup: keep the saved wallpaper if it is still on disk, else pick at
    // random. Both the scan and the state file feed this, and it waits for the
    // pair — whichever lands second is the one that actually restores.
    property bool restored: false
    property bool stateKnown: false

    // The saved line is a path or a #rrggbb; which one it is decides everything
    // downstream, so it is read apart once here rather than tested per use.
    function adopt(saved) {
        if (saved.startsWith("#")) {
            root.color = saved;
            root.current = "";
        } else {
            root.current = saved;
            root.color = "";
        }
    }

    function restore() {
        if (restored || !stateKnown)
            return;
        // A colour does not need the scan: it is not one of the files, and
        // waiting for a folder that may be empty would leave it unrestored.
        if (color) {
            restored = true;
            renderColor();
            return;
        }
        if (files.length === 0)
            return;
        restored = true;
        if (index >= 0)
            apply(current);
        else
            _random();
    }

    Component.onCompleted: root.rescan()
}
