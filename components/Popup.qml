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
    // Under Reduce motion a popup only fades: it opens where it will stand.
    property real slideOffset: root.opened || Theme.reduceMotion ? 0 : -6

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
    Component.onDestruction: {
        if (hovered)
            PopupPointer.hovered--;
        OpenPopup.dropKeys(root);
    }

    // --- keyboard ------------------------------------------------------------
    // The keys a Mac's menu-bar menus take: Escape puts the popup away, the
    // arrows walk its controls and Return (or Space) presses the one they are
    // on. Nothing is selected on opening; the first arrow picks the first
    // control, the way a menu opened by a click waits for you.
    //
    // A control takes part by having a `keyPress` function (or `keyStep`, a
    // slider's Left and Right), and draws its own highlight if it has a
    // `keyed` property; anything without one gets the focus ring below.
    // Up and Down go to the nearest control in the next row, keeping to the
    // column where there is one; Left and Right stay in the row. The keys
    // reach here from the bar, which takes the keyboard while its popup is up
    // (Bar.qml): a popup's own surface has none unless it grabs, and a grab
    // makes it a Qt popup that eats the hover the bar browses popups by.
    property bool takesKeys: true
    property Item keyItem: null
    // Escape, and Left with nothing to the left: a submenu goes back to its
    // menu (MenuPopup) rather than closing the whole menu.
    property var closeKey: () => OpenPopup.dismiss()
    property var backKey: null
    // Select the first control as soon as the popup opens, for a submenu
    // opened from the keyboard.
    property bool keyFromStart: false

    readonly property bool keysLive: root.takesKeys && root.opened
    onKeysLiveChanged: {
        if (!root.keysLive) {
            OpenPopup.dropKeys(root);
            root.setKey(null);
            return;
        }
        OpenPopup.addKeys(root);
        if (root.keyFromStart)
            Qt.callLater(() => root.setKey(root.keyTargets()[0] ?? null));
    }

    function setKey(item: Item): void {
        if (root.keyItem && root.keyItem.keyed !== undefined)
            root.keyItem.keyed = false;
        root.keyItem = item;
        if (!item)
            return;
        if (item.keyed !== undefined)
            item.keyed = true;
        root.showKey(item);
    }

    // Scrolled into its list if the list has it out of sight, and the ring
    // moved onto it.
    function showKey(item: Item): void {
        for (let p = item.parent; p && p !== body; p = p.parent) {
            if (p.contentY === undefined || p.contentItem === undefined)
                continue;
            const y = item.mapToItem(p.contentItem, 0, 0).y;
            if (y < p.contentY)
                p.contentY = y;
            else if (y + item.height > p.contentY + p.height)
                p.contentY = y + item.height - p.height;
        }
        const r = item.mapToItem(chrome, 0, 0);
        ring.rect = Qt.rect(r.x, r.y, item.width, item.height);
    }

    // Every control a key can reach, in reading order. Not one folded away:
    // hidden, sized to nothing, under something at zero opacity, or clipped
    // out by a box that is not a list (a list scrolls to it instead).
    function keyTargets(): var {
        const found = [];
        const walk = item => {
            for (const child of item.children) {
                if (!child.visible || child.opacity === 0 || !child.enabled)
                    continue;
                if ((typeof child.keyPress === "function" || typeof child.keyStep === "function") && child.width > 0 && child.height > 0 && root.inView(child))
                    found.push(child);
                walk(child);
            }
        };
        walk(body);
        const at = new Map(found.map(t => [t, t.mapToItem(body, 0, 0)]));
        found.sort((a, b) => at.get(a).y - at.get(b).y || at.get(a).x - at.get(b).x);
        return found;
    }

    function inView(item: Item): bool {
        for (let p = item.parent; p && p !== body; p = p.parent) {
            if (!p.clip || p.contentY !== undefined)
                continue;
            const r = item.mapToItem(p, 0, 0);
            if (r.y + item.height <= 0 || r.y >= p.height || r.x + item.width <= 0 || r.x >= p.width)
                return false;
        }
        return true;
    }

    // The control a step away from the selected one, or null.
    function neighbour(key: int): Item {
        const all = root.keyTargets();
        if (!all.length)
            return null;
        const cur = root.keyItem && all.includes(root.keyItem) ? root.keyItem : null;
        const forward = key === Qt.Key_Down || key === Qt.Key_Right || key === Qt.Key_Tab;
        if (!cur)
            return forward ? all[0] : all[all.length - 1];
        if (key === Qt.Key_Tab || key === Qt.Key_Backtab)
            return all[all.indexOf(cur) + (forward ? 1 : -1)] ?? null;

        const box = t => {
            const p = t.mapToItem(body, 0, 0);
            return { l: p.x, r: p.x + t.width, cx: p.x + t.width / 2, cy: p.y + t.height / 2, h: t.height };
        };
        const c = box(cur);
        // In the same row: centres closer than half the shorter one's height.
        const sameRow = b => Math.abs(b.cy - c.cy) < Math.min(b.h, c.h) / 2;
        const others = all.filter(t => t !== cur).map(t => ({ t: t, b: box(t) }));

        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            const side = others.filter(o => sameRow(o.b) && (forward ? o.b.cx > c.cx : o.b.cx < c.cx));
            side.sort((a, b) => Math.abs(a.b.cx - c.cx) - Math.abs(b.b.cx - c.cx));
            return side[0]?.t ?? null;
        }

        // The nearest row that way, then whatever in it overlaps the column
        // (a full-width row overlaps every column), then the nearest centre.
        const ahead = others.filter(o => !sameRow(o.b) && (forward ? o.b.cy > c.cy : o.b.cy < c.cy));
        if (!ahead.length)
            return null;
        const nearest = ahead.reduce((m, o) => Math.abs(o.b.cy - c.cy) < Math.abs(m.b.cy - c.cy) ? o : m);
        const row = ahead.filter(o => Math.abs(o.b.cy - nearest.b.cy) < Math.min(o.b.h, nearest.b.h) / 2);
        const gap = b => Math.max(0, b.l - c.r, c.l - b.r);
        row.sort((a, b) => gap(a.b) - gap(b.b) || Math.abs(a.b.cx - c.cx) - Math.abs(b.b.cx - c.cx));
        return row[0].t;
    }

    function key(event: var): bool {
        const k = event.key;
        const t = root.keyItem;
        switch (k) {
        case Qt.Key_Escape:
            root.closeKey();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (typeof t?.keyPress === "function")
                t.keyPress();
            return true;
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (typeof t?.keyStep === "function") {
                t.keyStep(k === Qt.Key_Right ? 1 : -1);
                return true;
            }
            // A menu row's submenu opens on Right, the way it does on hover.
            if (k === Qt.Key_Right && typeof t?.keyOpen === "function" && t.keyOpen())
                return true;
            break;
        case Qt.Key_Up:
        case Qt.Key_Down:
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            break;
        default:
            return false;
        }
        const next = root.neighbour(k);
        if (next)
            root.setKey(next);
        else if (k === Qt.Key_Left && root.backKey)
            root.backKey();
        return true;
    }

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

            // The pointer moving takes the selection back from the keys.
            onPointChanged: if (root.keyItem)
                root.setKey(null)
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

                // The keys' mark on a control that draws no highlight of its
                // own: a ring round it, which is what a Mac draws when the
                // keyboard rather than the pointer is on a control.
                Rectangle {
                    id: ring

                    property rect rect
                    visible: root.keyItem !== null && root.keyItem.keyed === undefined
                    x: rect.x - 2
                    y: rect.y - 2
                    width: rect.width + 4
                    height: rect.height + 4
                    z: 2
                    radius: Theme.selectionRadius
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.outlineHover
                }
            }
        }
    }
}
