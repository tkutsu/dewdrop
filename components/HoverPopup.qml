import QtQuick
import qs

// Hover-to-show plumbing shared by the modules and the individual tray icons:
// a settle delay, then either a text tooltip or a richer popup component.
Item {
    id: root

    required property Item anchorItem
    property bool hovered: false
    property string text: ""
    property Component popup: null

    readonly property var item: loader.item

    property bool settled: false

    // The popup is its own window, so walking the pointer into it leaves the
    // bar item and would otherwise close the thing being reached for.
    readonly property bool popupHovered: loader.item ? loader.item.hovered === true : false

    onHoveredChanged: {
        if (hovered) {
            leave.stop();
            delay.restart();
        } else {
            delay.stop();
            leave.restart();
        }
    }

    onPopupHoveredChanged: {
        if (popupHovered)
            leave.stop();
        else if (!root.hovered)
            leave.restart();
    }

    Timer {
        id: delay
        // GTK settles for half a second before showing a tooltip.
        interval: 500
        onTriggered: root.settled = true
    }

    Timer {
        id: leave
        // Long enough to cross the seam between the bar and the popup, short
        // enough that a tooltip still feels like it closes on the way out.
        interval: 150
        onTriggered: root.close()
    }

    // The rest of a hold the popup asked for (Popup.hold), if the pointer
    // was still away when the usual wait ran out.
    Timer {
        id: grace
        onTriggered: root.close()
    }

    function close(): void {
        if (root.hovered || root.popupHovered)
            return;
        const held = (loader.item?.heldUntil ?? 0) - Date.now();
        if (held > 0) {
            grace.interval = held;
            grace.restart();
            return;
        }
        root.settled = false;
    }

    Loader {
        id: loader
        active: root.settled && (root.popup !== null || root.text !== "")
        sourceComponent: root.popup !== null ? root.popup : plain

        onLoaded: {
            item.anchorItem = root.anchorItem;
            // Hang off the slab rather than the module's box: the box runs on
            // through the margin the pill claims for clicks, and a popup that
            // anchored to its bottom sat that margin too far from the bar.
            // Less the air the window keeps above its box for the shadow,
            // so it is the box and not the window that hangs popupGap down.
            item.anchor.rect = Qt.rect(0, 0, root.anchorItem.width, root.anchorItem.height - Theme.barMargin + Theme.popupGap - item.shadowTop);
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
