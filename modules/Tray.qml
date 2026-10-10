import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs
import qs.components

// tray: icon-size 12, spacing 13. Tooltips and menus are per icon rather than
// per module, so this one does its own hover handling instead of BarItem's.
BarItem {
    id: root

    readonly property var entries: SystemTray.items.values
        // Passive is the SNI way of saying "nothing worth showing right now".
        .filter(item => item.status !== Status.Passive)
        // The bar's own Bluetooth and Network modules say what these would.
        // blueman's applet comes back whenever its manager is opened (D-Bus
        // starts it as the pairing agent), and its icon would be a second
        // Bluetooth rune in the row.
        .filter(item => !/^(blueman|nm-applet)/.test(item.id))
        // Registration order is whatever the race at login happened to produce;
        // sorting by service id keeps the bar stable across restarts.
        .sort((a, b) => a.id.localeCompare(b.id))

    // Nothing in the tray is no module at all, rather than an empty one still
    // holding its gap in the row. It used to always have nm-applet and
    // blueman in it; now it can be empty.
    present: entries.length > 0

    // Icons the settings window keeps in the drawer ("tray:<id>" in
    // DrawerPins) fold out of the row while it is closed, one by one; with
    // every icon kept in, the tray as a whole is quiet and folds with the
    // rest. Pinning the tray brings them all out. Middle click stays the
    // icons' own.
    property bool drawerOut: false
    readonly property bool tucks: entries.some(item => DrawerPins.kept("tray:" + item.id))
    quiet: entries.every(item => DrawerPins.kept("tray:" + item.id))
    middlePins: false

    // Where the theme's artwork is at odds with the bar, the bar draws its own
    // glyph in its place. (nm-applet and blueman were the first two; the bar
    // has its own Network and Bluetooth modules now.) Anything unmatched
    // keeps its artwork; this is a correction, not a reimplementation of
    // somebody else's tray icon.
    function glyphFor(item) {
        // Mullvad is an Electron app and hands over a bare pixmap with no
        // name at all, a solid padlock at that. Its tooltip is where the
        // state lives: "Connected. Athens, Greece" while the tunnel is up,
        // and something else while it is coming up or down.
        if (item.id.startsWith("Mullvad VPN"))
            return item.tooltipTitle.startsWith("Connected") ? Theme.glyph.vpn : Theme.glyph.vpnOff;
        return "";
    }

    Repeater {
        // Diffed rather than replaced: an item joining or leaving the tray
        // otherwise rebuilt every icon, its tooltip and any open menu with it.
        model: ScriptModel {
            values: root.entries
        }

        delegate: Item {
            id: entry

            required property var modelData
            required property int index
            readonly property bool inkHovered: pointer.containsMouse && !root.pillDragging

            // A tray menu is one of the bar's popups like any other: one up at
            // a time, closed by a click elsewhere, handed over as the pointer
            // browses the bar (OpenPopup).
            readonly property bool menuOpen: OpenPopup.owner === entry

            // SNI has a status for this, but Telegram — the one app here that
            // ever asks — says it by swapping its icon for the attention
            // variant instead, so both spellings are read.
            readonly property bool attention: modelData.status === Status.NeedsAttention
                || String(modelData.icon).includes("-attention")

            // Empty when the theme's own artwork is what gets drawn.
            readonly property string glyph: root.glyphFor(modelData)

            // A tray app says it is switched off by renaming its icon —
            // blueman-disabled, nm-no-connection, anything wired "-offline" —
            // and the bar says the same by dimming it, as it does with a
            // module that is off or has nothing loaded yet. Mullvad has no
            // name to rename, so its open lock stands for the same thing.
            readonly property bool off: /disabled|offline|no-connection|-off\b/.test(String(modelData.icon))
                || glyph === Theme.glyph.vpnOff

            // Where the icon is drawn against its line: bouncing for attention,
            // pressed in under the pointer, or both at once.
            readonly property real shift: bounce.offset + (pointer.acting ? Theme.pressDip : 0)

            // Kept in the drawer and the drawer shut: folded out of the row.
            readonly property bool tucked: DrawerPins.kept("tray:" + modelData.id) && !root.drawerOut && !DrawerPins.pinned(root.pinKey)
            property real out: tucked ? 0 : 1

            Behavior on out {
                NumberAnimation {
                    duration: Theme.foldMs
                    easing.type: Easing.InOutCubic
                }
            }

            visible: out > 0
            clip: out < 1
            opacity: (entry.off ? Theme.dimOpacity : 1) * out

            Behavior on opacity {
                enabled: !entry.tucked && entry.out === 1
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }

            // Laid out on the ink, like every Glyph on the bar, and spaced by
            // the row's own gap. The artwork's box used to set the width, with
            // a guessed 3px of margin inside it taken back out of the gap
            // either side; blueman's drawing carries 4px, so the tray stood a
            // pixel further from its left neighbour than from its right.
            Layout.fillHeight: true
            implicitWidth: Math.round((entry.glyph ? substitute.implicitWidth : icon.inkWidth) * entry.out)

            FittedIcon {
                id: icon
                x: -inkX
                anchors.verticalCenter: parent.verticalCenter
                visible: !entry.glyph
                source: entry.glyph ? "" : entry.modelData.icon
                opacity: Theme.barInk(entry, Qt.rgba(1, 1, 1, 1)).a
                Behavior on opacity {
                    NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.InOutQuad }
                }
                // Everything here used to be drawn at one size, on the theme's
                // promise that a panel icon brings its own margin — with a
                // guess knocked off for apps publishing a pixmap, which hand
                // over a full-bleed logo and kept that promise least. The ink
                // is measured now, so the guess and the exception both go: an
                // icon that fills its box is drawn smaller whoever sent it.
                ink: Theme.iconInk
                transform: Translate {
                    y: entry.shift
                }
            }

            // Full height rather than centred: a Glyph centres its ink against
            // its own height, and the bar's is what every other glyph on it is
            // centred against.
            Glyph {
                id: substitute
                height: parent.height
                visible: !!entry.glyph
                text: entry.glyph
                fontSize: Theme.trayGlyphSize - (entry.glyph === Theme.glyph.vpn || entry.glyph === Theme.glyph.vpnOff ? 1 : 0)
                nudge: entry.glyph === Theme.glyph.vpn || entry.glyph === Theme.glyph.vpnOff ? -1 : 0
                transform: Translate {
                    y: entry.shift
                }
            }

            Bounce {
                id: bounce
                running: entry.attention
            }

            HoverPopup {
                anchorItem: entry
                hovered: pointer.containsMouse && !entry.menuOpen && !root.pillDragging
                pressed: pointer.pressed
                // Not the id when the app gives neither: a service name
                // ("chrome_status_icon_1") tells nobody anything.
                text: entry.modelData.tooltipTitle || entry.modelData.title
            }

            // Null for an item with no menu, which leaves every button that
            // would have opened one doing nothing.
            readonly property var toggleMenu: modelData.hasMenu ? () => OpenPopup.toggle(entry) : null

            // In the bar's selection mode the menu opens on the icon, the way
            // the pointer browses to it; Return activates one without a menu.
            readonly property bool keyOpens: modelData.hasMenu
            readonly property var keyPress: modelData.hasMenu ? null : () => modelData.activate()

            KeyRing {}

            // Cover half the gap either side, like a module's own padding:
            // the gap between two tray icons is split between them rather
            // than clicking on nothing.
            ClickArea {
                id: pointer
                name: entry.modelData.title || entry.modelData.tooltipTitle || entry.modelData.id || "Tray item"
                anchors.fill: parent
                anchors.leftMargin: -Theme.gap / 2
                anchors.rightMargin: -Theme.gap / 2
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor

                onContainsMouseChanged: if (entry.modelData.hasMenu)
                    OpenPopup.browse(entry, containsMouse && !root.pillDragging)

                // Right is the menu. An item that is nothing but its menu has
                // no useful activate(), so on one of those every button is.
                actions: entry.modelData.onlyMenu ? ({
                        [Qt.LeftButton]: entry.toggleMenu,
                        [Qt.RightButton]: entry.toggleMenu,
                        [Qt.MiddleButton]: entry.toggleMenu
                    }) : ({
                        [Qt.LeftButton]: () => entry.modelData.activate(),
                        [Qt.RightButton]: entry.toggleMenu,
                        [Qt.MiddleButton]: () => entry.modelData.secondaryActivate()
                    })

                onWheel: function (wheel) {
                    if (wheel.angleDelta.y !== 0)
                        entry.modelData.scroll(wheel.angleDelta.y, false);
                    if (wheel.angleDelta.x !== 0)
                        entry.modelData.scroll(wheel.angleDelta.x, true);
                }

                // One notch each way, as the wheel sends it.
                scrolls: true
                Accessible.onScrollUpAction: entry.modelData.scroll(120, false)
                Accessible.onScrollDownAction: entry.modelData.scroll(-120, false)
            }

            Loader {
                active: entry.menuOpen && entry.modelData.hasMenu

                sourceComponent: MenuPopup {
                    id: menu

                    anchorItem: entry
                    handle: entry.modelData.menu

                    // Flush under the icon and hung from its left edge, the
                    // way the system drops a menu from a menu bar extra —
                    // rather than centred on it and a margin's worth lower.
                    // Out by the shadow's room on the left and up by its
                    // room on top, so the box rather than its window is what
                    // lines up with the icon.
                    anchor.rect: Qt.rect(-menu.shadowSide, 0, entry.width, entry.height - Theme.barInset + Theme.popupGap - menu.shadowTop)
                    anchor.edges: Edges.Bottom | Edges.Left
                    anchor.gravity: Edges.Bottom | Edges.Right

                    onDismissed: OpenPopup.close(entry)
                }
            }
        }
    }
}
