pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.components
import "../Fuzzy.js" as Fuzzy

// Clipboard acquisition, filtering, copying and deletion for the launcher.
Singleton {
    id: root
    // --- clipboard -----------------------------------------------------------

    // cliphist's whole list, read once the first time the mode is opened and
    // filtered in here after that. Per keystroke it would be a process per
    // letter, for a list that cannot change while you are looking at it.
    property var clipEntries: []

    // Choose an icon from the preview without decoding the stored payload.
    function clipIcon(text) {
        const body = text.trim();
        if (body.startsWith("[[ binary data"))
            return /\b(png|jpe?g|gif|webp|bmp|tiff?|svg|avif|heic|ico)\b/i.test(body)
                ? "image-x-generic" : "application-octet-stream";
        if (/^(?:(?:copy|cut)\s+)?file:\/\//i.test(body) || /^(\/|~\/)/.test(body))
            return "folder";
        if (/^(https?|ftp):\/\/\S+$/i.test(body))
            return "internet-web-browser";
        return "text-x-generic";
    }

    function results(query) {
        // Still reading. An empty list and a list not yet asked for look the
        // same from here, and a "nothing" that turns into rows a frame later
        // reads as a bug.
        if (!clip.asked || (clip.running && !root.clipEntries.length))
            return [];

        // cliphist is not something the bar installs. It is also just not
        // running yet, or genuinely empty — the row says what to check rather
        // than guessing which.
        if (!root.clipEntries.length)
            return [
                Launcher.noteRow(Theme.glyph.clipboard, "no clipboard history", "needs cliphist storing")
            ];

        const terms = Launcher.prepTerms(query);
        const scored = [];
        const entries = root.clipEntries;

        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            // cliphist lists newest first, and with nothing typed that order
            // is the answer — the thing you just copied is the thing you want.
            let s = -i;

            if (terms.length) {
                const m = Launcher.matchPrepped(terms, e.fields);
                if (m === null)
                    continue;
                s = m - i * 0.1;
            }

            scored.push({
                s: s,
                e: e
            });
        }

        scored.sort((a, b) => b.s - a.s);
        return scored.slice(0, Launcher.maxResults).map(x => ({
                    kind: "clip",
                    id: x.e.id,
                    line: x.e.line,
                    icon: root.clipIcon(x.e.text),
                    // One line per row, so a copied paragraph does not arrive
                    // as a row with a newline in the middle of it.
                    title: x.e.text.replace(/\s+/g, " ").trim(),
                    subtitle: "",
                    raw: true
                }));
    }

    Process {
        id: clip

        // Whether the list has been asked for during this open, not whether it
        // has arrived.
        property bool asked: false

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            // Tab-separated: an id and the preview cliphist made of the entry,
            // which for an image is its own "[[ binary data ... ]]" line. The
            // id is what decodes back to the real thing, so both are kept —
            // and the text folded for the matcher, once, here.
            onStreamFinished: root.clipEntries = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                const body = l.slice(l.indexOf("\t") + 1);
                return {
                    id: l.slice(0, l.indexOf("\t")),
                    line: l,
                    text: body,
                    fields: Launcher.prepFields([[body, 1]])
                };
            })
        }
    }

    // Asked once per open, on the keystroke that first names the mode.
    // `asked` rather than "arrived": the second character typed must not
    // start a second read of the same list.
    function route(inMode, text): void {
        if (inMode && !clip.asked) {
            clip.asked = true;
            clip.running = true;
        }
    }

    // The list is read again for each opening.
    function cancel(): void {
        root.clipEntries = [];
        clip.asked = false;
    }

    // Enter copies the entry and closes; Ctrl+Delete ("forget") drops it
    // and keeps the box open on the rest.
    function activate(r, mode): bool {
        if (r?.kind !== "clip")
            return false;
        if (mode === "forget") {
            // cliphist takes the whole list line back on stdin, id and
            // preview both, rather than the id on its own.
            Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", r.line]);
            // Dropped here too rather than re-reading the list: the row
            // should go while the finger is still on the key.
            root.clipEntries = root.clipEntries.filter(e => e.id !== r.id);
            return false;
        }
        // decode, not the preview: the preview is one line of what may be
        // several, and for an image it is a description of the bytes.
        Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", r.id]);
        return true;
    }
}
