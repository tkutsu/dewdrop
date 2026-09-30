import QtQuick
import QtQuick.Effects
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

    // The dot is a separator inside the clock, not a module of its own, so the
    // two parts sit half a gap apart and read as one thing.
    readonly property int joint: Theme.gap - Math.round(Theme.gap / 2)

    // The point the bar centres on: the time at rest, and the dot once the
    // date is out. Never the module as a whole, since no two month or weekday
    // names are the same length and the clock would creep left and right
    // under the bar. The marker rides the room's spring from one to the
    // other, so the time slides over as the date opens rather than jumping.
    readonly property alias centreItem: centre

    // Just the time at rest; pointed at, the pill opens out into the day and
    // the date as well. Held out while the calendar is up, which the pointer
    // leaves the pill to get to.
    readonly property bool dated: root.containsMouse || root.popupOpen

    // The date comes and goes the way the music pill takes a new track
    // (Music.swap): arriving, the room opens on the spring and the date comes
    // into focus as it does; going, it blurs out first and only then does the
    // room close, so the pill never shuts over words still being read.
    property bool shownDated: false
    property real dateOpacity: 0

    onDatedChanged: {
        if (dated) {
            leave.stop();
            shownDated = true;
            arrive.restart();
        } else {
            arrive.stop();
            leave.restart();
        }
    }

    NumberAnimation {
        id: arrive
        target: root
        property: "dateOpacity"
        to: 1
        duration: Theme.foldMs
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: leave

        NumberAnimation {
            target: root
            property: "dateOpacity"
            to: 0
            duration: Theme.fadeMs / 2
            easing.type: Easing.InQuad
        }
        PropertyAction {
            target: root
            property: "shownDated"
            value: false
        }
    }

    // The slot brings its own joint, so the two come and go together.
    spacing: 0

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
    // and the date are one label with a word space between them and the dot has
    // only the one joint to mark. standalone names rather than dayName/monthName
    // or the "MMM" of formatDateTime: a label on its own wants the nominative,
    // which only shows in a locale that inflects (the calendar header makes the
    // same call for its own title).
    //
    // Its room springs open and shut the way the music title's does, past its
    // width and back, and the pill's edge passes over the words, which stay
    // put beside the time.
    Item {
        id: room

        readonly property real full: date.implicitWidth + root.joint

        Layout.fillHeight: true
        implicitWidth: root.shownDated ? full : 0
        clip: width !== full

        Behavior on implicitWidth {
            SpringAnimation {
                spring: Theme.springStiffness
                damping: Theme.springDamping
                epsilon: 0.25
            }
        }

        // The time's middle when the room is shut, the dot's when it is open.
        // In here rather than on the time, which is a Row and would lay it out.
        Item {
            id: centre

            readonly property real open: room.full > 0 ? room.width / room.full : 0

            x: room.width + time.width / 2 - open * (time.width / 2 + root.joint + dot.width / 2)
        }

        // Blurred through a layer only while it comes and goes, so the date
        // at rest is drawn as it always was.
        Row {
            id: date

            anchors.right: parent.right
            anchors.rightMargin: root.joint
            height: parent.height
            spacing: root.joint
            opacity: root.dateOpacity
            scale: 0.92 + 0.08 * root.dateOpacity

            layer.enabled: root.dateOpacity < 1
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 12
                blur: 1 - root.dateOpacity
            }

            BarText {
                height: parent.height
                text: Qt.locale().standaloneDayName(clock.date.getDay(), Locale.ShortFormat) + " " + clock.date.getDate() + " " + Qt.locale().standaloneMonthName(clock.date.getMonth(), Locale.ShortFormat)
            }

            // Its own child rather than punctuation glued to either label, so
            // it lands centred between them — at half the row's spacing, so
            // the two parts read as one clock rather than as two things the
            // bar happened to put next to each other. A middle dot is very
            // little ink, so it goes a size up to carry the same weight as the
            // rest.
            BarText {
                id: dot

                height: parent.height
                fontSize: Theme.textSize + 1
                text: "·"
            }
        }
    }

    // The time rolls to its next minute the way a timer's figures do
    // (RollingText), and only the figures that change move.
    RollingText {
        id: time

        Layout.fillHeight: true
        text: Qt.formatDateTime(clock.date, Settings.timeFormat)
    }

    // Left is the calendar (BarItem.popupButton); right is the app.
    actions: ({
            [Qt.RightButton]: () => Quickshell.execDetached([Paths.script("pwa-gcalendar.sh")]),
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
