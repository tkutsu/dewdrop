import QtQuick
import Quickshell
import qs.src.core
import qs.src.services

// The clock's month view. waybar rendered this as a <tt> block inside a Pango
// tooltip, which is why it could only ever be text; a real grid can show the
// months either side, take a click to step through them, and say what today is.
//
// A day is chosen with a click and stays chosen while the pointer goes down
// to its list, the way a Mac's month view works; the header's buttons act on
// that day.
Popup {
    id: root

    // Months from "now", the way waybar's shift_up/shift_down worked.
    property int offset: 0
    // Agenda's day, which turns at midnight, so a popup left open across it
    // moves its ring with the list underneath. Built from its parts: parsed
    // whole, "YYYY-MM-DD" is midnight in UTC rather than here.
    readonly property date today: root.dateOf(Agenda.today)
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + offset, 1)

    // The month turned to is fetched as it comes into view, if it has not
    // been already.
    onShownChanged: Agenda.ensure(shown)
    Component.onCompleted: Agenda.ensure(shown)
    Component.onDestruction: Agenda.lastShown = ""

    // The day the list is about. Nothing picked is today, so every open
    // starts there and a popup left open across midnight moves on with it.
    property string picked: ""
    readonly property string selected: root.picked !== "" ? root.picked : Agenda.today
    readonly property date selectedDate: root.dateOf(root.selected)

    function dateOf(key: string): date {
        const [y, m, d] = key.split("-").map(Number);
        return new Date(y, m - 1, d);
    }

    // A faint day from the month either side turns the grid to it as well.
    function select(day: date): void {
        const key = Agenda.dayString(day);
        root.picked = key === Agenda.today ? "" : key;
        root.offset += (day.getFullYear() - root.shown.getFullYear()) * 12 + day.getMonth() - root.shown.getMonth();
    }

    function goToday(): void {
        root.offset = 0;
        root.picked = "";
    }

    // The list's heading: the near days by name, the rest in full.
    function sayDay(key: string): string {
        const away = Math.round((root.dateOf(key) - root.today) / 86400000);
        if (away === 0)
            return "Today";
        if (away === 1)
            return "Tomorrow";
        if (away === -1)
            return "Yesterday";
        const day = root.dateOf(key);
        return Qt.formatDate(day, day.getFullYear() === root.today.getFullYear() ? "dddd d MMMM" : "dddd d MMMM yyyy");
    }

    // At most this many rows, and the box stops under the last one. The
    // window keeps the height of a full list regardless, so the box grows and
    // shrinks inside it as days are picked rather than the whole popup
    // resizing on every click (see Popup.reserveHeight).
    readonly property int listRows: 4
    readonly property int listRowHeight: 20
    readonly property int dotSize: 3
    // The time column fits the widest time, 12:30 PM or 12:30.
    readonly property int timeWidth: Math.max(42, Math.ceil(widestTime.advanceWidth) + 2)

    TextMetrics {
        id: widestTime
        font.family: Theme.bodyFont
        font.pixelSize: Theme.captionSize
        font.features: Theme.figures
        text: Settings.sayHourMinute(12, 30)
    }

    reserveHeight: list.visible ? chromeHeight - list.height + list.fullHeight : 0

    readonly property var locale: Qt.locale()
    readonly property int firstDay: locale.firstDayOfWeek

    // The grid spans the popup: seven whole-pixel columns, the odd pixels
    // split either side, and the discs keep their size inside wider cells.
    readonly property int cellWidth: Math.floor(Theme.popupWidth / 7)
    readonly property int cellHeight: 30
    readonly property int disc: 26

    function step(months: int): void {
        root.offset += months;
    }

    // A new task or event on that day, typed in the launcher: a title alone
    // is a task due then, a time and a title an event.
    function addOn(day: date): void {
        OpenPopup.dismiss();
        Launcher.openWith(Launcher.taskPrefix + " " + Agenda.dayString(day) + " ");
    }

    function openDay(day: date): void {
        OpenPopup.dismiss();
        const url = `https://calendar.google.com/calendar/r/day/${day.getFullYear()}/${day.getMonth() + 1}/${day.getDate()}`;
        // The same app the clock's own click opens, pointed at one day rather
        // than at wherever it was left.
        Quickshell.execDetached(Settings.webApp("calendar", url, url));
    }

    // The date in any cell of the grid, which starts on the week holding the
    // 1st of the month.
    readonly property int lead: (root.shown.getDay() - root.firstDay + 7) % 7

    function cellDate(index: int): date {
        return new Date(root.shown.getFullYear(), root.shown.getMonth(), 1 + index - root.lead);
    }

    // --- header: month, New, ‹ • ›, out to the app ----------------------------
    PopupHeader {
        width: Theme.popupWidth
        title: root.locale.standaloneMonthName(root.shown.getMonth(), Locale.LongFormat) + " " + root.shown.getFullYear()
        addable: Agenda.configured
        addName: "New task or event"
        onAdd: root.addOn(root.selectedDate)

        // One stepper, its three targets touching, so it reads apart from
        // the framed buttons either side.
        Row {
            anchors.verticalCenter: parent.verticalCenter

            PopupButton {
                glyph: Theme.glyph.monthBack
                name: "Previous month"
                onTapped: root.step(-1)
            }

            // Back to this month and today. Faint while already there.
            PopupButton {
                glyph: Theme.glyph.today
                name: "Today"
                live: root.offset !== 0 || root.picked !== ""
                onTapped: root.goToday()
            }

            PopupButton {
                glyph: Theme.glyph.monthOn
                name: "Next month"
                onTapped: root.step(1)
            }
        }

        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            name: "Open Google Calendar"
            onTapped: root.openDay(root.selectedDate)
        }
    }

    // --- the month --------------------------------------------------------------
    Column {
        x: Math.floor((Theme.popupWidth - root.cellWidth * 7) / 2)
        spacing: 2

        Row {
            Repeater {
                model: 7

                PopupText {
                    required property int index

                    width: root.cellWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.locale.dayName((root.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
                    color: Theme.label2
                    font.pixelSize: Theme.captionSize
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
                    readonly property bool isSelected: dayKey === root.selected
                    // A dot marks a day with calendar events.
                    readonly property bool busy: Agenda.has(dayKey, Agenda.monthKey(root.shown))

                    width: root.cellWidth
                    height: root.cellHeight

                    // The chosen day holds the strong grey; the one under the
                    // pointer or the keys the light one. Today keeps its own.
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.disc
                        height: width
                        radius: width / 2
                        visible: !dayCell.isToday && (dayCell.isSelected || dayCell.lit)
                        color: dayCell.isSelected ? Theme.selectionStrong : Theme.selection
                    }

                    // The keys (Popup.qml) light a day the way the pointer
                    // does, and Return picks it.
                    property bool keyed: false
                    readonly property var keyPress: () => root.select(dayCell.day)
                    readonly property bool lit: QsWindow.window?.keyItem ? dayCell.keyed : dayHover.hovered

                    HoverHandler {
                        id: dayHover
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: Qt.formatDateTime(dayCell.day, "dddd d MMMM yyyy")
                    Accessible.description: "Pointer: click selects, double-click opens it in Google Calendar; right-click adds a task or event"
                    Accessible.selected: dayCell.isSelected
                    Accessible.onPressAction: if (enabled && visible)
                        root.select(dayCell.day)

                    // The second click of a double opens the day it picked;
                    // a faint day has turned the month by then, so the cell
                    // under the pointer is checked against it.
                    TapHandler {
                        onTapped: if (tapCount > 1 && dayCell.isSelected)
                            root.openDay(dayCell.day);
                        else
                            root.select(dayCell.day)
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: root.addOn(dayCell.day)
                    }

                    // Today gets a filled disc rather than an underline: at
                    // this size an underline is one grey pixel. Its numeral
                    // and dot are black on it.
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.disc
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
                        font.pixelSize: Theme.popupTextSize
                        font.weight: dayCell.isToday || dayCell.isSelected ? Font.DemiBold : Font.Normal
                    }

                    // Something is on that day. One dot whether it is one
                    // thing or six: the list below says how many, and a
                    // count under every numeral would be a second grid.
                    // On a disc (today, the chosen day) it rises inside it.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: dayCell.isToday || dayCell.isSelected ? 5 : 1
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

    // --- the chosen day's events ----------------------------------------------
    // Present only once Google is connected: without it the popup is the
    // month view it always was.
    PopupSection {
        width: Theme.popupWidth
        visible: Agenda.configured
        title: root.sayDay(root.selected)

        RetryButton {
            service: Agenda
        }

        ReconnectButton {}
    }

    Column {
        id: list

        visible: Agenda.configured
        width: Theme.popupWidth
        spacing: 0

        readonly property var events: Agenda.forDay(root.selected)
        // The most the list can take: a full page and the "more" line.
        readonly property real fullHeight: root.listRowHeight * (root.listRows + 1)

        PopupNote {
            width: list.width
            visible: Agenda.trouble !== ""
            text: Agenda.trouble
            warn: true
            font.pixelSize: Theme.footnoteSize
        }

        PopupNote {
            width: list.width
            height: Math.max(root.listRowHeight, implicitHeight)
            verticalAlignment: Text.AlignVCenter
            visible: Agenda.trouble === "" && list.events.length === 0
            text: Agenda.loaded ? "No events" : "Connecting…"
        }

        Repeater {
            model: list.events.slice(0, root.listRows)

            Item {
                id: entry

                required property var modelData

                x: Theme.popupInset
                width: list.width - Theme.popupInset * 2
                height: root.listRowHeight

                PopupText {
                    width: root.timeWidth
                    height: root.listRowHeight
                    verticalAlignment: Text.AlignVCenter
                    textFormat: entry.modelData.allDay ? Text.PlainText : Text.RichText
                    text: entry.modelData.allDay ? Agenda.sayTime(entry.modelData)
                        : Settings.timeMarkup(Settings.hourDisplay(new Date(entry.modelData.start)), font.pixelSize)
                    color: entry.modelData.allDay ? Theme.label3 : Theme.label2
                    font.pixelSize: Theme.captionSize
                }

                PopupText {
                    x: root.timeWidth + 8
                    width: entry.width - x
                    height: root.listRowHeight
                    verticalAlignment: Text.AlignVCenter
                    text: entry.modelData.title
                    elide: Text.ElideRight
                }
            }
        }

        PopupText {
            x: Theme.popupInset
            visible: list.events.length > root.listRows
            height: root.listRowHeight
            verticalAlignment: Text.AlignVCenter
            text: `+${list.events.length - root.listRows} more`
            color: Theme.label3
            font.pixelSize: Theme.captionSize
        }
    }
}
