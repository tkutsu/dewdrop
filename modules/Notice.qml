import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// A notification as it arrives: who sent it and one line of what it said, on an
// island of its own beside the clock, folding away again once it has been
// seen. The bar's own version of the island a phone grows around its camera
// for the same thing, and the one place on screen a glance already goes to
// read the time.
//
// The notification itself stays in the centre after this has folded away; this
// is the moment of arrival and nothing after it (see services/Notifications.qml).
BarItem {
    id: root

    readonly property var entry: Notifications.latest
    // Kept through the fold: the notification can be closed while its notice
    // is still on the way out, and the line should not blank mid-fold.
    property string shownLine: ""

    onLineChanged: if (line !== "")
        shownLine = line

    // What goes on the line: the summary, and the body after it when there is
    // room. A sender with no summary is rare but legal, and falls back to the
    // body alone, then to its own name.
    readonly property string line: {
        if (!entry)
            return "";
        const summary = Notifications.plain(entry.summary);
        const body = Notifications.plain(entry.body);
        const head = summary || entry.appName;
        return body && body !== head ? head + "  ·  " + body : head;
    }

    // How wide the whole notice may get, which the bar sets from the room
    // between the clock and the right pill. The line takes whatever the icon,
    // the count and the padding leave of it, and elides past that.
    property int room: 0

    // Slides out from under the clock and back under it; the bar places the
    // pill off `reveal` (see Bar.qml), and nothing folds.
    stowed: !Notifications.showing
    folds: false
    spacing: Theme.appIconGap + 4

    // The pointer resting on it keeps it up — see Notifications.held.
    onContainsMouseChanged: Notifications.held = containsMouse

    AppIcon {
        id: icon
        Layout.alignment: Qt.AlignVCenter
        windowClass: Notifications.keyOf(root.entry)
        fallbackGlyph: Theme.glyph.notifNone
    }

    BarText {
        Layout.fillHeight: true
        text: root.shownLine
        // Summed from the parts rather than read off the row's width, which
        // is this line's own width plus theirs and would be a binding loop.
        // Never under a pixel: 0 is no ceiling at all.
        maxWidth: Math.max(1, root.room - root.padLeft - root.padRight - icon.implicitWidth - root.spacing - (burst.shown ? burst.implicitWidth + root.spacing : 0))
    }

    // How many more came in behind this one while it was up. Quieter than the
    // line, the way a count is: it is how much there is, not what it says.
    BarText {
        id: burst
        readonly property bool shown: Notifications.burst > 0
        Layout.fillHeight: true
        visible: shown
        text: "+" + Notifications.burst
        color: Theme.label2
    }

    // Left opens it in the centre — scrolled to and marked there, with what
    // arrived around it — rather than acting on it: its own action is one more
    // click away on its card, and a banner that ran the action outright also
    // closed the notification, so the click that asked to see it was the one
    // that took it away. Anything else only waves the notice off; the
    // notification stays in the centre either way.
    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            Notifications.focusOn(root.entry);
        Notifications.dismissNotice();
    }
}
