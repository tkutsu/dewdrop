pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import "../Fuzzy.js" as Fuzzy

// What the launcher knows: the query, where the selection is, what matches,
// and which apps get reached for often enough to float.
//
// This replaces Rofi.qml, and with it the whole dismiss-glass apparatus. rofi
// under native wayland sizes its layer surface to the window it draws, so a
// click that missed the box never reached it — Rofi.qml had to raise a
// screen-sized surface underneath, poll `pgrep -x rofi` to find out when to
// take it down again, and have rofi-launch.sh bracket the run with IPC calls
// to say when it was up. LauncherMenu.qml is its own screen-sized surface, so
// none of that has anywhere to live.
Singleton {
    id: root

    // --- modes ---------------------------------------------------------------

    // The first character of the query picks a mode. "@" is search: the word
    // after it can name an engine ("@y lofi"), and without one the query goes
    // to the fallback ("@lofi" is a Google search).
    //
    // One search prefix rather than one per family, because the split between
    // "web" and "AI" was a distinction about the destination, not about what
    // you are doing — in both cases you are typing a question and picking who
    // answers it.
    //
    // An at-sign, which is what addressing something reads as, and not the
    // full stop this would rather have been: a leading dot would take the
    // decimals off the calculator, since the mode is picked before anything
    // looks at what follows and ".5*2" would be a web search for "5*2". See
    // looksLikeMath. The underscore it used to be went to the model below,
    // the two having swapped places.
    //
    // One letter each, and Google has none at all — it is what a bare "@"
    // does, so the search run most often costs the fewest keys. That is also
    // why "@g" is GitHub: the initial was free, because the engine that would
    // have wanted it does not need one. Claude is "@l" for the same reason
    // read the other way — ChatGPT holds the "c", so the key moved to the
    // next free letter of the word, which costs nothing to remember because
    // the hint line marks the key where it falls: "@c[l]aude".
    //
    // %s is replaced with the URL-encoded query. Every engine here has a place
    // to put one, which is why there is no Gemini: neither gemini.google.com
    // nor AI Studio takes a prompt in the URL. Google has never shipped the
    // parameter, the AI Studio request for it has sat open since April 2025,
    // and the only thing that works is a browser extension typing into the box
    // for you — or, for Chrome's own omnibox, an x-omnibox-gemini *header*,
    // which is not something a URL can carry. An entry for it could only ever
    // open an empty chat and drop what was typed.
    //
    // `hint` is the word the query line's hint writes the engine as,
    // and `key` has to be one of its letters: the line brackets the key inside
    // the word rather than spelling it out beside it, so the word is the name
    // itself rather than an abbreviation making room for a repeat of the key.
    readonly property string enginePrefix: "@"

    readonly property var prefixes: ({
            // Keyed by the prefix, which has to be `enginePrefix` written out:
            // an object literal cannot name one of its own properties.
            "@": {
                // No key at all, rather than a key nothing types.
                fallback: "",
                // A list, not a map keyed by the letters: the rows below the
                // selected one are drawn in this order, and object key
                // enumeration is not an order anything should depend on.
                engines: [
                    {
                        key: "",
                        name: "Google",
                        hint: "google",
                        url: "https://www.google.com/search?q=%s"
                    },
                    {
                        key: "y",
                        name: "YouTube",
                        hint: "youtube",
                        url: "https://www.youtube.com/results?search_query=%s"
                    },
                    {
                        key: "c",
                        name: "ChatGPT",
                        hint: "chatgpt",
                        url: "https://chatgpt.com/?q=%s"
                    },
                    {
                        key: "l",
                        name: "Claude",
                        // /new is the fresh conversation and q= is what goes
                        // in it, which is the whole test for being in this
                        // list — see the note about Gemini above.
                        url: "https://claude.ai/new?q=%s",
                        hint: "claude"
                    },
                    {
                        key: "g",
                        name: "GitHub",
                        hint: "github",
                        url: "https://github.com/search?q=%s"
                    },
                    {
                        key: "w",
                        name: "Wikipedia",
                        hint: "wikipedia",
                        url: "https://en.wikipedia.org/w/index.php?search=%s"
                    },
                    {
                        key: "a",
                        name: "Arch Wiki",
                        hint: "archwiki",
                        url: "https://wiki.archlinux.org/index.php?search=%s"
                    },
                    {
                        key: "x",
                        name: "1337x",
                        hint: "1337x",
                        // Path, not a query string: 1337x takes the term as a
                        // path segment with the page number after it. The 1 is
                        // the first page.
                        url: "https://1337x.to/search/%s/1/"
                    },
                    {
                        key: "t",
                        name: "Translate",
                        hint: "translate",
                        // Auto-detect the source, English the target: the
                        // text is what changes, the direction rarely does.
                        url: "https://translate.google.com/?sl=auto&tl=en&text=%s&op=translate"
                    },
                    {
                        key: "m",
                        name: "Maps",
                        hint: "map",
                        url: "https://www.google.com/maps/search/%s"
                    }
                ]
            }
        })

    // The modes with nothing to choose between, so not `prefixes` entries:
    // that map is engine groups, and none of these has a second engine.
    //
    // Files, from fasd and fd. A calculation. A shell command. The clipboard.
    // The characters are the ones already on the keys they mean — "=" starts
    // what you would write on paper, ">" is a prompt, and a quote is what you
    // put round text you are pasting.
    readonly property string pathPrefix: "/"
    readonly property string calcPrefix: "="
    readonly property string cmdPrefix: ">"
    readonly property string clipPrefix: '"'
    // A question put to a model, answered in the box. The underscore, which
    // the web search had until the two changed places: a line waiting to be
    // filled in, and the one character here that starts nothing else — not a
    // path, not a sum, not a command, not a quoted line.
    readonly property string askPrefix: "_"
    // The library: artists, their records, the songs on them, and the stored
    // playlists. The sharp, which is the one piece of music notation that is
    // also a key on the keyboard, and the last of the punctuation here that
    // starts nothing else — it is not a path, a sum, a prompt, a quoted line
    // or a blank to be filled in.
    readonly property string musicPrefix: "#"
    // Writing something down, and setting something going. These two replace a
    // quick-entry overlay of their own: it was a second box on the same screen
    // doing the same job as this one — a line of text, a note underneath saying
    // what Enter would do — and having two of those is one more surface to
    // learn and one more place for the keyboard grab to go wrong.
    //
    // A comma because a task is a note jotted mid-sentence, and it is the last
    // punctuation key that starts nothing else here. A per-cent sign because it
    // is the other unclaimed key on the row of numbers and it already reads as
    // a quantity of something — which a duration is. It cannot be confused with
    // a sum, either: the unprefixed calculator only takes a query that looks
    // like maths, and nothing that starts with a per-cent does.
    readonly property string taskPrefix: ","
    readonly property string timerPrefix: "%"

    // What the hint in the query line says. Normally the modes, assembled
    // from the prefix characters themselves rather than typed out, so changing
    // one of them changes what the box says it does. No entry for apps: that
    // is what the box does when you tell it nothing, and a prefix line is a
    // list of the things you have to ask for.
    //
    // In search mode it turns into the engines, because by then the mode is
    // not the question any more — which of the ten answers it is, and the
    // letter that picks each one is the thing worth having in front of you.
    readonly property string prefixHint: [root.calcPrefix + "calc", root.cmdPrefix + "run", root.askPrefix + "ask", root.enginePrefix + "web", root.pathPrefix + "files", root.clipPrefix + "clip", root.musicPrefix + "music", root.taskPrefix + "task", root.timerPrefix + "timer"].join("   ")

    // Each engine written as one word with its key bracketed inside it:
    // "@[y]outube". The brackets are the whole instruction — which letter to
    // type and where it sits in the name — in the space the name was taking
    // anyway, where "@y youtube" spent a word saying the key twice.
    //
    // Google gets no brackets because it has no key, which is what "a bare @
    // is a Google search" looks like written down.
    readonly property string engineHint: root.prefixes[root.enginePrefix].engines.map(e => {
            const at = e.hint.indexOf(e.key);
            if (!e.key || at < 0)
                return root.enginePrefix + e.hint;
            return root.enginePrefix + e.hint.slice(0, at) + "[" + e.key + "]" + e.hint.slice(at + 1);
        }).join("   ")

    // Only while the box is still a menu of what it can do. The moment there
    // is a query, the line has been answered — there are rows underneath
    // saying what this particular query does, and the reminder is in the way
    // of them. Same again one level down: "@" on its own is someone looking
    // for the engine they want, and "@y" is someone who has found it.
    readonly property string hint: {
        // In music mode the keys stay up for as long as the mode does: there
        // are four of them and nothing on the rows says which is which.
        if (root.musicMode)
            return "tab expand  ·  enter queue  ·  ctrl+enter play  ·  alt+enter next";
        // These two stay up for as long as their mode does, for the same reason
        // music's does — and a better one. Everywhere else the line is a menu
        // of what the box can do, and it goes as soon as you have chosen, since
        // the rows underneath then say what your query does. Here the line is a
        // grammar, and a grammar is needed while the sentence is being written
        // rather than before it is started: "@fri" is wanted at the end of the
        // task, which is exactly the moment every other mode would have taken
        // the reminder away.
        if (root.timerMode)
            return Timers.syntax;
        if (root.taskMode)
            return Tasks.syntax;
        if (!root.query.length)
            return root.prefixHint;
        if (root.query === root.enginePrefix)
            return root.engineHint;
        return "";
    }

    // rofi drew 9 rows; this is how many are worth ranking behind them.
    readonly property int maxResults: 50
    // How hard usage history pushes a match up the list. High enough that the
    // app you always want wins a tie, low enough that it cannot drag a bad
    // match above a good one.
    readonly property real frecencyWeight: 8

    // --- state ---------------------------------------------------------------

    property bool shown: false
    // Whether the window exists, which is not the same thing as being wanted:
    // LauncherMenu.qml folds itself shut when `shown` goes false, so the window
    // has to outlive the intent by the length of that. See qs.Linger.
    readonly property bool active: linger.active
    property string query: ""
    property int index: 0

    // The row a choice was made on, or -1 for a box that was dismissed rather
    // than used. The exit animation is built on it — see LauncherMenu.qml —
    // and it is also the difference between the two ways out, so it has to be
    // set before hide() and cleared on the way back in.
    property int chosen: -1

    // The row the box is on, and whether the box is listing files at all.
    // Both are for the preview panel, which is the one thing that cares what
    // is selected rather than what is listed — see components/FilePreview.qml.
    readonly property var selected: root.results[root.index] ?? null
    readonly property bool pathMode: root.query.charAt(0) === root.pathPrefix
    readonly property bool musicMode: root.query.charAt(0) === root.musicPrefix
    readonly property bool taskMode: root.query.charAt(0) === root.taskPrefix
    readonly property bool timerMode: root.query.charAt(0) === root.timerPrefix
    // { appId: { count, last } }
    property var db: ({})

    // A new query is a new list, and the old cursor position means nothing in it.
    onQueryChanged: {
        root.index = 0;
        // A new list is also a new tree, and nothing that was open in the old
        // one was opened about this query.
        root.open = ({});
        root.route();
    }

    Linger {
        id: linger

        shown: root.shown
        // A choice takes longer to leave than a dismissal does.
        hold: root.chosen >= 0 ? Theme.zipTotalMs : Theme.revealMs
    }

    function toggle(): void {
        if (root.shown)
            root.hide();
        else
            root.show();
    }

    // Something other than typing has set the query, so the field has to catch
    // up. A signal rather than a binding from `query` back into the field: the
    // field is what everything typed comes from, and a two-way binding would
    // have it fighting itself on every keystroke.
    signal queryReplaced(text: string)

    // Open with a mode already picked, as if the prefix had been typed. The
    // popups on the bar and the two keybinds come in this way.
    function openWith(prefix: string): void {
        if (root.shown && root.query.charAt(0) === prefix) {
            root.hide();
            return;
        }
        if (!root.shown)
            root.show();
        root.query = prefix;
        // Whether anything hears this depends on whether show() built the
        // window before returning, which is the loader's business and not
        // something to depend on. The field adopts the query on creation too,
        // so exactly one of the two lands whichever way round it happens.
        root.queryReplaced(prefix);
    }

    function show(): void {
        root.query = "";
        root.index = 0;
        // Cheap enough to redo every open rather than risk showing a stale
        // list, and it runs while the box is still being drawn.
        fasd.running = true;
        // The modes that shell out start each open with nothing. Their answers
        // are tagged with the query they were for, so a stale one could not be
        // shown against the wrong input — but the clipboard has moved on since
        // last time, and a row that is merely old is not worth the doubt.
        root.calcAnswer = null;
        root.fdHits = null;
        root.clipEntries = [];
        clip.asked = false;
        root.musicQuery = "";
        root.open = ({});
        root.chosen = -1;
        root.shown = true;
    }

    // Leaving because a row was used, rather than because the box was
    // dismissed. Same exit as far as this file is concerned; the difference is
    // the animation the box plays on the way out.
    function leave(i): void {
        root.chosen = i;
        root.hide();
    }

    function hide(): void {
        root.shown = false;
        // A debounce that outlives the box would spawn its process against a
        // query nobody is looking at any more. Closing is not a keystroke, so
        // route() never runs to stop them.
        calcDebounce.stop();
        fdDebounce.stop();
        musicDebounce.stop();
    }

    // --- matching ------------------------------------------------------------

    // Space-separated terms are ANDed, the way rofi's `tokenize: true` did:
    // "fire priv" finds Firefox's private-window entry. Each term scores
    // against every [text, weight] field it is given and keeps its best hit;
    // a term that lands nowhere makes the whole thing a miss, which is null
    // rather than a low score — the caller drops those entirely.
    function matchScore(terms, fields) {
        let total = 0;
        for (const term of terms) {
            let best = null;
            for (const [text, weight] of fields) {
                const v = Fuzzy.score(term, text);
                if (v !== null && (best === null || v * weight > best))
                    best = v * weight;
            }
            if (best === null)
                return null;
            total += best;
        }
        return total;
    }

    readonly property var results: {
        const q = root.query;
        // Nothing typed, nothing listed: the box opens as a bare query line.
        // A single space is the "show me everything" gesture — appResults
        // trims it off, so a space arrives there as an empty app query and
        // returns the whole menu in frecency order.
        if (!q.length)
            return [];

        const sym = q.charAt(0);
        const rest = q.slice(1).trim();
        // charAt on an empty string gives "", which is none of these.
        if (sym === root.pathPrefix)
            return root.pathResults(rest);
        // Not strict: "=" is someone asking qalc a question on purpose, and
        // whatever it says back is the answer to it. See calcResults.
        if (sym === root.calcPrefix)
            return root.calcResults(rest, false);
        if (sym === root.cmdPrefix)
            return root.cmdResults(rest);
        if (sym === root.clipPrefix)
            return root.clipResults(rest);
        if (sym === root.askPrefix)
            return root.askResults(rest);
        if (sym === root.musicPrefix)
            return root.musicResults(rest);
        // Deliberately q.slice(1) rather than the trimmed `rest`: what follows
        // is a line somebody is typing, and trimming it means the space after
        // the prefix is eaten and ", " reads the same as ",". It matters for
        // the preview under the row, which otherwise flickers between "nothing
        // to set" and the real answer as the space goes in.
        if (sym === root.taskPrefix)
            return root.taskResults(q.slice(1));
        if (sym === root.timerPrefix)
            return root.timerResults(q.slice(1));
        if (root.prefixes[sym])
            return root.engineResults(sym, q.slice(1));

        // Unprefixed. A sum and a domain are things the query says outright,
        // so they sit above the list rather than inside it. Apps and power
        // commands are both guesses at what was meant, so they are ranked
        // against each other and share the ordering.
        const t = q.trim();
        return root.calcResults(root.looksLikeMath(t) ? t : "", true).concat(root.urlResults(t)).concat(root.mainResults(t));
    }

    // Everything the unprefixed query can turn up, in one ranking. Apps and
    // power commands score on the same scale and sort together, the way
    // krunner's do: "lock" should beat every app whose name merely contains
    // those letters, and "re" should not put reboot above a browser.
    function mainResults(query) {
        const terms = query.toLowerCase().split(/\s+/).filter(t => t.length);
        const scored = root.appMatches(terms).concat(root.powerMatches(terms));
        scored.sort((a, b) => b.s - a.s || a.row.title.localeCompare(b.row.title));
        return scored.slice(0, root.maxResults).map(x => x.row);
    }

    // Scored, not rendered: mainResults sorts these in with the power
    // commands, so the rows cannot be cut to maxResults yet.
    function appMatches(terms) {
        const scored = [];

        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay)
                continue;

            const f = root.frecency(e.id);
            // With nothing typed the list is pure history, so opening the
            // launcher and pressing Enter reruns what you last ran.
            let s = f;

            if (terms.length) {
                // rofi's drun-match-fields: name, generic, keywords,
                // categories. Weighted, because a hit on the name means more
                // than a hit on a category half the menu shares.
                //
                // Deliberately not e.id: Chrome PWAs are installed with ids
                // like "chrome-<hash>-Default", so every one of them would
                // answer to "chrome".
                const m = root.matchScore(terms, [[e.name, 1], [e.genericName, 0.7]].concat(Array.from(e.keywords ?? []).map(k => [k, 0.6])).concat(Array.from(e.categories ?? []).map(c => [c, 0.4])));
                if (m === null)
                    continue;
                // Logarithmic, so history breaks ties between comparable
                // matches without ever outweighing the match itself.
                s = m + root.frecencyWeight * Math.log2(1 + f);
            }

            scored.push({
                s: s,
                row: {
                    kind: "app",
                    entry: e,
                    icon: e.icon,
                    title: e.name,
                    subtitle: ""
                }
            });
        }

        return scored;
    }

    // --- power ---------------------------------------------------------------

    // The power menu's five, plus lock. Lock is not in Power.actions and is not
    // meant to be — the menu left it out on purpose (see services/Power.qml) —
    // but it is the one of the six anybody types, and a launcher is where you
    // type it.
    readonly property var powerCommands: [
        {
            key: "lock",
            label: "lock",
            glyph: Theme.glyph.lock,
            arg: "--lock",
            confirm: false
        }
    ].concat(Power.actions)

    // The other words each command answers to. The labels alone would not
    // find "restart", "sleep" or "power off", which are what these are called
    // half the time.
    readonly property var powerAliases: ({
            lock: "lock screen session",
            shutdown: "shutdown power off poweroff halt",
            reboot: "reboot restart",
            suspend: "suspend sleep",
            logout: "logout log out sign exit session",
            killprocess: "kill process window xkill"
        })

    function powerMatches(terms) {
        // With nothing typed the list is pure app history. The machine's off
        // switch has no business at the top of that.
        if (!terms.length)
            return [];

        const scored = [];
        for (const a of root.powerCommands) {
            // Aliases score just under the label, so a command found by its
            // real name outranks one found by a nickname.
            const m = root.matchScore(terms, [[a.label, 1]].concat((root.powerAliases[a.key] ?? "").split(" ").map(w => [w, 0.85])));
            if (m === null)
                continue;
            scored.push({
                s: m + root.frecencyWeight * Math.log2(1 + root.frecency("power:" + a.key)),
                row: {
                    kind: "power",
                    action: a,
                    glyph: a.glyph,
                    title: a.label,
                    subtitle: "power"
                }
            });
        }
        return scored;
    }

    // fasd's database, re-read on every open. It is one ~80-line file under
    // ~/.cache/fasd rather than a filesystem walk, so the whole thing lands in
    // about 15ms — long before the prefix has finished being typed.
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
    property var pathCache: []

    // One pass does two jobs: drop entries whose path has since been deleted
    // (fasd keeps them), and label each survivor d or f, so a row can pick its
    // icon and Enter can pick its action without stat-ing anything again.
    Process {
        id: fasd

        command: ["sh", "-c", "fasd -Ral | while IFS= read -r p; do if [ -d \"$p\" ]; then printf 'd %s\\n' \"$p\"; elif [ -e \"$p\" ]; then printf 'f %s\\n' \"$p\"; fi; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                // Split on the first space only: the type is one character, and
                // everything after it is the path, spaces and all.
                root.pathCache = text.split("\n").filter(l => l.length > 2).map(l => ({
                            dir: l.charAt(0) === "d",
                            path: l.slice(2)
                        }));
            }
        }
    }

    // What fd last found, tagged with the query it was for. See pump().
    property var fdHits: null

    // What never turns up in a search. Not a list here, because
    // ~/.config/fish/functions/f.fish searches the same machine from the
    // terminal and has to skip exactly the same things — two copies of a
    // 230-entry denylist drift the moment either is edited. fd reads the file
    // itself, so neither side parses it.
    //
    // A missing file costs a warning on fd's stderr, which nothing here reads,
    // and an unfiltered walk. The mode gets noisy rather than breaking.
    readonly property string fdIgnore: Quickshell.env("HOME") + "/_scripts/f/ignore"

    // A slash separates terms the same way a space does, so a path can be
    // described either way round: "downloads torrents" and "downloads/torrents"
    // are the same three-and-a-bit words about the same place, and neither is
    // the literal name of anything.
    function fdTerms(query) {
        return query.toLowerCase().split(/[\s/]+/).filter(t => t.length);
    }

    // Terms joined with a gap, so "hypr key" finds keybinds.lua under hypr the
    // same way the fasd half does. Escaped first: a query is typed text, and
    // an unbalanced bracket in it would be a regex error rather than no match.
    function fdPattern(query) {
        return root.fdTerms(query).map(t => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
    }

    Process {
        id: fd

        property string want: ""
        property string arg: ""

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
        command: ["timeout", "5", "fd", "--hidden", "--max-results", root.fdTerms(fd.arg).length > 1 ? "200" : "60", "--max-depth", "6", "--type", "f", "--type", "d", "--ignore-file", root.fdIgnore].concat(root.fdTerms(fd.arg).length > 1 ? ["--full-path"] : []).concat([root.fdPattern(fd.arg), Quickshell.env("HOME")])

        onExited: if (root.shown && fd.want !== fd.arg)
            fdDebounce.restart()

        stdout: StdioCollector {
            onStreamFinished: root.fdHits = ({
                    q: fd.arg,
                    // fd ends a directory with a slash, which is the only
                    // thing in the output that says which of the two it is.
                    list: text.split("\n").filter(l => l.length).map(l => ({
                                dir: l.charAt(l.length - 1) === "/",
                                path: l.charAt(l.length - 1) === "/" ? l.slice(0, -1) : l
                            }))
                })
        }
    }

    Timer {
        id: fdDebounce

        // Longer than the calculator's: this one spawns a walk of the disk,
        // and the fasd half has already put something on screen to look at.
        interval: 150
        onTriggered: root.pump(fd)
    }

    function tildeHome(path) {
        const home = Quickshell.env("HOME");
        return home && path.startsWith(home) ? "~" + path.slice(home.length) : path;
    }

    function pathResults(query) {
        // Split on slashes as well as spaces, so "downloads/torrents" scores
        // as two words against the name and the path rather than as one long
        // one that has to be a subsequence of either.
        const terms = root.fdTerms(query);
        const scored = [];

        for (let i = 0; i < root.pathCache.length; i++) {
            const e = root.pathCache[i];
            const cut = e.path.lastIndexOf("/");
            const base = e.path.slice(cut + 1);

            // fasd hands the list over already ranked by frecency, so with
            // nothing typed its order is the answer; scoring down the list is
            // what preserves it through the sort below.
            let s = -i;

            if (terms.length) {
                // The basename is the thing being thought of. The directories
                // above it are context and score at half, or a deep path would
                // beat the file actually named for the query on sheer length.
                const m = root.matchScore(terms, [[base, 1], [e.path, 0.5]]);
                if (m === null)
                    continue;
                // Rank still breaks ties between equally good matches, gently.
                s = m - i * 0.1;
            }

            scored.push({
                s: s,
                e: e,
                base: base
            });
        }

        scored.sort((a, b) => b.s - a.s);
        const rows = scored.slice(0, root.maxResults).map(x => root.pathRow(x.e.path, x.e.dir, false));

        // And then everything fasd has never heard of. Same two sources in
        // the same order as ~/.config/fish/functions/f.fish: what you have
        // opened before, then what is actually on the disk. f.fish can afford
        // a depth-7 walk with no result cap because fzf streams and you are
        // already waiting; this runs between keystrokes, so it is capped at 60
        // and stopped at depth 6, which lands in about 40ms.
        const hits = root.fdHits;
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
        return rows.slice(0, root.maxResults);
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

    // --- ask -----------------------------------------------------------------

    // Big Pickle is free on opencode's Zen for as long as opencode keeps it
    // there: a stealth model on a trial, which is also why the answers are
    // fed back into it. So this line is the one that will need changing, and
    // nothing typed here should be anything worth keeping private.
    //
    // Reached through the CLI rather than over HTTP because the free tier is
    // only served to opencode itself — a request straight to the API comes
    // back "can only be used from within OpenCode".
    readonly property string askModel: "opencode/big-pickle"
    // plan, not build: it can read the machine to answer questions about it
    // and cannot write to it. A box that opens on a keystroke must not be one
    // keystroke away from editing a file.
    readonly property string askAgent: "plan"

    // The answer lands in a box under a query line, not in a terminal: an
    // essay would be scrolled past rather than read, and the markdown would
    // be drawn as the asterisks it is written with.
    readonly property string askPreamble: "Answer in at most three sentences, as plain text: no markdown, no preamble, no closing question. "

    // { q, text } — the answer and the question it belongs to, so one that
    // lands after the query has moved on is shown against nothing. The same
    // tagging the modes below use, for the same reason.
    property var askAnswer: null
    // The question a run is currently out for, or "". Also what the row's
    // subtitle reads off, which is why the dots below have a clock.
    property string asking: ""
    property int askTick: 0

    // "thinking" with one, two and three dots — padded back out to three with
    // U+2008, the punctuation space, which is a period wide. The subtitle is
    // right-aligned, so a label that grows a character pushes the word left:
    // without the padding "thinking" walks back and forth twice a second while
    // the answer is out.
    readonly property string askLabel: {
        const dots = 1 + root.askTick % 3;
        return "thinking" + ".".repeat(dots) + "\u2008".repeat(3 - dots);
    }

    // The answer to what is on screen now, or "": the one thing the box needs
    // to know to draw it.
    readonly property string answerShown: {
        if (root.query.charAt(0) !== root.askPrefix)
            return "";
        const q = root.query.slice(1).trim();
        return root.askAnswer && root.askAnswer.q === q ? root.askAnswer.text : "";
    }

    // One row, which is the question itself: Enter on it asks, and Enter on
    // it once there is an answer copies that instead. The answer is not in the
    // row — three sentences do not fit on a 28px line — it is the block the
    // box grows underneath it. See LauncherMenu.qml.
    // --- tasks and timers ----------------------------------------------------

    // Typing writes something down; not typing lists what is already written.
    // Both in one mode, because "what is on the list" and "put this on the
    // list" are the same thought a second apart, and a launcher that made you
    // choose between them up front would be asking before you knew.
    //
    // The add row goes first when there is anything to add. Capture is what
    // this mode is for and the fastest thing in a launcher is the row your
    // finger is already on; the tasks underneath are there to be ticked off,
    // which is a thing you came to do rather than a thing you are mid-flow on.
    function taskResults(query) {
        if (!Tasks.configured)
            return [
                {
                    kind: "note",
                    glyph: Theme.glyph.tasks,
                    title: "Google Tasks not connected — run ~/_scripts/gtasks-setup",
                    raw: true,
                    subtitle: ""
                }
            ];

        const typed = query.trim();
        const rows = [];

        if (typed.length) {
            const p = Tasks.parse(typed);
            rows.push({
                kind: "task-add",
                glyph: Theme.glyph.plus,
                // What was typed, not what was parsed: the row is a preview of
                // the line, and a title that silently dropped the "@fri" would
                // leave you unsure whether it had been understood or eaten.
                title: typed,
                raw: true,
                // Not Tasks.preview: that is written to stand on its own and
                // opens by repeating the task back, which on a row that is
                // already showing the task is the same words twice. What is
                // left is the part that was worked out rather than typed.
                subtitle: !p.ok ? p.error : "add" + (p.day !== "" ? "  ·  " + Tasks.sayDay(p.day) : "") + (Tasks.lists.length > 1 ? "  ·  " + Tasks.lists[0].title : ""),
                ok: p.ok,
                text: typed
            });
        }

        // Filtered on the parsed title rather than the raw line, or the "@fri"
        // in ",milk @fri" would be a term no task could match and the list
        // below would empty out exactly as the date was typed.
        const core = typed.length ? Tasks.parse(typed).title : "";
        const terms = core.toLowerCase().split(/\s+/).filter(t => t.length);
        const scored = [];

        for (const task of Tasks.ordered) {
            let s = 0;
            if (terms.length) {
                const m = root.matchScore(terms, [[task.title, 1], [task.notes, 0.5]]);
                if (m === null)
                    continue;
                s = m;
            }
            scored.push({
                s: s,
                row: {
                    kind: "task",
                    task: task,
                    glyph: Theme.glyph.taskOpen,
                    title: task.title,
                    raw: true,
                    subtitle: Tasks.sayDay(Tasks.dayOf(task)),
                    // The subtitle here is a date at most, so the title is not
                    // in a fight with it for the row.
                    titleShare: 0.82,
                    // The order the list is already in is the order it should
                    // keep when nothing is typed: by date, soonest first. Only
                    // a real query is allowed to reorder it.
                    dim: Tasks.urgency(task) === "none"
                }
            });
        }

        if (terms.length)
            scored.sort((a, b) => b.s - a.s);

        return rows.concat(scored.slice(0, root.maxResults).map(x => x.row));
    }

    // The same shape for timers: the line being typed on top, what is already
    // running underneath. Enter on a running one holds it rather than cancelling
    // it — cancelling is the one action here that loses something, and it is not
    // what a list of timers is usually opened to do.
    function timerResults(query) {
        const typed = query.trim();
        const rows = [];

        if (typed.length) {
            const p = Timers.parse(typed);
            rows.push({
                kind: "timer-add",
                glyph: p.ok && p.kind === "alarm" ? Theme.glyph.alarm : Theme.glyph.timer,
                title: typed,
                raw: true,
                // Same again: "25m" is what was typed and "25 minutes" is what
                // it was read as, so the reading is worth showing and the label
                // beside it is not.
                subtitle: Timers.brief(typed),
                ok: p.ok,
                text: typed
            });
        }

        for (const e of Timers.entries)
            rows.push({
                kind: "timer",
                entry: e,
                glyph: e.kind === "alarm" ? Theme.glyph.alarm : (e.running ? Theme.glyph.timer : Theme.glyph.timerPaused),
                title: Timers.describe(e),
                raw: true,
                subtitle: e.running ? "" : "paused",
                dim: !e.running
            });

        return rows;
    }

    function askResults(query) {
        if (!query)
            return [];
        const answered = root.askAnswer && root.askAnswer.q === query;
        return [
            {
                kind: "ask",
                q: query,
                glyph: Theme.glyph.ask,
                title: query,
                raw: true,
                subtitle: root.asking === query ? root.askLabel : (answered ? "copy" : "ask"),
                answer: answered ? root.askAnswer.text : ""
            }
        ];
    }

    function askRun(q): void {
        if (!q || ask.running)
            return;
        root.askAnswer = null;
        root.asking = q;
        root.askTick = 0;
        ask.acc = "";
        ask.arg = q;
        ask.running = true;
    }

    Process {
        id: ask

        property string arg: ""
        // The answer as it arrives. opencode emits a JSON event per part, and
        // a long answer comes in several, so the block fills in rather than
        // appearing all at once.
        property string acc: ""

        // Through sh for the redirect, which is not a nicety: opencode reads
        // its stdin whenever its stdout is a pipe, and a process spawned from
        // here has a stdin that nothing will ever write to or close — so the
        // run hangs on it forever rather than answering. /dev/null is the EOF
        // it is waiting for. The question goes in as an argument for the same
        // reason the clipboard copy passes text as one: it is typed text, and
        // nothing should have to quote it.
        //
        // timeout, because this is a network call through a node process and
        // the box is sitting on it with a row that says "thinking".
        command: ["sh", "-c", 'exec timeout 60 opencode run --pure --dir "$1" --agent "$2" --format json --title launcher -m "$3" "$4" </dev/null', "sh", Quickshell.env("HOME"), root.askAgent, root.askModel, root.askPreamble + ask.arg]

        onExited: {
            root.asking = "";
            root.askAnswer = ({
                    q: ask.arg,
                    text: ask.acc.trim() || "no answer"
                });
        }

        stdout: SplitParser {
            onRead: function (line) {
                let e = null;
                // Every line is an event and only some of them are the answer.
                // A line that is not JSON at all is opencode talking to its
                // own terminal, which is not this box's business.
                try {
                    e = JSON.parse(line);
                } catch (err) {
                    return;
                }
                if (!e || e.type !== "text" || !e.part || !e.part.text)
                    return;
                ask.acc += (ask.acc ? "\n\n" : "") + e.part.text;
                root.askAnswer = ({
                        q: ask.arg,
                        text: ask.acc.trim()
                    });
            }
        }
    }

    // The dots after "thinking". Three and a half seconds of a word that does
    // not move reads as a box that has stopped rather than one that is busy.
    Timer {
        id: askDots

        running: root.asking !== ""
        repeat: true
        interval: 400
        onTriggered: root.askTick++
    }

    // --- shelling out --------------------------------------------------------

    // qalc, fd and cliphist are all the same shape: run this for the query as
    // it stands. A query that moves while one is in flight must not mean two
    // of them at once, and killing the running one is not the answer —
    // Process.running = false sends a signal and returns, so the next start
    // would race the death of the last. The new run is queued behind the old
    // one instead. All three finish in tens of milliseconds, so the queue is
    // never more than one deep.
    //
    // `want` is what the query asks for and `arg` is what the run in progress
    // was for. Every answer is tagged with the `arg` it came from, so one that
    // lands after the query has moved on is simply not matched by the results
    // binding rather than shown against the wrong input.
    //
    // Only the debounce timers call this. An exiting run that finds newer work
    // waiting restarts its timer rather than starting that work itself —
    // otherwise the debounce would only ever hold back the first run, and
    // every one after it would launch the moment the last exited. Typing
    // steadily would then mean a process per exit for as long as you typed,
    // which is the thing a debounce is there to stop.
    function pump(proc): void {
        if (proc.running || proc.want === proc.arg)
            return;
        proc.arg = proc.want;
        if (proc.arg)
            proc.running = true;
    }

    // Every keystroke: point the shelling-out modes at what the query now says
    // and start their clocks. Which of them gets read is the results binding's
    // business — but a mode has to have been asked before it is shown, or the
    // answer arrives a beat after the row it belongs to.
    function route(): void {
        const q = root.query;
        const sym = q.charAt(0);
        const rest = q.slice(1).trim();
        const t = q.trim();

        qalc.want = sym === root.calcPrefix ? rest : (root.looksLikeMath(t) ? t : "");
        if (qalc.want)
            calcDebounce.restart();
        else
            calcDebounce.stop();

        // Three characters before walking the disk. Fewer than that matches
        // most of the home directory, and fasd has already answered anyway.
        fd.want = sym === root.pathPrefix && rest.length >= 3 ? rest : "";
        if (fd.want)
            fdDebounce.restart();
        else
            fdDebounce.stop();

        // Read once and then kept, so this is a real ask only on the first #
        // of a session — and a rescan of mpd's database is what makes it one
        // again. See services/Library.qml.
        if (sym === root.musicPrefix) {
            Library.ensure();
            // Scoring ten thousand titles is 50ms for one word and 160ms for
            // three, which is a keystroke the box does not answer. Debounced
            // like the two that shell out, and for the same reason — the only
            // difference is that this one burns the time here rather than in
            // another process.
            //
            // Except for the first query of the mode, which is scored on the
            // spot: there is nothing on screen yet to stand in for it, and a
            // list that arrives blank and fills in 60ms later is the flicker
            // the debounce is supposed to prevent.
            if (!root.musicQuery)
                root.musicQuery = rest;
            else
                musicDebounce.restart();
        } else {
            musicDebounce.stop();
            root.musicQuery = "";
        }

        // Asked once per open, on the keystroke that first names the mode.
        // `asked` rather than "arrived": the second character typed must not
        // start a second read of the same list.
        if (sym === root.clipPrefix && !clip.asked) {
            clip.asked = true;
            clip.running = true;
        }
    }

    // --- calculator ----------------------------------------------------------

    // What qalc last said, and what it was asked. See pump().
    property var calcAnswer: null

    // qalc answers everything. "hello" is 2.718281828 B·h·L² — e, in
    // bytes·hours·litres² — and "1password" is 1 pa·word·s². So an unprefixed
    // query is gated on the way in rather than on what comes back.
    function looksLikeMath(q) {
        // A word against an open bracket is a call, and no application is
        // named like one: sqrt(2), log(10), sin(0).
        if (/^[a-z]+\(/i.test(q))
            return true;
        // Otherwise a sum, which starts with a number, a sign or a bracket and
        // carries an operator or a space past that. "192.168.1.1" and "7zip"
        // have the start but not the rest.
        if (!/^[-+(.\d]/.test(q) || !/[-+*/^%!]|\s/.test(q.slice(1)))
            return false;
        // And then: letters in a sum are units, and qalc will read any bare
        // word as one — "0 A.D." comes back 0 A·C·m, which is amperes by
        // coulombs by metres and is not what was being typed. A unit only
        // means a calculation when the query says what to turn it into, so
        // letters have to come with a "to" or an "in". "2+2" has neither and
        // needs neither.
        return !/[a-z]/i.test(q) || /\b(to|in)\b/i.test(q);
    }

    function calcResults(expr, strict) {
        const a = root.calcAnswer;
        if (!expr || !a || a.expr !== expr || !a.text)
            return [];

        // The other half of the gate, for the unprefixed case only. qalc hands
        // back what it was given when it cannot do anything with it — "1/0" is
        // answered with "1 / 0" — and a row that restates the query is not an
        // answer. Under "=" it is left alone: there the question was asked on
        // purpose, and "=2" showing 2 is qalc being right.
        const flat = t => t.replace(/\s+/g, "").toLowerCase();
        if (strict && flat(a.text) === flat(expr))
            return [];

        return [
            {
                kind: "calc",
                answer: a.text,
                badge: root.calcPrefix,
                title: a.text,
                subtitle: expr,
                raw: true
            }
        ];
    }

    Process {
        id: qalc

        property string want: ""
        property string arg: ""

        // The expression as an argument, not on stdin. Fed through a pipe,
        // qalc reads it as an interactive session and answers with its prompt
        // and ANSI colour wrapped round the number. -t is the terse mode this
        // wants, and it does units and currency with no more asking — the
        // exchange rates come from its own cache, so "10 usd to eur" answers
        // offline.
        //
        // Deliberately not a JS eval of the expression: the query line would
        // then be running whatever was typed into it, on every keystroke,
        // inside the process that draws the bar.
        //
        // Under timeout, because qalc can be asked something it will never
        // finish: "999999999!" pins a core and never returns. Without a limit
        // that would be the end of the calculator for the rest of the session
        // — the run never exits, so pump() is never called again and every
        // later expression queues behind a process that is not coming back.
        // Two seconds is an eternity next to the 20ms a real answer takes.
        command: ["timeout", "2", "qalc", "-t", qalc.arg]

        // Not pump() directly: see the note there. Nothing is queued once the
        // box is gone either, or closing mid-expression would still spawn one
        // more run against a query nobody can see.
        onExited: if (root.shown && qalc.want !== qalc.arg)
            calcDebounce.restart()

        stdout: StdioCollector {
            onStreamFinished: root.calcAnswer = ({
                    expr: qalc.arg,
                    text: text.trim()
                })
        }
    }

    Timer {
        id: calcDebounce

        interval: 60
        onTriggered: root.pump(qalc)
    }

    // --- urls ----------------------------------------------------------------

    // Enough of the real TLDs to cover what actually gets typed here. An
    // allowlist rather than a shape test, because "config.json" and "Fuzzy.js"
    // are the shape of a domain and neither is one.
    readonly property var tlds: ["com", "org", "net", "io", "dev", "ai", "app", "co", "gr", "uk", "de", "fr", "it", "es", "nl", "eu", "ru", "jp", "cn", "br", "ca", "au", "nz", "se", "no", "dk", "fi", "cz", "pt", "ro", "bg", "hu", "ch", "at", "be", "ie", "gov", "edu", "info", "xyz", "me", "tv", "gg", "fm", "to", "ly", "st", "page", "cloud", "tech", "site", "online", "store", "blog", "news", "live", "sh", "md", "so", "rs", "pl", "cc", "in", "us"]

    // Real TLDs that are also file extensions on this machine. A bare
    // "install.sh" or "README.md" is the file far more often than the site, so
    // these only count as a domain when something else in the string says URL:
    // a scheme, a www., a port or a path.
    //
    // Every one of these has to appear in `tlds` as well — that list is what
    // decides a domain at all, and this one only holds some of them back.
    readonly property var extTlds: ["sh", "md", "so", "rs", "pl", "cc", "in"]

    function urlResults(q) {
        // A domain has no spaces in it, and a query with one is a sentence.
        if (!q || /\s/.test(q))
            return [];

        const scheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(q);
        const host = (scheme ? (q.split("/")[2] ?? "") : q).split("/")[0].split("?")[0].split("#")[0].split(":")[0];

        let ok = scheme;
        if (!ok && (/^localhost$/i.test(host) || /^\d{1,3}(\.\d{1,3}){3}$/.test(host))) {
            ok = true;
        } else if (!ok) {
            const m = host.toLowerCase().match(/^([a-z0-9-]+\.)+([a-z]{2,})$/);
            const hint = /^www\./i.test(q) || /[/?#]/.test(q) || /:\d+/.test(q);
            ok = !!m && root.tlds.indexOf(m[2]) !== -1 && (hint || root.extTlds.indexOf(m[2]) === -1);
        }
        if (!ok)
            return [];

        // https for the internet, because a bare domain typed at a launcher
        // in 2026 is a site that has had TLS for a decade and anything that
        // has not will redirect. http for the machine and the LAN, where the
        // thing on the port is a dev server with no certificate and https is
        // the one that fails.
        const local = /^localhost$/i.test(host) || /^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host);

        return [
            {
                kind: "url",
                glyph: Theme.glyph.web,
                title: "open " + q,
                subtitle: host.replace(/^www\./i, ""),
                raw: true,
                url: scheme ? q : (local ? "http://" : "https://") + q
            }
        ];
    }

    // --- run command ---------------------------------------------------------

    function cmdResults(cmd) {
        // ">" on its own is the history, the same way the empty app query is.
        if (!cmd)
            return root.recent("cmd:").map(c => root.cmdRow(c, false));
        // Two rows for the one command, because the answer to "did that work"
        // lives in a terminal and the answer to "open this thing" does not.
        return [root.cmdRow(cmd, false), root.cmdRow(cmd, true)];
    }

    function cmdRow(cmd, term) {
        return {
            kind: "cmd",
            cmd: cmd,
            term: term,
            title: cmd,
            subtitle: term ? "run in terminal" : "run",
            badge: term ? root.cmdPrefix + "_" : root.cmdPrefix,
            raw: true
        };
    }

    // --- clipboard -----------------------------------------------------------

    // cliphist's whole list, read once the first time the mode is opened and
    // filtered in here after that. Per keystroke it would be a process per
    // letter, for a list that cannot change while you are looking at it.
    property var clipEntries: []

    function clipResults(query) {
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
                {
                    kind: "note",
                    glyph: Theme.glyph.clipboard,
                    title: "no clipboard history",
                    subtitle: "needs cliphist storing",
                    raw: true
                }
            ];

        const terms = query.toLowerCase().split(/\s+/).filter(t => t.length);
        const scored = [];

        for (let i = 0; i < root.clipEntries.length; i++) {
            const e = root.clipEntries[i];
            // cliphist lists newest first, and with nothing typed that order
            // is the answer — the thing you just copied is the thing you want.
            let s = -i;

            if (terms.length) {
                const m = root.matchScore(terms, [[e.text, 1]]);
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
        return scored.slice(0, root.maxResults).map(x => ({
                    kind: "clip",
                    id: x.e.id,
                    line: x.e.line,
                    glyph: Theme.glyph.clipboard,
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
            // id is what decodes back to the real thing, so both are kept.
            onStreamFinished: root.clipEntries = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => ({
                        id: l.slice(0, l.indexOf("\t")),
                        line: l,
                        text: l.slice(l.indexOf("\t") + 1)
                    }))
        }
    }

    // --- music ---------------------------------------------------------------

    // The library, and the one mode whose rows are a tree rather than a list.
    // What is in it is services/Library.qml's business; this is how it is laid
    // out, walked and acted on.

    // The tree's entire state: the keys of the rows Tab has opened. Keys are
    // paths ("artist:3/album:7"), so the same record found twice — once on
    // its own, once under its artist — opens where it was asked to and
    // nowhere else.
    property var open: ({})

    // The query the library has actually been scored against, which trails
    // the one in the box by the debounce below. The rows on screen are always
    // this query's rows, the way the calculator's answer is always tagged with
    // the expression it came from.
    property string musicQuery: ""

    Timer {
        id: musicDebounce

        // The calculator's interval. Both are answering the same thing — the
        // pause between two keystrokes — and one of them being a process and
        // the other a loop is not a reason for them to wait different lengths.
        interval: 60
        onTriggered: root.musicQuery = root.query.slice(1).trim()
    }

    // What the query turned up, ranked, before any of it is laid out as rows.
    //
    // Separate from the rows on purpose. The tree rearranges itself constantly
    // — every arrow key opens a record and shuts another — and the rows are
    // rebuilt each time it does. Ranking and laying out in one pass meant
    // every one of those presses re-scored the whole library: a tenth of a
    // second to walk down a discography whose order had not changed. This
    // depends on the query and the library and nothing else, so the walking is
    // free and only typing costs anything.
    readonly property var musicHits: {
        if (!Library.loaded || !root.musicQuery)
            return [];

        // Playlists are ranked here rather than in the library, which has
        // never heard of them — they are mpd's, not the database's. Same
        // matcher and the same scale, so they sort in among everything else
        // rather than being a section of their own.
        const scored = Library.search(root.musicQuery).map(h => ({
                    hit: h,
                    s: h.score
                }));
        const terms = root.musicQuery.toLowerCase().split(/\s+/).filter(t => t.length);
        for (const name of Mpd.playlists) {
            const m = root.matchScore(terms, [[name, 1]]);
            if (m !== null)
                scored.push({
                    playlist: name,
                    s: m
                });
        }
        scored.sort((a, b) => b.s - a.s);
        return scored.slice(0, root.maxResults);
    }

    function musicResults(query) {
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
        for (const x of root.musicHits) {
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

    function move(dir): void {
        const n = root.results.length;
        if (n)
            root.index = (root.index + dir + n) % n;
    }

    function selectAt(i): void {
        root.index = i;
    }

    // Tab. An artist or a record opens or shuts; anything inside one shuts
    // the one it is in and goes back up to it, so the same key that went in
    // comes back out. Opening only adds rows below the selection, and
    // shutting from inside lands on a row above everything that goes, so the
    // index never has to be looked up again afterwards.
    function fold(): void {
        const rows = root.results;
        const r = rows[root.index];
        if (!r)
            return;
        let at = root.index;
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
        root.index = at;
    }

    // A page, in a tree, is the next thing at this level rather than twelve
    // rows further down: an open record's songs are stepped over.
    //
    // On PageUp and PageDown, which are dead keys in this mode: the two things
    // they otherwise page — a model's answer and the / panel's file — are
    // neither of them on screen next to a library. See LauncherMenu.qml.
    function skip(dir): void {
        const rows = root.results;
        for (let i = root.index + dir; i >= 0 && i < rows.length; i += dir) {
            if (rows[i].kind === "music-track" && rows[i].parent)
                continue;
            root.index = i;
            return;
        }
    }

    // What the artwork panel is looking at. Worked out here because the row is
    // here; the panel only knows how to find a picture in a folder.
    readonly property string coverDir: {
        const r = root.selected;
        if (!root.musicMode || !r || r.kind.indexOf("music-") !== 0)
            return "";
        const kind = r.kind.slice(6);
        if (kind !== "artist" && kind !== "album" && kind !== "track")
            return "";
        return Library.coverDir(kind, r.at);
    }

    function engineResults(sym, rest) {
        const group = root.prefixes[sym];
        const m = rest.match(/^(\S+)(?:\s+(.*))?$/);
        let key = group.fallback;
        let q = rest.trim();
        // The first word is an engine key only if it actually names one, so
        // "_lofi" searches for lofi rather than looking for an engine "lofi".
        if (m && group.engines.some(e => e.key === m[1])) {
            key = m[1];
            q = (m[2] || "").trim();
        }

        // Selected engine first, the rest following in the order they are
        // listed, so the list does not reshuffle itself as you type.
        const picked = group.engines.filter(e => e.key === key);
        const others = group.engines.filter(e => e.key !== key);
        return picked.concat(others).map(e => ({
                    kind: "url",
                    badge: sym + e.key,
                    title: q ? e.name + " — " + q : e.name,
                    // The host, so it is clear where Enter goes — without the
                    // www., which is four characters carrying no information on
                    // a line that exists to be glanced at.
                    subtitle: e.url.split("/")[2].replace(/^www\./, ""),
                    url: e.url.replace("%s", encodeURIComponent(q))
                }));
    }

    // `mode` is only for the music rows — "queue", "play" or "next", from
    // which modifier was held with Enter.
    function activate(i, mode): void {
        const r = root.results[i];
        if (!r)
            return;

        // A row that is only telling you something has nothing to activate,
        // and closing the launcher would take the message with it.
        if (r.kind === "note")
            return;

        // Everything else in the library goes the same way: whatever files the
        // row stands for, wherever the key that chose it says to put them.
        // A playlist is the exception only in that mpd loads it by name — it
        // is a list of files this has never read.
        //
        // Only play leaves. Queueing and play-next are things you do several
        // of in a row, so the box stays up with the selection where it was.
        if (r.kind.indexOf("music-") === 0) {
            mode = mode || "queue";
            if (mode === "play")
                root.leave(i);
            if (r.kind === "music-playlist")
                Mpd.loadPlaylist(r.name, mode);
            else
                Mpd.enqueue(Library.files(r.kind.slice(6), r.at), mode);
            return;
        }

        // Ticking a task off is not leaving. You open this having let three
        // things pile up, and a box that shut after each one would have to be
        // reopened between them — same reasoning as queueing a song below.
        // Adding one does leave: that is a sentence finished.
        if (r.kind === "task") {
            Tasks.complete(r.task);
            return;
        }
        if (r.kind === "task-add") {
            if (!r.ok)
                return;
            root.leave(i);
            Tasks.run(r.text);
            return;
        }
        // Likewise: holding and releasing a timer is something you do to the
        // one you are looking at, and then look at the next one.
        if (r.kind === "timer") {
            Timers.toggle(r.entry.id);
            return;
        }
        if (r.kind === "timer-add") {
            if (!r.ok)
                return;
            root.leave(i);
            Timers.run(r.text);
            return;
        }

        // Asking is not leaving: the answer is drawn in this box, so the box
        // has to still be here when it arrives. Copying one is leaving, the
        // same way the calculator's answer is.
        if (r.kind === "ask") {
            if (!r.answer) {
                root.askRun(r.q);
                return;
            }
            root.leave(i);
            Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", r.answer]);
            return;
        }

        root.leave(i);
        if (r.kind === "app") {
            root.bump(r.entry.id);
            r.entry.execute();
        } else if (r.kind === "calc") {
            // The answer to the clipboard, which is the only place it could be
            // going. Through sh rather than as a wl-copy argument because an
            // answer can start with a minus — "-40 °C" would be read as flags.
            Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", r.answer]);
        } else if (r.kind === "cmd") {
            root.bump("cmd:" + r.cmd);
            // --hold keeps the window up after the command ends, which is the
            // only reason to have asked for a terminal: a command that exits
            // instantly would otherwise take its own output with it.
            if (r.term)
                Quickshell.execDetached(["kitty", "--hold", "sh", "-c", r.cmd]);
            else
                Quickshell.execDetached(["sh", "-c", r.cmd]);
        } else if (r.kind === "power") {
            root.bump("power:" + r.action.key);
            // The irreversible ones keep their second look. See Power.arm.
            if (r.action.confirm)
                Power.arm(r.action);
            else
                Power.run(r.action.arg);
        } else if (r.kind === "clip") {
            // decode, not the preview: the preview is one line of what may be
            // several, and for an image it is a description of the bytes.
            Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", r.id]);
        } else if (r.kind === "path") {
            // Keep fasd's ranking fresh, the same way f.fish does on its way
            // out, so picking a path here also trains `f` in the terminal.
            Quickshell.execDetached(["fasd", "-A", r.path]);
            // A file opens in $EDITOR the way f.fish opens one, and in a
            // terminal because that is where an editor lives. Still not
            // xdg-open: that would hand a .conf to a text viewer and a .png to
            // an image app, which is not what f does.
            //
            // A directory goes to Dolphin rather than to a prompt sitting in
            // it. f cd-s there because the next thing you type in a terminal
            // is a command about the place; picking a folder out of a list of
            // folders is the other errand, and it wants the folder open and
            // its contents visible without an ls.
            if (r.dir)
                Quickshell.execDetached(["dolphin", r.path]);
            else
                Quickshell.execDetached(["kitty", "-e", Quickshell.env("EDITOR") || "nvim", r.path]);
        } else {
            Quickshell.execDetached(["xdg-open", r.url]);
        }
    }

    // Ctrl+Delete. Only the clipboard has anything to forget: an app you
    // stop using falls off the list on its own, and a path is fasd's to keep.
    function forget(i): void {
        const r = root.results[i];
        if (!r || r.kind !== "clip")
            return;

        // cliphist takes the whole list line back on stdin, id and preview
        // both, rather than the id on its own.
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", r.line]);
        // Dropped here too rather than re-reading the list: the row should go
        // while the finger is still on the key.
        root.clipEntries = root.clipEntries.filter(e => e.id !== r.id);
    }

    // --- frecency ------------------------------------------------------------

    // Usage, decayed by how long ago it was: something run twice this morning
    // outranks something run twice last month.
    function frecency(id) {
        const r = root.db[id];
        if (!r)
            return 0;
        const ageH = (Date.now() - r.last) / 3600000;
        const w = ageH < 4 ? 4 : ageH < 24 ? 2 : ageH < 168 ? 1 : 0.5;
        return r.count * w;
    }

    // The keys under one namespace, best first. Commands share the app db
    // rather than getting one of their own: it is the same question asked of
    // a different kind of thing, and the same decay answers it.
    function recent(prefix) {
        return Object.keys(root.db).filter(k => k.indexOf(prefix) === 0).sort((a, b) => root.frecency(b) - root.frecency(a)).slice(0, 10).map(k => k.slice(prefix.length));
    }

    function bump(id): void {
        // A fresh object rather than a mutation: `db` is a var property, and
        // changing one in place does not notify, so the results binding would
        // keep the ranking it had until the next keystroke.
        const next = Object.assign({}, root.db);
        next[id] = {
            // Capped, so an app opened a thousand times cannot sit at the top
            // of the list for the rest of the machine's life.
            count: Math.min((root.db[id]?.count ?? 0) + 1, 200),
            last: Date.now()
        };
        root.db = next;
        store.setText(JSON.stringify(next));
    }

    FileView {
        id: store

        path: Quickshell.statePath("launcher-frecency.json")
        // Stated rather than left to the default: the load is what emits
        // `loaded`, and without it the first launch would write a db holding
        // one app over the real one — history would reset on every restart.
        preload: true
        // There is no file until the first launch, and a missing one on a
        // fresh install is not worth a line in the log.
        printErrors: false

        onLoaded: {
            try {
                root.db = JSON.parse(store.text());
            } catch (e) {
                root.db = {};
            }
        }
    }

    IpcHandler {
        target: "launcher"

        // Not show/hide: `show` is one of `qs ipc`'s own subcommands, and
        // `qs ipc call launcher show` prints the handler instead of calling it.
        function toggle(): void {
            root.toggle();
        }

        // Close if open, and say whether there was anything to close. The bool
        // is the point: smart-close.sh (Super+Q) has to tell "I closed the
        // launcher, stop here" from "nothing was up, go close a window" —
        // `toggle` would have opened the launcher in the second case.
        // Open already in a mode, for the keys that used to raise a box of
        // their own: Super+T and Super+Shift+T. Toggling rather than opening,
        // so the same key puts it away — and only when it is already in that
        // mode, or Super+T on an open task box would close it instead of
        // switching.
        function open(prefix: string): void {
            root.openWith(prefix);
        }

        function dismiss(): bool {
            const was = root.shown;
            root.hide();
            return was;
        }
    }
}
