import QtQuick
import qs

// What hangs off a bar item, for the modules and the individual tray icons:
// its tooltip, on hover, or the popup a click opened.
//
// Tooltips follow the Mac's help tags. The first one waits for the pointer to
// rest a moment, since it is there for a hesitation rather than a pass over
// the bar; once one is up the next shows as soon as it is reached (Tooltips).
// Leaving closes it at once, a click puts it away until the pointer has left,
// and none shows while a popup is open, just as none does while a menu is
// down from the menu bar.
Item {
    id: root

    required property Item anchorItem
    property bool hovered: false
    // Held down on the item: whatever the click did is the answer now, not
    // the tag that described it.
    property bool pressed: false
    // Shown outright, hover or not: a popup a click opened, which stays up
    // until something closes it (see BarItem).
    property bool open: false
    property string text: ""
    property Component popup: null

    readonly property var item: loader.item

    property bool settled: false
    property bool dismissed: false

    readonly property bool tipping: root.popup === null && root.text !== "" && root.settled && !root.dismissed && !Tooltips.blocked && OpenPopup.owner === null

    readonly property bool wanted: root.popup !== null ? root.open : root.tipping

    onTippingChanged: tipping ? Tooltips.shown() : Tooltips.hidden()
    Component.onDestruction: if (tipping)
        Tooltips.hidden()

    onPressedChanged: if (pressed)
        dismissed = true

    // Movement invalidates the old dwell, even if the pointer never leaves.
    Connections {
        target: Tooltips
        function onBlockedChanged(): void {
            if (root.popup !== null)
                return;
            delay.stop();
            root.settled = false;
            if (root.hovered && !Tooltips.blocked)
                delay.restart();
        }
    }

    onHoveredChanged: {
        if (hovered && !Tooltips.blocked) {
            if (Tooltips.warm)
                settled = true;
            else
                delay.restart();
        } else {
            delay.stop();
            settled = false;
            dismissed = false;
        }
    }

    Timer {
        id: delay
        // About the Mac's wait. GTK's half second put a tag under every
        // icon the pointer crossed on its way somewhere else.
        interval: 1000
        onTriggered: root.settled = true
    }

    // Keep the surface through the 140 ms exit and its final frame.
    Linger {
        id: lifetime
        shown: root.wanted
        hold: 160
    }

    Loader {
        id: loader
        // Remove tags at once, without drawing their exit fade during pill motion.
        active: lifetime.active && (root.popup !== null || !Tooltips.blocked)
        sourceComponent: root.popup !== null ? root.popup : plain

        onLoaded: {
            item.anchorItem = root.anchorItem;
            // Hang off the slab rather than the item's box: a module's box runs
            // on through the margin the pill claims for clicks, and a popup
            // that anchored to its bottom sat that margin too far from the
            // bar. A workspace's app icon is only the slab's height, and the
            // slab is centred on both. Less the air the window keeps above its
            // box for the shadow, so it is the box and not the window that
            // hangs popupGap down.
            const slabBottom = Theme.pillTop(root.anchorItem.height) + Theme.barHeight;
            item.anchor.rect = Qt.rect(0, 0, root.anchorItem.width, slabBottom + Theme.popupGap - item.shadowTop);
            item.requestedVisible = Qt.binding(() => root.wanted);
            item.visible = true;
        }
    }

    Component {
        id: plain

        Tooltip {
            text: root.text
        }
    }
}
