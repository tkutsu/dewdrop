import QtQuick
import QtQuick.Effects
import Quickshell
import qs

// A taskbar window icon. Three ways to find one, in order of how specific they
// are: the window class's desktop entry, an icon theme entry named after the
// class, and finally the generic glyph waybar used as window-rewrite-default.
//
// One icon stands for every window of that app on the workspace, with a count
// badge once there is more than one, and a dot under it while it holds the
// focused window.
Item {
    id: root

    property string windowClass
    property int count: 1
    // Hyprland says this window wants you. The icon bounces rather than
    // recolouring: it is the same thing a tray icon asking for attention says,
    // and the two should not say it differently.
    property bool urgent: false
    // One of this app's windows is the one you are in.
    property bool focused: false
    // Held under the pointer; the owner's MouseArea says so.
    property bool pressed: false
    // What to draw when nothing resolves. A window, on the taskbar; the
    // notifications draw their own mark for a sender with no icon.
    property string fallbackGlyph: Theme.glyph.window
    property alias badgeFill: badge.fill
    // The artwork's opacity, not the badge's: a dimmed icon keeps its count
    // as legible as a lit one.
    property real inkOpacity: 1

    readonly property real shift: bounce.offset + (root.pressed ? Theme.pressDip : 0)

    readonly property bool badged: count > 1

    // How far the focus dot has come in, 0..1. The dot fades with it and the
    // hole it cuts in the artwork opens with it.
    property real dotShown: focused ? 1 : 0

    Behavior on dotShown {
        NumberAnimation {
            duration: Theme.markMs * 0.6
            easing.type: Easing.OutCubic
        }
    }

    z: badged ? 1 : 0

    // The artwork moves and the badge does not. Every badge on this bar sits on
    // one line whatever icon it is pinned to, and one that rode the bounce up
    // would break that line for as long as the app is shouting.
    Bounce {
        id: bounce
        running: root.urgent
    }

    // DesktopEntries fills in asynchronously after startup, and heuristicLookup
    // is a method call, so nothing would re-run this binding on its own. Reading
    // the model's length gives the binding something to depend on.
    readonly property var entry: {
        DesktopEntries.applications.values.length;
        return windowClass ? DesktopEntries.heuristicLookup(windowClass) : null;
    }

    readonly property string iconName: {
        const override = Theme.appIconOverride[windowClass];
        if (override)
            return override;
        if (entry?.icon)
            return entry.icon;
        for (const candidate of [windowClass, windowClass.toLowerCase()]) {
            if (candidate && Quickshell.hasThemeIcon(candidate))
                return candidate;
        }
        return "";
    }

    // Only Ready counts: a name that resolves to nothing leaves the image blank
    // rather than erroring, which would hide the fallback.
    readonly property bool hasIcon: art.status === Image.Ready

    // The badge floats off the top right corner instead of widening the icon,
    // the way BadgedGlyph does for the bar's own modules. Claiming the width
    // would shunt every icon after it — and every workspace after that — along
    // the bar, so a window opening somewhere off to the left moves everything.
    implicitWidth: hasIcon ? art.implicitWidth : fallback.implicitWidth
    // Full bar height, so the badge can be placed against the bar's badge line
    // rather than against a box that is itself floating in the middle of the row.
    implicitHeight: Theme.barHeight

    // The artwork and its stand-in, cut through by a round hole where the
    // focus dot sits. The pill has no room under the icons' ink for a dot of
    // its own, so without the hole the two touched and the dot read as a drip
    // off the icon; with it the dot stands clear, the way an SF Symbol's badge is
    // knocked out of the glyph beneath it. The hole stays where the dot is
    // while the artwork bounces, so a shouting icon passes behind it.
    Item {
        id: artwork

        anchors.fill: parent
        layer.enabled: root.dotShown > 0
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskInverted: true
            maskSource: hole
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        ShadowedIcon {
            id: art

            visible: root.hasIcon
            opacity: root.inkOpacity
            y: Math.round((root.height - implicitHeight) / 2)
            source: root.iconName ? Quickshell.iconPath(root.iconName, true) : ""
            // The tray's line, found the same way (components/InkProbe.qml). The
            // taskbar used to sit on a guess instead: application icons fill their
            // box edge to edge where the theme's panel icons keep margin inside
            // theirs, so the box was made smaller — 13 against the tray's 16 — to
            // land the two sets at the same height. That only held for icons that
            // did fill their box. The ones drawn with any margin of their own came
            // out short, and the ones that overshot got a hand-written trim. The
            // ink is measured now, so one line covers every window on the bar and
            // the second box size goes.
            ink: Theme.iconInk
            transform: Translate { y: root.shift }
            // Unlike the tray, the box follows the artwork rather than staying
            // fixed. The tray keeps identical boxes so a row of unrelated icons
            // holds a steady rhythm; a workspace is the opposite job — its icons
            // pack tight (Theme.appIconGap) so the group reads as one thing — and
            // a fixed box would have each icon carrying whatever margin the ink
            // measurement took off it into the gap to the next.
            box: art.drawn
        }

        Glyph {
            id: fallback

            visible: !root.hasIcon
            opacity: root.inkOpacity
            implicitHeight: root.height
            text: root.fallbackGlyph
            transform: Translate { y: root.shift }
            // A glyph rather than artwork, so it is not the probe's to measure:
            // BarText lays it out on its ink already, and glyphSizeLarge is what
            // puts that ink on the same line the icons are pulled down to.
            fontSize: Theme.glyphSizeLarge
        }
    }

    // The hole's shape, read by the mask above rather than drawn.
    Item {
        id: hole

        width: artwork.width
        height: artwork.height
        visible: false
        layer.enabled: true

        Rectangle {
            readonly property real centreX: dot.x + dot.width / 2
            readonly property real centreY: dot.y + dot.height / 2

            width: (Theme.focusDotSize + Theme.focusDotClearance * 2) * root.dotShown
            height: width
            radius: width / 2
            x: centreX - width / 2
            y: centreY - height / 2
        }
    }

    // Under the icon, centred on its ink rather than its box, and still while
    // the artwork bounces, for the same reason the badge is.
    Rectangle {
        id: dot

        readonly property real inkCentre: root.hasIcon ? art.x + art.inkX + art.inkWidth / 2 : fallback.x + fallback.width / 2

        width: Theme.focusDotSize
        height: width
        radius: width / 2
        x: Math.round(inkCentre - width / 2)
        y: Math.round(Theme.pillTop(root.height) + Theme.focusDotLine - height / 2)
        color: Theme.fg
        opacity: root.dotShown
    }

    // Sits on the icon's top right corner, mostly outside it, so the app stays
    // recognisable underneath. appIconGap is narrower than the overhang, so the
    // badge does land on the next icon along; z lifts a badged icon above the
    // siblings painted after it rather than letting them cover the count.
    Badge {
        id: badge
        visible: root.badged
        text: Math.min(root.count, 99)
        x: root.implicitWidth - Theme.badgeSize / 2
        // A fixed line, so every badge on the bar sits at the same height
        // whatever size the icon beneath it is — measured from the top of the
        // pill rather than of this box (see Theme.pillTop), and riding its
        // edge the same way a module's own count does.
        y: Theme.pillTop(root.height) + Theme.badgeLine - Theme.badgeRise - height / 2
    }
}
