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
    // Whoever anchors a popup by one of its edges rather than by its middle
    // has to take these back off the anchor, or the box lands this far from
    // where it was aimed (HoverPopup, the tray and MenuPopup's submenus all do).
    //
    // Next to nothing above: the box hangs popupGap under the pill, and any
    // more room than that puts the top of the window over the pill's lower
    // half. Hyprland hands the pointer to the popup's window there, mask or
    // no mask, so a pointer resting low on a module opened its popup, was
    // taken off the module by it, and closed it again a moment later — and
    // stayed that way until it moved. The shadow's faint top edge is cut
    // off instead; it falls on the bar, where nothing showed it anyway.
    readonly property int shadowSide: Theme.shadowBlur
    readonly property int shadowTop: Theme.popupGap
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
        item: reach
    }

    // A popup that can be clicked has to outlive the pointer leaving the bar
    // item that opened it; HoverPopup watches this to decide when to close.
    readonly property bool hovered: pointer.hovered

    // Stay open a while even with the pointer outside. For a button whose
    // press shrinks the popup — a row gone from a list — and so leaves the
    // pointer over the empty strip under it, where the popup cannot see it:
    // without this the popup closed on the pointer it had just moved out from
    // under, before it could be brought back.
    property real heldUntil: 0

    function hold(ms: int): void {
        root.heldUntil = Date.now() + ms;
    }

    // Counted for the whole shell, so the right pill's drawer can tell a
    // pointer that has gone off to a popup from one that has left the bar.
    onHoveredChanged: PopupPointer.hovered += hovered ? 1 : -1
    Component.onDestruction: if (hovered)
        PopupPointer.hovered--

    // Where the popup takes the pointer: the box, and the strip of air above
    // it up to the window's top edge. The bar's surface ends at the pill, and
    // that edge is where the module lets go of the pointer, so the strip is
    // the seam between the two. Counted from the box alone, a pointer crossing
    // it slowly belonged to neither, and HoverPopup's leave timer closed the
    // popup before it arrived. The box and its shadow sit inside, so the
    // handler hears the pointer over anything a popup puts in its body.
    Item {
        id: reach

        x: root.shadowSide
        width: parent.width - root.shadowSide * 2
        height: root.shadowTop + root.chromeHeight

        HoverHandler {
            id: pointer
        }

        // Under the box rather than round it: the fill is translucent, so the
        // middle of the shadow shows through it too, and darkens it by about
        // the same amount the blur behind it lightens it.
        RectangularShadow {
            anchors.fill: chrome
            offset.y: Theme.shadowY
            radius: chrome.radius
            blur: Theme.shadowBlur
            color: Theme.shadow
        }

        Rectangle {
            id: chrome

            y: root.shadowTop
            width: parent.width
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

            Column {
                id: body
                x: root.hPadding
                y: root.vPadding
            }
        }
    }
}
