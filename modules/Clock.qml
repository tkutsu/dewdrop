import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The date opens the calendar; the neighbouring time opens timers.
BarItem {
    id: root

    popup: Calendar {}

    readonly property alias date: clock.date

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

    // Its countdown stops while the machine sleeps, so after a wake it still
    // shows the time it went down at until that runs out. Turned off and on,
    // it reads the clock again and schedules from now.
    Connections {
        target: WallClock

        function onWokeUp(): void {
            clock.enabled = false;
            clock.enabled = true;
        }
    }

    // The weekday and date are one label with a word space between them.
    // standalone names rather than dayName/monthName
    // or the "MMM" of formatDateTime: a label on its own wants the nominative,
    // which only shows in a locale that inflects (the calendar header makes the
    // same call for its own title).
    BarText {
        Layout.fillHeight: true
        text: Qt.locale().standaloneDayName(clock.date.getDay(), Locale.ShortFormat) + " " + clock.date.getDate() + " " + Qt.locale().standaloneMonthName(clock.date.getMonth(), Locale.ShortFormat)
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
