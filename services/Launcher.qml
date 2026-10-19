pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.components
import qs.services
import "../Fuzzy.js" as Fuzzy

// What the launcher knows: the query, where the selection is, what matches,
// and which apps get reached for often enough to float.
Singleton {
    id: root

    // --- modes ---------------------------------------------------------------

    // The first non-space character picks a mode. "%" is search: the word
    // after it can name an engine ("%y lofi"), and without one the query goes
    // to the fallback ("%lofi" is a Google search).
    //
    // One search prefix rather than one per family, because the split between
    // "web" and "AI" was a distinction about the destination, not about what
    // you are doing — in both cases you are typing a question and picking who
    // answers it.
    //
    // A percent sign leaves the hash free for music. A leading dot would take
    // decimals off the calculator, since the mode is picked before anything
    // looks at what follows: ".5*2" would be a web search for "5*2".
    // See looksLikeMath.
    //
    // One letter each, and Google has none at all — it is what a bare "%"
    // does, so the search run most often costs the fewest keys. Claude is
    // "%l" because ChatGPT holds the "c", so the key moved to the next free
    // letter of the word: "%l" opens Claude.
    //
    // %s is replaced with the URL-encoded query. Every engine here has a place
    // to put one, which is why there is no Gemini: neither gemini.google.com
    // nor AI Studio takes a prompt in the URL, so an entry could only open an
    // empty chat and drop what was typed.
    //
    readonly property string enginePrefix: "%"

    readonly property var engines: [
        {
            key: "",
            name: "Google",
            url: "https://www.google.com/search?q=%s"
        },
        {
            key: "y",
            name: "YouTube",
            url: "https://www.youtube.com/results?search_query=%s"
        },
        {
            key: "c",
            name: "ChatGPT",
            url: "https://chatgpt.com/?q=%s"
        },
        {
            key: "l",
            name: "Claude",
            // /new is the fresh conversation and q= is what goes
            // in it, which is the whole test for being in this
            // list — see the note about Gemini above.
            url: "https://claude.ai/new?q=%s",
        },
        {
            key: "x",
            name: "1337x",
            // Path, not a query string: 1337x takes the term as a
            // path segment with the page number after it. The 1 is
            // the first page.
            url: "https://1337x.to/search/%s/1/"
        },
        {
            key: "t",
            name: "Translate",
            // Auto-detect the source, English the target: the
            // text is what changes, the direction rarely does.
            url: "https://translate.google.com/?sl=auto&tl=en&text=%s&op=translate"
        },
        {
            key: "m",
            name: "Maps",
            url: "https://www.google.com/maps/search/%s"
        }
    ]

    // Modes with one destination use a prefix directly.
    //
    // Files, from fasd and fd. A calculation. The clipboard.
    // The characters are the ones already on the keys they mean — "=" starts
    // what you would write on paper, and a quote is what you
    // put round text you are pasting.
    readonly property string pathPrefix: "/"
    readonly property string calcPrefix: "="
    readonly property string clipPrefix: '"'
    // Open windows by workspace. An underscore tries windows first; a search
    // with no matching window falls through to ordinary query inference.
    readonly property string windowPrefix: "_"
    // The library: artists, their records, the songs on them, and the stored
    // playlists. A hash, which starts nothing else here — it is not a
    // path, a sum, a prompt, a quoted line or a window.
    readonly property string musicPrefix: "#"
    // Mail: the unread on its own, a search of the whole mailbox past it. The
    // at-sign, which is what an address reads as.
    readonly property string mailPrefix: "@"
    // Writing something down, and setting something going: here rather than in
    // a quick-entry box of their own, which would be a second line of text on
    // the same screen and one more place for the keyboard grab to go wrong.
    //
    // Tasks and timers share a comma: plain text writes down a task, while a
    // leading duration or time of day sets a timer or alarm.
    readonly property string taskPrefix: ","
    // Sleep, restart, shut down and the rest. The bang, which is how loud
    // turning the machine off should be; the bar's right-click opens it too.
    readonly property string powerPrefix: "!"

    readonly property var modes: [
        { prefix: root.calcPrefix, hint: "calc" },
        { prefix: root.clipPrefix, hint: "clipboard" },
        { prefix: root.windowPrefix, hint: "windows" },
        { prefix: root.pathPrefix, hint: "files" },
        { prefix: root.taskPrefix, hint: "tasks, timers, events" },
        { prefix: root.musicPrefix, hint: "music" },
        { prefix: root.enginePrefix, hint: "web" },
        { prefix: root.mailPrefix, hint: "email" },
        { prefix: root.powerPrefix, hint: "power" }
    ]

    // What the hint in the query line says. Normally the modes, assembled
    // from the prefix characters themselves rather than typed out, so changing
    // one of them changes what the box says it does. No entry for apps: that
    // is what the box does when you tell it nothing, and a prefix line is a
    // list of the things you have to ask for.
    //
    // In search mode it turns into the engines, because by then the mode is
    // not the question any more — which of them answers it is, and the
    // letter that picks each one is the thing worth having in front of you.
    readonly property string prefixHint: root.modes.map(mode => mode.prefix + mode.hint).join("   ")

    // How many rows are worth ranking; the box shows a dozen of them at once.
    readonly property int maxResults: 50
    // How hard usage history pushes a match up the list. High enough that the
    // app you always want wins a tie, low enough that it cannot drag a bad
    // match above a good one.
    readonly property real frecencyWeight: 8

    // --- state ---------------------------------------------------------------

    property bool shown: false
    readonly property int dismissMs: 200
    // Whether the window exists, which is not the same thing as being wanted:
    // LauncherMenu.qml defocuses and fades when `shown` goes false, so the window
    // has to outlive the intent by the length of that. See qs.Linger.
    readonly property bool active: linger.active
    // Once the window is gone, so is the question: left set, the last mode's
    // bindings would keep answering it for nobody (every window title change
    // re-ran `_`). show() starts from empty anyway.
    onActiveChanged: {
        if (active)
            return;
        root.query = "";
    }
    property string query: ""
    property int index: 0
    // The power row asking for its second press. Anything else the
    // selection or the query does takes the question back.
    property string armed: ""
    onIndexChanged: root.armed = ""
    onResultsChanged: if (root.index >= root.results.length)
        root.index = Math.max(0, root.results.length - 1)

    // The row the box is on, and whether the box is listing files at all.
    // Both are for the preview panel, which is the one thing that cares what
    // is selected rather than what is listed — see components/FilePreview.qml.
    readonly property var selected: root.results[root.index] ?? null
    readonly property var classification: root.classifyQuery(root.query)
    readonly property bool pathMode: root.classification.mode === root.pathPrefix
    readonly property bool musicMode: root.classification.mode === root.musicPrefix
    readonly property bool mailMode: root.classification.mode === root.mailPrefix
    readonly property bool taskMode: root.classification.mode === root.taskPrefix
    readonly property bool powerMode: root.classification.mode === root.powerPrefix

    // Follow query inference even while results are pending or selection changes.
    readonly property string queryIcon: {
        const c = root.classification;
        switch (c.mode) {
        case root.calcPrefix: return Theme.glyph.launcherCalc;
        case root.clipPrefix: return Theme.glyph.clipboard;
        case root.windowPrefix: return Theme.glyph.launcherWindow;
        case root.pathPrefix: return Theme.glyph.folder;
        case root.musicPrefix: return Theme.glyph.launcherMusic;
        case root.enginePrefix: return Theme.glyph.launcherWeb;
        case root.mailPrefix: return Theme.glyph.mailUnread;
        case root.powerPrefix: return Theme.glyph.launcherPower;
        case root.taskPrefix: {
            switch (Tasks.plan(c.text).kind) {
            case "alarm": return Theme.glyph.alarm;
            case "timer": return Theme.glyph.timer;
            case "event": return Theme.glyph.event;
            }
            return Theme.glyph.tasks;
        }
        case "main":
            if (c.math)
                return Theme.glyph.launcherCalc;
            if (c.email)
                return Theme.glyph.mailUnread;
            if (c.url || root.results[0]?.kind === "url")
                return Theme.glyph.launcherWeb;
        }
        return Theme.glyph.launcher;
    }

    // Classify without starting asynchronous work. route() calls this
    // directly: onQueryChanged can run before the classification binding updates.
    function classifyQuery(q) {
        if (!q.length)
            return { mode: "empty", text: "" };

        const leading = q.replace(/^\s+/, "");
        const sym = leading.charAt(0);
        if (root.modeResults[sym] || sym === root.enginePrefix) {
            // Keep an absolute path intact; "/ query" still selects file search.
            if (sym === root.pathPrefix && /^\/\S/.test(leading))
                return { mode: sym, text: leading.trim() };
            const rest = leading.slice(1);
            if (sym !== root.windowPrefix || !rest.trim() || root.windowResults(rest.trim()).length)
                return { mode: sym, text: sym === root.taskPrefix ? rest : rest.trim() };
        }

        // Automatic maths and URLs add rows to the main list. Files take over
        // only when neither applies; search remains a fallback after matching.
        const t = q.trim();
        const math = root.looksLikeMath(t);
        const email = root.parseEmail(t);
        const url = root.parseUrl(t);
        if (!math && !url && !email && root.looksLikePath(t))
            return { mode: root.pathPrefix, text: t };
        return { mode: "main", text: t, math: math, url: url, email: email };
    }

    // Recognize file search syntax independently of mode precedence.
    function looksLikePath(q) {
        // Home and explicit relative paths can contain spaces. Other guesses
        // require compact text so a sentence ending in ".txt" stays a question.
        if (/^(?:~(?:\/|$)|\.{1,2}\/)/.test(q))
            return true;
        return !/\s/.test(q) && (q.includes("/") || /^\.[^\d.\s]/.test(q) || /\.[a-z][a-z0-9]*$/i.test(q));
    }

    // { appId: { count, last } }
    property var db: ({})

    // A changed query starts at its first match.
    onQueryChanged: {
        root.index = 0;
        root.armed = "";

        root.route();
    }

    Linger {
        id: linger

        shown: root.shown
        // Keep the surface alive through the launcher's defocus and fade.
        hold: root.dismissMs
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
        if (root.shown && root.classifyQuery(root.query).mode === prefix) {
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
        OpenPopup.dismiss();
        root.rankingNow = Date.now();
        root.query = "";
        root.index = 0;
        root.armed = "";
        // File and clipboard results are refreshed for each opening.
        for (const provider of Object.values(root.providers))
            provider.cancel();
        root.shown = true;
    }

    function hide(): void {
        Tasks.commit();
        root.shown = false;
        root.armed = "";
        // Closing mid-CRT takes the command back with it.
        Power.leaving = null;
        // Closing is not a keystroke, so route() never runs to stop the clocks
        // the modes keep; a run they started against a box that is gone would
        // be work nobody sees.
        qalc.cancel();
        for (const provider of Object.values(root.providers))
            provider.cancel();
    }

    // --- matching ------------------------------------------------------------

    // Space-separated terms are ANDed: "fire priv" finds Firefox's private-window entry. Each term scores
    // against every field it is given and keeps its best hit; a term that
    // lands nowhere makes the whole thing a miss, which is null rather than a
    // low score — the caller drops those entirely.
    //
    // Folding is the expensive half of a score (see Fuzzy.js), so both sides
    // are folded before the loop rather than inside it: the terms once per
    // keystroke by prepTerms, the fields once per list by prepFields — or,
    // for a list too short to be worth keeping, once per call by matchScore.
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

    // Each explicit mode builds rows from the text prepared by classifyQuery.
    // The explicit calculator accepts whatever qalc says; automatic maths is strict.
    readonly property var providers: ({
        [root.musicPrefix]: LauncherMusic,
        [root.pathPrefix]: LauncherFiles,
        [root.mailPrefix]: LauncherMail,
        [root.clipPrefix]: LauncherClipboard
    })

    readonly property var modeResults: ({
            [root.pathPrefix]: rest => LauncherFiles.results(rest),
            [root.calcPrefix]: rest => root.calcResults(rest, false),
            [root.clipPrefix]: rest => LauncherClipboard.results(rest),
            [root.windowPrefix]: rest => root.windowResults(rest),
            [root.musicPrefix]: rest => LauncherMusic.results(rest),
            [root.mailPrefix]: rest => LauncherMail.results(rest),
            [root.taskPrefix]: rest => root.taskResults(rest),
            [root.powerPrefix]: rest => root.powerResults(rest)
        })

    readonly property var results: {
        if (!root.active)
            return [];
        const c = root.classification;
        // Empty opens with the most used; a space lists every match ranked alike.
        if (c.mode === "empty")
            return root.homeResults();

        const mode = root.modeResults[c.mode];
        if (mode)
            return mode(c.text);
        if (c.mode === root.enginePrefix)
            return root.engineResults(c.mode, c.text);

        // Unprefixed. A sum and a domain are things the query says outright,
        // so they sit above the list rather than inside it. Apps and power
        // commands are both guesses at what was meant, so they are ranked
        // against each other and share the ordering.
        const found = root.calcResults(c.math ? c.text : "", true).concat(root.emailResults(c.email), root.urlResults(c.text, c.url), root.mainResults(c.text));

        // Nothing matched, so it was a question: answer it the way "%" would.
        // Gated on the sum being spotted rather than on qalc's row, which
        // arrives a beat later and would have the engines flash up first.
        if (!found.length && !c.math)
            return root.engineResults(root.enginePrefix, c.text, false);
        return found;
    }

    // Rank apps, power commands, desktop controls and paired Bluetooth devices.
    function mainResults(query) {
        const terms = root.prepTerms(query);
        const scored = root.appMatches(terms).concat(root.powerMatches(terms), root.desktopMatches(terms), root.bluetoothMatches(terms));
        scored.sort((a, b) => b.s - a.s || (a.row.sortTitle ?? a.row.title).localeCompare(b.row.sortTitle ?? b.row.title));
        return scored.slice(0, root.maxResults).map(x => x.row);
    }

    // The menu with its fields folded, rebuilt when the installed apps
    // change and read on every keystroke.
    //
    // Name, generic name, keywords, categories. Weighted, because a hit on the name means more than a hit on a
    // category half the menu shares.
    //
    // Deliberately not e.id: Chrome PWAs are installed with ids like
    // "chrome-<hash>-Default", so every one of them would answer to "chrome".
    //
    // Each desktop action an app declares (Firefox's private window) is a row
    // of its own, answering to its own name first and its app's second, so
    // "fire priv" finds it. Settings.hiddenApps drops entries by id, and
    // single actions by their row id, "<app>:<action>": Quickshell ignores
    // OnlyShowIn, which is how blueman's XFCE-only one got in, and
    // LibreOffice's "New Spreadsheet" and kin only reopen the app they belong to.
    // A loop rather than flatMap, which Qt's JavaScript engine does not have.
    readonly property var appIndex: {
        const rows = [];
        for (const e of DesktopEntries.applications.values) {
            if (Settings.hiddenApps.includes(e.id))
                continue;
            rows.push({
                id: e.id,
                entry: e,
                fields: root.prepFields([[e.name, 1], [e.genericName, 0.8]].concat(Array.from(e.keywords ?? []).map(k => [k, 0.6])).concat(Array.from(e.categories ?? []).map(c => [c, 0.4])))
            });
            if (!Settings.showDesktopActions)
                continue;
            for (const a of e.actions ?? []) {
                const id = e.id + ":" + a.id;
                if (Settings.hiddenApps.includes(id))
                    continue;
                rows.push({
                    id: id,
                    entry: e,
                    action: a,
                    fields: root.prepFields([[a.name, 1], [e.name, 0.5]])
                });
            }
        }
        return rows;
    }

    // Scored, not rendered: mainResults sorts these in with the power
    // commands, so the rows cannot be cut to maxResults yet.
    function appMatches(terms) {
        const scored = [];

        for (const a of root.appIndex) {
            const e = a.entry;
            const f = root.frecency(a.id);
            // An action is listed unasked only once it has been used.
            if (a.action && !terms.length && !f)
                continue;
            // Empty matches are ranked by history for the home list and space.
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
                    id: a.id,
                    entry: e,
                    action: a.action ?? null,
                    icon: a.action?.icon || e.icon,
                    title: a.action?.name ?? e.name,
                    subtitle: a.action ? e.name : ""
                }
            });
        }

        return scored;
    }

    // Desktop actions run directly through their existing services.
    readonly property var desktopCommands: [
        { key: "mute", title: Audio.muted ? "Unmute sound" : "Mute sound", aliases: "audio volume speaker", glyph: Theme.glyph.vol[Theme.glyph.vol.length - 1], available: !!Audio.sink?.audio, run: () => Audio.toggleMute() },
        { key: "night", title: NightMode.on ? "Turn night mode off" : "Turn night mode on", aliases: "warm screen display light", glyph: Theme.glyph.nightOff, run: () => NightMode.toggle() },
        { key: "wifi", title: Network.wifiOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on", aliases: "wifi wireless network radio", glyph: Theme.glyph.wifiStrength[Theme.glyph.wifiStrength.length - 1], available: !!Network.wifi, run: () => Network.toggleWifi() },
        { key: "bluetooth-power", title: Bluetooth.on ? "Turn Bluetooth off" : "Turn Bluetooth on", aliases: "wireless radio" + (!Bluetooth.on ? " connect headphones headset " + Bluetooth.devices.filter(d => d.paired).map(d => d.name).join(" ") : ""), glyph: Theme.glyph.bluetooth, available: Bluetooth.present, run: () => Bluetooth.toggle() }
    ]

    function desktopMatches(terms) {
        const scored = [];
        for (const action of root.desktopCommands) {
            if (action.available === false || Settings.hiddenApps.includes("desktop:" + action.key))
                continue;
            const m = terms.length ? root.matchScore(terms, [[action.title, 1], [action.aliases, 0.8]]) : 0;
            if (m === null)
                continue;
            const f = root.frecency("desktop:" + action.key);
            scored.push({
                s: terms.length ? m + root.frecencyWeight * Math.log2(1 + f) : f,
                row: { kind: "desktop", action, title: action.title, glyph: action.glyph, raw: true }
            });
        }
        return scored;
    }

    // Match both actions and sort by name, so connection progress changes
    // the label without moving the device away from the selection.
    function bluetoothMatches(terms) {
        if (!Bluetooth.present || !Bluetooth.on)
            return [];
        const scored = [];
        for (const device of Bluetooth.devices) {
            if (!device.paired)
                continue;
            const connecting = device.state === BlueZ.BluetoothDeviceState.Connecting;
            const disconnecting = device.state === BlueZ.BluetoothDeviceState.Disconnecting;
            const title = (connecting ? "Connecting to " : disconnecting ? "Disconnecting " : device.connected ? "Disconnect " : "Connect ") + device.name;
            const status = connecting ? "Connecting…" : disconnecting ? "Disconnecting…" : device.pairing ? "Pairing…" : device.connected ? "Connected" : "Disconnected";
            const aliases = "bluetooth wireless connect disconnect" + (device.icon?.startsWith("audio-") ? " headphones headset audio" : "");
            const s = terms.length ? root.matchScore(terms, [[device.name, 1], ["Connect " + device.name, 1], ["Disconnect " + device.name, 1], [aliases, 0.8]]) : 0;
            if (s !== null)
                scored.push({
                    s,
                    row: {
                        kind: "bluetooth",
                        address: device.address,
                        connect: !device.connected,
                        title,
                        sortTitle: device.name,
                        subtitle: "Bluetooth · " + status,
                        glyph: Theme.glyph.bluetooth,
                        raw: true
                    }
                });
        }
        return scored;
    }

    // Resolve the current device rather than trusting a row from before a
    // state change or adapter replacement; never reverse a stale action.
    function activateBluetooth(row): void {
        if (!Bluetooth.present || !Bluetooth.on)
            return;
        const device = Bluetooth.devices.find(d => d.address === row.address && d.paired);
        if (!device || device.pairing || device.state === BlueZ.BluetoothDeviceState.Connecting || device.state === BlueZ.BluetoothDeviceState.Disconnecting || row.connect === device.connected)
            return;
        Bluetooth.activate(device);
    }

    // The box opens full: what gets used most, then every other app by name.
    // Desktop controls only once they have been used, so the list is not
    // headed by toggles nobody asked for. The modes are in the hint line.
    function homeResults() {
        const scored = root.appMatches([]).concat(root.desktopMatches([]).filter(x => x.s > 0));
        scored.sort((a, b) => b.s - a.s || a.row.title.localeCompare(b.row.title));
        return scored.slice(0, root.maxResults).map(x => x.row);
    }

    // --- power ---------------------------------------------------------------

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

    // An armed row trades its glyph for a tick and its subtitle for the
    // question the Mac would ask.
    function powerRow(a) {
        const armed = root.armed === a.key;
        return {
            kind: "power",
            action: a,
            armed: armed,
            glyph: armed ? Theme.glyph.powerConfirm : a.glyph,
            title: a.label,
            subtitle: armed ? a.question : "power"
        };
    }

    function powerMatches(terms) {
        // With nothing typed the list is pure app history. The machine's off
        // switch has no business at the top of that.
        if (!terms.length)
            return [];

        const scored = [];
        for (const a of Power.actions) {
            if (Settings.hiddenApps.includes("power:" + a.key))
                continue;
            // Aliases score just under the label, so a command found by its
            // real name outranks one found by a nickname.
            const m = root.matchScore(terms, [[a.label, 1]].concat((root.powerAliases[a.key] ?? "").split(" ").map(w => [w, 0.85])));
            if (m === null)
                continue;
            scored.push({
                s: m + root.frecencyWeight * Math.log2(1 + root.frecency("power:" + a.key)),
                row: root.powerRow(a)
            });
        }
        return scored;
    }

    // The ! mode: the whole menu in its own order, narrowed and ranked once
    // something is typed.
    function powerResults(query) {
        const terms = root.prepTerms(query);
        if (!terms.length)
            return Power.actions.filter(a => !Settings.hiddenApps.includes("power:" + a.key)).map(a => root.powerRow(a));
        return root.powerMatches(terms).sort((a, b) => b.s - a.s).map(x => x.row);
    }

    // The end of the CRT the box plays for Power.leaving: run the command
    // under the black it left, then close. Run first, so the black never
    // lapses between the exit and the hold.
    function leave(): void {
        const a = Power.leaving;
        if (!a)
            return;
        root.bump("power:" + a.key);
        Power.run(a.arg, true);
        root.hide();
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
        const typed = query.trim();
        const plan = typed.length ? Tasks.plan(typed) : null;
        const timerInput = plan?.kind === "timer" || plan?.kind === "alarm";
        const rows = root.timerResults(timerInput ? typed : "", plan);

        if (!Tasks.configured)
            return rows.concat([
                root.noteRow(Theme.glyph.tasks, `Google Tasks not connected — run ${Google.setup}`)
            ]);

        const parsedTask = typed.length ? Tasks.parse(typed) : null;
        if (typed.length && !timerInput) {
            const event = plan.kind === "event";
            rows.unshift({
                kind: "task-add",
                event: event,
                glyph: event ? Theme.glyph.event : Theme.glyph.plus,
                // Keep the typed day and task list names in the preview.
                title: typed,
                raw: true,
                subtitle: root.linePreview(typed, plan),
                // An event needs the calendar; the preview says so.
                ok: plan.ok && !(event && Google.needsConsent),
                text: typed
            });
        }

        // Day and task list names route the add; only the title filters tasks.
        const core = parsedTask?.title ?? "";
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
                    crossed: Tasks.isCrossed(task),
                    glyph: Theme.glyph.taskOpen,
                    title: task.title,
                    raw: true,
                    subtitle: Tasks.sayDay(Tasks.dayOf(task)),
                    // The subtitle here is a date at most, so the title is not
                    // in a fight with it for the row.
                    titleShare: 0.82,
                    // The order the list is already in is the order it should
                    // keep when nothing is typed: task lists and manual order.
                    // Only a real query is allowed to reorder it.
                    dim: Tasks.urgency(task) === "none"
                }
            });
        }

        if (terms.length)
            scored.sort((a, b) => b.s - a.s);

        return rows.concat(scored.slice(0, root.maxResults).map(x => x.row));
    }

    // What Enter makes of a `,` line (Tasks.plan), read from the parse rather
    // than the line: "alarm 15:00 today  ·  event 15:00–16:00",
    // "event  ·  fri 15:00–16:00", or the task's day and task list.
    function linePreview(typed, plan) {
        if (!plan.ok)
            return plan.error;
        const time = at => Timers.hhmm(at.getHours(), at.getMinutes());
        const ev = plan.event;
        const calendar = () => Google.needsConsent ? "calendar needs reconnect" : null;
        switch (plan.kind) {
        case "timer":
            return Timers.brief(typed, plan.timer);
        case "alarm":
            if (!ev)
                return Timers.brief(typed, plan.timer);
            return `alarm ${time(ev.start)} ${Tasks.sayDay(Tasks.dayString(ev.start))}  ·  ${calendar() ?? `event ${time(ev.start)}–${time(ev.end)}`}`;
        case "event":
            return "event  ·  " + (calendar() ?? `${Tasks.sayDay(Tasks.dayString(ev.start))} ${time(ev.start)}–${time(ev.end)}`);
        }
        const p = plan.task;
        const list = Tasks.lists.length > 1 ? Tasks.lists.find(l => l.id === p.list) : null;
        return "add" + (p.day !== "" ? "  ·  " + Tasks.sayDay(p.day) : "") + (list ? "  ·  " + list.title : "");
    }

    // Timer rows in tasks mode: a time being typed first, then existing timers.
    // Enter on a running timer pauses it; its countdown stays bound in the row.
    function timerResults(query, plan) {
        const typed = query.trim();
        const rows = [];

        if (typed.length) {
            rows.push({
                kind: "timer-add",
                glyph: plan.kind === "alarm" ? Theme.glyph.alarm : Theme.glyph.timer,
                title: typed,
                raw: true,
                // Same again: "25m" is what was typed and "25 minutes" is what
                // it was read as, so the reading is worth showing and the label
                // beside it is not.
                subtitle: root.linePreview(typed, plan),
                ok: plan.ok,
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

    // Untyped on purpose: a typed `subtitle: string` turns a missing argument
    // into the string "undefined", and typed parameters cannot take defaults.
    function noteRow(glyph, title, subtitle = "") {
        return {kind: "note", glyph, title, subtitle, raw: true};
    }

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
            const cls = t.wayland?.appId || t.lastIpcObject?.class || "";
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
                icon: AppIcons.resolve(cls, entry),
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
    // --- shelling out --------------------------------------------------------

    // Every keystroke: point the modes that work between keystrokes at what
    // the query now says. qalc and fd are QueuedProcesses and start their own
    // clocks off `want`; the library scores in-process and keeps its own.
    // Which of them gets read is the results binding's business — but a mode
    // has to have been asked before it is shown, or the answer arrives a beat
    // after the row it belongs to.
    function route(): void {
        const c = root.classifyQuery(root.query);
        qalc.want = c.mode === root.calcPrefix || c.math ? c.text : "";
        for (const [prefix, provider] of Object.entries(root.providers))
            provider.route(c.mode === prefix, c.text);
    }

    // --- calculator ----------------------------------------------------------

    // What qalc last said, and what it was asked. See QueuedProcess.
    property var calcAnswer: null

    // qalc answers everything. "hello" is 2.718281828 B·h·L² — e, in
    // bytes·hours·litres² — and "1password" is 1 pa·word·s². So an unprefixed
    // query is gated on the way in rather than on what comes back.
    function looksLikeMath(q) {
        // A numeric token has at most one decimal point. IPv4 addresses and
        // version strings cannot become maths just because a slash follows them.
        const numbers = q.match(/[\d.]+/g) || [];
        if (numbers.some(n => /\d/.test(n) && !/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(n)))
            return false;
        // Nor can a date or a phone number: "2026-10-05" is not 2011, and
        // "210 1234567" is not their product. One hyphen ("10-3") still is.
        if (/^\d+(?:-\d+){2,}$/.test(q) || /^\d+(?:\s+\d+)+$/.test(q))
            return false;
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

    // Recognize a complete address without treating a sentence or file as mail.
    function parseEmail(q) {
        if (!/^[a-z0-9.!#$%&'*+\/=?^_`{|}~-]+@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i.test(q))
            return null;
        const local = q.split("@")[0];
        return local.startsWith(".") || local.endsWith(".") || local.includes("..") ? null : q;
    }

    function emailResults(address) {
        if (!address)
            return [];
        return [{kind: "url", glyph: Theme.glyph.mailRead, title: "search gmail for " + address, subtitle: "gmail", raw: true, url: Email.web + "#search/" + encodeURIComponent(address)}];
    }

    // --- urls ----------------------------------------------------------------

    // Enough of the real TLDs to cover what actually gets typed here. An
    // allowlist rather than a shape test, because "config.json" and "Fuzzy.js"
    // are the shape of a domain and neither is one.
    readonly property var tlds: ["com", "org", "net", "io", "dev", "ai", "app", "co", "gr", "uk", "de", "fr", "it", "es", "nl", "eu", "ru", "jp", "cn", "br", "ca", "au", "nz", "se", "no", "dk", "fi", "cz", "pt", "ro", "bg", "hu", "ch", "at", "be", "ie", "gov", "edu", "info", "xyz", "me", "tv", "gg", "fm", "to", "ly", "st", "page", "cloud", "tech", "site", "online", "store", "blog", "news", "live", "sh", "md", "so", "rs", "pl", "cc", "in", "us"]

    // Real TLDs that are also file extensions on this machine. A bare
    // "install.sh" or "README.md" is the file far more often than the site, so
    // these only count as a domain when something else in the string says URL:
    // a scheme, a www., a port or query parameters. A slash alone can belong
    // to a file path such as "README.md/notes".
    //
    // Every one of these has to appear in `tlds` as well — that list is what
    // decides a domain at all, and this one only holds some of them back.
    readonly property var extTlds: ["sh", "md", "so", "rs", "pl", "cc", "in"]

    // Detect a URL without constructing UI rows.
    function parseUrl(q) {
        // A domain has no spaces in it, and a query with one is a sentence.
        if (!q || /\s/.test(q))
            return null;

        const scheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(q);
        const host = (scheme ? (q.split("/")[2] ?? "") : q).split("/")[0].split("?")[0].split("#")[0].split(":")[0];

        let ok = scheme;
        if (!ok && (/^localhost$/i.test(host) || /^\d{1,3}(\.\d{1,3}){3}$/.test(host))) {
            ok = true;
        } else if (!ok) {
            const m = host.toLowerCase().match(/^([a-z0-9-]+\.)+([a-z]{2,})$/);
            const hint = /^www\./i.test(q) || /[?#]/.test(q) || /:\d+/.test(q);
            ok = !!m && root.tlds.indexOf(m[2]) !== -1 && (hint || root.extTlds.indexOf(m[2]) === -1);
        }
        if (!ok)
            return null;

        // https for the internet, because a bare domain typed at a launcher
        // in 2026 is a site that has had TLS for a decade and anything that
        // has not will redirect. http for the machine and the LAN, where the
        // thing on the port is a dev server with no certificate and https is
        // the one that fails.
        const local = /^localhost$/i.test(host) || /^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host);
        return { host: host, url: scheme ? q : (local ? "http://" : "https://") + q };
    }

    // Build the URL row from the classifier's parsed destination.
    function urlResults(q, url) {
        if (!url)
            return [];
        return [
            {
                kind: "url",
                glyph: Theme.glyph.web,
                title: "open " + q,
                subtitle: url.host.replace(/^www\./i, ""),
                raw: true,
                url: url.url
            }
        ];
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

    function engineResults(sym, rest, keyed = true) {
        const engines = root.engines;
        const m = rest.match(/^(\S+)(?:\s+(.*))?$/);
        let key = "";
        let q = rest.trim();
        // The first word is an engine key only if it actually names one, so
        // "%lofi" searches for lofi rather than looking for an engine "lofi".
        // And only after the prefix: the unprefixed fallback is a question,
        // where "c programming" is about C, not a message to ChatGPT.
        if (keyed && m && engines.some(e => e.key === m[1])) {
            key = m[1];
            q = (m[2] || "").trim();
        }

        // Selected engine first, the rest following in the order they are
        // listed, so the list does not reshuffle itself as you type.
        const picked = engines.filter(e => e.key === key);
        const others = engines.filter(e => e.key !== key);
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

    // Select a tabbed Chromium window so a last-active PWA cannot cause a new one.

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
            desktop: (r, i) => {
                // Powering on keeps the search visible for the device action.
                if (r.action.key !== "bluetooth-power" || Bluetooth.on)
                    root.hide();
                root.bump("desktop:" + r.action.key);
                r.action.run();
            },
            bluetooth: (r, i) => root.activateBluetooth(r),
            app: (r, i) => {
                root.hide();
                root.bump(r.id);
                // execute() ignores Terminal=true, so a TUI app would start
                // with nowhere to draw. An action runs in its app's terminal.
                const run = r.action ?? r.entry;
                if (r.entry.runInTerminal)
                    Quickshell.execDetached({
                        command: Settings.inTerminal(run.command, run.name, false),
                        workingDirectory: r.entry.workingDirectory
                    });
                else
                    run.execute();
            },
            calc: (r, i) => {
                root.hide();
                root.copy(r.answer);
            },
            power: (r, i) => {
                // The irreversible ones ask on the first press and act on
                // the second, like every destructive button on the bar.
                if (r.action.confirm && !r.armed) {
                    root.armed = r.action.key;
                    return;
                }
                // Leaving the session or the screen goes out through the
                // box's CRT (LauncherMenu.qml), which calls leave().
                if (Power.fades(r.action.arg)) {
                    Power.leaving = r.action;
                    return;
                }
                root.hide();
                root.bump("power:" + r.action.key);
                Power.run(r.action.arg);
            },
            url: (r, i) => {
                root.hide();
                Quickshell.execDetached(["xdg-open", r.url]);
            },
            window: (r, i) => {
                root.hide();
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${r.address}" })`);
            },
            task: (r, i) => Tasks.complete(r.task),
            "task-add": (r, i) => {
                if (!r.ok)
                    return;
                root.hide();
                Tasks.run(r.text);
            },
            timer: (r, i) => Timers.toggle(r.entry.id),
            "timer-add": (r, i) => {
                if (!r.ok)
                    return;
                root.hide();
                // Tasks, not Timers: an alarm with a title is an event too.
                Tasks.run(r.text);
            }
        })

    // Ctrl+Enter requests play for library results, compose for mail, or the
    // folder for a file. Queue rows control the existing playback. A prefix
    // mode's rows belong to its provider, which says whether to close.
    function activate(i, mode): void {
        const r = root.results[i];
        // Ctrl+Enter in mail mode writes a new one with or without a row.
        const composes = root.mailMode && mode === "play";
        // A row that is only telling you something has nothing to activate,
        // and closing the launcher would take the message with it.
        if (!composes && (!r || r.kind === "note"))
            return;
        const provider = root.providers[root.classification.mode];
        if (provider) {
            if (provider.activate(r, mode))
                root.hide();
            return;
        }
        root.actions[r.kind](r, i);
    }

    // Ctrl+C with nothing selected in the query line copies the file's full path.
    function copyRow(i): void {
        const r = root.results[i];
        const text = r?.kind === "path" ? r.path : "";
        if (!text)
            return;
        root.hide();
        root.copy(text);
    }

    // Ctrl+Delete. Only the clipboard has anything to forget: an app you
    // stop using falls off the list on its own, and a path is fasd's to keep.
    function forget(i): void {
        LauncherClipboard.activate(root.results[i], "forget");
    }

    // --- frecency ------------------------------------------------------------
    // Read once per opening rather than live, so the list holds still while
    // it is up but a launch from days ago has aged by the next one.
    property double rankingNow: Date.now()

    // Usage, decayed by how long ago it was: something run twice this morning
    // outranks something run twice last month.
    function frecency(id) {
        const r = root.db[id];
        if (!r)
            return 0;
        const ageH = (root.rankingNow - r.last) / 3600000;
        const w = ageH < 4 ? 4 : ageH < 24 ? 2 : ageH < 168 ? 1 : 0.5;
        return r.count * w;
    }

    // How long an unused entry is kept. Past a week its weight is already at
    // the floor, and past this it is only a line in a file that would
    // otherwise grow by one for every command ever typed.
    readonly property real keepMs: 90 * 24 * 3600000

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

        path: Paths.state("launcher-frecency.json")
        // Stated rather than left to the default: the load is what emits
        // `loaded`, and without it the first launch would write a db holding
        // one app over the real one — history would reset on every restart.
        preload: true
        // There is no file until the first launch, and a missing one on a
        // fresh install is not worth a line in the log.
        printErrors: false

        onLoadFailed: root.db = ({})
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

        // Open in a mode, or close when that mode is already open. Super+T
        // and Super+Shift+T both use the combined tasks and timers mode.
        function open(prefix: string): void {
            root.openWith(prefix);
        }

        // Close if open, and say whether there was anything to close. The bool
        // is the point: smart-close.sh (Super+Q) has to tell "I closed the
        // launcher, stop here" from "nothing was up, go close a window" —
        // `toggle` would have opened the launcher in the second case.
        function dismiss(): bool {
            const was = root.shown;
            root.hide();
            return was;
        }
    }
}
