pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.src.core

// Files that landed in the downloads folder and have not been opened yet.
//
// A file arrived when it was created or last written, whichever is later: the
// creation time alone misses a download that ends after the folder was opened,
// and a server's date can leave the write time months back. Neither moves when
// the file is renamed. It was opened once it has been read after arriving, so
// opening one from the browser clears it too. Opening the folder clears the lot.
//
// Polled, because reading a file tells a watch on its folder nothing. Only the
// top level counts: a folder in here is something unpacked or sorted, not news.
Singleton {
    id: root

    // Seconds after arriving when a read does not count as opening: browsers
    // and thumbnailers read a finished file straight away.
    readonly property int readingGrace: 2

    // Hidden files and the browsers' partial ones. The empty placeholder
    // Firefox keeps under the final name never gets past the listing.
    readonly property var unfinished: /^\.|\.(part|crdownload|download|tmp)$/

    // [{ name, arrived, read }]
    property var files: []
    // Newest first.
    readonly property var unopened: root.files.filter(f => f.arrived > stored.seen && f.read <= f.arrived + root.readingGrace).sort((a, b) => b.arrived - a.arrived)
    readonly property string label: root.unopened.length === 0 ? "" : String(Math.min(root.unopened.length, 99))

    // The tooltip, one name a line. A long run stops rather than filling the screen.
    readonly property int summaryLines: 8
    readonly property string summary: {
        const count = root.unopened.length;
        if (count === 0)
            return "Downloads";
        const names = root.unopened.slice(0, root.summaryLines).map(f => f.name);
        if (count > root.summaryLines)
            names.push(`and ${count - root.summaryLines} more`);
        return names.join("\n");
    }

    function open(): void {
        root.clear();
        // Floats this window alone, in the box of hypr/configs/wrules.lua's
        // sizes.standard: the file manager tiles when opened any other way.
        const command = Settings.inFileManager(Settings.downloadsDir).map(word => `'${word.replace(/'/g, "'\\''")}'`).join(" ");
        Hyprland.dispatch(`hl.dsp.exec_cmd(${JSON.stringify(command)}, { float = true, center = true, size = { "monitor_w*0.6", "monitor_h*0.8" } })`);
    }

    // Everything here so far is no longer news. The files stay as they are.
    function clear(): void {
        stored.seen = Date.now() / 1000;
        state.writeAdapter();
    }

    function refresh(): void {
        lister.running = true;
    }

    function parse(text: string): var {
        const files = [];
        for (const line of text.split("\n")) {
            const [born, written, read, ...path] = line.split("\t");
            const name = path.join("\t").split("/").pop();
            if (name && !root.unfinished.test(name))
                files.push({ name, arrived: Math.max(Number(born) || 0, Number(written)), read: Number(read) });
        }
        return files;
    }

    Process {
        id: lister

        // stat for the times: find's own %B@ can print garbage while it walks.
        command: ["find", Settings.downloadsDir, "-maxdepth", "1", "-type", "f", "!", "-empty", "-exec", "stat", "--printf", "%.W\\t%.Y\\t%.X\\t%n\\n", "{}", "+"]
        stdout: StdioCollector {
            onStreamFinished: root.files = root.parse(text)
        }
    }

    Timer {
        id: poll

        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // The folder is listed only once the last visit is known. On the first run
    // there is none, and what is already there is not new.
    FileView {
        id: state

        path: Paths.state("downloads.json")
        printErrors: false
        onLoaded: poll.running = true
        onLoadFailed: {
            stored.seen = Date.now() / 1000;
            state.writeAdapter();
            poll.running = true;
        }

        JsonAdapter {
            id: stored

            property real seen: 0
        }
    }
}
