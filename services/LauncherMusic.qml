pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.services

// The launcher's # mode: the library laid out as rows, walked, and acted on.
//
// The one mode whose rows are a tree rather than a list, which is why it is a
// file of its own beside services/Library.qml rather than a section of
// services/Launcher.qml. What is in the library is Library's business; what
// the query turns up, how it is opened and shut, and what Enter does to a row
// is all here. The launcher only asks this for rows and hands rows back.
Singleton {
    id: root

    // The tree's entire state: the keys of the rows Tab has opened. Keys are
    // paths ("artist:3/album:7"), so the same record found twice — once on
    // its own, once under its artist — opens where it was asked to and
    // nowhere else.
    property var open: ({})

    // The query the library has actually been scored against, which trails
    // the one in the box by the debounce below. The rows on screen are always
    // this query's rows, the way the calculator's answer is always tagged with
    // the expression it came from.
    property string query: ""

    Timer {
        id: debounce

        // The calculator's interval. Both are answering the same thing — the
        // pause between two keystrokes — and one of them being a process and
        // the other a loop is not a reason for them to wait different lengths.
        interval: 60
        onTriggered: root.query = Launcher.query.slice(1).trim()
    }

    // Every keystroke, from Launcher.route(): whether the box is in this mode
    // and what follows the prefix if it is. A new query is a new tree, and
    // nothing that was open in the old one was opened about this query.
    function route(inMode, rest): void {
        root.open = ({});
        if (!inMode) {
            debounce.stop();
            root.query = "";
            return;
        }
        // Read once and then kept, so this is a real ask only on the first #
        // of a session — and a rescan of mpd's database is what makes it one
        // again. See services/Library.qml.
        Library.ensure();
        // Scoring ten thousand titles is 50ms for one word and 160ms for
        // three, which is a keystroke the box does not answer. Debounced
        // like the modes that shell out, and for the same reason — the only
        // difference is that this one burns the time here rather than in
        // another process.
        //
        // Except for the first query of the mode, which is scored on the
        // spot: there is nothing on screen yet to stand in for it, and a
        // list that arrives blank and fills in 60ms later is the flicker
        // the debounce is supposed to prevent.
        if (!root.query)
            root.query = rest;
        else
            debounce.restart();
    }

    // For a box that is closing: a debounce that outlived it would score a
    // query nobody is looking at any more.
    function cancel(): void {
        debounce.stop();
    }

    Connections {
        target: Library

        // A rescan while the mode is open would otherwise leave "reading the
        // library" up until the next keystroke happened to ask again. Both
        // flags, because a dump that was in flight is thrown away and the
        // moment to ask again is when it finishes, not when it was doomed.
        function onLoadedChanged() {
            root.reask();
        }
        function onLoadingChanged() {
            root.reask();
        }
    }

    function reask(): void {
        if (!Library.loaded && !Library.loading && Launcher.musicMode)
            Library.ensure();
    }

    // --- ranking -------------------------------------------------------------

    // What the query turned up, ranked, before any of it is laid out as rows.
    //
    // Separate from the rows on purpose. The tree rearranges itself constantly
    // — every arrow key opens a record and shuts another — and the rows are
    // rebuilt each time it does. Ranking and laying out in one pass meant
    // every one of those presses re-scored the whole library: a tenth of a
    // second to walk down a discography whose order had not changed. This
    // depends on the query and the library and nothing else, so the walking is
    // free and only typing costs anything.
    readonly property var hits: {
        if (!Library.loaded || !root.query)
            return [];

        // Playlists are ranked here rather than in the library, which has
        // never heard of them — they are mpd's, not the database's. Same
        // matcher and the same scale, so they sort in among everything else
        // rather than being a section of their own.
        const scored = Library.search(root.query).map(h => ({
                    hit: h,
                    s: h.score
                }));
        const terms = Launcher.prepTerms(root.query);
        for (const name of Mpd.playlists) {
            const m = Launcher.matchScore(terms, [[name, 1]]);
            if (m !== null)
                scored.push({
                    playlist: name,
                    s: m
                });
        }
        scored.sort((a, b) => b.s - a.s);
        return scored.slice(0, Launcher.maxResults);
    }

    // --- rows ----------------------------------------------------------------

    function results(query) {
        // route() has already started the read; this is what stands in while
        // it happens. A note rather than an empty list, for the reason the
        // clipboard has one: a "nothing here" that turns into a hundred rows a
        // moment later reads as a bug rather than as a wait.
        if (!Library.loaded)
            return [
                {
                    kind: "note",
                    key: "note",
                    glyph: Theme.glyph.track,
                    title: "reading the library",
                    subtitle: "",
                    raw: true
                }
            ];

        // "#" on its own is the stored playlists. Ten thousand tracks in no
        // particular order is not a list anybody reads — and the playlists are
        // the one thing in this mode the search below cannot reach, a saved
        // queue having no artist and no album to be found under.
        if (!query)
            return Mpd.playlists.map(name => root.playlistRow(name));

        const rows = [];
        for (const x of root.hits) {
            if (x.playlist !== undefined)
                rows.push(root.playlistRow(x.playlist));
            else if (x.hit.kind === "artist")
                root.pushArtist(rows, x.hit.at);
            else if (x.hit.kind === "album")
                root.pushAlbum(rows, x.hit.at, 0);
            else
                rows.push(root.trackRow(x.hit.at, 0, ""));
        }
        return rows;
    }

    // "1 track", "14 tracks". A discography that says "1 tracks" is one
    // nobody read back.
    function plural(n, word) {
        return n + " " + word + (n === 1 ? "" : "s");
    }

    function playlistRow(name) {
        return {
            kind: "music-playlist",
            key: "playlist:" + name,
            name: name,
            glyph: Theme.glyph.playlist,
            title: name,
            subtitle: "playlist",
            raw: true
        };
    }

    // Pushed rather than returned, all three of these: a row that can carry
    // children has to put them directly underneath itself, and a function that
    // handed back an array would leave the caller splicing.
    function pushArtist(rows, at): void {
        const a = Library.artists[at];
        const key = "artist:" + at;
        rows.push({
            kind: "music-artist",
            key: key,
            at: at,
            indent: 0,
            glyph: Theme.glyph.artist,
            title: a.name,
            subtitle: [a.albums.length ? root.plural(a.albums.length, "album") : "", root.plural(a.tracks, "track")].filter(x => x).join("  ·  "),
            raw: true
        });

        if (!root.open[key])
            return;
        for (const al of a.albums)
            root.pushAlbum(rows, al, 1, key + "/");
    }

    function pushAlbum(rows, at, indent, prefix): void {
        const l = Library.albums[at];
        const key = (prefix ?? "") + "album:" + at;
        rows.push({
            kind: "music-album",
            key: key,
            at: at,
            indent: indent,
            glyph: Theme.glyph.album,
            title: l.name,
            // Under its artist, the artist is the row above and saying so
            // again is noise. On its own it is the thing that tells two
            // records of the same name apart.
            subtitle: [indent ? "" : Library.artistName(l.artist), Library.year(l.date), root.plural(l.tracks.length, "track")].filter(x => x).join("  ·  "),
            raw: true
        });

        if (!root.open[key])
            return;
        for (const ti of l.tracks)
            rows.push(root.trackRow(ti, indent + 1, key));
    }

    function trackRow(at, indent, parent) {
        const t = Library.tracks[at];
        return {
            kind: "music-track",
            key: (parent ? parent + "/" : "") + "track:" + at,
            at: at,
            indent: indent,
            // Which album row this one belongs to, if it is inside one.
            parent: parent,
            glyph: Theme.glyph.track,
            title: t.title,
            // Inside a record, who plays it and what it is on are both rows
            // above; all that is left to say is how long it runs.
            subtitle: indent ? t.time : [t.artist, Library.albumName(t.album)].filter(x => x).join("  ·  "),
            raw: true
        };
    }

    // --- walking the tree ----------------------------------------------------

    // Tab. An artist or a record opens or shuts; anything inside one shuts
    // the one it is in and goes back up to it, so the same key that went in
    // comes back out. Opening only adds rows below the selection, and
    // shutting from inside lands on a row above everything that goes, so the
    // index never has to be looked up again afterwards.
    function fold(): void {
        const rows = Launcher.results;
        const r = rows[Launcher.index];
        if (!r)
            return;
        let at = Launcher.index;
        if (r.kind !== "music-artist" && r.kind !== "music-album") {
            if (!r.indent)
                return;
            while (at > 0 && (rows[at].indent ?? 0) >= r.indent)
                at--;
        }
        // A fresh object rather than a mutation: `open` is a var property,
        // and changing one in place does not notify.
        const next = Object.assign({}, root.open);
        const key = rows[at].key;
        if (next[key])
            delete next[key];
        else
            next[key] = true;
        root.open = next;
        Launcher.index = at;
    }

    // A page, in a tree, is the next thing at this level rather than twelve
    // rows further down: an open record's songs are stepped over.
    //
    // On PageUp and PageDown, which are dead keys in this mode: the two things
    // they otherwise page — a model's answer and the / panel's file — are
    // neither of them on screen next to a library. See LauncherMenu.qml.
    function skip(dir): void {
        const rows = Launcher.results;
        for (let i = Launcher.index + dir; i >= 0 && i < rows.length; i += dir) {
            if (rows[i].kind === "music-track" && rows[i].parent)
                continue;
            Launcher.index = i;
            return;
        }
    }

    // What the artwork panel is looking at. Worked out here because the row is
    // here; the panel only knows how to find a picture in a folder.
    readonly property string coverDir: {
        const r = Launcher.selected;
        if (!Launcher.musicMode || !r || r.kind.indexOf("music-") !== 0)
            return "";
        const kind = r.kind.slice(6);
        if (kind !== "artist" && kind !== "album" && kind !== "track")
            return "";
        return Library.coverDir(kind, r.at);
    }

    // --- acting on a row -----------------------------------------------------

    // Enter, with `mode` from the modifier held: "queue", "play" or "next".
    // Every row goes the same way — whatever files it stands for, wherever
    // the key that chose it says to put them. A playlist is the exception
    // only in that mpd loads it by name: it is a list of files this has never
    // read.
    //
    // Returns whether the box should leave. Only play does: queueing and
    // play-next are things you do several of in a row, so the box stays up
    // with the selection where it was.
    function activate(r, mode): bool {
        mode = mode || "queue";
        if (r.kind === "music-playlist")
            Mpd.loadPlaylist(r.name, mode);
        else
            Mpd.enqueue(Library.files(r.kind.slice(6), r.at), mode);
        return mode === "play";
    }
}
