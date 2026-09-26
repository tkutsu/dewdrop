import QtQuick
import QtQuick.Effects
import Quickshell
import qs

// The bar's popup chrome. It used to copy the old GTK tooltip's near-opaque
// grey; it is the launcher's box now, which is the bar's own half-black with a
// hairline round it, so everything the shell hangs below the pills reads as one
// surface rather than as two generations of one.
// Anchored under the item that owns it, so a module only has to supply content.
// Content sizes the window: a Column is the body so children must not anchor to
// fill it, or the popup has nothing to take its size from.
PopupWindow {
    id: root

    // Not `required`: the loaders that create these set it immediately after
    // construction, and a required property warns on every instantiation.
    property Item anchorItem
    property real padding: 6
    // A popover's corner by default; the menus round themselves tighter.
    property int radius: Theme.popupRadius
    // The two axes split for the menus, whose rows run edge to edge and so want
    // no side padding at all — only enough top and bottom to stay clear of the
    // rounded corners. Everything else sets `padding` once and gets both.
    property real hPadding: padding
    property real vPadding: padding
    default property alias content: body.data
    // Popups whose body is one run of text want the parts touching; the ones
    // that stack separate sections set this.
    property alias spacing: body.spacing

    anchor {
        item: root.anchorItem
        edges: Edges.Bottom
        gravity: Edges.Bottom
        // Let the compositor slide a popup along the bar rather than letting it
        // run off the edge of the screen.
        adjustment: PopupAdjustment.SlideX
    }

    // Never zero in either direction. A popup here is a real Wayland surface,
    // and one that asks for a zero size is a protocol error that takes the
    // whole connection down with it — the shell dies, not just the popup.
    //
    // MenuPopup is the one that gets here: it has no padding to stand in for
    // its contents, and QsMenuOpener fills its rows in over DBus some time
    // after the window has been built, so a tray menu is briefly a window
    // around nothing. Clamped rather than held back until it has rows, because
    // this has to hold for every popup, including the ones not written yet.
    implicitWidth: Math.max(1, body.implicitWidth + hPadding * 2) + shadowSide * 2
    implicitHeight: Math.max(chromeHeight, reserveHeight) + shadowTop + shadowBottom
    color: "transparent"

    // The room the window keeps round the box for its shadow to fall into.
    // The shadow drops, so there is less of it above than below. Whoever
    // anchors a popup by one of its edges rather than by its middle has to
    // take these back off the anchor, or the box lands this far from where it
    // was aimed (HoverPopup, the tray and MenuPopup's submenus all do).
    readonly property int shadowSide: Theme.shadowBlur
    readonly property int shadowTop: Theme.shadowBlur - Theme.shadowY
    readonly property int shadowBottom: Theme.shadowPad

    // How tall the box is drawn, which is not always how tall the window is.
    readonly property real chromeHeight: Math.max(1, body.implicitHeight + vPadding * 2)

    // Room to keep below the box, for a popup whose content folds open and
    // shut. Resizing a popup is a reposition round trip with the compositor,
    // and the frame caught in the middle of it shows as the whole popup
    // jerking. A popup that asks for its tallest size up front grows the box
    // inside a window that never changes, and the unused strip is transparent
    // and let through by the mask below.
    property real reserveHeight: 0
    mask: Region {
        item: chrome
    }

    // A popup that can be clicked has to outlive the pointer leaving the bar
    // item that opened it; HoverPopup watches this to decide when to close.
    readonly property bool hovered: pointer.hovered

    // Under the box rather than round it: the fill is translucent, so the
    // middle of the shadow shows through it too, and darkens it by about the
    // same amount the blur behind it lightens it.
    RectangularShadow {
        anchors.fill: chrome
        offset.y: Theme.shadowY
        radius: chrome.radius
        blur: Theme.shadowBlur
        color: Theme.shadow
    }

    Rectangle {
        id: chrome

        x: root.shadowSide
        y: root.shadowTop
        width: parent.width - root.shadowSide * 2
        height: root.chromeHeight
        color: Theme.popupBg
        radius: root.radius

        Rim {
            anchors.fill: parent
            radius: chrome.radius
            // Above the rows, which run edge to edge in a menu and would
            // otherwise paint over it where the pointer is.
            z: 1
        }

        HoverHandler {
            id: pointer
        }

        Column {
            id: body
            x: root.hPadding
            y: root.vPadding
        }
    }
}
