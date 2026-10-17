import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs

// A module's icon with a count or a small attention dot on its corner.
Item {
    id: root

    property string glyph
    property int glyphSize: Theme.glyphSize
    property string badge: ""
    property bool dot: false
    property bool underdot: false
    // Passed through for the handful of glyphs whose ink box misreports.
    property real nudge: 0

    readonly property bool badged: badge !== ""

    // The icon's width, badge or no badge: the badge floats in the gap to the
    // next module instead of pushing it along, so every icon on the bar sits the
    // same distance from the next one whether it is counting something or not.
    implicitWidth: icon.implicitWidth
    implicitHeight: Theme.barHeight

    Glyph {
        id: icon
        text: root.glyph
        fontSize: root.glyphSize
        nudge: root.nudge
        implicitHeight: root.height
        layer.enabled: root.underdot && root.badged
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskInverted: true
            maskSource: hole
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Badge {
        id: count

        visible: root.badged
        text: root.badge
        dot: root.dot || root.underdot
        dotSize: root.underdot ? Theme.focusDotSize : Theme.badgeDotSize
        // Sample the icon's box, centred vertically, rather than the pill.
        fill: Theme.badgeBg(icon, Qt.rect(0, Math.floor((icon.height - root.glyphSize) / 2) + root.nudge, icon.width, root.glyphSize))
        // Overlapping the icon's right edge by half the badge keeps the icon
        // recognisable underneath and stops a wide pill from swallowing it.
        // A two-digit capsule grows rightwards into the gap, so it steps back
        // 2px to keep from crowding the next icon.
        x: root.underdot ? (icon.implicitWidth - width) / 2
            : root.dot ? Math.round(icon.implicitWidth - width / 2)
            : Math.round(icon.implicitWidth - Theme.badgeSize / 2) - (root.badge.length > 1 ? 2 : 0)
        // A fixed line rather than the icon's own top, so every badge on the
        // bar sits at the same height whatever size its icon is — measured
        // from the top of the pill, since this box reaches up into the margin
        // the pill claims, and raised from there onto the pill's edge.
        y: root.underdot ? Math.round(Theme.pillTop(root.height) + Theme.focusDotLine - height / 2)
            : Math.round(Theme.pillTop(root.height) + Theme.badgeLine - Theme.badgeRise - height / 2) + (root.dot ? 1 : 0)
    }

    // Match the left pill's clearance so the underdot stays separate from the glyph.
    Item {
        id: hole
        width: root.width
        height: root.height
        visible: false
        layer.enabled: root.underdot && root.badged

        Rectangle {
            width: Theme.focusDotSize + Theme.focusDotClearance * 2
            height: width
            radius: width / 2
            x: count.x + count.width / 2 - width / 2
            y: count.y + count.height / 2 - height / 2
        }
    }
}
