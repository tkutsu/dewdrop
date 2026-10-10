import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import qs

// The bar's popup chrome. It used to copy the old GTK tooltip's near-opaque
// grey; it is the launcher's box now, frosted glass (Theme.popupBg) with a
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
    // Keep keyboard entry available for the weather location search.
    property bool acceptsKeyboard: false
    property bool probes: true
    grabFocus: root.acceptsKeyboard && root.requestedVisible
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
    // MenuPopup is the one that could get here: it has no padding to stand in
    // for its contents, and QsMenuOpener fills its rows in over DBus some time
    // after it has been built. It holds itself back until they are in, but the
    // clamp stays, because this has to hold for every popup, including the
    // ones not written yet.
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
    //
    // The shadow itself is a popover's; a tooltip, smaller and nearer the
    // surface, casts a smaller one.
    property int shadowBlur: Theme.shadowBlur
    property int shadowY: Theme.shadowY
    readonly property int shadowSide: shadowBlur
    readonly property int shadowTop: Theme.popupGap
    readonly property int shadowBottom: shadowBlur + shadowY

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

    // Where the compositor puts this window on screen, which Quickshell does
    // not say, worked out from the anchor the way the compositor works it
    // out: the anchor's window on screen, the point on the anchor's rect its
    // edges pick, and the window hung off that point towards its gravity.
    // The anchor's window is the bar, a strip across the top or bottom of its
    // screen, or for a submenu the menu it came out of, which knows where it
    // is itself. Slid back onto the screen at the end, which is near enough
    // for a flip as well. Only asked while shown, and asked again on each
    // show: mapToItem gives the binding nothing to re-run on.
    readonly property point windowOnScreen: {
        const item = root.anchorItem;
        const win = item?.QsWindow.window;
        if (!root.visible || !win || !root.screen)
            return Qt.point(0, 0);
        const base = win.windowOnScreen ?? Qt.point(0, win.anchors?.top ? 0 : root.screen.height - win.height);
        const set = root.anchor.rect;
        const r = set.width > 0 || set.height > 0 ? set : Qt.rect(0, 0, item.width, item.height);
        const p = item.mapToItem(null, r.x, r.y);
        const e = root.anchor.edges, g = root.anchor.gravity;
        const ax = base.x + p.x + (e & Edges.Left ? 0 : e & Edges.Right ? r.width : r.width / 2);
        const ay = base.y + p.y + (e & Edges.Top ? 0 : e & Edges.Bottom ? r.height : r.height / 2);
        const x = ax - (g & Edges.Right ? 0 : g & Edges.Left ? root.width : root.width / 2);
        const y = ay - (g & Edges.Bottom ? 0 : g & Edges.Top ? root.height : root.height / 2);
        return Qt.point(Math.max(0, Math.min(root.screen.width - root.width, x)), Math.max(0, Math.min(root.screen.height - root.height, y)));
    }

    // How bright the screen is behind the box, for its frost.
    BackdropProbe {
        id: under

        screen: root.screen
        area: Qt.rect(root.windowOnScreen.x + root.shadowSide, root.windowOnScreen.y + root.shadowTop, root.width - root.shadowSide * 2, root.chromeHeight)
        active: root.visible && root.probes
        ringOnly: true
    }

    // Whether the pointer is on the popup, which the bar counts (below).
    readonly property bool hovered: pointer.hovered

    // Fade the surface and compositor blur together without crossing the
    // blur mask's alpha cutoff; keep the surface alive through its exit.
    // Tooltips and menus fade without moving their content.
    property bool grows: true
    // A menu is there the moment it is asked for and only fades on its way
    // out, as the Mac's do; everything else fades in too.
    property bool fadesIn: true
    property bool requestedVisible: true
    readonly property bool opened: root.backingWindowVisible && root.requestedVisible
    HyprlandWindow.opacity: root.revealProgress
    property real revealProgress: root.opened ? 1 : 0
    property real slideOffset: root.opened ? 0 : -6

    // On from `visible`, which is set before the surface maps, not from
    // backingWindowVisible: that flips `opened` and the guard in the same
    // tick, and when the guard lost the race the reveal jumped to 1 on the
    // first frame, which was every time. The exit stays inside the 160 ms
    // the loaders keep the surface for.
    Behavior on revealProgress {
        enabled: root.visible
        NumberAnimation {
            duration: root.opened ? (root.grows ? 220 : root.fadesIn ? 140 : 0) : 140
            easing.type: root.opened ? Easing.BezierSpline : Easing.InOutQuad
            easing.bezierCurve: [0.2, 0, 0.2, 1, 1, 1]
        }
    }
    Behavior on slideOffset {
        enabled: root.visible
        NumberAnimation {
            duration: root.opened ? 280 : 140
            easing.type: root.opened ? Easing.OutCubic : Easing.InQuad
        }
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
    // it slowly belonged to neither, and a click there closed the popup it
    // was on its way into. The box and its shadow sit inside, so the handler
    // hears the pointer over anything a popup puts in its body.
    Item {
        id: reach
        enabled: root.requestedVisible

        x: root.shadowSide
        width: parent.width - root.shadowSide * 2
        height: root.shadowTop + root.chromeHeight

        HoverHandler {
            id: pointer
        }

        // Animate only the drawing; keep the hit area fixed.
        Item {
            anchors.fill: parent

            transform: Translate {
                y: root.grows && !OpenPopup.switched ? root.slideOffset : 0
            }

            // Under the box rather than round it: the fill is translucent, so
            // the middle of the shadow shows through it too, and darkens it by
            // about the same amount the blur behind it lightens it.
            RectangularShadow {
                anchors.fill: chrome
                offset.y: root.shadowY
                radius: chrome.radius
                blur: root.shadowBlur
                color: Theme.shadow
            }

            Rectangle {
                id: chrome

                y: root.shadowTop
                width: parent.width
                height: root.chromeHeight
                // Thickened over a bright screen (BackdropProbe), and eased
                // there: the reading lands a few frames after the box. Only
                // ever up from popupBg, so the blur stays.
                color: Theme.frostOver(under.luma)

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.revealMs
                    }
                }
                radius: root.radius

                Rim {
                    anchors.fill: parent
                    radius: chrome.radius
                    // Above the rows, which run edge to edge in a menu and
                    // would otherwise paint over it where the pointer is.
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
}
