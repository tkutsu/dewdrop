import QtQuick
import QtQuick.Layouts
import qs

// The per-module shell: pointer handling, scroll accumulation and the hover
// popup. Spacing is not its business — the bar's rows space their children
// uniformly, so a module is exactly as wide as what it draws. What a click
// does is the module's `actions`, a table from button to what it runs (see
// ClickArea).
ClickArea {
    id: root

    default property alias content: layout.data
    // Modules are spaced by the pill they sit in; this is for the one whose
    // own contents are a group rather than a row of separate things.
    property alias spacing: layout.spacing

    // Text for a plain hover tooltip, or a Component for something richer — a
    // calendar, a volume slider. A tooltip says what the icon cannot: the
    // state behind it ("Volume 40%", "Home Wi-Fi"), or for a tool, its name.
    // A short phrase in sentence case with no full stop, and nothing on a
    // module whose own text already says it. It appears on hover; the popup on a
    // click of `popupButton`, and stays until a click anywhere else, because
    // a popup is somewhere to go rather than something to glance at.
    // `popupItem` is the live instance, for modules that need to drive it
    // (scrolling the calendar through months).
    property string tooltip: ""
    property Component popup: null
    readonly property var popupItem: clicked.item

    // The button that opens the popup. It takes that button from the module's
    // own `actions`. Qt.NoButton for a module that opens it from somewhere of
    // its own with togglePopup() (Music's title).
    property int popupButton: Qt.LeftButton
    readonly property bool popupOpen: OpenPopup.owner === root

    function togglePopup(): void {
        OpenPopup.toggle(root);
    }

    // With another module's popup up, arriving here opens this one in its
    // place (OpenPopup.browse). Only where the whole module is the popup's
    // button: Music's popup belongs to its title, which browses for itself,
    // and the rest of it is controls that a pointer on its way to them
    // should not open anything.
    onContainsMouseChanged: if (containsMouse && popup !== null && popupButton !== Qt.NoButton)
        OpenPopup.browse(root)

    // Fitts's law: the modules at the ends of the bar back onto a screen edge,
    // which makes them the cheapest targets on screen — but only if their hit
    // area reaches that edge instead of stopping at the row's margin. Padding
    // widens the MouseArea; the content still sits where the margin put it.
    property int padLeft: 0
    property int padRight: 0

    // The click's press-in: the contents dip a pixel while the button is held.
    // A module that answers to several targets inside itself (Music) turns
    // this off and dips each target on its own instead.
    property bool dips: true

    // Wheel events arrive in 1/8-degree units and a single notch is 120 of
    // them. Free-spinning wheels and touchpads send fractions, so accumulate
    // rather than firing per event.
    signal scrollUp
    signal scrollDown
    property int scrollThreshold: 120
    property real _scrollAcc: 0

    // Whether the module is there at all — false for something that was never
    // set up, which is not the same as having nothing to say. Use this rather
    // than `visible`, which the drawer below drives.
    property bool present: true

    // The module's name in Settings, for the ones that can be switched off
    // on the settings page. Off is `present` false from outside: the module
    // is not on this machine's bar at all.
    property string settingsKey: pinKey
    readonly property bool here: present && Settings.moduleOn(settingsKey)

    // Nothing to say right now: no unread mail, no updates, a tool rather than
    // a status. The right pill keeps modules like that in its drawer, so the
    // bar shows what is true at the moment and the rest is a click away.
    property bool quiet: false

    // The module's name in DrawerPins, for the ones the right pill's drawer
    // holds: middle click then pins it out of the drawer, and again lets it
    // go back to its own `quiet`. Empty for everything else, which keeps
    // middle click for itself.
    property string pinKey: ""
    // Whether the module stands out of the drawer while it is closed: when
    // it has something to say, or always once it is pinned.
    readonly property bool showsClosed: pinKey === "" || !quiet || DrawerPins.pinned(pinKey)

    // Whether to mark a pinned module as pinned. Set by the drawer's owner
    // while the drawer is open, which is when pinned and unpinned stand side
    // by side and the difference is worth saying.
    property bool marksPin: false

    // Put away in the drawer. Set by whoever owns the drawer (Bar.qml), off
    // `showsClosed` and whether the drawer is open.
    property bool stowed: false

    // How far out of the drawer the module is, 0..1. It folds to nothing
    // rather than blinking out: its width goes, and so does the gap in front
    // of it, which the row would otherwise go on reserving for an item of no
    // width. The contents keep their size and slide under the module's left
    // edge as it closes, so it reads as being drawn in behind its neighbour
    // rather than as squashed.
    //
    // A module that folds runs it on a spring (Theme.foldSpring), held to
    // 0..1: the module lands at its own width and stays there while the
    // spring carries on past it. Each module rounds its width to a pixel (see
    // below), and ten of them settling back through the same rounding at
    // once moved the pill's edge in jumps of several pixels. What is past 1
    // goes to the glass instead, as one amount (overrun).
    readonly property real reveal: folds ? Math.min(1, Math.max(0, _sprung)) : _eased
    // How far past its full width the spring has carried the module, in
    // pixels, for the pill's glass to run on by (Pill.stretch).
    readonly property real overrun: folds ? Math.max(0, _sprung - 1) * (layout.implicitWidth + padLeft + padRight + (lead ? Theme.gap : 0)) : 0

    property real _sprung: stowed ? 0 : 1
    Behavior on _sprung {
        enabled: root.folds
        SpringAnimation {
            spring: Theme.foldSpring
            // Closing, damped to where it barely goes past, so the edge
            // glides in to rest rather than being stopped at shut.
            damping: root.stowed ? Theme.foldCloseDamping : Theme.foldDamping
            // Of the whole fold rather than a pixel: the drawer is a few
            // hundred pixels, and at the default 1% the last few of them
            // would snap into place.
            epsilon: 0.001
        }
    }

    // How it runs for the pills beside the clock, which keep their width:
    // longer and evenly, because the bar lays its own easing over each stage
    // of the drop it draws off `reveal` (Bar.drop).
    property int foldDuration: Theme.foldMs
    property int foldEasing: Easing.InOutCubic

    property real _eased: stowed ? 0 : 1
    Behavior on _eased {
        enabled: !root.folds
        NumberAnimation {
            duration: root.foldDuration
            easing.type: root.foldEasing
        }
    }

    // Whether `reveal` takes the width with it. A module in the right pill's
    // drawer folds; a pill beside the clock keeps its width and lets the bar
    // draw it off `reveal` instead (see Bar.drop).
    property bool folds: true
    readonly property real _fold: folds ? reveal : 1

    visible: here && reveal > 0
    clip: _fold < 1
    // Whether a gap goes in front of this module: yes, unless it is the first
    // in its pill (Pill sets that). The gap folds with the module, so a module
    // going into the drawer takes its share of the row with it.
    //
    // Rounded to the nearest pixel here, the width below too, because the
    // layout would otherwise round them up: a module a hundredth of the way
    // out of the drawer was given a whole pixel of width and another of gap,
    // and seven of them together made the pill jump fifteen pixels on the
    // first frame of the fold and again on the last.
    //
    // But rounded all alike, the modules folding together take their pixels
    // on the same frame: every gap is the same width, so ten of them went
    // from one pixel to the next at once and the drawer moved in lurches of
    // ten. Mid-fold, each module rounds a different fraction of the way
    // between two pixels (_dither, spread by the golden ratio by its place in
    // the row), so they take their pixels in turn and the pill's edge moves
    // a pixel or two at a time. At rest it is nought and nothing moves.
    // Gap and width are rounded as one, for the same reason.
    property bool lead: true
    readonly property real _dither: _fold > 0 && _fold < 1 ? ((parent?.children.indexOf(root) ?? -1) + 1) * 0.618034 % 1 - 0.5 : 0
    readonly property int _gap: lead ? Math.round(Theme.gap * _fold + _dither) : 0
    Layout.leftMargin: _gap
    // Whether a module follows this one: yes, unless it is the last in its
    // pill (Pill sets that too), whose padding runs out to the pill's end
    // instead.
    property bool trail: true

    // How far past its box the module answers on a side with a neighbour:
    // halfway across the gap, so the gap between two icons is split down the
    // middle rather than a dead strip that clicks on nothing. The neighbour
    // takes the other half. Folds with the gap it reaches into.
    readonly property real _reach: Theme.gap * _fold / 2

    implicitWidth: Math.round((layout.implicitWidth + padLeft + padRight + (lead ? Theme.gap : 0)) * _fold + _dither) - _gap
    implicitHeight: Theme.barHeight
    Layout.fillHeight: true

    hoverEnabled: true
    // config.jsonc sets "cursor": false on every module — no pointer hand.
    cursorShape: Qt.ArrowCursor
    containmentMask: reach

    // The module answers for half the gap either side of it (_reach), and
    // for its contents' badges as well: a count badge hangs out past the
    // module's box, over the gap to the next one (BadgedGlyph), and a click
    // on it is a click on the icon. Hover, the wheel and every button, here
    // and on the layers above.
    QtObject {
        id: reach

        function contains(point: point): bool {
            if (point.x >= span.x && point.y >= 0 && point.x < span.x + span.width && point.y < root.height)
                return true;
            for (const item of layout.children)
                for (const part of item.children)
                    if (part instanceof Badge && part.visible && part.contains(part.mapFromItem(root, point)))
                        return true;
            return false;
        }
    }

    // The box plus that half gap either side, as an item rather than only as
    // the mask: Qt looks for a child under the pointer only inside its
    // parent's box and its children's boxes, and asks no mask about that. With
    // the reach in the mask alone, a click in the gap stopped at the module
    // and never got to the pin or the popup's button, which fill this.
    Item {
        id: span
        x: root.lead ? -root._reach : 0
        width: root.width - x + (root.trail ? root._reach : 0)
        height: root.height
    }

    // The reach again, for the layers over the span: their x is span's.
    QtObject {
        id: spanReach

        function contains(point: point): bool {
            return reach.contains(Qt.point(point.x + span.x, point.y));
        }
    }

    // Pinned to the right and at its own width rather than filling the
    // module, so that folding into the drawer takes the module's left edge
    // across its contents instead of squeezing them.
    RowLayout {
        id: layout
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.padRight
        width: implicitWidth
        // On the contents rather than the module, which several modules set
        // an opacity of their own on to say they are still loading. In step
        // with the slot, so the icon and the room it stands in come and go
        // together rather than one after the other.
        opacity: root._fold
        spacing: Theme.gap
        transform: Translate {
            y: root.dips && (root.acting || pin.acting || opener.acting) ? Theme.pressDip : 0
        }
    }

    // The pin mark: the badge's disc on the lower right corner, where the
    // badge takes the upper. It stays inside the pill, because the bar's
    // surface ends at the pill's bottom edge and anything past it is cut off.
    Rectangle {
        readonly property int size: Theme.pinMarkSize

        x: Math.round(layout.x + layout.width - size / 2)
        y: Theme.pillTop(root.height) + Theme.barHeight - size - 1
        width: size
        height: size
        radius: size / 2
        color: Theme.badgeBg(root)
        opacity: root.pinKey !== "" && root.marksPin && DrawerPins.pinned(root.pinKey) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }

        Rim {
            anchors.fill: parent
            radius: parent.radius
            topColor: Theme.markRimTop
        }

        Glyph {
            anchors.centerIn: parent
            text: Theme.glyph.pin
            fontSize: Theme.pinGlyphSize
            color: Theme.badgeFg
        }
    }

    // Middle click on a pinnable module is the pin and nothing else. A layer
    // on top that answers to the middle button alone takes it before the
    // module's own actions can; left, right, hover and the wheel all go on
    // through to the module.
    ClickArea {
        id: pin
        anchors.fill: span
        containmentMask: spanReach
        enabled: root.pinKey !== ""
        acceptedButtons: Qt.MiddleButton
        cursorShape: Qt.ArrowCursor
        actions: ({
                [Qt.MiddleButton]: () => DrawerPins.toggle(root.pinKey)
            })
    }

    // The popup's button, taken the same way as the pin's above.
    ClickArea {
        id: opener
        anchors.fill: span
        containmentMask: spanReach
        enabled: root.popup !== null && root.popupButton !== Qt.NoButton
        acceptedButtons: root.popupButton
        cursorShape: Qt.ArrowCursor
        actions: ({
                [root.popupButton]: root.togglePopup
            })
    }

    onWheel: function (wheel) {
        root._scrollAcc += wheel.angleDelta.y;
        while (root._scrollAcc >= root.scrollThreshold) {
            root._scrollAcc -= root.scrollThreshold;
            root.scrollUp();
        }
        while (root._scrollAcc <= -root.scrollThreshold) {
            root._scrollAcc += root.scrollThreshold;
            root.scrollDown();
        }
    }

    // --- tooltip and popup ---------------------------------------------------
    // The tooltip stands aside while any popup is up, this one's included
    // (HoverPopup).
    HoverPopup {
        id: hover
        anchorItem: root
        hovered: root.containsMouse
        pressed: root.pressed || pin.pressed || opener.pressed
        text: root.tooltip
    }

    HoverPopup {
        id: clicked
        anchorItem: root
        open: root.popupOpen
        popup: root.popup
    }
}
