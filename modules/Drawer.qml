import QtQuick
import QtQuick.Layouts
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
    // holds something — a handle that opened onto nothing would be a control
    // for its own sake.
    property bool holding: false
    // Whether the pointer is anywhere on the bar or in one of its popups.
    property bool pointerNear: false

    present: holding

    // A dot is a few pixels of ink, and its box ended at the ink: a click a
    // pixel to its right fell into the gap before the next module and did
    // nothing. The box reaches halfway across that gap instead, and gives the
    // same back as margin so nothing on the bar moves.
    padRight: Math.round(Theme.gap / 2)
    Layout.rightMargin: -Math.round(Theme.gap / 2)
    onHoldingChanged: if (!holding)
        open = false

    // A middle dot, the clock's own separator, rather than a chevron: the
    // handle is a place to click, not an arrow to follow, and the modules
    // coming out beside it say which way it opened. Text rather than a Glyph
    // and a size up, the same as the clock's, so the two dots on the bar are
    // the same mark.
    BarText {
        Layout.fillHeight: true
        fontSize: Theme.textSize + 1
        text: "\u00b7"
        // A step down the label scale: it is a handle on the modules, not one
        // of them, and it should not read as another status.
        color: Theme.label2
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            root.open = !root.open;
    }

    // A drawer left open is the whole bar again, so it shuts itself once the
    // pointer has been off the bar for a moment — the way a menu bar folds
    // its extras back when you are done with them. A popup counts as the bar,
    // so reading one never folds the modules away from under it.
    Timer {
        running: root.open && !root.pointerNear
        interval: 4000
        onTriggered: root.open = false
    }
}
