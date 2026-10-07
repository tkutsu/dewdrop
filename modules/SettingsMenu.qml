import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The settings window: settings.json, drawn. Two pages, the bar and the
// launcher, each a list of things with a tick on the ones that show; a click
// flips one and writes it straight through Settings.set(). A filter line
// takes the keyboard, Tab turns the page and Escape closes.
//
// On OverlayWindow like the launcher rather than a bar popup, because a bar
// popup takes no keyboard and the launcher's page is every app on the machine.
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

    readonly property var pages: ["Bar", "Launcher"]
    property int page: 0
    property string query: ""

    readonly property int boxWidth: 460
    readonly property int boxPad: 12
    readonly property int rowHeight: 22
    readonly property int headerHeight: 28
    readonly property int visibleRows: 18
    readonly property int lineHeight: Theme.queryTextSize + 12
    readonly property int fullHeight: boxPad * 2 + lineHeight + boxPad + Theme.pillBorder + visibleRows * rowHeight

    // --- what the pages list -------------------------------------------------
    // A row is who it is and nothing about whether it shows: the tick is read
    // from Settings by the row itself, so a click redraws one tick instead of
    // rebuilding the list under the pointer. `list` is the setting a row
    // lives in.

    // The right pill's modules that settings.json can switch off, in the
    // pill's own order. Not the gear: switched off, there would be no way
    // back here but the file.
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
            bluetooth: { title: "Bluetooth", glyph: Theme.glyph.bluetooth },
            network: { title: "Network", glyph: Theme.glyph.wifiStrength[Theme.glyph.wifiStrength.length - 1] },
            tray: { title: "Tray", glyph: Theme.glyph.tray },
            language: { title: "Keyboard layout", glyph: Theme.glyph.keyboard }
        })

    readonly property var barRows: {
        const modules = RightPillOrder.keys.filter(k => root.modules[k]).map(k => ({ list: "modules", id: k, title: root.modules[k].title, glyph: root.modules[k].glyph }));
        // What is running now, and whatever is hidden but not running, so it
        // can still be let back.
        const items = SystemTray.items.values.filter(item => !/^(blueman|nm-applet)/.test(item.id));
        const tray = items.map(item => ({ list: "hiddenTray", id: item.id, title: item.tooltipTitle || item.title || item.id, icon: item.icon }));
        for (const id of Settings.hiddenTray)
            if (!items.some(item => item.id === id))
                tray.push({ list: "hiddenTray", id, title: id, glyph: Theme.glyph.tray });
        tray.sort((a, b) => a.title.localeCompare(b.title));
        return root.section("Right pill", modules).concat(root.section("Tray", tray));
    }

    // Every app, each followed by its own actions, then the launcher's
    // controls and power commands, under the ids Launcher filters on.
    readonly property var launcherRows: {
        const apps = [];
        const entries = DesktopEntries.applications.values.slice().sort((a, b) => a.name.localeCompare(b.name));
        for (const e of entries) {
            apps.push({ list: "hiddenApps", id: e.id, title: e.name, icon: e.icon });
            for (const a of e.actions ?? [])
                apps.push({ list: "hiddenApps", id: e.id + ":" + a.id, title: e.name + " · " + a.name, icon: a.icon || e.icon });
        }
        const controls = Launcher.desktopCommands.map(c => ({ list: "hiddenApps", id: "desktop:" + c.key, title: c.title, glyph: c.glyph }));
        const power = Launcher.powerCommands.map(p => ({ list: "hiddenApps", id: "power:" + p.key, title: p.name ?? p.label, glyph: p.glyph }));
        return root.section("Apps", apps).concat(root.section("Controls", controls)).concat(root.section("Power", power));
    }

    readonly property var rows: root.page === 0 ? root.barRows : root.launcherRows

    // A heading over the rows that pass the filter, or nothing at all.
    function section(title: string, rows: var): var {
        const terms = root.query.toLowerCase().split(/\s+/).filter(t => t);
        const hits = rows.filter(r => terms.every(t => r.title.toLowerCase().includes(t)));
        return hits.length ? [{ header: title, id: "#" + title }].concat(hits) : [];
    }

    function showing(row: var): bool {
        return row.list === "modules" ? Settings.moduleOn(row.id) : !Settings[row.list].includes(row.id);
    }

    function flip(row: var): void {
        if (row.list === "modules")
            Settings.set("modules", Object.assign({}, Settings.modules, { [row.id]: !Settings.moduleOn(row.id) }));
        else
            Settings.toggleIn(row.list, row.id);
    }

    // --- the box -------------------------------------------------------------

    BackdropProbe {
        id: under

        screen: root.screen
        area: Qt.rect(Math.round((root.width - root.boxWidth) / 2), Math.round((root.height - root.fullHeight) / 2), root.boxWidth, root.fullHeight)
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

        readonly property int fold: Math.round(root.fullHeight * (1 - root.reveal) / 2)

        x: Math.round((root.width - root.boxWidth) / 2)
        y: Math.round((root.height - root.fullHeight) / 2) + box.fold
        width: root.boxWidth
        height: root.fullHeight - 2 * box.fold
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
            height: root.fullHeight

            // The pages, as words in the query's size: the one open in full
            // ink, the other a click away.
            Row {
                id: tabs

                x: root.boxPad
                y: root.boxPad
                height: root.lineHeight
                spacing: 16

                Repeater {
                    model: root.pages

                    Text {
                        required property string modelData
                        required property int index

                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        color: root.page === index ? Theme.fg : tabHover.hovered ? Theme.label2 : Theme.label3
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.queryTextSize
                        font.weight: Theme.bodyWeight

                        HoverHandler {
                            id: tabHover
                        }

                        TapHandler {
                            onTapped: root.page = index
                        }
                    }
                }
            }

            TextInput {
                id: input

                anchors.left: tabs.right
                anchors.leftMargin: 24
                anchors.right: parent.right
                anchors.rightMargin: root.boxPad
                y: root.boxPad
                height: root.lineHeight
                color: Theme.fg
                selectionColor: Theme.selection
                selectedTextColor: Theme.fg
                selectByMouse: true
                font.family: Theme.bodyFont
                font.pixelSize: Theme.popupTextSize
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                focus: true
                onTextChanged: root.query = text

                Component.onCompleted: forceActiveFocus()

                PopupText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text
                    text: "Filter"
                    color: Theme.label3
                }

                Keys.onPressed: function (event) {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        Preferences.hide();
                        break;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab:
                        root.page = (root.page + 1) % root.pages.length;
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }
            }

            Rectangle {
                y: root.boxPad * 2 + root.lineHeight
                width: parent.width
                height: Theme.pillBorder
                color: Theme.stroke
            }

            ListView {
                id: list

                x: root.boxPad - Theme.selectionInset
                y: root.boxPad * 2 + root.lineHeight + Theme.pillBorder
                width: root.boxWidth - 2 * (root.boxPad - Theme.selectionInset)
                height: root.visibleRows * root.rowHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // A page starts at its top.
                onModelChanged: if (root.page !== list.lastPage) {
                    list.lastPage = root.page;
                    list.positionViewAtBeginning();
                }
                property int lastPage: 0

                model: ScriptModel {
                    values: root.rows
                    objectProp: "id"
                }

                delegate: Item {
                    id: row

                    required property var modelData

                    width: list.width
                    height: modelData.header ? root.headerHeight : root.rowHeight

                    PopupText {
                        x: 6
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: !!row.modelData.header
                        text: row.modelData.header ?? ""
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                        font.weight: Font.DemiBold
                    }

                    ChoiceRow {
                        anchors.fill: parent
                        visible: !row.modelData.header
                        text: row.modelData.title ?? ""
                        current: !row.modelData.header && root.showing(row.modelData)
                        onTapped: root.flip(row.modelData)

                        // The thing itself at the right edge, as the
                        // launcher draws it.
                        Item {
                            width: 16
                            height: parent.height

                            IconImage {
                                id: icon

                                anchors.centerIn: parent
                                implicitSize: 16
                                source: row.modelData.icon ? (String(row.modelData.icon).includes("/") ? row.modelData.icon : Quickshell.iconPath(row.modelData.icon, true)) : ""
                                visible: !!row.modelData.icon && status === Image.Ready
                            }

                            Glyph {
                                anchors.centerIn: parent
                                visible: !icon.visible
                                text: row.modelData.glyph ?? Theme.glyph.window
                                fontSize: Theme.popupGlyphSize
                            }
                        }
                    }
                }
            }
        }
    }
}
