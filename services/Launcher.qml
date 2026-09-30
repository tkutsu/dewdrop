pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.components
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

    // The first character of the query picks a mode. "#" is search: the word
    // after it can name an engine ("#y lofi"), and without one the query goes
    // to the fallback ("#lofi" is a Google search).
    //
    // One search prefix rather than one per family, because the split between
    // "web" and "AI" was a distinction about the destination, not about what
    // you are doing — in both cases you are typing a question and picking who
    // answers it.
    //
    // A hash, which is what a search tag reads as, and not the full stop this
    // would rather have been: a leading dot would take the decimals off the
    // calculator, since the mode is picked before anything looks at what
    // follows and ".5*2" would be a web search for "5*2". See looksLikeMath.
    // The underscore it used to be went to the windows below.
    //
    // One letter each, and Google has none at all — it is what a bare "#"
    // does, so the search run most often costs the fewest keys. Claude is
    // "#l" because ChatGPT holds the "c", so the key moved to the next free
    // letter of the word, which costs nothing to remember because the hint
    // line marks the key where it falls: "#c[l]aude".
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
    readonly property string enginePrefix: "#"

    readonly property var prefixes: ({
            // Keyed by the prefix, which has to be `enginePrefix` written out:
            // an object literal cannot name one of its own properties.
            "#": {
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
                        hint: "maps",
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
    // The windows that are open, by workspace, to go to one. The underscore:
    // the one character here that starts nothing else — not a path, not a
    // sum, not a command, not a quoted line.
    readonly property string windowPrefix: "_"
    // The library: artists, their records, the songs on them, and the stored
    // playlists. An ampersand, which starts nothing else here — it is not a
    // path, a sum, a prompt, a quoted line or a window.
    readonly property string musicPrefix: "&"
    // Mail: the unread on its own, a search of the whole mailbox past it. The
    // at-sign, which is what an address reads as.
    readonly property string mailPrefix: "@"
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
    // not the question any more — which of them answers it is, and the
    // letter that picks each one is the thing worth having in front of you.
    readonly property string prefixHint: [root.pathPrefix + "files", root.windowPrefix + "windows", root.clipPrefix + "clipboard", root.enginePrefix + "web", root.mailPrefix + "email", root.cmdPrefix + "run", root.taskPrefix + "task", root.timerPrefix + "timer", root.musicPrefix + "music", root.calcPrefix + "calc"].join("   ")

    // Each engine written as one word with its key bracketed inside it:
    // "#[y]outube". The brackets are the whole instruction — which letter to
    // type and where it sits in the name — in the space the name was taking
    // anyway, where "#y youtube" spent a word saying the key twice.
    //
    // Google gets no brackets because it has no key, which is what "a bare #
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
    // of them. Same again one level down: "#" on its own is someone looking
    // for the engine they want, and "#y" is someone who has found it.
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
        // The keys, and Gmail's own search operators, which nothing on a mail
        // row hints at.
        if (root.mailOpen)
            return "tab back  ·  ↑↓ scroll  ·  enter open in gmail";
        if (root.mailMode)
            return "tab read  ·  ctrl+enter new mail  ·  from:  subject:  has:attachment";
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
    readonly property bool pathMode: root.pathQuery(root.query) !== null
    readonly property bool musicMode: root.query.charAt(0) === root.musicPrefix
    readonly property bool mailMode: root.query.charAt(0) === root.mailPrefix
    readonly property bool taskMode: root.query.charAt(0) === root.taskPrefix
    readonly property bool timerMode: root.query.charAt(0) === root.timerPrefix

    // What the files mode is asked, or null outside it. "/" asks outright. A
    // query that is "~" or starts "~/" is a path already, so it asks without
    // the prefix — the way a sum reaches the calculator unasked — and keeps
    // its tilde, which fdTerms reads as home.
    //
    // A function of the query rather than a property bound to it: route()
    // runs from onQueryChanged, which can fire before a binding on `query`
    // has caught up, and a stale answer there asks fd about the keystroke
    // before this one.
    function pathQuery(q) {
        if (q.charAt(0) === root.pathPrefix)
            return q.slice(1).trim();
        return /^~(\/|$)/.test(q) ? q.trim() : null;
    }
    // { appId: { count, last } }
    property var db: ({})

    // A new query is a new list, and the old cursor position means nothing in it.
    onQueryChanged: {
        root.index = 0;
        root.mailOpen = null;
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
        // The calculator's and fd's last answers are kept: each is tagged with
        // the query it was for, so it can only ever show against that query —
        // and it has to be kept, because QueuedProcess will not run the same
        // query twice in a row. Clearing them here meant that reopening the
        // box and typing the last expression again showed nothing at all.
        // The clipboard is different: it has moved on since last time, and a
        // row that is merely old is not worth the doubt.
        root.clipEntries = [];
        clip.asked = false;
        fasd.asked = false;
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
        // Closing is not a keystroke, so route() never runs to stop the clocks
        // the modes keep; a run they started against a box that is gone would
        // be work nobody sees.
        qalc.cancel();
        fd.cancel();
        LauncherMusic.cancel();
        mailSearch.stop();
        mailSearch.want = "";
    }

    // --- matching ------------------------------------------------------------

    // Space-separated terms are ANDed, the way rofi's `tokenize: true` did:
    // "fire priv" finds Firefox's private-window entry. Each term scores
    // against every field it is given and keeps its best hit; a term that
    // lands nowhere makes the whole thing a miss, which is null rather than a
    // low score — the caller drops those entirely.
    //
    // Folding is the expensive half of a score (see Fuzzy.js), so both sides
    // are folded before the loop rather than inside it: the terms once per
    // keystroke by prepTerms, the fields once per list by prepFields — or,
    // for a list too short to be worth keeping, once per call by matchScore.
    // Per entry per keystroke, which is what a folded term inside a folded
    // field loop came to, was a keystroke's worth of normalize() calls.
    function prepTerms(query) {
        return query.split(/\s+/).filter(t => t.length).map(t => Fuzzy.prepQuery(t));
    }

    // [text, weight] pairs to [raw, low, weight], with the empty ones gone: a
    // missing generic name is not a field that fails to match, it is no field.
    function prepFields(fields) {
        const out = [];
        for (const [text, weight] of fields) {
            if (!text)
                continue;
            const p = Fuzzy.prep(text);
            out.push([p[0], p[1], weight]);
        }
        return out;
    }

    function matchScore(terms, fields) {
        return root.matchPrepped(terms, root.prepFields(fields));
    }

    function matchPrepped(terms, fields) {
        let total = 0;
        for (const term of terms) {
            let best = null;
            for (const [raw, low, weight] of fields) {
                const v = Fuzzy.scorePrepped(term, raw, low);
                if (v !== null && (best === null || v * weight > best))
                    best = v * weight;
            }
            if (best === null)
                return null;
            total += best;
        }
        return total;
    }

    // Each mode's rows, keyed by the character that picks it and given the
    // query with that character off. Most trim it: a space after the prefix
    // is not part of a path or a sum. The two that take a line being typed
    // do not, or ", " would read the same as "," and the preview under the
    // row would flicker between "nothing to set" and the real answer as the
    // space went in. The calculator is not strict here: "=" is someone asking
    // qalc a question on purpose, and whatever it says back is the answer.
    readonly property var modeResults: ({
            [root.calcPrefix]: rest => root.calcResults(rest.trim(), false),
            [root.cmdPrefix]: rest => root.cmdResults(rest.trim()),
            [root.clipPrefix]: rest => root.clipResults(rest.trim()),
            [root.windowPrefix]: rest => root.windowResults(rest.trim()),
            [root.musicPrefix]: rest => LauncherMusic.results(rest.trim()),
            [root.mailPrefix]: rest => root.mailResults(rest.trim()),
            [root.taskPrefix]: rest => root.taskResults(rest),
            [root.timerPrefix]: rest => root.timerResults(rest)
        })

    readonly property var results: {
        const q = root.query;
        // Nothing typed, nothing listed: the box opens as a bare query line.
        // A single space is the "show me everything" gesture — appResults
        // trims it off, so a space arrives there as an empty app query and
        // returns the whole menu in frecency order.
        if (!q.length)
            return [];

        const files = root.pathQuery(q);
        if (files !== null)
            return root.pathResults(files);

        const sym = q.charAt(0);
        const mode = root.modeResults[sym];
        if (mode)
            return mode(q.slice(1));
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
        const terms = root.prepTerms(query);
        const scored = root.appMatches(terms).concat(root.powerMatches(terms));
        scored.sort((a, b) => b.s - a.s || a.row.title.localeCompare(b.row.title));
        return scored.slice(0, root.maxResults).map(x => x.row);
    }

    // The menu with its fields folded, rebuilt when the installed apps
    // change and read on every keystroke.
    //
    // rofi's drun-match-fields: name, generic, keywords, categories.
    // Weighted, because a hit on the name means more than a hit on a
    // category half the menu shares.
    //
    // Deliberately not e.id: Chrome PWAs are installed with ids like
    // "chrome-<hash>-Default", so every one of them would answer to "chrome".
    readonly property var appIndex: DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => ({
                entry: e,
                fields: root.prepFields([[e.name, 1], [e.genericName, 0.7]].concat(Array.from(e.keywords ?? []).map(k => [k, 0.6])).concat(Array.from(e.categories ?? []).map(c => [c, 0.4])))
            }))

    // Scored, not rendered: mainResults sorts these in with the power
    // commands, so the rows cannot be cut to maxResults yet.
    function appMatches(terms) {
        const scored = [];

        for (const a of root.appIndex) {
            const e = a.entry;
            const f = root.frecency(e.id);
            // With nothing typed the list is pure history, so opening the
            // launcher and pressing Enter reruns what you last ran.
            let s = f;

            if (terms.length) {
                const m = root.matchPrepped(terms, a.fields);
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
                        fields: root.prepFields([[base, 1], [path, 0.5]])
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
        return Settings.expand(query).toLowerCase().split(/[\s/]+/).filter(t => t.length);
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
        command: ["timeout", "5", "fd", "--hidden", "--max-results", root.fdTerms(fd.arg).length > 1 ? "200" : "60", "--max-depth", "6", "--type", "f", "--type", "d", "--ignore-file", root.fdIgnore].concat(root.fdTerms(fd.arg).length > 1 ? ["--full-path"] : []).concat([root.fdPattern(fd.arg), Settings.home])

        onResult: function (arg, text) {
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

    function pathResults(query) {
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
                const m = root.matchPrepped(terms, e.fields);
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
                    title: `Google Tasks not connected — run ${Google.setup}`,
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
        const terms = root.prepTerms(core);
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

        // No title here: it is Timers.describe(entry), which counts down, and
        // a string that changed every second would rebuild this list every
        // second and have the view drop every row. The delegate binds it
        // live off `entry` instead — see LauncherMenu.qml.
        for (const e of Timers.entries)
            rows.push({
                kind: "timer",
                entry: e,
                glyph: e.kind === "alarm" ? Theme.glyph.alarm : (e.running ? Theme.glyph.timer : Theme.glyph.timerPaused),
                title: "",
                raw: true,
                subtitle: e.running ? "" : "paused",
                dim: !e.running
            });

        return rows;
    }

    // --- mail ----------------------------------------------------------------

    // "@" on its own is the unread the bar already has, so it is on screen at
    // once. Anything past it is a Gmail search, which is a round trip to
    // Google — debounced harder than the disk walk for it, and shown only
    // once the answer for this exact query is back (see Email.found).
    function mailResults(query) {
        const note = title => [
                {
                    kind: "note",
                    glyph: Theme.glyph.mailRead,
                    title: title,
                    raw: true,
                    subtitle: ""
                }
            ];
        if (!Email.configured)
            return note(`Gmail not connected — run ${Google.setup}`);

        // Reading one: its row alone, as the header over its text, which the
        // box draws under the list (see LauncherMenu's reader).
        if (root.mailOpen)
            return [root.mailRow(root.mailOpen)];

        if (!query) {
            if (!Email.loaded)
                return note(Email.trouble || "reading mail…");
            if (Email.threads.length)
                return Email.threads.map(root.mailRow);
            // Nothing unread: the inbox, newest first, which route() has
            // already asked for. The note stands in until it lands.
            const recent = Email.found;
            if (!recent || recent.q !== root.recentMail || !recent.rows.length)
                return note("no unread mail");
            return recent.rows.map(root.mailRow);
        }

        const found = Email.found;
        if (!found || found.q !== query)
            return note("searching…");
        if (found.trouble)
            return note(found.trouble);
        return found.rows.length ? found.rows.map(root.mailRow) : note("no mail matches");
    }

    // The thread Tab opened to read, or null. The thread itself rather than
    // its id: reading marks it read, which takes it off the unread list this
    // would otherwise have to find it in.
    property var mailOpen: null
    // Its text, "" until it lands.
    readonly property string mailText: root.mailOpen ? (Email.bodies[root.mailOpen.message] ?? "") : ""

    // Tab in mail mode: read the selected mail, or go back to the list from
    // one, onto the row it was read from if it is still there. Reading counts
    // as read, the way opening it in Gmail does.
    function mailFold(): void {
        const open = root.mailOpen;
        if (open) {
            root.mailOpen = null;
            root.index = Math.max(0, root.results.findIndex(x => x.kind === "mail" && x.thread.id === open.id));
            return;
        }
        const r = root.selected;
        if (!r || r.kind !== "mail")
            return;
        Email.read(r.thread);
        if (r.thread.unread)
            Email.markRead(r.thread);
        root.mailOpen = Object.assign({}, r.thread, {
            unread: false
        });
        root.index = 0;
    }

    // Subject first, since it is what the mail is; who and when to the right.
    // A read thread sits a shade back; a starred one wears the star, which is
    // what put it at the top of a search.
    function mailRow(t) {
        return {
            kind: "mail",
            thread: t,
            glyph: t.starred ? Theme.glyph.mailStarred : t.unread ? Theme.glyph.mailUnread : Theme.glyph.mailRead,
            title: t.subject,
            subtitle: [t.from, Email.sayWhen(t.at)].filter(x => x).join("  ·  "),
            raw: true,
            dim: !t.unread
        };
    }

    Timer {
        id: mailSearch

        property string want: ""

        interval: 300
        onTriggered: Email.search(mailSearch.want, true)
    }

    // What a bare "#" lists when nothing is unread.
    readonly property string recentMail: "in:inbox"

    // --- windows -------------------------------------------------------------

    // Every window, grouped by the workspace it is on in the order the bar
    // lists them, and within one in the order Hyprland does. Typing narrows
    // the list rather than reordering it: the workspaces are the map, and a
    // window found by name is still found where it lives. Special workspaces
    // go last, being the ones nobody keeps in their head.
    function windowResults(query) {
        const terms = root.prepTerms(query);
        const rows = [];

        for (const t of Hyprland.toplevels.values) {
            const ws = t.workspace;
            if (!ws)
                continue;
            // A window that opened since the last `hyprctl clients` has no IPC
            // object yet; its Wayland app id is the same name a moment early.
            const cls = t.lastIpcObject?.class || t.wayland?.appId || "";
            const entry = cls ? DesktopEntries.heuristicLookup(cls) : null;
            const app = entry?.name || cls;

            if (terms.length && root.matchScore(terms, [[t.title, 1], [app, 0.8], [cls, 0.6]]) === null)
                continue;

            rows.push({
                kind: "window",
                address: t.address,
                // Negative ids are the special workspaces, sorted after the
                // numbered ones rather than before them.
                order: ws.id < 0 ? 1e6 - ws.id : ws.id,
                at: rows.length,
                icon: root.windowIcon(cls, entry),
                title: t.title || app,
                subtitle: [app, root.workspaceLabel(ws)].filter(x => x).join("  ·  "),
                raw: true
            });
        }

        // Hyprland's own order inside a workspace, said outright rather than
        // left to whether the engine's sort happens to be stable.
        rows.sort((a, b) => a.order - b.order || a.at - b.at);
        return rows.slice(0, root.maxResults);
    }

    // What the bar calls a workspace: its name, which for the ten on the
    // number row is the key that reaches it (see modules/Workspaces.qml).
    function workspaceLabel(ws) {
        return (ws.name ?? "").replace(/^special:/, "");
    }

    // The same search the taskbar makes (components/AppIcon.qml): the desktop
    // entry's icon, else a theme icon named after the class. Empty for none,
    // which the row answers with the window glyph.
    function windowIcon(cls, entry) {
        const override = Theme.appIconOverride[cls];
        if (override)
            return override;
        if (entry?.icon)
            return entry.icon;
        for (const candidate of [cls, cls.toLowerCase()])
            if (candidate && Quickshell.hasThemeIcon(candidate))
                return candidate;
        return "";
    }

    // --- shelling out --------------------------------------------------------

    // Every keystroke: point the modes that work between keystrokes at what
    // the query now says. qalc and fd are QueuedProcesses and start their own
    // clocks off `want`; the library scores in-process and keeps its own.
    // Which of them gets read is the results binding's business — but a mode
    // has to have been asked before it is shown, or the answer arrives a beat
    // after the row it belongs to.
    function route(): void {
        const q = root.query;
        const sym = q.charAt(0);
        const rest = q.slice(1).trim();
        const t = q.trim();
        const files = root.pathQuery(q);

        qalc.want = sym === root.calcPrefix ? rest : (root.looksLikeMath(t) ? t : "");

        // Three characters before walking the disk. Fewer than that matches
        // most of the home directory, and fasd has already answered anyway.
        fd.want = files !== null && files.length >= 3 ? files : "";

        LauncherMusic.route(sym === root.musicPrefix, rest);

        // A bare "#" with nothing unread lists the inbox instead. Asked at
        // once rather than after the debounce: nothing was typed to wait out.
        if (sym === root.mailPrefix && !rest && !Email.threads.length)
            Email.search(root.recentMail, false);

        const mail = sym === root.mailPrefix ? rest : "";
        if (mail !== mailSearch.want) {
            mailSearch.want = mail;
            if (mail)
                mailSearch.restart();
            else
                mailSearch.stop();
        }

        // Asked once per open, on the keystroke that first names the mode.
        // `asked` rather than "arrived": the second character typed must not
        // start a second read of the same list.
        if (files !== null && !fasd.asked) {
            fasd.asked = true;
            fasd.running = true;
        }
        if (sym === root.clipPrefix && !clip.asked) {
            clip.asked = true;
            clip.running = true;
        }
    }

    // --- calculator ----------------------------------------------------------

    // What qalc last said, and what it was asked. See QueuedProcess.
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

    QueuedProcess {
        id: qalc

        interval: 60

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
        // — the run never exits, so the queue behind it is never pumped and
        // every later expression waits on a process that is not coming back.
        // Two seconds is an eternity next to the 20ms a real answer takes.
        command: ["timeout", "2", "qalc", "-t", qalc.arg]

        onResult: function (arg, text) {
            root.calcAnswer = ({
                    expr: arg,
                    text: text.trim()
                });
        }
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
            return root.recent("cmd:").map(root.cmdRow);
        return [root.cmdRow(cmd)];
    }

    function cmdRow(cmd) {
        return {
            kind: "cmd",
            cmd: cmd,
            title: cmd,
            subtitle: "run in terminal",
            badge: root.cmdPrefix,
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

        const terms = root.prepTerms(query);
        const scored = [];
        const entries = root.clipEntries;

        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            // cliphist lists newest first, and with nothing typed that order
            // is the answer — the thing you just copied is the thing you want.
            let s = -i;

            if (terms.length) {
                const m = root.matchPrepped(terms, e.fields);
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
            // id is what decodes back to the real thing, so both are kept —
            // and the text folded for the matcher, once, here.
            onStreamFinished: root.clipEntries = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                const body = l.slice(l.indexOf("\t") + 1);
                return {
                    id: l.slice(0, l.indexOf("\t")),
                    line: l,
                    text: body,
                    fields: root.prepFields([[body, 1]])
                };
            })
        }
    }

    // --- selection -----------------------------------------------------------

    function move(dir): void {
        const n = root.results.length;
        if (n)
            root.index = (root.index + dir + n) % n;
    }

    function selectAt(i): void {
        root.index = i;
    }

    // --- engines -------------------------------------------------------------

    function engineResults(sym, rest) {
        const group = root.prefixes[sym];
        const m = rest.match(/^(\S+)(?:\s+(.*))?$/);
        let key = group.fallback;
        let q = rest.trim();
        // The first word is an engine key only if it actually names one, so
        // "#lofi" searches for lofi rather than looking for an engine "lofi".
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

    // --- activating ----------------------------------------------------------

    // Text to the clipboard. Through sh rather than as a wl-copy argument
    // because an answer can start with a minus — "-40 °C" would be read as
    // flags — and because it is typed text that nothing should have to quote.
    function copy(text): void {
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", text]);
    }

    // What Enter does to a row, by kind. Each one decides whether the box
    // leaves, and the ones that do say so first: leaving snapshots the list
    // for the exit animation (see LauncherMenu.qml), and a bump or an
    // execute before it would re-rank the rows the box is closing over.
    //
    // Ticking a task off and holding a timer are not leaving. You open this
    // having let three things pile up, and a box that shut after each one
    // would have to be reopened between them. Adding a task or a timer does
    // leave: that is a sentence finished.
    readonly property var actions: ({
            app: (r, i) => {
                root.leave(i);
                root.bump(r.entry.id);
                r.entry.execute();
            },
            calc: (r, i) => {
                root.leave(i);
                root.copy(r.answer);
            },
            cmd: (r, i) => {
                root.leave(i);
                root.bump("cmd:" + r.cmd);
                // Floating by title (see wrules.lua), and held open after the
                // command ends: one that exits instantly would otherwise take
                // its own output with it.
                Quickshell.execDetached(Settings.inTerminal(["sh", "-c", r.cmd], r.cmd + " (floating)", true));
            },
            power: (r, i) => {
                root.leave(i);
                root.bump("power:" + r.action.key);
                // The irreversible ones keep their second look. See Power.arm.
                if (r.action.confirm)
                    Power.arm(r.action);
                else
                    Power.run(r.action.arg);
            },
            clip: (r, i) => {
                root.leave(i);
                // decode, not the preview: the preview is one line of what
                // may be several, and for an image it is a description of
                // the bytes.
                Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", r.id]);
            },
            path: (r, i) => {
                root.leave(i);
                // Keep fasd's ranking fresh, the same way f.fish does on its
                // way out, so picking a path here also trains `f` in the
                // terminal.
                Quickshell.execDetached(["fasd", "-A", r.path]);
                // A text file opens in $EDITOR the way f.fish opens one, and
                // in a terminal because that is where an editor lives. Not
                // xdg-open for those: it would hand a .conf to a text viewer.
                // Anything binary does go to xdg-open, though, or a .png opens
                // in nvim as a screen of bytes. `file` decides, at the moment
                // of opening rather than per row, and an empty file counts as
                // text because it reads as binary to `file` and is almost
                // always something about to be written.
                //
                // A directory goes to Dolphin rather than to a prompt sitting
                // in it. f cd-s there because the next thing you type in a
                // terminal is a command about the place; picking a folder out
                // of a list of folders is the other errand, and it wants the
                // folder open and its contents visible without an ls.
                if (r.dir)
                    Quickshell.execDetached([Settings.fileManager, r.path]);
                else
                    Quickshell.execDetached(["sh", "-c", 'f=$1; shift; [ -s "$f" ] && [ "$(file -Lb --mime-encoding -- "$f")" = binary ] && exec xdg-open "$f"; exec "$@"', "sh", r.path, ...Settings.inTerminal([Settings.editor, r.path])]);
            },
            url: (r, i) => {
                root.leave(i);
                Quickshell.execDetached(["xdg-open", r.url]);
            },
            mail: (r, i) => {
                root.leave(i);
                Email.open(r.thread);
            },
            window: (r, i) => {
                root.leave(i);
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${r.address}" })`);
            },
            task: (r, i) => Tasks.complete(r.task),
            "task-add": (r, i) => {
                if (!r.ok)
                    return;
                root.leave(i);
                Tasks.run(r.text);
            },
            timer: (r, i) => Timers.toggle(r.entry.id),
            "timer-add": (r, i) => {
                if (!r.ok)
                    return;
                root.leave(i);
                Timers.run(r.text);
            }
        })

    // `mode` is only for the music rows — "queue", "play" or "next", from
    // which modifier was held with Enter.
    function activate(i, mode): void {
        const r = root.results[i];
        // Ctrl+Enter in mail mode writes a new one, whatever row is selected
        // and whether or not there is one: what was typed is the subject.
        if (root.mailMode && mode === "play") {
            if (r)
                root.leave(i);
            else
                root.hide();
            Email.compose(root.query.slice(1).trim());
            return;
        }
        if (!r)
            return;
        // A row that is only telling you something has nothing to activate,
        // and closing the launcher would take the message with it.
        if (r.kind === "note")
            return;
        if (r.kind.indexOf("music-") === 0) {
            if (LauncherMusic.activate(r, mode))
                root.leave(i);
            return;
        }
        root.actions[r.kind](r, i);
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

    // How long an unused entry is kept. Past a week its weight is already at
    // the floor, and past this it is only a line in a file that would
    // otherwise grow by one for every command ever typed.
    readonly property int keepMs: 90 * 24 * 3600000

    function bump(id): void {
        // A fresh object rather than a mutation: `db` is a var property, and
        // changing one in place does not notify, so the results binding would
        // keep the ranking it had until the next keystroke.
        const next = {};
        const since = Date.now() - root.keepMs;
        for (const k in root.db)
            if (root.db[k].last >= since)
                next[k] = root.db[k];
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
