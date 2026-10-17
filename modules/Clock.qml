import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The date opens the calendar.
BarItem {
    id: root
    name: "Calendar"
    textPress: true
    Layout.leftMargin: -1
    Layout.rightMargin: -1

    popup: Calendar {}

    // What is left of today: the all-day ones, then what is on now, then
    // what is still to come. Nothing to say once the day's last has ended.
    tooltip: Agenda.todays.filter(ev => ev.allDay || ev.end > WallClock.now)
        .map(ev => `${ev.allDay ? "All day" : ev.start <= WallClock.now ? "Now" : Agenda.sayTime(ev)} · ${ev.title}`)
        .join("\n")

    readonly property alias date: clock.date

    // Up is the next month and down the one before, the way round every
    // wheel on the bar goes.
    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
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

    // Date format letters use Qt's localized weekday and month names.
    BarText {
        Layout.fillHeight: true
        tightWidth: true
        text: Settings.applyCase(Qt.formatDate(clock.date, Settings.dateFormat), Settings.dateCase)
    }

    // Left is the calendar (BarItem.popupButton); right is the app.
    actions: ({
            [Qt.RightButton]: () => {
                OpenPopup.dismiss();
                Quickshell.execDetached(Settings.webApp("calendar", "", "https://calendar.google.com/"));
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
