pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everything that differs from one machine to the next: which monitors,
// the clock's format, fonts, the apps the bar opens, where the
// wallpapers and the music are.
//
// Two files beside shell.qml. settings.default.json is in the repo: every
// setting with its default and a comment on what it does, which makes it the
// documentation as well as the fallback. settings.json is the machine's own
// (git ignores it), starts as a copy of the defaults, and wins key by key.
// Both may carry // comments and trailing commas, which are stripped before
// parsing. Edits are picked up on save.
//
// Shared settings live at the root for use by components and services.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    property var defaults: ({})
    property var user: ({})
    readonly property var values: Object.assign({}, root.defaults, root.user)

    // --- values --------------------------------------------------------------
    readonly property var screens: root.values.screens ?? []
    readonly property bool groupWindows: root.values.groupWindows === true
    readonly property string groupWindowBadgeStyle: ["dot", "badge"].includes(root.values.groupWindowBadgeStyle) ? root.values.groupWindowBadgeStyle : "hide"
    readonly property string weatherDisplay: ["hour", "average", "worst", "day"].includes(root.values.weatherDisplay)
        ? root.values.weatherDisplay : "hour"
    readonly property string weatherFormat: root.values.weatherFormat || "{icon}{temp}°"
    // The weather format cut at its tokens and at ^[…] and _[…]: each part is
    // a token or literal text, with a shift of "sup", "sub" or "" for the
    // baseline. The icon stays on the line whatever its shift. Text typed
    // straight after {temp} at its size (the ° in {temp}°) is its `unit`, drawn
    // in one piece with the figures so they keep the font's own spacing.
    readonly property var weatherParts: {
        const parts = [];
        let shift = "";
        for (const token of root.weatherFormat.split(/(\{icon\}|\{temp\}|\^\[|_\[|\])/)) {
            if ((token === "^[" || token === "_[") && !shift) {
                shift = token === "^[" ? "sup" : "sub";
                continue;
            }
            if (token === "]" && shift) {
                shift = "";
                continue;
            }
            if (token === "")
                continue;
            const last = parts[parts.length - 1];
            const literal = token !== "{icon}" && token !== "{temp}";
            const unit = literal && last?.token === "{temp}" && last.shift === shift && !last.unit ? token.match(/^\S+/)?.[0] ?? "" : "";
            if (unit)
                last.unit = unit;
            if (token.length > unit.length)
                parts.push({ token: token.slice(unit.length), shift });
        }
        return parts;
    }
    readonly property string weatherUnit: ["celsius", "fahrenheit", "kelvin"].includes(root.values.weatherUnit)
        ? root.values.weatherUnit : "celsius"
    // Checked against the models the Weather service offers.
    readonly property string weatherModel: root.values.weatherModel ?? "best_match"
    readonly property string datetimeFormat: root.values.datetimeFormat ?? "ddd d MMM HH:mm"
    readonly property string datetimeCase: ["normal", "uppercase", "lowercase"].includes(root.values.datetimeCase) ? root.values.datetimeCase : "normal"
    // Alarm readouts use the same casing and hour notation as Date & Time.
    readonly property string timeCase: root.datetimeCase
    readonly property string dateOrder: ["dmy", "mdy", "ymd"].includes(root.values.dateOrder) ? root.values.dateOrder : "dmy"
    readonly property bool smallAmPm: root.values.smallAmPm === true
    readonly property bool twelveHour: /AP|ap/.test(root.datetimeFormat.replace(/'(?:[^']|'')*'/g, ""))
    readonly property var layoutNames: root.values.layoutNames ?? ({})
    readonly property bool layoutChangeBounce: root.values.layoutChangeBounce === true
    readonly property string font: root.values.font ?? ""
    readonly property string monoFont: root.values.monoFont ?? ""
    // The setting, or the first terminal installed (Tools.terminals).
    readonly property string terminal: Tools.terminal
    readonly property string editor: root.values.editor || Quickshell.env("EDITOR") || "nvim"
    readonly property string fileManager: root.values.fileManager ?? ""
    readonly property string screenshotCommand: (root.values.screenshotCommand ?? "").trim()
    readonly property string updateCommand: (root.values.updateCommand ?? "").trim() || "if command -v yay >/dev/null; then yay; else sudo pacman -Syu; fi"
    readonly property string cleanupCommand: (root.values.cleanupCommand ?? "").trim()
    readonly property bool commandsInTerminal: root.values.commandsInTerminal !== false
    readonly property string sessionSaveCommand: (root.values.sessionSaveCommand ?? "").trim()
    // What a right click on Network, Bluetooth, Disks, Battery or System
    // opens, and the button in its popup. Empty hides the button. The
    // monitor runs in the terminal.
    readonly property string networkCommand: (root.values.networkCommand ?? "").trim()
    readonly property string bluetoothCommand: (root.values.bluetoothCommand ?? "").trim()
    readonly property string disksCommand: (root.values.disksCommand ?? "").trim()
    readonly property string batteryCommand: (root.values.batteryCommand ?? "").trim()
    // The idle timers (services/Energy.qml): minutes without input before
    // the display turns off, and before the machine sleeps. 0 is never.
    readonly property int displayOffMinutes: root.minutes(root.values.displayOffMinutes)
    readonly property int sleepMinutes: root.minutes(root.values.sleepMinutes)
    readonly property string monitorCommand: (root.values.monitorCommand ?? "").trim()
    readonly property string fileSearchIgnore: root.expand(root.values.fileSearchIgnore ?? "")
    readonly property var hiddenApps: root.values.hiddenApps ?? []
    readonly property bool showDesktopActions: root.values.showDesktopActions === true
    // The launcher's mode hints: off, a group at a time, or all at once.
    readonly property string launcherHints: ["cycle", "all"].includes(root.values.launcherHints) ? root.values.launcherHints : "off"
    // Whether ? help is among them, and on its own when they are off.
    readonly property bool launcherHelpHint: root.values.launcherHelpHint !== false
    readonly property var launcherPrefixes: Object.assign({}, root.defaults.launcherPrefixes, root.user.launcherPrefixes)
    readonly property var webShortcuts: root.values.webShortcuts ?? []
    readonly property string defaultTaskList: root.values.defaultTaskList ?? ""
    readonly property var mailCategories: root.values.mailCategories ?? []
    readonly property var ephemeralNotificationApps: root.values.ephemeralNotificationApps ?? []
    readonly property var ephemeralNotificationSummaries: root.values.ephemeralNotificationSummaries ?? []
    readonly property var feedChannels: root.values.feedChannels ?? []
    readonly property int feedDays: Math.max(1, Math.round(Number(root.values.feedDays ?? 30) || 30))
    readonly property var feedUrls: root.values.feedUrls ?? []
    readonly property var feedTitles: root.values.feedTitles ?? ({})
    readonly property var webApps: root.values.webApps ?? ({})
    readonly property string downloadsDir: root.expand(root.values.downloadsDir || "~/Downloads")
    readonly property string wallpaperDir: root.expand(root.values.wallpaperDir ?? "")
    readonly property real wallpaperParallaxZoom: Math.max(1, Number(root.values.wallpaperParallaxZoom ?? 1) || 1)
    // The lock screen: what the glass shows, whether the picture follows the
    // pointer, and PIN Mode: whether the password is checked without Return
    // once it is lockPasswordLength long.
    readonly property bool lockClock: root.values.lockClock !== false
    readonly property bool lockNotifications: root.values.lockNotifications !== false
    readonly property bool lockPreviews: root.values.lockPreviews === true
    readonly property bool lockPower: root.values.lockPower !== false
    readonly property bool lockAsTyped: root.values.lockAsTyped === true
    readonly property int lockPasswordLength: Math.max(0, Math.floor(Number(root.values.lockPasswordLength) || 0))
    // The line over the lock's time, in one format: the date in Date & Time's
    // tokens, then the weather from the first word holding a weather token on,
    // its other text as typed. Blank shows no line. A blank time follows
    // Hour Format.
    readonly property var lockWeatherTokens: ["icon", "temp", "avgicon", "worsticon", "avgtemp", "desc", "avgdesc", "high", "low"]
    readonly property string lockDateLine: root.values.lockDateLine ?? "ddd d  {icon} {temp}°"
    readonly property int lockWeatherAt: root.lockDateLine.search(new RegExp(`\\S*\\{(?:${root.lockWeatherTokens.join("|")})\\}`))
    readonly property string lockDateFormat: (root.lockWeatherAt < 0 ? root.lockDateLine : root.lockDateLine.slice(0, root.lockWeatherAt)).trim()
    readonly property string lockWeatherFormat: root.lockWeatherAt < 0 ? "" : root.lockDateLine.slice(root.lockWeatherAt).trim()
    readonly property string lockTimeFormat: root.values.lockTimeFormat || root.hourFormat
    readonly property bool lockTwelveHour: /AP|ap/.test(root.lockTimeFormat.replace(/'(?:[^']|'')*'/g, ""))
    readonly property bool lockSmallAmPm: root.values.lockSmallAmPm !== false
    readonly property string lockCase: ["normal", "uppercase", "lowercase"].includes(root.values.lockCase) ? root.values.lockCase : "normal"
    readonly property bool reduceMotion: root.values.reduceMotion === true
    readonly property bool reduceTransparency: root.values.reduceTransparency === true
    readonly property bool scrollMusicTitles: root.values.scrollMusicTitles === true
    readonly property bool showMpris: root.values.showMpris !== false
    readonly property string mpdSocket: root.expand(root.values.mpdSocket ?? "")
    readonly property string mpdConfig: root.expand(root.values.mpdConfig ?? "~/.config/mpd/mpd.conf")

    // A whole number of minutes, 0 for anything that is not one.
    function minutes(value: var): int {
        return Math.max(0, Math.round(Number(value) || 0));
    }

    // The settings window's way in: one key into settings.json. The file is
    // written back whole as plain JSON, so comments typed into it by hand go;
    // every setting is documented in settings.default.json instead. Whatever
    // the file already said wins over the defaults as before, and the watcher
    // below reads the new file back like any other edit.
    function set(key: string, value: var): void {
        // Writing now would replace the file that did not parse, and every
        // setting in it, with the last ones that did (none, at startup).
        if (root.userBroken) {
            Notify.send("Setting not saved", "settings.json did not parse. Fix it first, so this change does not replace it.");
            return;
        }
        const user = Object.assign({}, root.user, { [key]: value });
        root.user = user;
        userFile.setText("// This machine's settings over settings.default.json, which documents\n// each one. The settings window (the gear) rewrites this file.\n" + JSON.stringify(user, null, 4) + "\n");
    }

    // An empty override restores the title supplied by the feed.
    function setFeedTitle(url: string, title: string): void {
        const titles = Object.assign({}, root.feedTitles);
        if (title.trim())
            titles[url] = title.trim();
        else
            delete titles[url];
        root.set("feedTitles", titles);
    }

    // Why `value` cannot start this launcher mode, or nothing if it can. A
    // letter or a digit would take over the start of an app's name; comparing
    // cases finds letters in any script, which QML's regexes cannot.
    function launcherPrefixProblem(key: string, value: string): string {
        if (value.length !== 1 || /[\s\d]/.test(value) || value.toLowerCase() !== value.toUpperCase())
            return "Use one symbol, not a letter or number.";
        const prefixes = root.launcherPrefixes;
        return Object.keys(prefixes).some(k => k !== key && prefixes[k] === value) ? "Another mode uses this symbol." : "";
    }

    function setLauncherPrefix(key: string, value: string): void {
        root.set("launcherPrefixes", Object.assign({}, root.launcherPrefixes, { [key]: value }));
    }

    function badgeStyle(key: string): string {
        const style = root.values[key + "BadgeStyle"];
        return ["underdot", "hide"].includes(style) ? style : "badge";
    }

    // Apply casing to the complete label before it is drawn in character columns.
    function applyCase(text: string, mode: string): string {
        switch (mode) {
        case "uppercase":
            return text.toLocaleUpperCase();
        case "lowercase":
            return text.toLocaleLowerCase();
        case "capitalize":
            return text.toLocaleLowerCase().replace(/(^|\s)(\S)/g,
                (_, space, first) => space + first.toLocaleUpperCase());
        default:
            return text;
        }
    }

    function clockDisplay(date: date): var {
        return root.timeDisplay(date, root.datetimeFormat);
    }

    // The formatted time, with the ranges RollingText draws two-thirds size:
    // ^[...] raised to the capitals' tops, _[...] on the baseline as a small
    // AM/PM is, and with Smaller AM/PM the AM/PM tokens, closed up to the time. Quoted literals stay as typed, so
    // '^[' shows the characters. Each run is marked with a private-use
    // character before formatting and found again after it.
    function timeDisplay(date: date, timeFormat: string, small: var, textCase: var): var {
        const smallAmPm = small ?? root.smallAmPm;
        const mode = textCase ?? root.timeCase;
        let open = "";
        const format = timeFormat.replace(/'(?:[^']|'')*'|\^\[|_\[|\]|AP|ap/g, token => {
            if (token[0] === "'")
                return token;
            if (token === "^[" || token === "_[") {
                if (open)
                    return token;
                open = token;
                return token === "^[" ? "\uE002" : "\uE003";
            }
            if (token === "]") {
                if (!open)
                    return token;
                open = "";
                return "\uE001";
            }
            return smallAmPm && !open ? "\uE000" + token + "\uE001" : token;
        });
        // An unclosed run goes to the end.
        const marked = Qt.formatDateTime(date, format) + (open ? "\uE001" : "");
        const markers = /[\uE000-\uE003]/g;
        const cased = root.applyCase(marked.replace(markers, ""), mode);

        let text = "";
        let offset = 0;
        const smallRanges = [];
        const runs = /([\uE000\uE002\uE003])([^\uE001]*)\uE001/g;
        let match;
        while ((match = runs.exec(marked)) !== null) {
            // Casing can change a string's length (\u00DF to SS), so a run's place
            // is counted in the cased text.
            const before = marked.slice(0, match.index).replace(markers, "");
            const start = root.applyCase(before, mode).length;
            const end = root.applyCase(before + match[2], mode).length;
            const amPm = match[1] === "\uE000";
            const between = cased.slice(offset, start);
            text += amPm ? between.replace(/\s+$/, "") : between;
            const at = text.length;
            text += cased.slice(start, end);
            smallRanges.push(amPm ? { start: at, end: text.length }
                : { start: at, end: text.length, shift: match[1] === "\uE002" ? "sup" : "sub" });
            offset = end;
        }
        text += cased.slice(offset);
        return { text, smallRanges };
    }

    // A time of day as everything outside the clock says it: the Hour Format,
    // with the clock's letter case and Smaller AM/PM. Plain text gets the
    // closed-up AM/PM; timeMarkup draws it small.
    readonly property string hourFormat: root.twelveHour ? "h:mm AP" : "HH:mm"

    function hourDisplay(date: date): var {
        return root.timeDisplay(date, root.hourFormat);
    }

    function sayTime(date: date): string {
        return root.hourDisplay(date).text;
    }

    // For a time kept as hours and minutes rather than a moment.
    function sayHourMinute(hour: int, minute: int): string {
        return root.sayTime(new Date(2000, 0, 1, hour, minute));
    }

    // A timeDisplay as rich text for a line `pixelSize` tall, its small runs
    // at the bar's two-thirds size: on the baseline, or raised.
    function timeMarkup(display: var, pixelSize: int, ratio: var): string {
        const escape = text => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const small = Math.max(1, Math.round(pixelSize * (ratio ?? 2 / 3)));
        let markup = "";
        let offset = 0;
        for (const range of display.smallRanges) {
            const align = range.shift === "sup" ? "; vertical-align: super" : "";
            markup += escape(display.text.slice(offset, range.start))
                + `<span style="font-size: ${small}px${align}">${escape(display.text.slice(range.start, range.end))}</span>`;
            offset = range.end;
        }
        return markup + escape(display.text.slice(offset));
    }

    // Switch hour notation while preserving custom separators, literals and other tokens.
    function setTwelveHour(enabled: bool): void {
        if (enabled !== root.twelveHour)
            root.set("datetimeFormat", root.withTwelveHour(root.datetimeFormat, enabled));
    }

    function setLockTwelveHour(enabled: bool): void {
        if (enabled !== root.lockTwelveHour)
            root.set("lockTimeFormat", root.withTwelveHour(root.lockTimeFormat, enabled));
    }

    function withTwelveHour(current: string, enabled: bool): string {
        if (/^(?:HH|h):mm(?::ss)?(?: [Aa][Pp])?$/.test(current)) {
            const seconds = current.includes(":ss");
            return enabled ? (seconds ? "h:mm:ss AP" : "h:mm AP") : (seconds ? "HH:mm:ss" : "HH:mm");
        }
        let format = current.replace(/'(?:[^']|'')*'|H{1,2}|h{1,2}/g,
            token => token[0] === "'" ? token : enabled ? "h".repeat(token.length) : "H".repeat(token.length));
        if (enabled)
            format += " AP";
        else
            format = format.replace(/'(?:[^']|'')*'|\s*(?:AP|ap)/g, token => token[0] === "'" ? token : "");
        return format.trim();
    }

    // A list setting with `item` put in or taken out.
    function toggleIn(key: string, item: string): void {
        const list = Array.from(root.values[key] ?? []);
        const at = list.indexOf(item);
        if (at >= 0)
            list.splice(at, 1);
        else
            list.push(item);
        root.set(key, list);
    }

    function screenOn(name: string): bool {
        return root.screens.length === 0 || root.screens.includes(name);
    }

    // "~" and "$XDG_RUNTIME_DIR" as the shell would read them.
    function expand(path: string): string {
        return path.replace(/^~(?=\/|$)/, root.home).replace("$XDG_RUNTIME_DIR", Quickshell.env("XDG_RUNTIME_DIR"));
    }

    // A command in the chosen terminal. `--title=` in the joined form every
    // common terminal accepts, and a held window is a prompt rather than a
    // flag, because only kitty has --hold.
    function inTerminal(command: var, title: string, hold: bool): var {
        const run = hold ? ["sh", "-c", '"$@"; printf "\\nPress Enter to close. "; read _', "sh", ...command] : command;
        return [root.terminal, ...(title ? ["--title=" + title] : []), "-e", ...run];
    }

    // The program a command line starts, for Tools to look for.
    function program(command: string): string {
        return root.expand(command.trim().split(/\s+/)[0] ?? "");
    }

    // A right click's app (networkCommand and the rest), ready to run. Empty
    // when it is not set or not installed, and the popup says which.
    function helper(command: string, inTerminal: bool): var {
        const program = root.program(command);
        if (!program || !Tools.has(program) || (inTerminal && !Tools.hasTerminal))
            return [];
        return inTerminal ? root.inTerminal(["sh", "-c", command], program.split("/").pop() + " (floating)") : ["sh", "-c", command];
    }

    // Upgrade's or Clean Up's command: in the chosen terminal, unless the
    // commands open their own.
    function commandLine(command: string, title: string): var {
        return root.commandsInTerminal ? root.inTerminal(["sh", "-c", command], title, true) : ["sh", "-c", command];
    }

    // A folder in the chosen file manager. The setting may carry flags after
    // the program, as "dolphin --new-window" does: without it Dolphin hands a
    // folder it already has open to that window, wherever it is hidden.
    function inFileManager(path: string): var {
        return [...root.fileManager.split(/\s+/).filter(s => s), path];
    }

    readonly property var webAppDefinitions: ({
        gmail: { title: "Gmail", appId: "fmgjjmmmlfnkbppncabfkddbjimcfncm" },
        calendar: { title: "Google Calendar", appId: "kjbdgfilnfhdoflbpgamdcdgpehopbep" },
        tasks: { title: "Google Tasks", appId: "okhfeehhillipaleckndoboggdkcebmo" }
    })
    readonly property var desktopApps: DesktopEntries.applications.values

    // Chromium's site-derived app id is stable across profiles and app names.
    function automaticWebApp(key: string): var {
        const definition = root.webAppDefinitions[key];
        return definition ? root.desktopApps.find(e => e.id.startsWith(`chrome-${definition.appId}-`)) ?? null : null;
    }

    // An unavailable explicit choice falls back to the website.
    function webAppEntry(key: string): var {
        const chosen = root.webApps[key] || "";
        if (chosen === "browser") return null;
        return chosen ? DesktopEntries.byId(chosen) : root.automaticWebApp(key);
    }

    // Offer every installed app so other browsers' PWAs can be selected too.
    function webAppOptions(key: string): var {
        const automatic = root.automaticWebApp(key);
        const options = [
            { value: "", label: automatic ? `Automatic (${automatic.name})` : "Automatic (Website)" },
            { value: "browser", label: "Website" },
            ...root.desktopApps.slice().sort((a, b) => a.name.localeCompare(b.name)).map(e => ({ value: e.id, label: e.name }))
        ];
        const chosen = root.webApps[key];
        if (chosen && !options.some(o => o.value === chosen))
            options.push({ value: chosen, label: chosen + " (Unavailable)" });
        return options;
    }

    // Preserve direct links to threads, compose windows and calendar days.
    function webApp(key: string, url: string, home: string): var {
        const entry = root.webAppEntry(key);
        if (!entry || !entry.command.length) return ["xdg-open", url || home];
        const command = entry.command.slice();
        if (url) command.push(command.some(arg => arg.startsWith("--app-id="))
            ? `--app-launch-url-for-shortcuts-menu-item=${url}` : url);
        const run = entry.runInTerminal ? root.inTerminal(command, entry.name, false) : command;
        return entry.workingDirectory ? { command: run, workingDirectory: entry.workingDirectory } : run;
    }

    // --- the files -----------------------------------------------------------
    // JSON plus // comments and trailing commas. The comment stripper walks
    // the text rather than using a regex so that a "//" inside a string — a
    // URL, say — is left alone.
    function parse(text: string): var {
        let out = "";
        let quoted = false;
        for (let i = 0; i < text.length; i++) {
            const c = text[i];
            if (quoted) {
                out += c;
                if (c === "\\")
                    out += text[++i] ?? "";
                else if (c === '"')
                    quoted = false;
            } else if (c === '"') {
                quoted = true;
                out += c;
            } else if (c === "/" && text[i + 1] === "/") {
                while (i + 1 < text.length && text[i + 1] !== "\n")
                    i++;
            } else if (c === "}" || c === "]") {
                out = out.replace(/,\s*$/, "");
                out += c;
            } else {
                out += c;
            }
        }
        return JSON.parse(out);
    }

    // A file that does not parse keeps the last settings that did, and says
    // so where it will be seen: whoever saved it is looking at the screen.
    // Qt's JSON.parse names no line ("Parse error" and nothing else), so the
    // notice points at the edit instead.
    // Whether settings.json, as it is on disk, is one that did not parse.
    property bool userBroken: false

    function loadUser(): void {
        const user = root.load(userFile, "settings.json");
        root.userBroken = user === null;
        if (user)
            root.user = user;
    }

    function load(view: var, name: string): var {
        try {
            return root.parse(view.text());
        } catch (e) {
            console.warn(`${name}: ${e.message}`);
            Notify.send(`${name} did not parse`, "Look for a missing comma or quote in the last change. The bar keeps the settings it had.");
            return null;
        }
    }

    // Both read here, before anything that asked for a setting has finished
    // being built, so the bar starts on the real values rather than on none
    // and again a moment later. `loaded` is too late for that: it comes after
    // the first reader has already been handed "" — the wallpaper service
    // scanned `find ""` at boot, found nothing, and restored nothing. text()
    // on a blocking view reads the file on the spot instead. A missing
    // settings.json is left to onLoadFailed below rather than reported as
    // one that did not parse.
    Component.onCompleted: {
        root.defaults = root.load(defaultFile, "settings.default.json") ?? root.defaults;
        userFile.text();
        if (userFile.loaded)
            root.loadUser();
    }

    // After startup these keep the values current: an edit to settings.json
    // lands here.
    FileView {
        id: defaultFile

        path: Quickshell.shellPath("settings.default.json")
        blockLoading: true
        onLoaded: root.defaults = root.load(defaultFile, "settings.default.json") ?? root.defaults
    }

    FileView {
        id: userFile

        path: Quickshell.shellPath("settings.json")
        blockLoading: true
        printErrors: false
        // watchChanges only signals: text() goes on returning what was read
        // at startup, and `loaded` never fires again, until reload().
        watchChanges: true
        onFileChanged: userFile.reload()
        onLoaded: root.loadUser()
        // First run: the defaults, comments and all, as the file to edit.
        onLoadFailed: userFile.setText(defaultFile.text())
    }
}
