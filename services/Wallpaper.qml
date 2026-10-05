pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.components

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
    readonly property string thumbDir: Paths.cache("wallpaper-thumbs")
    property var thumbs: ({})

    function thumbOf(path) {
        return root.thumbs[path] ?? path;
    }

    // Every scan hands over a new array whether anything moved or not, and
    // every scroll notch scans, so the script is only asked when the listing
    // changed. The listing carries each file's mtime and size, so a wallpaper
    // replaced under the same name is a change too. One that changes while
    // the script runs asks for another scan once it is done.
    property string thumbed: ""
    property bool rethumb: false

    function thumbnailAll(listing: string): void {
        if (!root.files.length || listing === root.thumbed)
            return;
        if (thumbnail.running) {
            root.rethumb = true;
            return;
        }
        root.thumbed = listing;
        thumbnail.exec([Quickshell.shellPath("scripts/wallpaper-thumbs"), root.thumbDir].concat(root.files));
    }

    Process {
        id: thumbnail

        onExited: if (root.rethumb) {
            root.rethumb = false;
            root.rescan();
        }

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
    // the day has taken it. Empty while an image is up.
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
    property string sampledPath: ""

    // Each screen shares its desktop fade with its bar's wallpaper strip.
    property var backdrops: ({})
    property var strips: ({})

    function registerBackdrop(name, renderer) {
        const next = Object.assign({}, root.backdrops);
        if (renderer)
            next[name] = renderer;
        else
            delete next[name];
        root.backdrops = next;
    }

    function registerStrip(name, strip) {
        const next = Object.assign({}, root.strips);
        if (strip)
            next[name] = strip;
        else
            delete next[name];
        root.strips = next;
    }

    readonly property var presentation: Quickshell.screens.map(s => root.backdrops[s.name]).find(view => view?.ready) ?? null

    readonly property string behind: root.presentation ? String(root.presentation.average) : root.onScreen || root.sampled

    // The surface colour itself: the hue of what is behind, kept to a near
    // black. Saturation is capped so a vivid wallpaper tints the glass rather
    // than dyeing it, and the lightness is fixed so white labels on it keep
    // exactly the contrast they had on black.
    function tintOf(behind) {
        if (!behind)
            return Qt.color("black");
        const c = Qt.color(behind);
        return Qt.hsla(Math.max(0, c.hslHue), Math.min(c.hslSaturation, 0.5), 0.08, 1);
    }

    readonly property color tint: root.tintOf(root.behind)

    Binding {
        target: Theme
        property: "tint"
        value: root.tint
    }

    // And the colour itself, for what has to be drawn solid where the pills
    // are glass and before the bar has read its own strip (Pill.surface).
    Binding {
        target: Theme
        property: "backdrop"
        value: root.behind ? Qt.color(root.behind) : "black"
    }

    // --- the window border ------------------------------------------------------
    // Hyprland's focused border is the same tinted glass, lifted out of the
    // near black so it still reads as an edge against a dark window.
    // decoration.lua keeps a neutral grey for while the shell is down, and a
    // config reload puts that grey back, so the border is sent again after one.
    // Keep border IPC tied to selection, rather than sending it every fade frame.
    readonly property color borderTint: root.tintOf(root.onScreen || root.sampled)
    readonly property color border: Qt.hsla(Math.max(0, root.borderTint.hslHue), root.borderTint.hslSaturation, 0.38, 1)

    function paintBorder() {
        const rgba = "rgba(" + String(root.border).slice(1) + "ff)";
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ general = { col = { active_border = "${rgba}" } } })`]);
    }

    // Not while a new image is still being sampled: the tint is black for that
    // moment, and Hyprland would animate to grey and back.
    onBorderChanged: if (root.onScreen || root.sampled)
        root.paintBorder()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.paintBorder();
        }
    }

    // The image's own size, for the bar to cut out just the rows of it that
    // are behind the bar (WallpaperStrip). Read from the file's header (-ping),
    // which takes no time. `measuredPath` says the answer is in, whether or not
    // it had a size in it: a file magick cannot read but Qt can still goes up,
    // as plain wallpaper with no strip, rather than never.
    property size currentSize: Qt.size(0, 0)
    property string measuredPath: ""

    onCurrentChanged: {
        root.sampled = "";
        root.sampledPath = "";
        root.currentSize = Qt.size(0, 0);
        root.measuredPath = "";
    }

    // Both magick runs are bounded: a file it hangs on would otherwise hold
    // the fade, which waits for them. Timed out, the answer is empty, and the
    // image goes up plain.
    QueuedProcess {
        id: measure
        interval: 0
        want: root.current
        command: ["timeout", "10", "magick", "identify", "-ping", "-format", "%w %h", arg + "[0]"]

        onResult: (path, text) => {
            if (path !== root.current)
                return;
            const [w, h] = text.trim().split(" ");
            if (Number(w) > 0 && Number(h) > 0)
                root.currentSize = Qt.size(Number(w), Number(h));
            root.measuredPath = path;
        }
    }

    QueuedProcess {
        id: sample
        interval: 0
        want: root.current
        command: ["timeout", "10", "magick", "-define", "jpeg:size=256x256", arg, "-resize", "64x64!", "-scale", "1x1!", "-format", "#%[hex:p{0,0}]", "info:"]

        onResult: (path, text) => {
            if (path !== root.current)
                return;
            const hex = text.trim();
            if (/^#[0-9a-fA-F]{6}/.test(hex))
                root.sampled = hex.slice(0, 7);
            root.sampledPath = path;
        }
    }

    readonly property int index: files.indexOf(root.current)
    readonly property string tooltip: "No wallpapers found"

    // Every entry point rescans first, so newly added files join the rotation.
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
        root.adopt(files[target]);
        root.save();
    }

    function setColor(hex) {
        root.lastColor = hex;
        root.adopt(hex);
        root.save();
    }

    // Three lines: what is on screen — a path or a #rrggbb — the colour to
    // come back to, and whether a colour drifts. Each line is only ever added
    // after the last, so a state written before one of them existed still
    // reads.
    function save() {
        state.setText(`${root.color || root.current}\n${root.lastColor}\n${root.drift ? "drift" : ""}\n`);
    }

    Connections {
        target: WallClock
        function onWokeUp(): void {
            root.hour = root.hourNow();
        }
    }

    function openFolder() {
        Quickshell.execDetached(Settings.inTerminal(["yazi", root.dir]));
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
        // Path, mtime, size: the last two only for the thumbnails to notice a
        // file replaced in place.
        command: ["find", root.dir, "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", ")", "-printf", "%p\t%T@\t%s\n"]

        stdout: StdioCollector {
            onStreamFinished: {
                const listing = text.split("\n").filter(l => l !== "").sort();
                root.files = listing.map(l => l.split("\t").slice(0, -2).join("\t"));
                root.thumbnailAll(listing.join("\n"));
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
            return;
        }
        if (files.length === 0)
            return;
        restored = true;
        if (index < 0)
            _random();
    }

    Component.onCompleted: {
        root.rescan();
        root.paintBorder();
    }
}
