import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// A notification as it arrives: who sent it and one line of what it said, on an
// pill of its own beside the clock, folding away again once it has been
// seen. The bar's own version of the pill a phone grows around its camera
// for the same thing, and the one place on screen a glance already goes to
// read the time.
//
// The notification itself stays in the centre after this has folded away; this
// is the moment of arrival and nothing after it (see services/Notifications.qml).
BarItem {
    id: root

    readonly property var entry: Notifications.latest

    // What the notice says (its line, icon and count), kept as it was while
    // it is drawn back into the clock. Letting go of a notice can close its
    // notification (a fleeting one expires on the spot), which empties the
    // entry and zeroes the count the moment it starts to go.
    //
    // `current` is null unless there is a notice up to read, and `kept` only
    // ever takes it when it is not. A Binding with a `when` did this before
    // and blanked the line anyway: its value and its condition both hung off
    // the entry going null, and Qt re-evaluated the value first.
    readonly property var current: Notifications.showing && entry ? {
        line: line,
        key: Notifications.keyOf(entry),
        picture: Notifications.pictureOf(entry),
        burst: Notifications.burst
    } : null
    property var kept: ({ line: "", key: "", picture: "", burst: 0 })

    onCurrentChanged: if (current)
        kept = current

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
    // between the clock (or the timer beside it) and the right pill. The line takes whatever the icon,
    // the count and the padding leave of it, and elides past that.
    property int room: 0

    // Comes out of the clock and is drawn back into it; the bar draws the
    // pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: !Notifications.showing
    folds: false
    spacing: Theme.appIconGap + 4

    // The pointer resting on it keeps it up — see Notifications.held.
    onContainsMouseChanged: Notifications.held = containsMouse

    AppIcon {
        id: icon
        Layout.alignment: Qt.AlignVCenter
        windowClass: root.kept.key
        source: root.kept.picture
        fallbackGlyph: Theme.glyph.notif
    }

    BarText {
        Layout.fillHeight: true
        text: root.kept.line
        // Summed from the parts rather than read off the row's width, which
        // is this line's own width plus theirs and would be a binding loop.
        // Never under a pixel: 0 is no ceiling at all.
        maxWidth: Math.max(1, root.room - root.padLeft - root.padRight - icon.implicitWidth - root.spacing - (burst.shown ? burst.implicitWidth + root.spacing : 0))
    }

    // How many more came in behind this one while it was up. Quieter than the
    // line, the way a count is: it is how much there is, not what it says.
    BarText {
        id: burst
        readonly property bool shown: root.kept.burst > 0
        Layout.fillHeight: true
        visible: shown
        text: "+" + root.kept.burst
        color: Theme.label2
    }

    // Left runs its default action, as clicking its card in the centre does
    // (Notifications.activate). One without a default opens in the centre
    // instead, scrolled to and marked there. Anything else only waves the
    // notice off, and the notification stays in the centre.
    actions: ({
            [Qt.LeftButton]: () => {
                const n = root.entry;
                if (n?.actions.some(a => a.identifier === "default"))
                    Notifications.activate(n);
                else
                    Notifications.focusOn(n);
                Notifications.dismissNotice();
            },
            [Qt.RightButton]: () => Notifications.dismissNotice(),
            [Qt.MiddleButton]: () => Notifications.dismissNotice()
        })
}
