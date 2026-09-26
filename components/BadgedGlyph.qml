import QtQuick
import QtQuick.Layouts
import qs

// A module's icon with its count on the corner, in place of the number that
// used to trail it as text. Everything that counts something on this bar —
// unread mail, pending updates, notifications, volume — reads the same way as
// the taskbar's grouped windows do.
Item {
    id: root

    property string glyph
    property int glyphSize: Theme.glyphSize
    property string badge: ""
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
    }

    Badge {
        id: count

        visible: root.badged
        text: root.badge
        // Overlapping the icon's right edge by half the badge keeps the icon
        // recognisable underneath and stops a wide pill from swallowing it.
        x: icon.implicitWidth - Theme.badgeSize / 2
        // A fixed line rather than the icon's own top, so every badge on the
        // bar sits at the same height whatever size its icon is — measured
        // from the top of the pill, since this box reaches up into the margin
        // the pill claims, and raised from there onto the pill's edge.
        y: Theme.pillTop(root.height) + Theme.badgeLine - Theme.badgeRise - height / 2
    }
}
