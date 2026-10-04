import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// clock#time. The calendar the Pango tooltip used to draw as a <tt> block is a
// real grid now, opened by a click.
BarItem {
    id: root

    popup: Calendar {}

    // Each label claims half the row spacing next to the centre anchor.
    readonly property int centreMargin: -Math.round(Theme.gap / 2)

    // The point the bar centres on. Both labels change width — the day number
    // carries one digit or two, and no two month or weekday names are the same
    // length — so centring the module as a whole would leave the clock creeping
    // left and right under it. Pinning the gap between them keeps it still.
    readonly property alias centreItem: centreGap

    // Up is the next month and down the one before, the way round every
    // wheel on the bar goes.
    onScrollUp: if (popupItem)
        popupItem.offset++
    onScrollDown: if (popupItem)
        popupItem.offset--

    // Singletons are lazy, and nothing reads Agenda until the popup opens —
    // so without this the calendar would not be fetched until the first click,
    // and would open on "Connecting…" every time the shell started.
    Component.onCompleted: Agenda.ensure(new Date())

    SystemClock {
        id: clock
        // By the minute unless the format shows seconds: at Seconds this
        // re-evaluated the date and the time, on every bar, sixty times for
        // each time it could possibly have mattered.
        precision: Settings.timeFormat.includes("s") ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Which day, then what time — two facts rather than three, so the weekday
    // and the date are one label with a word space between them.
    // standalone names rather than dayName/monthName
    // or the "MMM" of formatDateTime: a label on its own wants the nominative,
    // which only shows in a locale that inflects (the calendar header makes the
    // same call for its own title).
    BarText {
        Layout.fillHeight: true
        Layout.rightMargin: root.centreMargin
        text: Qt.locale().standaloneDayName(clock.date.getDay(), Locale.ShortFormat) + " " + clock.date.getDate() + " " + Qt.locale().standaloneMonthName(clock.date.getMonth(), Locale.ShortFormat)
    }

    // A zero-width anchor keeps the date/time gap centred without punctuation.
    Item {
        id: centreGap

        Layout.fillHeight: true
        Layout.preferredWidth: 0
        Layout.maximumWidth: 0
    }

    // The time rolls to its next minute the way a timer's figures do
    // (RollingText), and only the figures that change move.
    RollingText {
        Layout.fillHeight: true
        Layout.leftMargin: root.centreMargin
        text: Qt.formatDateTime(clock.date, Settings.timeFormat)
    }

    // Left is the calendar (BarItem.popupButton); right is the app.
    actions: ({
            [Qt.RightButton]: () => {
                OpenPopup.dismiss();
                Quickshell.execDetached([Paths.script("pwa-gcalendar.sh")]);
            },
            [Qt.MiddleButton]: () => {
                // was: t=$(date '+%F %T'); wl-copy; notify-send
                // Not clock.date: that one only moves on the minute now, and a
                // timestamp is the one thing here that wants the seconds.
                const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss");
                Quickshell.clipboardText = stamp;
                Quickshell.execDetached(["notify-send", "Copied timestamp", stamp]);
            }
        })
}
