pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../Fuzzy.js" as Fuzzy

// MPD's database as the launcher's # mode has to see it: artists holding
// albums holding tracks, with all three ranked against one query at once.
//
// A copy, and deliberately so. MPD can answer `search title "..."` itself, but
// only as a round trip per keystroke, only on substrings, and never on three
// kinds of thing at once — and the answer would still have to be assembled
// into a tree here. Ten thousand tracks is a tenth of a second to read and a
// few megabytes to hold, which is the cheaper end of that trade by a distance.
Singleton {
    id: root

    // Whether the copy is good. Not whether it exists: a database update makes
    // every path and tag in it a guess, and the flag is what goes false.
    property bool loaded: false
    property bool loading: false
    // The last read came back with nothing, which is mpc failing rather than
    // a library: see the end of build().
    property bool failed: false
    property real triedAt: 0

    // { name, raw, low, albums: [albumIndex], loose: [trackIndex], tracks }
    property var artists: []
    // { name, raw, low, artist: artistIndex, date, tracks: [trackIndex] }
    property var albums: []
    // { file, title, raw, low, artist, album: albumIndex, time }
    property var tracks: []

    // `raw` and `low` on all three are Fuzzy.prep's two halves, folded once
    // here rather than ten thousand times per keystroke. That split is the
    // whole reason the mode is usable — see the note in Fuzzy.js.

    // Read on the first "#", not at startup. A tenth of a second of mpc and a
    // parse is not worth paying at every login for a mode that may never be
    // opened, and the one time it is paid there is a row on screen saying so.
    function ensure(): void {
        if (root.loaded || root.loading)
            return;
        // Not straight back at a read that has just failed. Whoever asked
        // hears `loading` drop and would ask again at once, and that was mpc
        // spawned in a loop for as long as the # mode stayed open.
        if (root.failed && Date.now() - root.triedAt < 5000)
            return;
        root.triedAt = Date.now();
        root.loading = true;
        dump.running = true;
    }

    // A dump that was in flight when the database changed describes the
    // library that was, and is thrown away when it lands rather than
    // published as if it were the one that is.
    property bool stale: false

    Connections {
        target: Mpd

        // Not reloaded from here: the launcher is usually not open when mpd
        // finishes a rescan, and the next "#" will ask. When it is open in
        // music mode, LauncherMusic sees `loaded` drop and asks at once.
        function onDatabaseChanged() {
            root.loaded = false;
            root.stale = root.loading;
        }
    }

    Process {
        id: dump

        // One line per song, tab separated, in the order MPD walks the
        // directories — which is the order the files are numbered in on disk.
        // That ordering is on purpose and is not %track%: one record here is
        // tagged "A Radio Ready Version of the Album ...", with track numbers
        // to match, while the filenames it was ripped to are right. Where the
        // tags are good the two agree anyway.
        //
        // Deliberately not `listallinfo` over the socket. Same data, but it
        // arrives as eighty thousand lines through SplitParser — a signal
        // each — rather than one string to split.
        //
        // Under timeout, the same way the calculator and fd are: a dump that
        // never exits (mpc waiting on an mpd that is up but not answering,
        // mid-update or wedged) would leave `loading` set for the rest of
        // the session, and "reading the library" on screen for as long. A
        // real dump of this library is a tenth of a second.
        command: ["timeout", "15", "mpc", "-f", "%file%\t%albumartist%\t%artist%\t%album%\t%title%\t%date%\t%time%", "listall"]

        // After the collector, which waits for the stream before letting the
        // exit through. A dump that failed to spawn never closes its stdout,
        // so this is the only signal that comes back — and without it
        // `loading` would stay set and ensure() would never ask again.
        onExited: root.loading = false

        stdout: StdioCollector {
            onStreamFinished: root.build(text)
        }
    }

    function build(text): void {
        if (root.stale) {
            root.stale = false;
            return;
        }

        // Most titles fold to themselves, and one that does is kept as the
        // string it already is rather than as three equal copies of it.
        const prep = s => {
            const p = Fuzzy.prep(s);
            const raw = p[0] === s ? s : p[0];
            return [raw, p[1] === raw ? raw : p[1]];
        };

        const artists = [];
        const albums = [];
        const tracks = [];
        // Name to index while building, thrown away after: the rows index into
        // the three arrays above, and a string key on every one of ten
        // thousand rows is memory spent to say what a number already says.
        const artistAt = ({});
        const albumAt = ({});

        for (const line of text.split("\n")) {
            const f = line.split("\t");
            if (f.length < 7)
                continue;

            const file = f[0];
            const cut = file.lastIndexOf("/");
            const dir = cut < 0 ? "" : file.slice(0, cut);
            const title = f[4] || file.slice(cut + 1);
            const date = f[5];

            // Who the record belongs to, which is not always who plays the
            // track: a guest on one song must not split the album in two. Two
            // hundred files here carry no albumartist at all, so the track's
            // own artist stands in — and the thirty-odd with neither are
            // simply not filed under anybody. They stay reachable as tracks,
            // which is all a loose file in __etc ever was.
            const who = f[1] || f[2];
            // The folder when there is no album tag. This library is laid out
            // artist/album/track, so the directory is the album's name in
            // every case the tag has failed to be.
            const what = f[3] || (dir ? dir.slice(dir.lastIndexOf("/") + 1) : "");

            let ai = -1;
            if (who) {
                ai = artistAt[who];
                if (ai === undefined) {
                    ai = artists.length;
                    artistAt[who] = ai;
                    const p = prep(who);
                    artists.push({
                        name: who,
                        raw: p[0],
                        low: p[1],
                        albums: [],
                        loose: [],
                        tracks: 0
                    });
                }
            }

            let li = -1;
            if (ai >= 0 && what) {
                // Keyed on the artist as well as the name, or the eleven
                // different Greatest Hits in here would be one record with a
                // hundred and forty songs on it.
                const key = who + "\u0000" + what;
                li = albumAt[key];
                if (li === undefined) {
                    li = albums.length;
                    albumAt[key] = li;
                    const p = prep(what);
                    albums.push({
                        name: what,
                        raw: p[0],
                        low: p[1],
                        artist: ai,
                        date: date,
                        tracks: []
                    });
                    artists[ai].albums.push(li);
                } else if (!albums[li].date && date) {
                    // The date is a per-track tag, so a record that came in
                    // with an untagged first song still gets its year off the
                    // second one.
                    albums[li].date = date;
                }
            }

            const p = prep(title);
            const ti = tracks.length;
            tracks.push({
                file: file,
                title: title,
                raw: p[0],
                low: p[1],
                artist: f[2] || who,
                album: li,
                time: f[6]
            });

            if (li >= 0)
                albums[li].tracks.push(ti);
            else if (ai >= 0)
                artists[ai].loose.push(ti);
            if (ai >= 0)
                artists[ai].tracks++;
        }

        // An artist's records in the order they were made, which is the order
        // anybody thinks of them in. MPD hands them over in directory order,
        // which is alphabetical, and a discography sorted alphabetically is a
        // list rather than a shape. Undated records go last rather than to
        // 1970 — they are the bootlegs and the loose folders, and they belong
        // at the bottom of the list, not the top.
        for (const a of artists)
            a.albums.sort((x, y) => {
                const dx = albums[x].date || "9999";
                const dy = albums[y].date || "9999";
                return dx.localeCompare(dy) || albums[x].name.localeCompare(albums[y].name);
            });

        root.artists = artists;
        root.albums = albums;
        root.tracks = tracks;
        // A dump that came back with nothing is a dump that failed. `mpc`
        // puts its errors on stderr and exits nonzero, but stdout closes
        // either way, so an mpd that was down reads here exactly like one
        // that answered and had nothing to say. Latching `loaded` on that
        // empty answer left the mode dead for the rest of the session --
        // `ensure()` never asks twice. A library that really is empty costs
        // a re-dump per "#", which is a tenth of a second nobody with no
        // music will notice.
        root.loaded = tracks.length > 0;
        root.failed = !root.loaded;
    }

    // --- searching -----------------------------------------------------------

    // The kinds weigh against each other so a tie goes to the broader thing:
    // having found an artist you are offered everything they made, where
    // having found one of their songs you are offered the song. Small margins,
    // though — a track whose title is exactly the query still beats an artist
    // the query is merely a subsequence of.
    readonly property var weight: ({
            artist: 1,
            album: 0.95,
            track: 0.9
        })

    // How much of a parent's match rubs off on its children. Enough that
    // "chili under the bridge" finds the song — the title has three of those
    // words and the band has the fourth — and not so much that every track an
    // artist ever recorded ranks above the one actually named.
    readonly property real inherit: 0.5

    // How many rows are worth ranking. The launcher's own cap is the same
    // number and applies to what comes back from here.
    readonly property int maxHits: 50

    // And how far below the best hit a row may score and still be worth a
    // line. A subsequence matcher turned on ten thousand titles will always
    // find something: "bohren" is in "Bigmouth Strikes Again" if you are
    // willing to walk far enough between the letters, and fifty rows of that
    // bury the two bands actually called it. An absolute threshold cannot do
    // this — the scores a good match earns depend entirely on how long the
    // query is — but the distance to whatever won can, and on everything
    // tried here the real answers sit in the top third and the accidents fall
    // off a cliff well below it.
    readonly property real floor: 0.6

    // What the query turns up: the things that matched, ranked, as
    // { kind, at, score }. The tree under them is the launcher's business —
    // this says what is in it.
    function search(query) {
        if (!root.loaded)
            return [];

        const terms = query.split(/\s+/).filter(t => t.length).map(t => Fuzzy.prepQuery(t));
        if (!terms.length)
            return [];

        // Read into locals once. This runs inside the launcher's results
        // binding, and every `root.tracks[i]` in the loops below would
        // register a dependency of its own — ten thousand of them, per
        // keystroke, on a property that changes once a session.
        const artists = root.artists;
        const albums = root.albums;
        const tracks = root.tracks;
        const inherit = root.inherit;
        const nA = artists.length;
        const nL = albums.length;
        const nT = tracks.length;

        // Per term, every artist's, album's and track's score against it, or
        // null for no match. Worked out once and then shared downwards: a
        // track's score is partly its album's and an album's is partly its
        // artist's, and neither is worth recomputing ten thousand times. This
        // is the same number of Fuzzy calls as scoring the three lists
        // separately would be — the sharing is free.
        const aS = [];
        const lS = [];
        const tS = [];
        for (const term of terms) {
            const a = new Array(nA);
            const l = new Array(nL);
            const t = new Array(nT);
            for (let i = 0; i < nA; i++)
                a[i] = Fuzzy.scorePrepped(term, artists[i].raw, artists[i].low);
            for (let i = 0; i < nL; i++)
                l[i] = Fuzzy.scorePrepped(term, albums[i].raw, albums[i].low);
            for (let i = 0; i < nT; i++)
                t[i] = Fuzzy.scorePrepped(term, tracks[i].raw, tracks[i].low);
            aS.push(a);
            lS.push(l);
            tS.push(t);
        }

        const n = terms.length;
        const hits = [];
        // Which artists and albums came up in their own right, so a child that
        // has nothing of its own to say can be left to its parent.
        const shownArtist = ({});
        const shownAlbum = ({});

        for (let i = 0; i < nA; i++) {
            let s = 0;
            let k = 0;
            for (; k < n; k++) {
                const v = aS[k][i];
                if (v === null)
                    break;
                s += v;
            }
            if (k < n)
                continue;
            shownArtist[i] = true;
            hits.push({
                kind: "artist",
                at: i,
                score: s * root.weight.artist
            });
        }

        for (let i = 0; i < nL; i++) {
            const parent = albums[i].artist;
            let s = 0;
            let k = 0;
            for (; k < n; k++) {
                let v = lS[k][i];
                const up = parent >= 0 ? aS[k][parent] : null;
                if (up !== null && (v === null || up * inherit > v))
                    v = up * inherit;
                if (v === null)
                    break;
                s += v;
            }
            if (k < n)
                continue;
            // Its artist is already a row, so it is hanging under that row an
            // indent away and a second copy at the top level is the same
            // record listed twice. Unconditional, where the tracks below get
            // to keep a match of their own: an album title is long enough that
            // a fuzzy query lands in one by accident constantly — "Under the
            // Covers: Essential Red Hot Chili Peppers" matched "rhcp" and
            // "pepper" on its own name and was drawn twice for both — and it
            // is never more than one keystroke away underneath its artist
            // anyway.
            if (shownArtist[parent])
                continue;
            shownAlbum[i] = true;
            hits.push({
                kind: "album",
                at: i,
                score: s * root.weight.album
            });
        }

        for (let i = 0; i < nT; i++) {
            const t = tracks[i];
            const parent = t.album;
            const grand = parent >= 0 ? albums[parent].artist : -1;
            let s = 0;
            let own = false;
            let k = 0;
            for (; k < n; k++) {
                let v = tS[k][i];
                if (v !== null)
                    own = true;
                const up = parent >= 0 ? lS[k][parent] : null;
                if (up !== null && (v === null || up * inherit > v))
                    v = up * inherit;
                // Two steps up, and worth two steps of the discount: an
                // artist's name says less about one of their songs than the
                // record it is on does.
                const over = grand >= 0 ? aS[k][grand] : null;
                if (over !== null) {
                    const w = over * inherit * inherit;
                    if (v === null || w > v)
                        v = w;
                }
                if (v === null)
                    break;
                s += v;
            }
            if (k < n)
                continue;
            // Same rule as the albums above, one level down. A track that
            // matched nothing on its own title is only here because of the
            // record or the band it belongs to, and both of those are rows
            // you can open. A track that did match its own title stays,
            // wherever its parents are — typing a song's name should find the
            // song.
            if (!own && (shownAlbum[parent] || shownArtist[grand]))
                continue;
            hits.push({
                kind: "track",
                at: i,
                score: s * root.weight.track
            });
        }

        if (!hits.length)
            return hits;

        // Cut first, sort what survives: a sort is the one thing here that
        // costs more than a pass, and most of what it would have ordered is
        // about to be dropped.
        //
        // Only while the winner is positive. A fraction of a score at or
        // below zero is a bar above the winner itself, and a query that
        // matched a handful of long titles late would list nothing.
        let best = -Infinity;
        for (const h of hits)
            if (h.score > best)
                best = h.score;
        const kept = best > 0 ? hits.filter(h => h.score >= best * root.floor) : hits;
        kept.sort((x, y) => y.score - x.score || root.name(x).localeCompare(root.name(y)));
        return kept.slice(0, root.maxHits);
    }

    // --- reading a hit -------------------------------------------------------

    function name(hit) {
        if (hit.kind === "artist")
            return root.artists[hit.at].name;
        if (hit.kind === "album")
            return root.albums[hit.at].name;
        return root.tracks[hit.at].title;
    }

    function artistName(i) {
        return i >= 0 ? root.artists[i].name : "";
    }

    function albumName(i) {
        return i >= 0 ? root.albums[i].name : "";
    }

    // The four digits of it. MPD hands over whatever was in the tag, which on
    // this machine is anything from "1991" to "2008-04-05".
    function year(date) {
        return date ? String(date).slice(0, 4) : "";
    }

    // Every file a row stands for, in the order it should be played: an
    // artist's records oldest first and each one in its own order, an album's
    // songs in theirs, a track's own.
    //
    // Explicit files, rather than letting MPD find them again from the tags
    // the row was built out of. It is the only way that cannot miss: an album
    // whose name came from its folder because the tag was empty has nothing
    // for `findadd album` to match on.
    function files(kind, at) {
        if (kind === "track")
            return [root.tracks[at].file];
        if (kind === "album")
            return root.albums[at].tracks.map(i => root.tracks[i].file);
        if (kind !== "artist")
            return [];

        const a = root.artists[at];
        const out = [];
        for (const li of a.albums)
            for (const ti of root.albums[li].tracks)
                out.push(root.tracks[ti].file);
        // And whatever of theirs was never on a record. Last, because a
        // stray file is the exception and the albums are what was asked for.
        for (const ti of a.loose)
            out.push(root.tracks[ti].file);
        return out;
    }

    // The directory a row's artwork is in, absolute. MPD serves pictures over
    // the protocol in binary chunks; the file sitting beside the music is the
    // same picture for the cost of a directory listing, which is the trade
    // Mpd.cover already makes for what is playing.
    function coverDir(kind, at) {
        let file = "";
        if (kind === "track") {
            file = root.tracks[at].file;
        } else if (kind === "album") {
            const l = root.albums[at];
            file = l.tracks.length ? root.tracks[l.tracks[0]].file : "";
        } else if (kind === "artist") {
            // The first record, which is the earliest one: an artist has no
            // cover of their own, and the one everybody pictures is rarely
            // whichever happened to sort first alphabetically.
            const a = root.artists[at];
            if (a.albums.length) {
                const l = root.albums[a.albums[0]];
                file = l.tracks.length ? root.tracks[l.tracks[0]].file : "";
            } else if (a.loose.length) {
                file = root.tracks[a.loose[0]].file;
            }
        }
        if (!file)
            return "";
        const cut = file.lastIndexOf("/");
        return cut < 0 ? Mpd.musicDir : Mpd.musicDir + file.slice(0, cut + 1);
    }
}
