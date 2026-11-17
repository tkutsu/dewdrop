pragma Singleton
import QtQuick
import Quickshell
import qs.src.core
import qs.src.components

// Text search for the launcher: the lines inside files under home that hold
// the query, from ripgrep, opened in the editor at the line.
//
// No index. With the shared ignore file, a walk of everything the file
// search can see takes ~150ms when nothing matches and a few ms when
// something does, so an index would only add a daemon and a stale answer.
Singleton {
    id: root

    // What rg last found, tagged with the query it was for. See QueuedProcess.
    property var hits: null

    // Fewer than this matches most of home, as with the file search's fd.
    readonly property int minLength: 3

    // Between the path, the line number and the line. Neither a path nor a
    // line of text holds a unit separator, where rg's default colon turns up
    // in both.
    readonly property string sep: "\x1f"

    // Searched the way the file search walks: hidden files, with git's
    // ignores lifted and the shared ignore file applied, to the same depth.
    //
    // --fixed-strings: a typed query is text, not a pattern, so an unbalanced
    // bracket finds nothing rather than raising an error. --max-count: one
    // log full of the word cannot fill the list on its own. Long lines are
    // cut, so a minified file costs a row rather than a megabyte.
    readonly property var flags: ["--hidden", "--no-ignore-vcs", "--smart-case", "--fixed-strings", "--no-heading", "--line-number", "--color=never", "--field-match-separator", "\\x1f", "--max-count", "3", "--max-columns", "200", "--max-columns-preview", "--max-depth", "6", "--max-filesize", "1M"].concat(Settings.fileSearchIgnore ? ["--ignore-file", Settings.fileSearchIgnore] : [])

    QueuedProcess {
        id: rg

        // As long as fd's, and for the same reason: each run walks the disk.
        interval: 200

        // rg has no cap on the total, so head is the cap: closing the pipe
        // stops the walk. Bounded by timeout for the same reason fd is.
        command: ["timeout", "5", "sh", "-c", 'rg "$@" | head -n 200', "sh", ...root.flags, "--", rg.arg, Settings.home]

        onResult: function (arg, text) {
            if (!Launcher.shown || arg !== rg.want)
                return;
            root.hits = ({ q: arg, list: root.parse(text) });
        }
    }

    // rg walks in parallel, so the order it finds things in changes from run
    // to run and the list would reshuffle under every keystroke. Shallow
    // first, then by path and line: what sits near the top of home is what
    // you wrote, where three directories down is usually something a program
    // keeps.
    function parse(text) {
        const list = [];
        for (const l of text.split("\n")) {
            const parts = l.split(root.sep);
            if (parts.length < 3)
                continue;
            list.push({
                path: parts[0],
                line: parseInt(parts[1]),
                text: parts.slice(2).join(root.sep),
                depth: parts[0].split("/").length
            });
        }
        return list.sort((a, b) => a.depth - b.depth || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0) || a.line - b.line);
    }

    // A path row as the file search draws it, with the line: copy, Show in
    // Folder and the preview all take it as it is.
    function hitRow(h) {
        return {
            kind: "path",
            path: h.path,
            dir: false,
            line: h.line,
            icon: "text-x-generic",
            title: h.text.trim(),
            subtitle: LauncherFiles.tildeHome(h.path) + ":" + h.line
        };
    }

    function results(query) {
        if (!Tools.has("rg"))
            return [Launcher.needsRow(Theme.glyph.launcherText, "no text search", "rg")];
        if (query.length < root.minLength)
            return [Launcher.noteRow(Theme.glyph.launcherText, "Search inside files", "Three or more characters")];
        // The last answer stands in while the next one runs: typing one more
        // letter narrows a list, and a blank one for a beat is a flicker.
        const hits = root.hits;
        if (!hits)
            return [];
        if (hits.q === query && !hits.list.length)
            return [Launcher.noteRow(Theme.glyph.launcherText, "No matches", "")];
        return hits.list.slice(0, Launcher.maxResults).map(h => root.hitRow(h));
    }

    function route(inMode, text): void {
        rg.want = inMode && text.length >= root.minLength ? text : "";
    }

    function cancel(): void {
        rg.cancel();
        root.hits = null;
    }

    // Return opens the editor at the line, in a terminal as the file search
    // does; Ctrl+Return shows the file in its folder. Both train fasd, so a
    // file found by what is in it turns up in `f` and / afterwards.
    function activate(r, mode): bool {
        if (r?.kind !== "path")
            return false;
        if (mode === "play") {
            LauncherFiles.reveal(r);
            return true;
        }
        Quickshell.execDetached(["fasd", "-A", r.path]);
        Quickshell.execDetached(Settings.inTerminal([Settings.editor, "+" + r.line, r.path]));
        return true;
    }
}
