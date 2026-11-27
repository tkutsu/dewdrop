import QtQuick
import Quickshell.Io

// A FileView for a file only the shell writes: the timers, the pins, the
// places of the modules.
//
// Quickshell 0.3.2 takes a file that does not parse, or an empty one, as
// loaded: its JsonAdapter keeps the defaults, and the next save writes them
// over whatever was there. Settings refuses to save instead (userBroken),
// since someone is in the middle of editing it. Nobody edits these, so a bad
// one is kept beside it as <name>.broken and the store starts afresh. An
// empty one only starts afresh.
//
// This onLoaded runs before the one a store sets, so the copy is safe before
// the store can write, and the store can read `setAside` to start as it
// would on a first run.
FileView {
    id: root

    property bool setAside: false

    onLoaded: {
        root.setAside = !root.parses(root.text());
        // An empty file has nothing in it to keep.
        if (!root.setAside || !root.text().trim())
            return;
        const name = root.path.split("/").pop();
        broken.path = root.path + ".broken";
        broken.setText(root.text());
        Notify.send(`${name} did not parse`, `It was set aside as ${name}.broken, and the shell started without it.`);
    }

    function parses(text: string): bool {
        try {
            const value = JSON.parse(text);
            return !!value && typeof value === "object" && !Array.isArray(value);
        } catch (error) {
            return false;
        }
    }

    property FileView broken: FileView {
        preload: false
        blockWrites: true
        printErrors: false
    }
}
