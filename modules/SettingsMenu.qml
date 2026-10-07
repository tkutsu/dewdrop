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

    property real reveal: root.opened ? 1 : 0

    Behavior on reveal {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }

    property int page: 0
    property string query: ""

    readonly property int boxWidth: 700
    readonly property int boxHeight: 560
    readonly property int boxPad: 12
    readonly property int sideWidth: 168

    // --- the pages -----------------------------------------------------------

    // The right pill, in its own order.
    readonly property var modules: ({
            audio: { title: "Volume", glyph: Theme.glyph.vol[Theme.glyph.vol.length - 1] },
            email: { title: "Mail", glyph: Theme.glyph.mailUnread },
            tasks: { title: "Tasks", glyph: Theme.glyph.tasks },
            updater: { title: "Updates", glyph: Theme.glyph.update },
            bell: { title: "Notifications", glyph: Theme.glyph.notif },
            satty: { title: "Screenshot", glyph: Theme.glyph.satty },
            idle: { title: "Caffeine", glyph: Theme.glyph.idleOff },
            wallpaper: { title: "Wallpaper", glyph: Theme.glyph.wallpaper },
            night: { title: "Night mode", glyph: Theme.glyph.nightOff },
            sys: { title: "System", glyph: Theme.glyph.gauge },
            settings: { title: "Settings", glyph: Theme.glyph.settings },
            drives: { title: "Drives", glyph: Theme.glyph.drive },
            bluetooth: { title: "Bluetooth", glyph: Theme.glyph.bluetooth },
            network: { title: "Network", glyph: Theme.glyph.wifiStrength[Theme.glyph.wifiStrength.length - 1] },
            tray: { title: "Tray", glyph: Theme.glyph.tray },
            language: { title: "Keyboard layout", glyph: Theme.glyph.keyboard }
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
            for (const a of e.actions ?? [])
                rows.push(root.shownInLauncher(e.id + ":" + a.id, e.name + " · " + a.name, { icon: a.icon || e.icon }));
        }
        return rows;
    }

    // Named for what they do rather than by Launcher's own titles, which
    // say which way they would flip right now ("Turn Wi-Fi off").
    readonly property var controlRows: [
        root.shownInLauncher("desktop:mute", "Mute sound", { glyph: Theme.glyph.vol[Theme.glyph.vol.length - 1] }),
        root.shownInLauncher("desktop:dnd", "Do not disturb", { glyph: Theme.glyph.notif }),
        root.shownInLauncher("desktop:night", "Night mode", { glyph: Theme.glyph.nightOff }),
        root.shownInLauncher("desktop:wifi", "Wi-Fi", { glyph: Theme.glyph.wifiStrength[Theme.glyph.wifiStrength.length - 1] }),
        root.shownInLauncher("desktop:bluetooth-power", "Bluetooth", { glyph: Theme.glyph.bluetooth })
    ]

    readonly property var powerRows: Launcher.powerCommands.map(p => root.shownInLauncher("power:" + p.key, p.name ?? (p.label[0].toUpperCase() + p.label.slice(1)), { glyph: p.glyph }))

    readonly property var pages: [
        {
            title: "Bar",
            sections: [
                {
                    title: "Workspaces",
                    rows: [
                        { type: "toggle", id: "groupWindows", title: "Group windows by app", text: "One icon per app on each workspace; a click opens it into one per window. Off gives every window its own icon.", get: () => Settings.groupWindows, set: v => Settings.set("groupWindows", v) }
                    ]
                },
                {
                    title: "Right pill",
                    text: "Auto shows an icon when it has something to show. Pinned always shows it. Drawer keeps it behind the chevron.",
                    rows: RightPillOrder.keys.filter(k => root.modules[k]).map(k => root.placement(k))
                },
                {
                    title: "Tray icons",
                    text: "Apps' own status icons, listed while the app runs. Off keeps an icon behind the chevron while the drawer is closed; with the drawer open it is there and works as before.",
                    rows: root.trayRows
                },
                {
                    title: "Clock",
                    rows: [
                        { type: "text", id: "timeFormat", title: "Time format", text: "A Qt date format: HH:mm reads 14:05, h:mm AP reads 2:05 PM, and with seconds (HH:mm:ss) it ticks every second.", placeholder: "HH:mm", get: () => Settings.timeFormat, set: v => Settings.set("timeFormat", v || "HH:mm") }
                    ]
                },
                {
                    title: "Wallpaper",
                    rows: [
                        { type: "slider", id: "wallpaperParallaxZoom", title: "Parallax zoom", text: "How far the picture is enlarged to leave it room to pan as you change workspace. 1× turns the motion off.", from: 1, to: 1.3, step: 0.01, format: v => v.toFixed(2) + "×", get: () => Settings.wallpaperParallaxZoom, set: v => Settings.set("wallpaperParallaxZoom", v) }
                    ]
                }
            ]
        },
        {
            title: "Launcher",
            sections: [
                {
                    title: "Apps",
                    text: "Off leaves an app, or one of its own actions, out of the launcher's results. Nothing is uninstalled, and its desktop file is left alone.",
                    rows: root.appRows
                },
                {
                    title: "Controls",
                    text: "The switches the launcher offers for sound, notifications, night mode and the radios.",
                    rows: root.controlRows
                },
                {
                    title: "Power",
                    text: "Lock, sleep, restart and the rest, found by typing their names.",
                    rows: root.powerRows
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
                const rows = terms.length ? section.rows.filter(r => terms.every(t => (r.title + " " + (r.text ?? "")).toLowerCase().includes(t))) : section.rows;
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
        visible: box.height > 0
        offset.y: Theme.shadowY
        radius: box.radius
        blur: Theme.shadowBlur
        color: Theme.shadow
    }

    // Opens out from its own middle and folds back into it, like the
    // launcher dismissed.
    Rectangle {
        id: box

        readonly property int fold: Math.round(root.boxHeight * (1 - root.reveal) / 2)

        x: Math.round((root.width - root.boxWidth) / 2)
        y: Math.round((root.height - root.boxHeight) / 2) + box.fold
        width: root.boxWidth
        height: root.boxHeight - 2 * box.fold
        clip: true
        radius: Theme.popupRadius
        color: Theme.frostOver(under.luma)

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

            y: -box.fold
            width: root.boxWidth
            height: root.boxHeight

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
                    radius: Theme.selectionRadius + 2
                    color: Theme.well

                    Glyph {
                        x: 8
                        height: parent.height
                        text: Theme.glyph.launcher
                        fontSize: Theme.captionSize
                        color: Theme.label2
                    }

                    TextInput {
                        id: filter

                        anchors.fill: parent
                        anchors.leftMargin: 26
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.fg
                        selectionColor: Theme.selection
                        selectedTextColor: Theme.fg
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
                            x: 8
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

                x: root.sideWidth + Theme.pillBorder + root.boxPad - Theme.selectionInset
                // The whole height, padded inside rather than out, so the
                // list scrolls on under the box's edges instead of stopping
                // short of them.
                width: root.boxWidth - x - root.boxPad + Theme.selectionInset
                height: root.boxHeight
                topMargin: root.boxPad
                bottomMargin: root.boxPad
                clip: true
                boundsBehavior: Flickable.StopAtBounds

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

                        Column {
                            topPadding: entry.modelData.id === root.entries[0]?.id ? 0 : 14
                            bottomPadding: 6
                            spacing: 3

                            PopupText {
                                x: 8
                                text: entry.modelData.heading
                                font.weight: Font.DemiBold
                            }

                            PopupText {
                                x: 8
                                width: list.width - 16
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
