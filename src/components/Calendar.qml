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
    Component.onCompleted: {
        Agenda.ensure(shown);
        Qt.callLater(root.settle);
    }
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

    // This many rows show, and the rest are a scroll away. The window keeps
    // the height of a full list regardless, so the box grows and shrinks
    // inside it as days are picked rather than the whole popup resizing on
    // every click (see Popup.reserveHeight).
    readonly property int listRows: 5
    readonly property int listRowHeight: 22
    readonly property int dotSize: 3
    // The time column fits the widest time, 12:30 PM or 12:30, and "in 59m".
    readonly property int timeWidth: Math.max(42, Math.ceil(Math.max(widestTime.advanceWidth, widestSoon.advanceWidth)) + 2)

    TextMetrics {
        id: widestTime
        font.family: Theme.bodyFont
        font.pixelSize: Theme.captionSize
        font.features: Theme.figures
        text: Settings.sayHourMinute(12, 30)
    }

    TextMetrics {
        id: widestSoon
        font: widestTime.font
        text: "in 59m"
    }

    // --- now and next, on today ---------------------------------------------
    // The time by the minute, so the rows reconsider once a minute rather
    // than on every one of WallClock's five-second ticks.
    readonly property double now: Math.floor(WallClock.now / 60000) * 60000
    readonly property bool showingToday: root.selected === Agenda.today

    function isOver(ev: var): bool {
        return root.showingToday && !ev.allDay && ev.end <= root.now;
    }

    function isNow(ev: var): bool {
        return root.showingToday && !ev.allDay && ev.start <= root.now && root.now < ev.end;
    }

    // The first of today's timed events still to start.
    readonly property var upNext: root.showingToday ? list.events.find(ev => !ev.allDay && ev.start > root.now) ?? null : null

    // A delegate's modelData is a copy, so the event is matched, not compared.
    function isNext(ev: var): bool {
        return !!root.upNext && ev.id === root.upNext.id && ev.start === root.upNext.start;
    }

    // A Join button that is always out: on the call under way, and on the
    // next one from ten minutes before it.
    function joinShown(ev: var): bool {
        return !!ev.link && (root.isNow(ev) || (root.isNext(ev) && ev.start - root.now <= 10 * 60000));
    }

    // What the time column says: "now", "in 25m" inside the hour, or the time.
    function sayWhen(ev: var): string {
        if (root.isNow(ev))
            return "now";
        if (root.isNext(ev) && ev.start - root.now < 3600000)
            return `in ${Math.max(1, Math.ceil((ev.start - root.now) / 60000))}m`;
        return "";
    }

    // Opening the popup, or picking today again, shows the first event not yet
    // over at the top, with the morning's a scroll up. Any other day starts at
    // its top.
    function settle(): void {
        const events = list.events;
        const live = events.findIndex(ev => !ev.allDay && ev.end > root.now);
        const overBefore = root.showingToday && events.slice(0, live < 0 ? events.length : live).some(ev => !ev.allDay);
        if (!overBefore)
            rows.contentY = rows.originY;
        else if (live < 0)
            rows.positionViewAtEnd();
        else
            rows.positionViewAtIndex(live, ListView.Beginning);
    }

    onSelectedChanged: Qt.callLater(root.settle)

    // Out to the event's own page in the Calendar app.
    function openEvent(ev: var): void {
        OpenPopup.dismiss();
        Quickshell.execDetached(Settings.webApp("calendar", ev.url, ev.url));
    }

    function join(ev: var): void {
        OpenPopup.dismiss();
        Qt.openUrlExternally(ev.link);
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
        // The most the list can take: a page of rows.
        readonly property real fullHeight: root.listRowHeight * root.listRows

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

        // An empty day from today on says what comes after it, from the
        // months already held; a tap goes to that day.
        EventRow {
            id: nextUp

            readonly property var upcoming: list.events.length === 0 && Agenda.loaded && Agenda.trouble === "" && root.selected >= Agenda.today
                ? Agenda.next(root.selected) : null
            readonly property date upcomingDay: new Date(nextUp.upcoming?.start ?? 0)

            visible: nextUp.upcoming !== null
            ev: nextUp.upcoming ?? ({})
            lead: "Next"
            aside: !nextUp.upcoming ? "" : Qt.formatDate(nextUp.upcomingDay, "ddd d MMM")
                + (nextUp.upcoming.allDay ? "" : " · " + Settings.sayTime(nextUp.upcomingDay))
            name: nextUp.upcoming ? "Show " + root.sayDay(Agenda.dayString(nextUp.upcomingDay)) : ""
            onTapped: root.select(nextUp.upcomingDay)
        }

        ListView {
            id: rows

            width: list.width
            height: Math.min(contentHeight, list.fullHeight)
            visible: count > 0
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            SmoothScroll {
                view: rows
            }
            layer.enabled: contentHeight > height
            layer.effect: ScrollEdges {
                view: rows
            }
            Accessible.role: Accessible.List
            Accessible.name: "Events"
            Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
            Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

            model: list.events
            onModelChanged: Qt.callLater(root.settle)

            delegate: EventRow {
                required property var modelData

                ev: modelData
                dim: root.isOver(modelData)
                lead: modelData.allDay ? "all day" : root.sayWhen(modelData)
                aside: modelData.place && !modelData.link ? modelData.place : ""
                // Only an event Google gave a page for opens.
                name: modelData.url ? "Open " + modelData.title : ""
                onTapped: root.openEvent(modelData)
            }
        }
    }

    // One line of the list: the time (or "now", "in 25m"), the calendar's
    // colour, the title with anything else in grey after it, and Join for an
    // event with a call. The event on now draws how far through it is.
    component EventRow: PopupRow {
        id: row

        property var ev: ({})
        // In the time column instead of the time; empty shows the time.
        property string lead: ""
        property string aside: ""
        // Over, today: drawn faint, the way a ticked-off task is.
        property bool dim: false

        readonly property bool live: root.isNow(row.ev)
        readonly property int textX: Theme.popupInset + root.timeWidth + 14

        width: ListView.view ? ListView.view.width : list.width
        height: root.listRowHeight
        opacity: row.dim ? 0.4 : 1
        acceptsTap: row.name !== ""

        PopupText {
            x: Theme.popupInset
            width: root.timeWidth
            height: row.height
            verticalAlignment: Text.AlignVCenter
            textFormat: row.lead !== "" ? Text.PlainText : Text.RichText
            text: row.lead !== "" ? row.lead : Settings.timeMarkup(Settings.hourDisplay(new Date(row.ev.start ?? 0)), font.pixelSize)
            color: row.live || (row.lead !== "" && root.isNext(row.ev)) ? Theme.fg : row.lead === "all day" || row.lead === "Next" ? Theme.label3 : Theme.label2
            font.pixelSize: Theme.captionSize
        }

        // Which calendar it is on, in the colour Google gives that calendar.
        Rectangle {
            x: Theme.popupInset + root.timeWidth + 4
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 14
            radius: 1.5
            color: row.ev.colour || Theme.label3
        }

        Row {
            id: words

            x: row.textX
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            readonly property real room: (join.visible ? join.x - 4 : row.width - Theme.popupInset) - x

            PopupText {
                id: title
                width: Math.min(implicitWidth, words.room)
                text: row.ev.title ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }

            PopupText {
                anchors.baseline: title.baseline
                width: Math.max(0, words.room - title.width - words.spacing)
                visible: row.aside !== "" && width > 20
                text: row.aside
                textFormat: Text.PlainText
                color: Theme.label3
                font.pixelSize: Theme.captionSize
                elide: Text.ElideRight
            }
        }

        PopupButton {
            id: join

            x: row.width - Theme.popupInset - width + 4
            anchors.verticalCenter: parent.verticalCenter
            visible: !!row.ev.link && (row.hovered || root.joinShown(row.ev))
            glyph: Theme.glyph.join
            name: "Join " + (row.ev.title ?? "")
            onTapped: root.join(row.ev)
        }

        // How far through the event under way it is.
        Rectangle {
            visible: row.live
            x: row.textX
            y: row.height - 3
            width: row.width - Theme.popupInset - x
            height: 2
            radius: 1
            color: Theme.selection

            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, (root.now - (row.ev.start ?? 0)) / Math.max(1, (row.ev.end ?? 1) - (row.ev.start ?? 0))))
                height: parent.height
                radius: 1
                color: row.ev.colour || Theme.label2
            }
        }
    }
}
