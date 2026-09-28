import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs
import qs.components

// The handle of the right pill's drawer: the modules with nothing to say right
// now — no unread mail, no updates, the tools that are never news — fold away
// behind it, and a click brings them back out to its left. The bar then shows
// what is true at the moment, and the rest is one click from it.
//
// The modules decide for themselves whether they are quiet (BarItem.quiet);
// this only says whether the drawer is open. Bar.qml puts the two together.
BarItem {
    id: root

    property bool open: false
    // Whether anything is in the drawer. The handle is only there while it
    // holds something — a chevron that opened onto nothing would be a control
    // for its own sake.
    property bool holding: false
    // Whether the pointer is anywhere on the bar or in one of its popups.
    property bool pointerNear: false

    present: holding
    tooltip: open ? "Show less" : "Show more"

    // A chevron is a few pixels of ink, and its box ended at the ink: a click
    // a pixel to its right fell into the gap before the next module and did
    // nothing. The box reaches halfway across that gap instead, and gives the
    // same back as margin so nothing on the bar moves. One pixel more comes
    // back than it takes: at the full gap the chevron read as set apart from
    // the icon beside it.
    padRight: Math.round(Theme.gap / 2)
    Layout.rightMargin: -Math.round(Theme.gap / 2) - 1
    onHoldingChanged: if (!holding)
        open = false

    // One chevron that turns over, on the drawer's own clock, rather than
    // two glyphs swapped at the start of the fold: the handle moves with the
    // modules it is handing out, and ends pointing the way they will go back.
    //
    // Mirrored rather than rotated. A half turn about the box's centre lands
    // the ink a pixel higher than it started (the box is an odd height), so
    // the open chevron sat above the icons beside it; a mirror only ever
    // moves it sideways, about its own middle, onto the same columns.
    property real turned: root.open ? 1 : 0

    Behavior on turned {
        NumberAnimation {
            duration: Theme.foldMs
            easing.type: Easing.OutCubic
        }
    }

    Glyph {
        id: chevron

        Layout.fillHeight: true
        text: Theme.glyph.drawer
        transform: Scale {
            origin.x: chevron.width / 2
            xScale: 1 - 2 * root.turned
        }
        color: Theme.handle
    }

    actions: ({
            [Qt.LeftButton]: () => {
                root.open = !root.open;
            }
        })

    // A drawer left open is the whole bar again, so it shuts itself once the
    // pointer has been off the bar for a moment — the way a menu bar folds
    // its extras back when you are done with them. A popup counts as the bar,
    // so reading one never folds the modules away from under it.
    Timer {
        running: root.open && !root.pointerNear
        interval: 4000
        onTriggered: root.open = false
    }

    // And at once on a click anywhere off the bar and its popups: the same
    // custom>>click from Hyprland that closes a popup (see OpenPopup.qml),
    // which still hands the click on to whatever it landed on. Clicks on the
    // bar itself are Bar.qml's.
    Connections {
        target: Hyprland
        enabled: root.open

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data === "click" && PopupPointer.hovered === 0 && PopupPointer.bars === 0)
                root.open = false;
        }
    }
}
