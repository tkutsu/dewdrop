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
    property real reveal: stowed ? 0 : 1

    // How `reveal` runs. The pills beside the clock take longer and run it
    // evenly, because the bar lays its own easing over each stage of the drop
    // it draws off it (Bar.drop).
    property int foldDuration: Theme.foldMs
    property int foldEasing: Easing.InOutCubic

    Behavior on reveal {
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
    property bool lead: true
    Layout.leftMargin: lead ? Math.round(Theme.gap * _fold) : 0

    implicitWidth: Math.round((layout.implicitWidth + padLeft + padRight) * _fold)
    implicitHeight: Theme.barHeight
    Layout.fillHeight: true

    hoverEnabled: true
    // config.jsonc sets "cursor": false on every module — no pointer hand.
    cursorShape: Qt.ArrowCursor

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

    // The pin mark: the badge's dark disc on the lower right corner, where the
    // badge takes the upper. It stays inside the pill, because the bar's
    // surface ends at the pill's bottom edge and anything past it is cut off.
    Rectangle {
        readonly property int size: Theme.pinMarkSize

        x: layout.x + layout.width - size / 2
        y: Theme.pillTop(root.height) + Theme.barHeight - size - 1
        width: size
        height: size
        radius: size / 2
        color: Theme.badgeBg
        opacity: root.pinKey !== "" && root.marksPin && DrawerPins.pinned(root.pinKey) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
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
        anchors.fill: parent
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
        anchors.fill: parent
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
