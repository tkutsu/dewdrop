import QtQuick
import Quickshell
import qs
import qs.services

// The clock's month view. waybar rendered this as a <tt> block inside a Pango
// tooltip, which is why it could only ever be text; a real grid can show the
// months either side, take a click to step through them, and say what today is.
Popup {
    id: root

    // Months from "now", the way waybar's shift_up/shift_down worked.
    property int offset: 0
    readonly property date today: new Date()
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + offset, 1)

    // The month turned to is fetched as it comes into view, if it has not
    // been already.
    onShownChanged: Agenda.ensure(shown)
    Component.onCompleted: Agenda.ensure(shown)

    // The day the list under the grid is about: the one under the pointer,
    // or today. A dot says a day has something on it; resting on the day says
    // what, without leaving the popup for the app.
    property string hoverDay: ""
    readonly property string listDay: hoverDay !== "" ? hoverDay : Agenda.today

    // A fixed number of rows, so the popup is the same height whatever day
    // is under the pointer: a popup that resized on hover would jerk on every
    // cell (see Popup.reserveHeight).
    readonly property int listRows: 4
    readonly property int listRowHeight: 18
    readonly property int dotSize: 3

    readonly property var locale: Qt.locale()
    readonly property int firstDay: locale.firstDayOfWeek

    readonly property real cell: 24
    readonly property int fontSize: Theme.popupTextSize

    // The column of week numbers down the left. Narrower than a day: it is a
    // margin note, not an eighth day.
    readonly property real weekWidth: 20

    // Google Calendar, the same app the clock's own click opens (see
    // ~/_scripts/pwa-gcalendar.sh, which holds this id too), but pointed at
    // one day rather than at wherever it was left.
    readonly property string calendarApp: "kjbdgfilnfhdoflbpgamdcdgpehopbep"

    function step(months) {
        offset += months;
    }

    function openDay(day) {
        const url = `https://calendar.google.com/calendar/r/day/${day.getFullYear()}/${day.getMonth() + 1}/${day.getDate()}`;
        Quickshell.execDetached(["chromium", "--profile-directory=Default", "--app-id=" + root.calendarApp, "--app-launch-url-for-shortcuts-menu-item=" + url]);
    }

    // ISO 8601: weeks start on Monday, and week 1 is the one with the year's
    // first Thursday in it — so a week belongs to whichever year its Thursday
    // does, which is how a date in late December can be in week 1.
    function isoWeek(day) {
        const thursday = new Date(day.getFullYear(), day.getMonth(), day.getDate() - (day.getDay() + 6) % 7 + 3);
        const jan1 = new Date(thursday.getFullYear(), 0, 1);
        return 1 + Math.floor(Math.round((thursday - jan1) / 86400000) / 7);
    }

    // The date in any cell of the grid, which starts on the week holding the
    // 1st of the month.
    readonly property int lead: (root.shown.getDay() - root.firstDay + 7) % 7

    function cellDate(index) {
        return new Date(root.shown.getFullYear(), root.shown.getMonth(), 1 + index - root.lead);
    }

    Column {
        spacing: 5

        // --- header: ‹ month year › ---------------------------------------
        // Over the days and not the week column, like everything above the
        // grid: the column is a note in its margin.
        Item {
            x: root.weekWidth
            width: root.cell * 7
            height: title.implicitHeight + 2

            PopupText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                opacity: backHover.hovered ? 1 : 0.5
                font.pixelSize: root.fontSize + 2
                HoverHandler {
                    id: backHover
                }
                TapHandler {
                    onTapped: root.step(-1)
                }
            }

            PopupText {
                id: title
                anchors.centerIn: parent
                text: root.locale.standaloneMonthName(root.shown.getMonth(), Locale.LongFormat) + " " + root.shown.getFullYear()
                font.weight: Font.DemiBold

                // Clicking the title comes back to the current month, which is
                // otherwise a lot of arrow presses away.
                TapHandler {
                    onTapped: root.offset = 0
                }
            }

            PopupText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                opacity: forwardHover.hovered ? 1 : 0.5
                font.pixelSize: root.fontSize + 2
                HoverHandler {
                    id: forwardHover
                }
                TapHandler {
                    onTapped: root.step(1)
                }
            }
        }

        Row {
            x: root.weekWidth

            Repeater {
                model: 7

                PopupText {
                    required property int index

                    width: root.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: root.locale.dayName((root.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
                    color: Theme.label2
                }
            }
        }

        Row {
            // The week numbers. The footer that used to sit under the grid said
            // "Saturday 26 September" under a header that already said September
            // and a disc that already said 26; this is the one fact about the
            // month that nothing else here shows.
            Column {
                Repeater {
                    model: 6

                    PopupText {
                        required property int index

                        width: root.weekWidth
                        height: root.cell
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignLeft
                        // The Monday of the row, which is the day ISO numbers a
                        // week by whichever day the locale starts its rows on.
                        text: root.isoWeek(root.cellDate(index * 7 + (8 - root.firstDay) % 7))
                        color: Theme.label3
                        font.pixelSize: root.fontSize - 2
                    }
                }
            }

            Grid {
                columns: 7

                Repeater {
                    // Six rows always, so the popup does not resize as the months
                    // go by.
                    model: 42

                    Item {
                        id: dayCell

                        required property int index

                        readonly property date day: root.cellDate(index)
                        readonly property bool thisMonth: day.getMonth() === root.shown.getMonth()
                        readonly property bool isToday: day.toDateString() === root.today.toDateString()
                        readonly property string dayKey: Agenda.dayString(day)
                        readonly property bool busy: Agenda.has(dayKey)

                        width: root.cell
                        height: root.cell

                        // A click opens that day in the calendar, and the pointer
                        // says so first with the same fill any other clickable
                        // row gets under it.
                        Rectangle {
                            anchors.centerIn: parent
                            width: root.cell - 4
                            height: width
                            radius: width / 2
                            visible: dayHover.hovered && !dayCell.isToday
                            color: Theme.selection
                        }

                        HoverHandler {
                            id: dayHover
                            onHoveredChanged: {
                                if (hovered)
                                    root.hoverDay = dayCell.dayKey;
                                else if (root.hoverDay === dayCell.dayKey)
                                    root.hoverDay = "";
                            }
                        }

                        TapHandler {
                            onTapped: root.openDay(dayCell.day)
                        }

                        // Today gets a filled pill rather than an underline: at this
                        // size an underline is one grey pixel.
                        // Today is a filled disc with the number cut out of it,
                        // the way the system's calendar marks it.
                        Rectangle {
                            anchors.centerIn: parent
                            width: root.cell - 4
                            height: width
                            radius: width / 2
                            visible: dayCell.isToday
                            color: Theme.calToday
                        }

                        PopupText {
                            anchors.centerIn: parent
                            text: dayCell.day.getDate()
                            // The days either side are context, not padding — worth
                            // showing, faintly, so a month boundary reads at a glance.
                            color: dayCell.isToday ? Theme.calTodayText : (dayCell.thisMonth ? Theme.fg : Theme.label3)
                            font.weight: dayCell.isToday ? Font.DemiBold : Font.Normal
                        }

                        // Something is on that day. One dot whether it is one
                        // thing or six: the list below says how many, and a
                        // count under every numeral would be a second grid.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            width: root.dotSize
                            height: width
                            radius: width / 2
                            visible: dayCell.busy
                            color: dayCell.isToday ? Theme.calTodayText : (dayCell.thisMonth ? Theme.label2 : Theme.label3)
                        }
                    }
                }
            }
        }
    
        // --- the day's events ---------------------------------------------
        // Under the grid, for the day under the pointer or today. Present
        // only once Google is connected: without it the popup is the month
        // view it always was.
        Column {
            visible: Agenda.configured
            x: root.weekWidth
            width: root.cell * 7
            height: root.listRowHeight * root.listRows + 6
            topPadding: 6
            spacing: 0

            readonly property var events: Agenda.forDay(root.listDay)

            // Wraps rather than elides: the one long thing that lands here
            // is the reconnect message, which is no use cut short.
            PopupText {
                visible: parent.events.length === 0
                width: parent.width
                height: root.listRowHeight * root.listRows
                verticalAlignment: Text.AlignTop
                text: !Agenda.loaded ? (Agenda.trouble !== "" ? Agenda.trouble : "Connecting…") : (root.listDay === Agenda.today ? "Nothing today" : "Nothing on")
                color: Theme.label3
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: parent.events.slice(0, root.listRows)

                Row {
                    required property var modelData

                    height: root.listRowHeight
                    spacing: 8

                    PopupText {
                        width: 42
                        height: root.listRowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: Agenda.sayTime(modelData)
                        color: modelData.allDay ? Theme.label3 : Theme.label2
                        font.pixelSize: root.fontSize - 1
                    }

                    PopupText {
                        width: root.cell * 7 - 50
                        height: root.listRowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.title
                        elide: Text.ElideRight
                    }
                }
            }

            PopupText {
                visible: parent.events.length > root.listRows
                height: root.listRowHeight
                verticalAlignment: Text.AlignVCenter
                text: `+${parent.events.length - root.listRows} more`
                color: Theme.label3
                font.pixelSize: root.fontSize - 1
            }
        }
    }
}
