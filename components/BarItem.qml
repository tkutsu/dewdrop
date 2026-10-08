import QtQuick
import QtQuick.Layouts
import qs

// The per-module shell: pointer handling, scroll accumulation and the hover
// popup. Each module carries half the gap to its neighbours as clickable
// padding. What a click does is the module's `actions`, a table from button
// to what it runs (see ClickArea).
ClickArea {
    id: root

    default property alias content: layout.data
    // Spacing within a module whose contents are a group.
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
    // The pill whose row this module sits in, if it does: while the pill
    // drags a module to a new place, tooltips and popups keep still.
    readonly property Item pill: parent?.parent instanceof Pill ? parent.parent : null
    readonly property bool pillDragging: pill?.dragging ?? false
    readonly property bool reordering: pillDragging && pill.dragSource === root
    readonly property bool inkHovered: containsMouse && !pillDragging

    function togglePopup(): void {
        OpenPopup.toggle(root);
    }

    // With another module's popup up, resting here opens this one in its
    // place (OpenPopup.browse). Only where the whole module is the popup's
    // button: Music's popup belongs to its title, which browses for itself,
    // and the rest of it is controls that a pointer on its way to them
    // should not open anything.
    onContainsMouseChanged: if (popup !== null && popupButton !== Qt.NoButton)
        OpenPopup.browse(root, containsMouse && !root.pillDragging)

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

    // The module's key in the right pill's saved order.
    property string settingsKey: pinKey
    readonly property bool here: present

    // Nothing to say right now: no unread mail, no updates, a tool rather than
    // a status. The right pill keeps modules like that in its drawer, so the
    // bar shows what is true at the moment and the rest is a click away.
    property bool quiet: false

    // The module's name in DrawerPins, for the ones the right pill's drawer
    // holds: middle click then pins it out of the drawer, and again lets it
    // go back to its own `quiet`. Empty for everything else, which keeps
    // middle click for itself.
    property string pinKey: ""
    // Off for a module whose middle click is its own (the tray's icons):
    // it is still in the drawer, but pinned only from the settings window.
    property bool middlePins: true
    // Whether the module stands out of the drawer while it is closed: when
    // it has something to say and is not kept in, is pinned, or owns the
    // open popup. A quiet popup owner waits until its popup closes before
    // folding away.
    readonly property bool showsClosed: pinKey === "" || popupOpen || DrawerPins.pinned(pinKey) || (!quiet && !DrawerPins.kept(pinKey))

    // Whether to mark a pinned module as pinned. Set by the drawer's owner
    // while the drawer is open, which is when pinned and unpinned stand side
    // by side and the difference is worth saying.
    property bool marksPin: false

    // Put away in the drawer. Set by whoever owns the drawer (Bar.qml), off
    // `showsClosed` and whether the drawer is open.
    property bool stowed: false

    // Modules add their own finite motion; folds include the spring's full settling.
    property bool contentAnimating: false
    readonly property bool animating: contentAnimating || foldSpring.running || foldEase.running

    // How far out of the drawer the module is, 0..1. It folds to nothing
    // rather than blinking out: its width and gap padding go together.
    // The contents keep their size and slide under the module's left
    // edge as it closes, so it reads as being drawn in behind its neighbour
    // rather than as squashed.
    //
    // Once the spring first reaches its destination, keep the module there
    // for the rest of the settling. Otherwise each undershoot starts folding
    // and clipping an open icon again, or briefly reveals a closed one.
    // All the remaining spring motion goes to the pill's glass (overrun).
    property bool _landed: false
    property bool _initialized: false
    Component.onCompleted: {
        _initialized = true;
        _landed = stowed ? _sprung <= 0 : _sprung >= 1;
    }
    onStowedChanged: _landed = false
    on_SprungChanged: if (_initialized && (stowed ? _sprung <= 0 : _sprung >= 1))
        _landed = true

    readonly property real reveal: folds ? (_landed ? (stowed ? 0 : 1) : Math.min(1, Math.max(0, _sprung))) : _eased
    // How far past its full width the spring has carried the module, in
    // pixels, or past nothing as a negative: for the pill's glass to run on
    // or squeeze in by (Pill.stretch).
    readonly property real overrun: folds ? (_sprung - reveal) * _fullWidth : 0

    property real _sprung: stowed ? 0 : 1
    Behavior on _sprung {
        enabled: root.folds && root._started
        SpringAnimation {
            id: foldSpring
            spring: Theme.drawerSpring
            damping: Theme.drawerDamping
            // Of the whole fold rather than a pixel: the drawer is a few
            // hundred pixels, and at the default 1% the last few of them
            // would snap into place.
            epsilon: 0.001
        }
    }

    // No spring while the bar starts (Theme.startMs). The drawer's modules
    // hear from their services a moment after they are made, and each sprang
    // out of the drawer as it did: clipped to its own box as it unfolded,
    // which cut its badge in half and drew an edge across its icon. They
    // take their places at once instead.
    property bool _started: false
    Timer {
        interval: Theme.startMs
        running: root.folds
        onTriggered: root._started = true
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
            id: foldEase
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
    // Half the gap on each side with a neighbour. Pill turns these off at
    // the row's ends, where padLeft/padRight carry the pill's padding instead.
    property bool lead: true
    property bool trail: true
    readonly property int _moduleGap: parent?.parent?.moduleGap ?? Theme.gap
    // Split odd gaps asymmetrically to keep settled content on whole pixels.
    readonly property real _leftGap: lead ? Math.floor(_moduleGap / 2) : 0
    readonly property real _rightGap: trail ? Math.ceil(_moduleGap / 2) : 0
    readonly property real _fullWidth: layout.implicitWidth + padLeft + padRight + _leftGap + _rightGap

    // How far the pill has pushed this module along, drawn only, while its
    // glass runs past or is squeezed in (Pill.stretch).
    property real shift: 0
    transform: Translate {
        x: root.shift
    }

    // Round content and padding together. Stagger the rounding across modules
    // so a fold does not move every module's edge by a pixel on the same frame.
    readonly property real _dither: _fold > 0 && _fold < 1 ? ((parent?.children.indexOf(root) ?? -1) + 1) * 0.618034 % 1 - 0.5 : 0
    implicitWidth: Math.round(_fullWidth * _fold + _dither)
    implicitHeight: Theme.barHeight
    Layout.fillHeight: true

    hoverEnabled: true
    // Keep the normal pointer over bar modules.
    cursorShape: Qt.ArrowCursor
    containmentMask: reach

    // The box includes the gap padding. Also answer for badges that extend
    // past it: a count badge can hang over the next module (BadgedGlyph).
    // A click on it is a click on the icon, for hover, the wheel and every
    // button, here and on the layers above.
    QtObject {
        id: reach

        function contains(point: point): bool {
            if (point.x >= 0 && point.y >= 0 && point.x < root.width && point.y < root.height)
                return true;
            for (const item of layout.children)
                for (const part of item.children)
                    if (part instanceof Badge && part.visible && part.contains(part.mapFromItem(root, point)))
                        return true;
            return false;
        }
    }

    // Include badge overhang in the popup and pin buttons' boxes too. A mask
    // alone cannot route a click to a child whose box ends before the badge.
    Item {
        id: span
        width: {
            let right = root.width;
            for (const item of layout.children)
                for (const part of item.children)
                    if (part instanceof Badge && part.visible)
                        right = Math.max(right, layout.x + item.x + part.x + part.width);
            return right;
        }
        height: root.height
    }

    // Pinned to the right and at its own width rather than filling the
    // module, so that folding into the drawer takes the module's left edge
    // across its contents instead of squeezing them.
    RowLayout {
        id: layout
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.padRight + root._rightGap
        width: implicitWidth
        // On the contents rather than the module, which several modules set
        // an opacity of their own on to say they are still loading. In step
        // with the slot, so the icon and the room it stands in come and go
        // together rather than one after the other.
        opacity: root._fold * (root.reordering ? 0.35 : 1)
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
        containmentMask: reach
        enabled: root.pinKey !== "" && root.middlePins
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
        containmentMask: reach
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
        hovered: root.containsMouse && !root.pillDragging
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
