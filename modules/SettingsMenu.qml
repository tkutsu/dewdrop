import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import qs
import qs.components
import qs.services

// The settings window: pages down the left, the open page's settings on the
// right, a filter line over the pages that searches all of them.
//
// Everything on a page is data. A page is sections, a section is a heading,
// a few words on what it is for and its settings, and a setting is the plain
// object SettingRow describes: a type that picks its control, words, and a
// get and a set onto wherever the value lives. Adding one is adding an
// object to `pages` below; nothing else here changes.
//
// On OverlayWindow like the launcher rather than a bar popup, because a bar
// popup takes no keyboard, and the launcher's page is every app there is.
OverlayWindow {
    id: root

    // The launcher's layer namespace, for its blur rule in wrules.lua: the
    // same box on the same terms.
    name: "launcher"
    shown: Preferences.shown
    inputItem: box
    onDismissed: Preferences.hide()

    // Match the launcher's width bounce and defocus without scaling the controls.
    property alias widthRatio: motion.widthRatio
    property alias contentAlpha: motion.contentAlpha
    property alias exitBlur: motion.exitBlur
    readonly property real extraWidth: root.boxWidth * (root.widthRatio - 1)
    readonly property bool presenting: root.opened || root.contentAlpha > 0

    SpotlightMotion {
        id: motion
        opened: root.opened
        dismissMs: Preferences.dismissMs
    }


    property int page: 0
    property string query: ""

    readonly property int boxWidth: 700
    readonly property int boxHeight: 560
    readonly property int boxPad: Theme.panelPadding
    readonly property int sideWidth: 168

    // --- the pages -----------------------------------------------------------

    // Module mode controls, shared by both pills.
    readonly property var modules: ({
            audio: { title: "Volume", glyph: Theme.glyph.vol[Theme.glyph.vol.length - 1] },
            email: { title: "Mail", glyph: Theme.glyph.mailUnread },
            tasks: { title: "Tasks", glyph: Theme.glyph.tasks },
            updater: { title: "Updates", glyph: Theme.glyph.update },
            feeds: { title: "Feeds", glyph: Theme.glyph.feeds },
            bell: { title: "Notifications", glyph: Theme.glyph.notif },
            satty: { title: "Screenshot", glyph: Theme.glyph.satty },
            idle: { title: "Caffeine", glyph: Theme.glyph.idleOff },
            wallpaper: { title: "Wallpaper", glyph: Theme.glyph.wallpaper },
            night: { title: "Night Mode", glyph: Theme.glyph.nightOff },
            sys: { title: "System", glyph: Theme.glyph.gauge },
            settings: { title: "Settings", glyph: Theme.glyph.settings },
            drives: { title: "Drives", glyph: Theme.glyph.drive },
            bluetooth: { title: "Bluetooth", glyph: Theme.glyph.bluetooth },
            network: { title: "Network", glyph: Theme.glyph.wifiStrength[Theme.glyph.wifiStrength.length - 1] },
            tray: { title: "Tray", glyph: Theme.glyph.tray },
            language: { title: "Keyboard Layout", glyph: Theme.glyph.keyboard },
            date: { title: "Date", glyph: Theme.glyph.calendar },
            weather: { title: "Weather", glyph: Theme.glyph.weather },
            time: { title: "Time", glyph: Theme.glyph.timer },
            countdown: { title: "Timer", glyph: Theme.glyph.timer }
        })

    readonly property var pinOptions: [
        { value: "auto", label: "Auto" },
        { value: "pinned", label: "Pinned" },
        { value: "drawer", label: "Drawer" }
    ]

    function placement(key: string): var {
        const m = root.modules[key];
        return { type: "choice", id: "pin:" + key, title: m.title, glyph: m.glyph, options: root.pinOptions, get: () => DrawerPins.mode(key), set: v => DrawerPins.setMode(key, v) };
    }

    function badgeStyle(key: string): var {
        const m = root.modules[key];
        return { type: "choice", id: key + "BadgeStyle", title: m.title, glyph: m.glyph,
            options: [{ value: "badge", label: "Badge" }, { value: "dot", label: "Dot" }, { value: "underdot", label: "Underdot" }, { value: "hide", label: "Hide" }],
            get: () => Settings.badgeStyle(key), set: v => Settings.set(key + "BadgeStyle", v) };
    }

    // Running now, and kept in but not running, so it can still be let out.
    readonly property var trayRows: {
        const items = SystemTray.items.values.filter(item => !/^(blueman|nm-applet)/.test(item.id));
        const rows = items.map(item => root.trayRow(item.id, item.tooltipTitle || item.title || item.id, item.icon));
        for (const key of Object.keys(DrawerPins.pins))
            if (key.startsWith("tray:") && !items.some(item => "tray:" + item.id === key))
                rows.push(root.trayRow(key.slice(5), key.slice(5) + " (not running)", ""));
        return rows.sort((a, b) => a.title.localeCompare(b.title));
    }

    function trayRow(id: string, title: string, icon: string): var {
        const key = "tray:" + id;
        return { type: "toggle", id: key, title, icon, glyph: Theme.glyph.tray, get: () => !DrawerPins.kept(key), set: v => DrawerPins.setMode(key, v ? "auto" : "drawer") };
    }

    // A row for anything the launcher can be told to leave out, under the id
    // Launcher filters on (see Settings.hiddenApps).
    function shownInLauncher(id: string, title: string, look: var): var {
        return Object.assign({ type: "toggle", id: "launcher:" + id, title, get: () => !Settings.hiddenApps.includes(id), set: v => {
                if (v === Settings.hiddenApps.includes(id))
                    Settings.toggleIn("hiddenApps", id);
            } }, look);
    }

    readonly property var appRows: {
        const rows = [];
        for (const e of DesktopEntries.applications.values.slice().sort((a, b) => a.name.localeCompare(b.name))) {
            rows.push(root.shownInLauncher(e.id, e.name, { icon: e.icon }));
            if (!Settings.showDesktopActions)
                continue;
            for (const a of e.actions ?? [])
                rows.push(root.shownInLauncher(e.id + ":" + a.id, e.name + " · " + a.name, { icon: a.icon || e.icon }));
        }
        return rows;
    }

    // Named for what they do rather than by Launcher's own titles, which
    // say which way they would flip right now ("Turn Wi-Fi off").
    readonly property var controlRows: [
        root.shownInLauncher("desktop:mute", "Mute Sound", { glyph: Theme.glyph.vol[Theme.glyph.vol.length - 1] }),
        root.shownInLauncher("desktop:night", "Night Mode", { glyph: Theme.glyph.nightOff }),
        root.shownInLauncher("desktop:wifi", "Wi-Fi", { glyph: Theme.glyph.wifiStrength[Theme.glyph.wifiStrength.length - 1] }),
        root.shownInLauncher("desktop:bluetooth-power", "Bluetooth", { glyph: Theme.glyph.bluetooth })
    ]

    readonly property var powerRows: Power.actions.map(p => root.shownInLauncher("power:" + p.key, p.name, { glyph: p.glyph }))

    function feedAddressProblem(value: string): string {
        return /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/.test(value)
            ? "" : "Enter a full http:// or https:// feed address.";
    }

    function channelProblem(value: string): string {
        return /^(?:@[\w.-]+|UC[\w-]{22})$/.test(value)
            || /^https?:\/\/(?:www\.|m\.)?youtube\.com\/(?:@[\w.-]+|channel\/UC[\w-]{22})(?:[/?#][^\s]*)?$/.test(value)
            ? "" : "Enter a YouTube @handle, channel ID or channel link.";
    }

    // Gmail's inbox tabs, by the names its search takes (category:updates).
    readonly property var mailRows: [["primary", "Primary"], ["updates", "Updates"], ["promotions", "Promotions"], ["social", "Social"], ["forums", "Forums"]].map(([key, title]) => ({
                type: "toggle", id: "mail:" + key, title, get: () => Settings.mailCategories.includes(key), set: v => {
                    if (v !== Settings.mailCategories.includes(key))
                        Settings.toggleIn("mailCategories", key);
                }
            }))

    readonly property var connectedScreens: Quickshell.screens.map(s => s.name).filter(name => name)
    readonly property var displayRows: {
        const selected = Array.from(Settings.screens);
        const connected = root.connectedScreens;
        const active = selected.filter(name => connected.includes(name));
        const rows = [{ type: "toggle", id: "screens", title: "All Displays", enabled: connected.length > 0,
            get: () => Settings.screens.length === 0,
            set: v => Settings.set("screens", v ? [] : root.connectedScreens.slice()) }];
        if (selected.length)
            for (const name of [...new Set([...connected, ...selected])])
                rows.push({ type: "toggle", id: "screen:" + name, title: name + (connected.includes(name) ? "" : " (Disconnected)"),
                    enabled: !selected.includes(name) || (selected.length > 1 && (!connected.includes(name) || active.length > 1)),
                    get: () => Settings.screenOn(name), set: v => root.setDisplay(name, v) });
        return rows;
    }

    // Keep a selected display connected so editing visibility cannot hide every bar.
    function setDisplay(name: string, shown: bool): void {
        const selected = Array.from(Settings.screens);
        const next = shown ? [...new Set([...selected, name])] : selected.filter(n => n !== name);
        if (next.length && (!root.connectedScreens.length || next.some(n => root.connectedScreens.includes(n))))
            Settings.set("screens", next);
    }

    readonly property var layoutRows: [...new Set(Keyboard.layouts.map(l => l.name))].map(name => ({
        type: "text", id: "layout:" + name, title: name, placeholder: name.slice(0, 2).toUpperCase(),
        get: () => Settings.layoutNames[name] ?? "",
        set: v => {
            const names = Object.assign({}, Settings.layoutNames);
            if (v.trim()) names[name] = v.trim();
            else delete names[name];
            Settings.set("layoutNames", names);
        }
    }))

    readonly property var fontFamilies: Qt.fontFamilies().slice().sort((a, b) => a.localeCompare(b))

    // Keep a saved family selectable even if its font is currently missing.
    function fontOptions(current: string): var {
        const options = root.fontFamilies.map(name => ({ value: name, label: name }));
        if (!root.fontFamilies.includes(current))
            options.unshift({ value: current, label: current ? current + " (Unavailable)" : "Default" });
        return options;
    }

    function webApp(key: string): var {
        return { type: "dropdown", id: "webApp:" + key, title: "Open With", keywords: Settings.webAppDefinitions[key].title,
            tooltip: "Automatic uses an installed Chromium app when available, then the website.",
            options: Settings.webAppOptions(key), get: () => Settings.webApps[key] || "",
            set: v => Settings.set("webApps", Object.assign({}, Settings.webApps, { [key]: v })) };
    }

    readonly property var pages: [
        {
            title: "Bar",
            sections: [
                {
                    title: "Displays",
                    rows: root.displayRows
                },
                {
                    title: "Workspaces",
                    rows: [
                        { type: "toggle", id: "groupWindows", title: "Group Windows by App", tooltip: "Click a group to expand its windows.", get: () => Settings.groupWindows, set: v => Settings.set("groupWindows", v) },
                        { type: "choice", id: "groupWindowBadgeStyle", title: "Group Indicator",
                            options: [{ value: "hide", label: "Hide" }, { value: "dot", label: "Dot" }, { value: "badge", label: "Count" }],
                            get: () => Settings.groupWindowBadgeStyle, set: v => Settings.set("groupWindowBadgeStyle", v) },
                        { type: "toggle", id: "magnifyMark", title: "Magnify Under the Mark", tooltip: "The glass magnifies the icons it passes over as it moves between workspaces.", get: () => Settings.magnifyMark, set: v => Settings.set("magnifyMark", v) }
                    ]
                },
                {
                    title: "Keyboard Layout",
                    rows: [
                        { type: "toggle", id: "layoutChangeNotification", title: "Show Notification", text: "Transient, for three seconds.", get: () => Settings.layoutChangeNotification, set: v => Settings.set("layoutChangeNotification", v) },
                        { type: "toggle", id: "layoutChangeBounce", title: "Show And Bounce For 3s", tooltip: "Shows the module for three seconds and bounces once. Reduce Motion dims it instead.", get: () => Settings.layoutChangeBounce, set: v => Settings.set("layoutChangeBounce", v) }
                    ]
                },
                {
                    title: "Count Indicators",
                    rows: ["email", "tasks", "countdown", "bell", "updater", "feeds"].map(key => root.badgeStyle(key))
                },
                {
                    title: "Keyboard Labels",
                    rows: root.layoutRows
                },
                {
                    title: "Module Visibility",
                    text: "Auto shows active modules. Pinned always shows them. Drawer keeps them behind the chevron. Drag modules to move or reorder them.",
                    rows: RightPillOrder.keys.filter(k => root.modules[k]).map(k => root.placement(k))
                },
                {
                    title: "Tray Icons",
                    text: "Off keeps an icon in the drawer.",
                    rows: root.trayRows
                }
            ]
        },
        {
            title: "Appearance",
            sections: [
                {
                    title: "Fonts",
                    rows: [
                        { type: "dropdown", id: "font", title: "Interface Font", options: root.fontOptions(Settings.font), get: () => Settings.font, set: v => Settings.set("font", v) },
                        { type: "dropdown", id: "monoFont", title: "Monospaced Font", options: root.fontOptions(Settings.monoFont), get: () => Settings.monoFont, set: v => Settings.set("monoFont", v) }
                    ]
                },
                {
                    title: "Wallpaper",
                    rows: [
                        { type: "text", id: "wallpaperDir", title: "Image Folder", placeholder: Settings.defaults.wallpaperDir, get: () => Settings.values.wallpaperDir, set: v => Settings.set("wallpaperDir", v.trim() || Settings.defaults.wallpaperDir) }
                    ]
                }
            ]
        },
        {
            title: "Date & Time",
            sections: [
                {
                    title: "Time",
                    rows: [
                        { type: "choice", id: "twelveHour", title: "Hour Format", options: [{ value: false, label: "24h" }, { value: true, label: "12h" }], get: () => Settings.twelveHour, set: v => Settings.setTwelveHour(v) },
                        { type: "text", id: "timeFormat", title: "Custom Format", tooltip: "Clock and alarms.\nH/HH: 24h hour. h/hh: 12h hour with AP/ap.\nm/mm: minutes. s/ss: seconds.\nAP/ap: upper/lowercase AM/PM.\nz/zzz: fractional seconds. t: time zone.\ntt/ttt: UTC offset without/with colon.\ntttt: full time zone name.\nPut literal text in single quotes.", placeholder: Settings.defaults.timeFormat, get: () => Settings.timeFormat, set: v => Settings.set("timeFormat", v || Settings.defaults.timeFormat) },
                        { type: "choice", id: "timeCase", title: "Letter Case", options: [{ value: "uppercase", label: "UPPER" }, { value: "lowercase", label: "lower" }], get: () => Settings.timeCase, set: v => Settings.set("timeCase", v) },
                        { type: "toggle", id: "smallAmPm", title: "Smaller AM/PM", tooltip: "For 12h bar readouts. Popup times stay full size.", get: () => Settings.smallAmPm, set: v => Settings.set("smallAmPm", v) }
                    ]
                },
                {
                    title: "Date",
                    rows: [
                        { type: "text", id: "dateFormat", title: "Custom Format", tooltip: "d/dd: day. ddd/dddd: short/full weekday.\nM/MM: month. MMM/MMMM: short/full month name.\nyy/yyyy: year. Names use your locale.\nPut literal text in single quotes.", placeholder: Settings.defaults.dateFormat, get: () => Settings.dateFormat, set: v => Settings.set("dateFormat", v || Settings.defaults.dateFormat) },
                        { type: "choice", id: "dateCase", title: "Letter Case", options: [{ value: "normal", label: "Default" }, { value: "uppercase", label: "UPPER" }, { value: "lowercase", label: "lower" }], get: () => Settings.dateCase, set: v => Settings.set("dateCase", v) }
                    ]
                }
            ]
        },
        {
            title: "Launcher",
            sections: [
                {
                    title: "File Search",
                    rows: [
                        { type: "text", id: "fileSearchIgnore", title: "Ignore File", tooltip: "Extra patterns in fd's ignore-file format. Empty uses fd's normal rules.", placeholder: "No extra ignore file", get: () => Settings.values.fileSearchIgnore ?? "", set: v => Settings.set("fileSearchIgnore", v.trim()) }
                    ]
                },
                {
                    title: "Desktop Actions",
                    rows: [
                        { type: "toggle", id: "showDesktopActions", title: "Include App Shortcuts", tooltip: "App actions such as New Private Window.", get: () => Settings.showDesktopActions, set: v => Settings.set("showDesktopActions", v) }
                    ]
                },
                {
                    title: "Controls",
                    rows: root.controlRows
                },
                {
                    title: "Power",
                    rows: root.powerRows
                },
                {
                    title: "Apps",
                    text: "Off hides an app or shortcut from launcher results.",
                    rows: root.appRows
                }
            ]
        },
        {
            title: "Apps & Services",
            sections: [
                {
                    title: "Default Apps",
                    rows: [
                        { type: "text", id: "terminal", title: "Terminal", tooltip: "Must accept --title=<title> and -e <command>.", placeholder: Settings.defaults.terminal, get: () => Settings.values.terminal, set: v => Settings.set("terminal", v.trim() || Settings.defaults.terminal) },
                        { type: "text", id: "editor", title: "Editor", placeholder: Quickshell.env("EDITOR") || "nvim", get: () => Settings.values.editor ?? "", set: v => Settings.set("editor", v.trim()) },
                        { type: "text", id: "fileManager", title: "File Manager", tooltip: "Flags may follow the program name.", placeholder: Settings.defaults.fileManager, get: () => Settings.values.fileManager, set: v => Settings.set("fileManager", v.trim() || Settings.defaults.fileManager) }
                    ]
                },
                {
                    title: "Screenshots",
                    rows: [
                        { type: "text", id: "screenshotCommand", title: "Capture Command", text: "Empty hides the screenshot button.", placeholder: "Not configured", get: () => Settings.screenshotCommand, set: v => Settings.set("screenshotCommand", v.trim()) }
                    ]
                },
                {
                    title: "External Helpers",
                    rows: [
                        { type: "text", id: "scriptsDir", title: "Scripts Folder", tooltip: "Helpers for power, display, updates and cleanup.", placeholder: Settings.defaults.scriptsDir, get: () => Settings.values.scriptsDir, set: v => Settings.set("scriptsDir", v.trim() || Settings.defaults.scriptsDir) }
                    ]
                },
                {
                    title: "Music",
                    rows: [
                        { type: "toggle", id: "showMpris", title: "Show Now Playing", tooltip: "Media from browsers and other MPRIS apps.", get: () => Settings.showMpris, set: v => Settings.set("showMpris", v) },
                        { type: "toggle", id: "scrollMusicTitles", title: "Scroll Long Titles", tooltip: "Reduce Motion keeps titles still.", get: () => Settings.scrollMusicTitles, set: v => Settings.set("scrollMusicTitles", v) },
                        { type: "text", id: "mpdSocket", title: "MPD Socket", placeholder: Settings.defaults.mpdSocket, get: () => Settings.values.mpdSocket, set: v => Settings.set("mpdSocket", v.trim() || Settings.defaults.mpdSocket) }
                    ]
                },
                {
                    title: "Tasks",
                    rows: [
                        root.webApp("tasks"),
                        { type: "dropdown", id: "defaultTaskList", title: "Default List", tooltip: "Unavailable lists fall back to the first list.", placeholder: "No task lists available", options: Tasks.lists.map(l => ({ value: l.id, label: l.title })), get: () => Tasks.defaultList.id, set: v => Settings.set("defaultTaskList", v) }
                    ]
                },
                {
                    title: "Calendar",
                    rows: [root.webApp("calendar")]
                },
                {
                    title: "Feeds",
                    text: "Your YouTube subscriptions are followed already. Add extra channels or RSS and Atom feeds below.",
                    rows: [
                        { type: "list", id: "feedChannels", title: "Extra YouTube Channels", placeholder: "@handle or channel link", validate: root.channelProblem, get: () => Settings.feedChannels, set: v => Settings.set("feedChannels", v) },
                        { type: "list", id: "feedUrls", title: "RSS Feeds", tooltip: "RSS or Atom feed addresses, shown under the videos. Leave a title blank to use the feed's own title.", placeholder: "https://example.com/feed.xml", validate: root.feedAddressProblem, get: () => Settings.feedUrls, set: v => Settings.set("feedUrls", v),
                            getTitle: url => Settings.feedTitles[url] ?? "", setTitle: (url, title) => Settings.setFeedTitle(url, title) }
                    ]
                },
                {
                    title: "Mail",
                    rows: [
                        root.webApp("gmail"),
                        { type: "text", id: "downloadsDir", title: "Attachment Folder", placeholder: Settings.defaults.downloadsDir, get: () => Settings.values.downloadsDir || Settings.defaults.downloadsDir, set: v => Settings.set("downloadsDir", v.trim() || Settings.defaults.downloadsDir) }
                    ]
                },
                {
                    title: "Mail Inbox Tabs",
                    text: "Count and announce unread mail from these tabs. None selected includes the whole inbox; other tabs fold into Other.",
                    rows: root.mailRows
                }
            ]
        },
        {
            title: "Accessibility",
            sections: [
                {
                    title: "Motion",
                    rows: [
                        { type: "toggle", id: "reduceMotion", title: "Reduce Motion", text: "Limit animation, parallax and scrolling titles.", get: () => Settings.reduceMotion, set: v => Settings.set("reduceMotion", v) }
                    ]
                },
                {
                    title: "Transparency",
                    rows: [
                        { type: "toggle", id: "reduceTransparency", title: "Reduce Transparency", text: "Use solid surfaces instead of glass.", get: () => Settings.reduceTransparency, set: v => Settings.set("reduceTransparency", v) }
                    ]
                }
            ]
        }
    ]

    // The list as drawn: the open page, or with a filter typed, whatever
    // matches it on any page. The sections' words stand aside while
    // filtering, so the hits sit close together.
    readonly property var entries: {
        const terms = root.query.toLowerCase().split(/\s+/).filter(t => t);
        const out = [];
        root.pages.forEach((page, p) => {
            if (!terms.length && p !== root.page)
                return;
            for (const section of page.sections) {
                const rows = terms.length ? section.rows.filter(r => {
                    const labels = r.type === "choice" ? r.options.map(o => o.label) : [];
                    const words = [page.title, section.title, r.title, r.text ?? "", r.tooltip ?? "", r.keywords ?? "", ...labels].join(" ").toLowerCase();
                    return terms.every(t => words.includes(t));
                }) : section.rows;
                if (!rows.length)
                    continue;
                const title = terms.length ? page.title + " · " + section.title : section.title;
                out.push({ id: "#" + page.title + "/" + section.title, heading: title, text: terms.length ? "" : (section.text ?? "") });
                for (const r of rows)
                    out.push({ id: page.title + "/" + r.id, setting: r });
            }
        });
        return out;
    }

    // --- the box -------------------------------------------------------------

    BackdropProbe {
        id: under

        screen: root.screen
        area: Qt.rect(Math.round((root.width - root.boxWidth) / 2), Math.round((root.height - root.boxHeight) / 2), root.boxWidth, root.boxHeight)
        active: true
    }

    RectangularShadow {
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        visible: root.presenting
        opacity: root.contentAlpha
        offset.y: Theme.shadowY
        radius: box.radius
        blur: Theme.shadowBlur
        color: Theme.shadow
    }

    Rectangle {
        id: box

        x: Math.round((root.width - root.boxWidth - root.extraWidth) / 2)
        y: Math.round((root.height - root.boxHeight) / 2)
        width: Math.round(root.boxWidth + root.extraWidth)
        height: root.boxHeight
        visible: root.presenting
        clip: true
        radius: Theme.panelRadius
        color: Theme.frostOver(under.luma)

        // Keep the glass above the compositor's blur cutoff until the final fade.
        layer.enabled: root.exitBlur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 16
            blur: root.exitBlur
            opacity: 1 - Math.max(0, (root.exitBlur - 0.4) / 0.6)
        }

        Rim {
            anchors.fill: parent
            radius: box.radius
            z: 10
        }

        // Clicks on the box stay on it rather than dismissing it.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: content

            // Animate the surrounding glass without rewrapping the settings text.
            x: Math.round((box.width - width) / 2)
            width: root.boxWidth
            height: root.boxHeight
            opacity: root.contentAlpha

            // Escape from anywhere in the box that has not used it itself
            // (a field putting its text back does).
            Keys.onEscapePressed: Preferences.hide()

            // --- the sidebar ---------------------------------------------

            Column {
                x: root.boxPad
                y: root.boxPad
                width: root.sideWidth - 2 * root.boxPad
                spacing: 2

                Rectangle {
                    width: parent.width
                    height: 26
                    radius: Theme.selectionRadius
                    color: Theme.well

                    Glyph {
                        x: Theme.popupInset
                        height: parent.height
                        text: Theme.glyph.launcher
                        fontSize: Theme.captionSize
                        color: Theme.label2
                    }

                    TextInput {
                        id: filter
                        Accessible.name: "Search settings"

                        anchors.fill: parent
                        anchors.leftMargin: 26
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.fg
                        selectionColor: Theme.textSelection
                        selectedTextColor: Theme.fg
                        cursorDelegate: TextCaret { textInput: filter }
                        selectByMouse: true
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.popupTextSize
                        focus: true
                        onTextChanged: root.query = text
                        Component.onCompleted: forceActiveFocus()

                        PopupText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !filter.text
                            text: "Search"
                            color: Theme.label3
                        }

                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Escape && filter.text) {
                                filter.text = "";
                            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                filter.text = "";
                                root.page = (root.page + (event.key === Qt.Key_Tab ? 1 : root.pages.length - 1)) % root.pages.length;
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }
                    }
                }

                Item {
                    width: 1
                    height: 8
                }

                Repeater {
                    model: root.pages

                    PopupRow {
                        id: tab

                        required property var modelData
                        required property int index
                        readonly property bool open: root.page === index && !root.query

                        name: tab.modelData.title
                        width: parent.width
                        height: 26
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: {
                            filter.text = "";
                            root.page = index;
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.selectionRadius
                            color: Theme.selectionStrong
                            visible: tab.open
                        }

                        PopupText {
                            x: Theme.popupInset
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.modelData.title
                            font.weight: tab.open ? Font.DemiBold : Font.Normal
                            color: tab.open ? Theme.fg : Theme.label2
                        }
                    }
                }
            }

            Rectangle {
                x: root.sideWidth
                width: Theme.pillBorder
                height: parent.height
                color: Theme.stroke
            }

            // --- the page ------------------------------------------------

            ListView {
                id: list

                // In the accessibility tree as a list to scroll, half a view a step.

                Accessible.role: Accessible.List

                Accessible.name: "Settings"

                Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)

                Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

                x: root.sideWidth + Theme.pillBorder + root.boxPad
                // The whole height, padded inside rather than out, so the
                // list scrolls on under the box's edges instead of stopping
                // short of them.
                width: content.width - x - root.boxPad
                height: root.boxHeight
                topMargin: root.boxPad
                bottomMargin: root.boxPad
                clip: true
                layer.enabled: contentHeight + topMargin + bottomMargin > height
                layer.effect: ScrollEdges {
                    view: list
                }
                boundsBehavior: Flickable.StopAtBounds

                SmoothScroll { view: list }

                // A page, and a new search, start at their top.
                Connections {
                    target: root

                    function onPageChanged(): void {
                        list.contentY = list.originY - list.topMargin;
                    }

                    function onQueryChanged(): void {
                        list.contentY = list.originY - list.topMargin;
                    }
                }

                model: ScriptModel {
                    values: root.entries
                    objectProp: "id"
                }

                delegate: Loader {
                    id: entry

                    required property var modelData

                    width: list.width
                    sourceComponent: modelData.heading !== undefined ? heading : row

                    Component {
                        id: heading

                        // Sections stand apart the way System Settings' groups
                        // do: four times the air above a heading as under it,
                        // so each heading reads with its own rows.
                        Column {
                            topPadding: entry.modelData.id === root.entries[0]?.id ? 0 : 24
                            bottomPadding: 6
                            spacing: 3

                            PopupText {
                                x: Theme.popupInset
                                text: entry.modelData.heading
                                font.weight: Font.DemiBold
                            }

                            PopupText {
                                x: Theme.popupInset
                                width: list.width - Theme.popupInset * 2
                                visible: !!entry.modelData.text
                                text: entry.modelData.text
                                wrapMode: Text.Wrap
                                color: Theme.label2
                                font.pixelSize: Theme.captionSize
                                lineHeight: 1.15
                            }
                        }
                    }

                    Component {
                        id: row

                        SettingRow {
                            width: list.width
                            setting: entry.modelData.setting
                        }
                    }
                }
            }
        }
    }
}
