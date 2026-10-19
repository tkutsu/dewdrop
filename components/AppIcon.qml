import QtQuick
import QtQuick.Effects
import Quickshell
import qs
import qs.services

// A taskbar window icon. Three ways to find one, in order of how specific they
// are: the window class's desktop entry, an icon theme entry named after the
// class, and finally the generic glyph waybar used as window-rewrite-default.
//
// One icon stands for every window of that app on the workspace, with a dot
// under it while it holds the focused window.
Item {
    id: root
    transform: [
        ModuleIconScale { icon: root },
        Translate { x: root.spread }
    ]

    property string windowClass
    // Hyprland says this window wants you, or this is an urgent notice's
    // sender. The icon bounces rather than recolouring: it is the same thing a
    // tray icon asking for attention says, and they should not say it
    // differently.
    property bool urgent: false
    // One of this app's windows is the one you are in.
    property bool focused: false
    // Held under the pointer; the owner's MouseArea says so.
    property bool pressed: false
    // What to draw when nothing resolves. A window, on the taskbar; the
    // notifications draw their own mark for a sender with no icon.
    property string fallbackGlyph: Theme.glyph.window
    // A picture to draw instead of looking the class up, for a notification
    // whose sender sent its icon as a file.
    property string source: ""
    // The artwork's opacity, not the dot's: a dimmed icon keeps its dot as
    // legible as a lit one.
    property real inkOpacity: 1
    // Standalone bar modules space from the artwork's visible edges.
    property bool tightWidth: false
    // A corner dot's bounds in this icon, supplied by the workspace badge.
    property rect cornerDot: Qt.rect(0, 0, 0, 0)
    // How far the glass passing over it has magnified the artwork, 0..1, to
    // Theme.markZoom. The dot and the hole keep their places.
    property real magnify: 0
    // How far the glass moves it sideways, in whole pixels, so the gaps in a
    // magnified group grow as much as the icons do.
    property int spread: 0
    // Room either side for the magnified artwork in the layer that cuts the
    // dot's hole, which would otherwise crop it to the icon's width.
    readonly property int bleed: Math.ceil(Theme.iconSize * (Theme.markZoom - 1) / 2)

    readonly property real shift: bounce.offset + (root.pressed ? Theme.pressDip : 0)

    // How far the focus dot has come in, 0..1. The dot fades with it and the
    // hole it cuts in the artwork opens with it.
    property real dotShown: focused ? 1 : 0

    Behavior on dotShown {
        NumberAnimation {
            duration: Theme.markMs * 0.6
            easing.type: Easing.OutCubic
        }
    }

    // The artwork moves and the dot does not. Every dot on this bar sits on
    // one line whatever icon it is under, and one that rode the bounce up
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
        if (!windowClass)
            return null;
        // Native app IDs can be namespaced while the installed desktop ID is short.
        return DesktopEntries.heuristicLookup(windowClass)
            || DesktopEntries.byId(windowClass.split(".").pop().toLowerCase());
    }

    readonly property string iconName: AppIcons.resolve(root.windowClass, root.entry)

    // Only Ready counts: a name that resolves to nothing leaves the image blank
    // rather than erroring, which would hide the fallback.
    readonly property bool hasIcon: art.status === Image.Ready

    // Visible horizontal bounds let the workspace mark light the artwork as it enters.
    readonly property real inkLeft: artwork.x + (hasIcon ? art.x + art.inkX : fallback.x)
    readonly property real inkWidth: hasIcon ? art.inkWidth : fallback.width

    implicitWidth: hasIcon ? (tightWidth ? art.inkWidth : art.implicitWidth) : fallback.implicitWidth
    // Full bar height, so the dot can be placed against the bar's dot line
    // rather than against a box that is itself floating in the middle of the row.
    implicitHeight: Theme.barHeight

    // The artwork and its stand-in, cut through by a round hole where the
    // focus or corner dot sits. The pill has no room under the icons' ink for
    // a dot of its own, so without the hole the two touched and the dot read as a drip
    // off the icon; with it the dot stands clear, the way an SF Symbol's badge is
    // knocked out of the glyph beneath it. The hole stays where the dot is
    // while the artwork bounces, so a shouting icon passes behind it.
    Item {
        id: artwork

        x: -root.bleed
        width: root.width + root.bleed * 2
        height: root.height
        // Under Reduce motion the bounce dims the artwork instead (Bounce.fade).
        opacity: bounce.fade
        layer.enabled: root.dotShown > 0 || root.cornerDot.width > 0
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskInverted: true
            maskSource: hole
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        FittedIcon {
            id: art

            x: root.bleed + (root.tightWidth ? -inkX : 0)
            visible: root.hasIcon
            opacity: Theme.barInk(root, Qt.rgba(1, 1, 1, 1)).a * root.inkOpacity
            y: Math.round((root.height - implicitHeight) / 2)
            source: root.source || (root.iconName ? Quickshell.iconPath(root.iconName, true) : "")
            // The tray's line, found the same way (services/Ink.qml). The
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
            magnify: root.magnify
            magnifiedSize: Math.round(drawn * Theme.markZoom)
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

            x: root.bleed
            visible: !root.hasIcon
            opacity: root.inkOpacity
            implicitHeight: root.height
            text: root.fallbackGlyph
            transform: [
                Scale {
                    origin.x: fallback.width / 2
                    origin.y: fallback.height / 2
                    xScale: 1 + (Theme.markZoom - 1) * root.magnify
                    yScale: xScale
                },
                Translate { y: root.shift }
            ]
            // A glyph rather than artwork, so it is not the probe's to measure:
            // BarText lays it out on its ink already, and glyphSizeLarge is what
            // puts that ink on the same line the icons are pulled down to.
            fontSize: Theme.glyphSizeLarge
        }
    }

    // The hole's shape, read by the mask above rather than drawn.
    Item {
        id: hole

        x: artwork.x
        width: artwork.width
        height: artwork.height
        visible: false
        layer.enabled: root.dotShown > 0 || root.cornerDot.width > 0

        Rectangle {
            readonly property real centreX: dot.x + dot.width / 2
            readonly property real centreY: dot.y + dot.height / 2

            width: (Theme.focusDotSize + Theme.focusDotClearance * 2) * root.dotShown
            height: width
            radius: width / 2
            x: centreX - width / 2 - hole.x
            y: centreY - height / 2
        }

        Rectangle {
            visible: root.cornerDot.width > 0
            width: root.cornerDot.width + Theme.focusDotClearance * 2
            height: width
            radius: width / 2
            x: root.cornerDot.x - Theme.focusDotClearance - hole.x
            y: root.cornerDot.y - Theme.focusDotClearance
        }
    }

    // Under the icon, centred on its ink rather than its box, and still while
    // the artwork bounces.
    Rectangle {
        id: dot

        readonly property real inkCentre: artwork.x + (root.hasIcon ? art.x + art.inkX + art.inkWidth / 2 : fallback.x + fallback.width / 2)

        width: Theme.focusDotSize
        height: width
        radius: width / 2
        x: inkCentre - width / 2
        y: Math.round(Theme.pillTop(root.height) + Theme.focusDotLine - height / 2)
        color: Theme.fg
        opacity: root.dotShown
    }
}
