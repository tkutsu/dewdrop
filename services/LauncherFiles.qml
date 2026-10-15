pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.components
import "../Fuzzy.js" as Fuzzy

// File search, ranking and opening for the launcher.
Singleton {
    id: root
    // fasd's database, re-read on the first "/" of each open. It is one
    // ~80-line file under ~/.cache/fasd rather than a filesystem walk, so the
    // whole thing lands in about 15ms — long before the prefix has finished
    // being typed. Asked for then rather than on every open, because most
    // opens never reach it. The last read stands in while the new one runs:
    // a list that is a session old is still the right list, where a blank
    // one for a frame is a flicker.
    //
    // This half is instant and needs no debounce, which is why it is a
    // separate process from the fd half below rather than one call that
    // returns both: the list you have opened before is on screen from the
    // first keystroke, and the disk is walked behind it. What fasd cannot do
    // is reach a file never opened at all, and that is what fd is for.
    //
    // Nothing is filtered out of this. fasd only ever records paths opened on
    // purpose, so cache and build noise never enters it — the ignore file the
    // fd half uses was measured against this database and matched none of it.
    //
    // { dir, path, base, fields }, with `fields` the basename and the path
    // folded for the matcher — once, here, rather than per keystroke.
    property var pathCache: []

    // One pass does two jobs: drop entries whose path has since been deleted
    // (fasd keeps them), and label each survivor d or f, so a row can pick its
    // icon and Enter can pick its action without stat-ing anything again.
    Process {
        id: fasd

        // Whether the list has been asked for during this open, not whether
        // it has arrived.
        property bool asked: false

        command: ["sh", "-c", "fasd -Ral | while IFS= read -r p; do if [ -d \"$p\" ]; then printf 'd %s\\n' \"$p\"; elif [ -e \"$p\" ]; then printf 'f %s\\n' \"$p\"; fi; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                // Split on the first space only: the type is one character, and
                // everything after it is the path, spaces and all.
                root.pathCache = text.split("\n").filter(l => l.length > 2).map(l => {
                    const path = l.slice(2);
                    const base = path.slice(path.lastIndexOf("/") + 1);
                    // The basename is the thing being thought of. The
                    // directories above it are context and score at half, or
                    // a deep path would beat the file actually named for the
                    // query on sheer length.
                    return {
                        dir: l.charAt(0) === "d",
                        path: path,
                        base: base,
                        fields: Launcher.prepFields([[base, 1], [path, 0.5]])
                    };
                });
            }
        }
    }

    // What fd last found, tagged with the query it was for. See QueuedProcess.
    property var fdHits: null

    // What never turns up in a search. Not a list here, because
    // ~/.config/fish/functions/f.fish searches the same machine from the
    // terminal and has to skip exactly the same things — two copies of a
    // 230-entry denylist drift the moment either is edited. fd reads the file
    // itself, so neither side parses it.
    //
    // A missing file costs a warning on fd's stderr, which nothing here reads,
    // and an unfiltered walk. The mode gets noisy rather than breaking.
    readonly property string fdIgnore: Paths.script("f/ignore")

    // A slash separates terms the same way a space does, so a path can be
    // described either way round: "downloads torrents" and "downloads/torrents"
    // are the same three-and-a-bit words about the same place, and neither is
    // the literal name of anything.
    //
    // A leading "~" is home, as the shell reads it: fasd and fd both hold
    // whole paths, and neither has a tilde in it to match.
    function fdTerms(query) {
        return Settings.expand(query).toLowerCase().split(/[\s/]+/).filter(t => t.length && t !== "." && t !== "..");
    }

    // Terms joined with a gap, so "hypr key" finds keybinds.lua under hypr the
    // same way the fasd half does. Escaped first: a query is typed text, and
    // an unbalanced bracket in it would be a regex error rather than no match.
    function fdPattern(query) {
        return root.fdTerms(query).map(t => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
    }

    QueuedProcess {
        id: fd

        // Longer than the calculator's: this one spawns a walk of the disk,
        // and the fasd half has already put something on screen to look at.
        interval: 150

        // Lowercase pattern plus fd's smart case means this is case-
        // insensitive, which is what a launcher query wants.
        // Bounded like qalc's, and for the same reason rather than the same
        // risk: this one comes back in about 20ms, but a stalled mount under
        // $HOME is not something a launcher should be able to hang on.
        //
        // --full-path, but only past the first word. fd matches the base name
        // alone by default, and for one word that is exactly right: "launcher"
        // means a thing called launcher, not the hundred files sitting inside
        // a directory of that name. A second word cannot be part of the same
        // name, though — at that point the query is describing a path rather
        // than naming a file ("download torrent", "hypr/keybinds"), and only
        // the whole path can answer it. Which is also what f.fish does, having
        // never had a pattern at all: it lists the disk and lets the matcher
        // see the paths whole.
        //
        // The cap goes up with it, because a path pattern matches every file
        // under every directory it describes and the first 60 in walk order
        // would all come from whichever one fd reached first. The ranking
        // below still puts a name match over a path match; this is about
        // giving it enough to rank.
        // Resolve an existing absolute path before searching the home directory.
        command: ["timeout", "5", "sh", "-c", 'case "$1" in /*) if [ -d "$1" ]; then printf "%s/\\n" "${1%/}"; exit; elif [ -e "$1" ]; then printf "%s\\n" "$1"; exit; fi;; esac; shift; exec "$@"', "sh", Settings.expand(fd.arg), "fd", "--hidden", "--max-results", root.fdTerms(fd.arg).length > 1 ? "200" : "60", "--max-depth", "6", "--type", "f", "--type", "d", "--ignore-file", root.fdIgnore].concat(root.fdTerms(fd.arg).length > 1 ? ["--full-path"] : []).concat([root.fdPattern(fd.arg), Settings.home])

        onResult: function (arg, text) {
            if (!Launcher.shown || arg !== fd.want)
                return;
            root.fdHits = ({
                    q: arg,
                    // fd ends a directory with a slash, which is the only
                    // thing in the output that says which of the two it is.
                    list: text.split("\n").filter(l => l.length).map(l => ({
                                dir: l.charAt(l.length - 1) === "/",
                                path: l.charAt(l.length - 1) === "/" ? l.slice(0, -1) : l
                            }))
                });
        }
    }

    function tildeHome(path) {
        const home = Settings.home;
        return home && path.startsWith(home) ? "~" + path.slice(home.length) : path;
    }

    function results(query) {
        const hits = root.fdHits;
        if (hits && hits.q === query) {
            const exact = Settings.expand(query).replace(/\/$/, "") || "/";
            const direct = hits.list.find(h => h.path === exact);
            if (direct)
                return [root.pathRow(direct.path, direct.dir, false)];
        }
        // Split on slashes as well as spaces, so "downloads/torrents" scores
        // as two words against the name and the path rather than as one long
        // one that has to be a subsequence of either.
        const terms = root.fdTerms(query).map(t => Fuzzy.prepQuery(t));
        const scored = [];
        // A local, not root.pathCache[i] in the loop: each read inside the
        // results binding would register as a dependency of its own.
        const cache = root.pathCache;

        for (let i = 0; i < cache.length; i++) {
            const e = cache[i];

            // fasd hands the list over already ranked by frecency, so with
            // nothing typed its order is the answer; scoring down the list is
            // what preserves it through the sort below.
            let s = -i;

            if (terms.length) {
                const m = Launcher.matchPrepped(terms, e.fields);
                if (m === null)
                    continue;
                // Rank still breaks ties between equally good matches, gently.
                s = m - i * 0.1;
            }

            scored.push({
                s: s,
                e: e
            });
        }

        scored.sort((a, b) => b.s - a.s);
        const rows = scored.slice(0, Launcher.maxResults).map(x => root.pathRow(x.e.path, x.e.dir, false));

        // And then everything fasd has never heard of. Same two sources in
        // the same order as ~/.config/fish/functions/f.fish: what you have
        // opened before, then what is actually on the disk. f.fish can afford
        // a depth-7 walk with no result cap because fzf streams and you are
        // already waiting; this caps the scan at 60 hits, or 200 for multiple terms,
        // and stopped at depth 6, which lands in about 40ms.
        if (hits && hits.q === query) {
            const seen = {};
            for (const r of rows)
                seen[r.path] = true;
            for (const h of hits.list) {
                if (seen[h.path])
                    continue;
                rows.push(root.pathRow(h.path, h.dir, true));
            }
        }
        return rows.slice(0, Launcher.maxResults);
    }

    function pathRow(path, dir, fresh) {
        const cut = path.lastIndexOf("/");
        return {
            kind: "path",
            path: path,
            dir: dir,
            icon: dir ? "folder" : "text-x-generic",
            title: path.slice(cut + 1),
            subtitle: root.tildeHome(path.slice(0, cut) || "/"),
            // Rows fasd did not know about, drawn a shade back: they are the
            // ones you have not opened before, and the list is still ordered
            // history first.
            dim: fresh
        };
    }

    function browserFocus(path) {
        if (!/\.(?:html?|xhtml)$/i.test(path))
            return "";
        const browser = Hyprland.toplevels.values.find(t => (t.wayland?.appId || t.lastIpcObject?.class || "").toLowerCase() === "chromium");
        return browser ? `hl.dsp.focus({ window = "address:0x${browser.address}" })` : "";
    }

    // Ctrl+Enter on a file is Spotlight's ⌘↵: its folder, opened with the
    // file selected. Through the FileManager1 interface rather than a flag of
    // one file manager's own: Dolphin, Nautilus and Nemo all answer it, and
    // D-Bus starts one if none is running. Each part of the path is escaped,
    // so a "#" or a space in a name stays part of the name.
    function reveal(r): void {
        Quickshell.execDetached(["fasd", "-A", r.path]);
        const uri = "file://" + r.path.split("/").map(encodeURIComponent).join("/");
        Quickshell.execDetached(["busctl", "--user", "call", "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "ShowItems", "ass", "1", uri, ""]);
    }

    // Three characters before walking the disk. Fewer than that matches most
    // of the home directory, and fasd has already answered anyway. fasd is
    // asked once per open, on the keystroke that first names the mode.
    function route(inMode, text): void {
        fd.want = inMode && text.length >= 3 ? text : "";
        if (inMode && !fasd.asked) {
            fasd.asked = true;
            fasd.running = true;
        }
    }

    function cancel(): void {
        fd.cancel();
        root.fdHits = ({q: "", list: []});
        fasd.asked = false;
    }

    function activate(r, mode): bool {
        if (r?.kind !== "path")
            return false;
        if (mode === "play") {
            root.reveal(r);
            return true;
        }
        // Keep fasd's ranking fresh, the same way f.fish does on its way out,
        // so picking a path here also trains `f` in the terminal.
        Quickshell.execDetached(["fasd", "-A", r.path]);
        // A directory goes to the file manager rather than to a prompt sitting
        // in it. f cd-s there because the next thing you type in a terminal is
        // a command about the place; picking a folder out of a list of folders
        // is the other errand, and it wants the folder open and its contents
        // visible without an ls.
        //
        // HTML/XHTML use the default application. Focus an existing Chromium
        // browser first when it is the default: a last-active PWA would
        // otherwise make Chromium create another window. Other text files open
        // in $EDITOR the way f.fish opens one, and in a terminal because that
        // is where an editor lives. Not xdg-open for those: it would hand a
        // .conf to a text viewer. Anything binary does go to xdg-open, though,
        // or a .png opens in nvim as a screen of bytes. `file` decides, at the
        // moment of opening rather than per row, and an empty file counts as
        // text because it reads as binary to `file` and is almost always
        // something about to be written.
        if (r.dir)
            Quickshell.execDetached(Settings.inFileManager(r.path));
        else
            Quickshell.execDetached(["sh", "-c", 'f=$1; browser=$2; shift 2; case "$f" in *.[hH][tT][mM]|*.[hH][tT][mM][lL]|*.[xX][hH][tT][mM][lL]) mime=text/html; case "$f" in *.[xX][hH][tT][mM][lL]) mime=application/xhtml+xml;; esac; [ -n "$browser" ] && [ "$(xdg-mime query default "$mime")" = chromium.desktop ] && hyprctl dispatch "$browser" >/dev/null 2>&1; exec xdg-open "$f";; esac; [ -s "$f" ] && [ "$(file -Lb --mime-encoding -- "$f")" = binary ] && exec xdg-open "$f"; exec "$@"', "sh", r.path, root.browserFocus(r.path), ...Settings.inTerminal([Settings.editor, r.path])]);
        return true;
    }
}
