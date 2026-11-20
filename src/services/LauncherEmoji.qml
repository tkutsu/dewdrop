pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core
import "../lib/Fuzzy.js" as Fuzzy

// Emoji for the launcher: found by their name or by any of the words people
// call them ("lol", "puppy", "lit"), copied on Enter.
Singleton {
    id: root

    // [{ char, name, words }], read from assets/emoji.json the first time the
    // mode opens and kept: unlike the clipboard, it cannot change while the
    // shell is running. See scripts/emoji-data.py for where it comes from.
    property var entries: []

    // Every typed word has to begin a word of the emoji's name or keywords.
    // Not the fuzzy matcher the other modes use: run across a dozen keywords,
    // "cat" would find c…a…t in nearly every row. A whole word of the name
    // counts most, then a whole keyword, so "lol" is 😂 and not the start of
    // "lollipop"; then the start of a name's word, then of a keyword. What
    // was picked before rises like an app does.
    function score(terms, e) {
        let total = 0;
        for (const term of terms) {
            let best = 0;
            for (const [word, named] of e.words) {
                if (!word.startsWith(term))
                    continue;
                const whole = word.length === term.length;
                const s = named ? (whole ? 30 : 20) : (whole ? 25 : 10);
                if (s > best)
                    best = s;
            }
            if (!best)
                return null;
            total += best;
        }
        return total;
    }

    function results(query) {
        if (!file.loaded)
            return [];
        if (!root.entries.length)
            return [Launcher.noteRow(Theme.glyph.launcher, "No emoji list", "assets/emoji.json is missing")];

        const terms = query.split(/\s+/).filter(t => t.length).map(t => Fuzzy.prepQuery(t));
        const scored = [];
        root.entries.forEach((e, i) => {
            const m = root.score(terms, e);
            if (m === null)
                return;
            // Among equal matches the shorter name is the plainer emoji
            // ("red heart" before "heart with arrow", "fire" before "fire
            // engine"), then Unicode's order, faces before flags.
            scored.push({ s: m + Launcher.frecencyWeight * Math.log2(1 + Launcher.frecency("emoji:" + e.char)) - e.name.length * 0.01 - i * 1e-5, e });
        });
        scored.sort((a, b) => b.s - a.s);
        return scored.slice(0, Launcher.maxResults).map(x => ({
                    kind: "emoji",
                    emoji: x.e.char,
                    title: x.e.name,
                    subtitle: ""
                }));
    }

    FileView {
        id: file

        // Named only once the mode is asked for, so a shell that never
        // opens it never reads it.
        property bool asked: false
        property bool loaded: false

        path: asked ? Quickshell.shellPath("assets/emoji.json") : ""
        printErrors: false
        onLoadFailed: file.loaded = true
        onLoaded: {
            try {
                root.entries = JSON.parse(file.text()).map(([char, name, keywords]) => ({
                    char,
                    // CLDR writes names in lower case; a row reads as a sentence.
                    name: name.charAt(0).toUpperCase() + name.slice(1),
                    words: Fuzzy.prepQuery(name).split(/[\s:,]+/).filter(w => w).map(w => [w, true])
                        .concat(Fuzzy.prepQuery(keywords).split(/\s+/).filter(w => w).map(w => [w, false]))
                }));
            } catch (e) {
                root.entries = [];
            }
            file.loaded = true;
        }
    }

    function route(inMode, text): void {
        if (inMode)
            file.asked = true;
    }

    // Nothing to throw away between openings.
    function cancel(): void {}

    // Enter copies it and closes. Counted after the box has gone, so the
    // list does not re-rank under the exit.
    function activate(r, mode): bool {
        if (r?.kind !== "emoji")
            return false;
        Launcher.copy(r.emoji);
        Launcher.heldBumps.push("emoji:" + r.emoji);
        return true;
    }
}
