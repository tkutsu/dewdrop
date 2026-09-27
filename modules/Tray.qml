import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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
        // Registration order is whatever the race at login happened to produce;
        // sorting by service id keeps the bar stable across restarts.
        .sort((a, b) => a.id.localeCompare(b.id))

    // Where the theme's artwork is at odds with the bar, the bar draws its own
    // glyph in its place. nm-applet is where it started: its wireless
    // icons are filled cones with a padlock welded onto them, which at this
    // size is a blob in a row of outlined Material glyphs. Keyed by the icon
    // name rather than the item id, because the state lives in the name — the
    // item is "nm-applet" whether it is on wifi, on a cable or on nothing.
    // Anything unmatched keeps its artwork; this is a correction, not a
    // reimplementation of somebody else's tray icon.
    function glyphFor(item) {
        // Mullvad is the exception to reading the name: it is an Electron app
        // and hands over a bare pixmap with no name at all. Its tooltip is
        // where the state lives: "Connected. Athens, Greece" while the tunnel
        // is up, and something else while it is coming up or down.
        if (item.id.startsWith("Mullvad VPN"))
            return item.tooltipTitle.startsWith("Connected") ? Theme.glyph.vpn : Theme.glyph.vpnOff;
        const name = String(item.icon);
        // nm-applet carries the signal in the name, quantised to five buckets,
        // with "-secure" after it on an encrypted network — which is dropped,
        // because every network worth joining is encrypted and a padlock
        // welded to every wireless icon says nothing for the pixels it costs.
        const signal = name.match(/nm-signal-(\d+)/);
        if (signal) {
            const step = [0, 25, 50, 75, 100].indexOf(parseInt(signal[1], 10));
            return Theme.glyph.wifiStrength[step] ?? Theme.glyph.wifiStrength[0];
        }
        // The frames nm-applet cycles while a connection comes up. The empty
        // cone is the honest picture of it: there is no signal yet, and it is
        // the same glyph the first bucket uses, so the icon fills rather than
        // being replaced once there is.
        if (name.includes("nm-stage"))
            return Theme.glyph.wifiStrength[0];
        if (name.includes("nm-no-connection"))
            return Theme.glyph.wifiOff;
        if (name.includes("nm-device-wired"))
            return name.includes("offline") ? Theme.glyph.wiredOff : Theme.glyph.wired;
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

            property bool menuOpen: false

            // SNI has a status for this, but Telegram — the one app here that
            // ever asks — says it by swapping its icon for the attention
            // variant instead, so both spellings are read.
            readonly property bool attention: modelData.status === Status.NeedsAttention
                || String(modelData.icon).includes("-attention")

            // Empty when the theme's own artwork is what gets drawn.
            readonly property string glyph: root.glyphFor(modelData)

            // blueman renames its icon with its state — blueman-tray,
            // blueman-active once something is connected, blueman-disabled
            // with the radio off — and the theme draws the three differently,
            // so the icon changed shape every time a headset came and went.
            // One drawing, whatever the state: the state is in the tooltip
            // and the menu, where it is read rather than glimpsed.
            readonly property string iconSource: String(modelData.icon).replace(/blueman-[a-z-]+/, "blueman-tray")

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

            opacity: entry.off ? Theme.dimOpacity : 1

            Behavior on opacity {
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
            implicitWidth: entry.glyph ? substitute.implicitWidth : icon.inkWidth

            // A pixel less air either side of the wifi cone: it is widest at
            // its top edge and a point at the bottom, so most of its height
            // stands well in from the ink box, and at the row's gap it read
            // as set apart from both neighbours.
            readonly property bool cone: Theme.glyph.wifiStrength.includes(entry.glyph) || entry.glyph === Theme.glyph.wifiOff
            Layout.leftMargin: entry.cone ? -1 : 0
            Layout.rightMargin: entry.cone ? -1 : 0
            ShadowedIcon {
                id: icon
                x: -inkX
                anchors.verticalCenter: parent.verticalCenter
                visible: !entry.glyph
                source: entry.glyph ? "" : entry.iconSource
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
                fontSize: Theme.trayGlyphSize
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
                hovered: pointer.containsMouse && !entry.menuOpen
                text: entry.modelData.tooltipTitle || entry.modelData.title || entry.modelData.id
            }

            // Null for an item with no menu, which leaves every button that
            // would have opened one doing nothing.
            readonly property var toggleMenu: modelData.hasMenu ? () => {
                entry.menuOpen = !entry.menuOpen;
            } : null

            ClickArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor

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
            }

            Loader {
                active: entry.menuOpen && entry.modelData.hasMenu

                sourceComponent: MenuPopup {
                    id: menu

                    anchorItem: entry
                    handle: entry.modelData.menu
                    visible: true

                    // Flush under the icon and hung from its left edge, the
                    // way the system drops a menu from a menu bar extra —
                    // rather than centred on it and a margin's worth lower.
                    // Out by the shadow's room on the left and up by its
                    // room on top, so the box rather than its window is what
                    // lines up with the icon.
                    anchor.rect: Qt.rect(-menu.shadowSide, 0, entry.width, entry.height - Theme.barMargin + Theme.popupGap - menu.shadowTop)
                    anchor.edges: Edges.Bottom | Edges.Left
                    anchor.gravity: Edges.Bottom | Edges.Right

                    onDismissed: entry.menuOpen = false

                    // Without a grab, a click anywhere else leaves the menu on
                    // screen — layer surfaces get no focus-out of their own.
                    // The whole tree, not just this window: a click on a
                    // submenu the grab does not list counts as "anywhere else".
                    HyprlandFocusGrab {
                        active: true
                        windows: menu.windows
                        onCleared: entry.menuOpen = false
                    }
                }
            }
        }
    }
}
