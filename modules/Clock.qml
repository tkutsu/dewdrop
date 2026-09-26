import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// clock#time. The calendar the Pango tooltip used to draw as a <tt> block is a
// real grid now; the click actions carry over unchanged.
BarItem {
    id: root

    popup: Calendar {}

    // The dot is a separator inside the clock, not a module of its own, so the
    // two parts sit half a gap apart and read as one thing. The margins go on
    // the labels either side rather than on the dot: a RowLayout clamps a cell
    // to zero width once its margins outweigh it, and at 3px wide the dot loses
    // that argument — it ends up shoved left with a full gap still on its right.
    readonly property int dotGap: -Math.round(Theme.gap / 2)

    // The point the bar centres on. Both labels change width — the day number
    // carries one digit or two, and no two month or weekday names are the same
    // length — so centring the module as a whole would leave the clock creeping
    // left and right under it. The dot never changes width, so pinning that
    // instead holds the whole thing still.
    readonly property alias centreItem: dot

    // "actions": { "on-scroll-up": "shift_up", "on-scroll-down": "shift_down" }
    onScrollUp: if (popupItem)
        popupItem.offset--
    onScrollDown: if (popupItem)
        popupItem.offset++

    // Singletons are lazy, and nothing reads Agenda until the popup opens —
    // so without this the calendar would not be fetched until the first hover,
    // and would open on "Connecting…" every time the shell started.
    Component.onCompleted: Agenda.ensure(new Date())

    SystemClock {
        id: clock
        // The bar shows a date and HH:mm; neither changes more than once a
        // minute, and at Seconds this re-evaluated both, on every bar, sixty
        // times for each time it could possibly have mattered.
        precision: SystemClock.Minutes
    }

    // Which day, then what time — two facts rather than three, so the weekday
    // and the date are one label with a word space between them and the dot has
    // only the one joint to mark. standalone names rather than dayName/monthName
    // or the "MMM" of formatDateTime: a label on its own wants the nominative,
    // which only shows in a locale that inflects (the calendar header makes the
    // same call for its own title).
    BarText {
        Layout.fillHeight: true
        Layout.rightMargin: root.dotGap
        text: Qt.locale().standaloneDayName(clock.date.getDay(), Locale.ShortFormat) + " " + clock.date.getDate() + " " + Qt.locale().standaloneMonthName(clock.date.getMonth(), Locale.ShortFormat)
    }

    // Its own child rather than punctuation glued to either label, so it takes
    // the row's spacing on both sides and lands centred between them — at half
    // that spacing, so the two parts read as one clock rather than as two things
    // the bar happened to put next to each other. A middle dot is very little
    // ink, so it goes a size up to carry the same weight as the rest.
    BarText {
        id: dot

        Layout.fillHeight: true
        fontSize: Theme.textSize + 1
        text: "\u00b7"
    }

    BarText {
        Layout.fillHeight: true
        Layout.leftMargin: root.dotGap
        text: Qt.formatDateTime(clock.date, "HH:mm")
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.MiddleButton) {
            // was: t=$(date '+%F %T'); wl-copy; notify-send
            // Not clock.date: that one only moves on the minute now, and a
            // timestamp is the one thing here that wants the seconds.
            const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss");
            Quickshell.clipboardText = stamp;
            Quickshell.execDetached(["notify-send", "Copied timestamp", stamp]);
        } else if (mouse.button === Qt.LeftButton) {
            Quickshell.execDetached([Quickshell.env("HOME") + "/_scripts/pwa-gcalendar.sh"]);
        }
    }
}
