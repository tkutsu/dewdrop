import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services

// The clock's month view. waybar rendered this as a <tt> block inside a Pango
// tooltip, which is why it could only ever be text; a real grid can show the
// months either side, take a click to step through them, and say what today is.
Popup {
    id: root

    // Its parts touch; the air is their own.
    spacing: 0

    // Months from "now", the way waybar's shift_up/shift_down worked.
    property int offset: 0
    // Agenda's day, which turns at midnight, so a popup left open across it
    // moves its ring with the list underneath. Built from its parts: parsed
    // whole, "YYYY-MM-DD" is midnight in UTC rather than here.
    readonly property date today: {
        const [y, m, d] = Agenda.today.split("-").map(Number);
        return new Date(y, m - 1, d);
    }
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + offset, 1)

    // The month turned to is fetched as it comes into view, if it has not
    // been already.
    onShownChanged: Agenda.ensure(shown)
    Component.onCompleted: Agenda.ensure(shown)
    Component.onDestruction: Agenda.lastShown = ""

    // The day the list under the grid is about: the one under the pointer,
    // or today. A dot says a day has something on it; resting on the day says
    // what, without leaving the popup for the app.
    property string hoverDay: ""
    readonly property string listDay: hoverDay !== "" ? hoverDay : Agenda.today
    // The day under the pointer or the keys right now. Moving off it to the
    // list below keeps its list, so its tasks can be ticked off there.
    property string litDay: ""

    // Dated tasks are in the day's list too, after its events, though only an
    // event earns a day its dot. Subtasks stay with their parent.
    readonly property var tasksByDay: {
        const map = ({});
        for (const task of Tasks.topLevel) {
            const day = Tasks.dayOf(task);
            if (day !== "")
                map[day] = (map[day] ?? []).concat([task]);
        }
        return map;
    }

    onRequestedVisibleChanged: if (!requestedVisible)
        Tasks.commit()

    Timer {
        id: letGo
        interval: 150
        onTriggered: {
            const key = QsWindow.window?.keyItem;
            if (!listHover.hovered && key?.parent !== list)
                root.hoverDay = root.litDay;
        }
    }

    // At most this many rows, and the box stops under the last one. The
    // window keeps the height of a full list regardless, so the box grows and
    // shrinks inside it as the pointer crosses the grid rather than the whole
    // popup resizing on every cell (see Popup.reserveHeight).
    readonly property int listRows: 4
    readonly property int listRowHeight: 20
    readonly property int dotSize: 3

    // The window is held at the height of a full list; the box stops under
    // whatever the day actually has.
    reserveHeight: list.visible ? chromeHeight - list.height + list.fullHeight : 0

    readonly property var locale: Qt.locale()
    readonly property int firstDay: locale.firstDayOfWeek

    readonly property real cell: 28

    function step(months) {
        offset += months;
    }

    // One of the header's arrows: a day cell's worth of target round a
    // chevron, lit on hover the way a day is.
    component MonthStep: Item {
        id: arrow

        property alias text: glyph.text
        property string name: ""
        signal step

        width: root.cell
        height: root.cell

        Rectangle {
            anchors.centerIn: parent
            width: root.cell - 4
            height: width
            radius: width / 2
            visible: arrowHover.hovered
            color: Theme.selection
        }

        PopupText {
            id: glyph
            anchors.centerIn: parent
            // Up a pixel: the guillemet sits high in Inter's box.
            anchors.verticalCenterOffset: -1
            opacity: arrowHover.hovered ? 1 : 0.6
            font.pixelSize: Theme.popupTextSize + 4
        }

        HoverHandler {
            id: arrowHover
        }

        Accessible.role: Accessible.Button
        Accessible.name: arrow.name
        Accessible.onPressAction: if (enabled && visible)
            arrow.step()
        readonly property var keyPress: () => arrow.step()

        TapHandler {
            onTapped: arrow.step()
        }
    }

    // A new task or event on that day, typed in the launcher: a title alone
    // is a task due then, a time and a title an event.
    function addOn(day) {
        OpenPopup.dismiss();
        Launcher.openWith(Launcher.taskPrefix + " " + Agenda.dayString(day) + " ");
    }

    function openDay(day) {
        OpenPopup.dismiss();
        const url = `https://calendar.google.com/calendar/r/day/${day.getFullYear()}/${day.getMonth() + 1}/${day.getDate()}`;
        // The same app the clock's own click opens, pointed at one day rather
        // than at wherever it was left.
        Quickshell.execDetached(Settings.webApp("calendar", url, url));
    }

    // The date in any cell of the grid, which starts on the week holding the
    // 1st of the month.
    readonly property int lead: (root.shown.getDay() - root.firstDay + 7) % 7

    function cellDate(index) {
        return new Date(root.shown.getFullYear(), root.shown.getMonth(), 1 + index - root.lead);
    }

    Column {
        spacing: 5

        RetryButton {
            anchors.right: parent.right
            service: Agenda
        }

        // --- header: ‹ month year › ---------------------------------------
        // The arrows stand over the first and last columns and are a whole
        // day cell each, with the same hover disc a day gets: a bare chevron
        // was a few pixels of ink to aim at.
        Item {
            width: root.cell * 7
            height: root.cell

            MonthStep {
                anchors.left: parent.left
                text: "‹"
                name: "Previous month"
                onStep: root.step(-1)
            }

            PopupText {
                id: title
                anchors.centerIn: parent
                text: root.locale.standaloneMonthName(root.shown.getMonth(), Locale.LongFormat) + " " + root.shown.getFullYear()
                font.weight: Font.DemiBold

                // Clicking the title comes back to the current month, which is
                // otherwise a lot of arrow presses away.
                Accessible.role: Accessible.Button
                Accessible.name: "Current month"
                Accessible.onPressAction: if (enabled && visible)
                    root.offset = 0
                readonly property var keyPress: () => root.offset = 0

                TapHandler {
                    onTapped: root.offset = 0
                }
            }

            MonthStep {
                anchors.right: parent.right
                text: "›"
                name: "Next month"
                onStep: root.step(1)
            }
        }

        Row {
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
                    // Events only: a day with nothing but tasks keeps a bare
                    // numeral, and its tasks are in the list when it is rested on.
                    readonly property bool busy: Agenda.has(dayKey, Agenda.monthKey(root.shown))

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
                        visible: dayCell.lit && !dayCell.isToday
                        color: Theme.selection
                    }

                    // The keys (Popup.qml) light a day and list its events
                    // the way the pointer does, and Return opens it.
                    property bool keyed: false
                    readonly property var keyPress: () => root.openDay(dayCell.day)
                    readonly property bool lit: QsWindow.window?.keyItem ? dayCell.keyed : dayHover.hovered
                    onLitChanged: {
                        if (dayCell.lit) {
                            root.litDay = dayCell.dayKey;
                            root.hoverDay = dayCell.dayKey;
                        } else if (root.litDay === dayCell.dayKey) {
                            root.litDay = "";
                            letGo.restart();
                        }
                    }

                    HoverHandler {
                        id: dayHover
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: Qt.formatDateTime(dayCell.day, "dddd d MMMM yyyy")
                    // Resting on a day lists its agenda below (ClickArea).
                    Accessible.description: "Pointer: hover; right-click adds a task or event"
                    Accessible.onPressAction: if (enabled && visible)
                        root.openDay(dayCell.day)

                    TapHandler {
                        onTapped: root.openDay(dayCell.day)
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: root.addOn(dayCell.day)
                    }

                    // Today gets a filled pill rather than an underline: at this
                    // size an underline is one grey pixel.
                    // Today is a filled disc with the number and its dot cut
                    // out of it, the way the system's calendar marks it: the
                    // popup's glass shows through them.
                    Item {
                        anchors.fill: parent
                        visible: dayCell.isToday
                        layer.enabled: visible
                        layer.effect: OpacityMask {
                            invert: true
                            maskSource: todayMask
                            // Preserve the glyph and dot's coverage directly;
                            // thresholding their alpha roughens the edges.
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.cell - 4
                            height: width
                            radius: width / 2
                            color: Theme.calToday
                        }
                    }

                    ShaderEffectSource {
                        id: todayMask

                        sourceItem: marks
                        hideSource: dayCell.isToday
                        live: dayCell.isToday
                        visible: false
                    }

                    // The numeral and its dot: drawn on any other day, and on
                    // today only the shape cut out of the disc, so opaque.
                    Item {
                        id: marks

                        anchors.fill: parent

                        PopupText {
                            anchors.centerIn: parent
                            text: dayCell.day.getDate()
                            // The days either side are context, not padding — worth
                            // showing, faintly, so a month boundary reads at a glance.
                            color: dayCell.isToday ? "white" : (dayCell.thisMonth ? Theme.fg : Theme.label3)
                            font.pixelSize: Theme.popupTextSize
                            font.weight: dayCell.isToday ? Font.DemiBold : Font.Normal
                        }

                        // Something is on that day. One dot whether it is one
                        // thing or six: the list below says how many, and a
                        // count under every numeral would be a second grid.
                        // On today it rises to fall inside the disc, or the
                        // cut would notch the disc's rim rather than leave a dot.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: dayCell.isToday ? 4 : 1
                            width: root.dotSize
                            height: width
                            radius: width / 2
                            visible: dayCell.busy
                            color: dayCell.isToday ? "white" : (dayCell.thisMonth ? Theme.label2 : Theme.label3)
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
            id: list

            visible: Agenda.configured
            x: Theme.popupInset
            width: root.cell * 7 - Theme.popupInset * 2
            topPadding: 6
            spacing: 0

            readonly property var events: Agenda.forDay(root.listDay, root.hoverDay ? Agenda.monthKey(root.shown) : Agenda.thisMonth)
            // The day's tasks after its events, the way the dot counts both.
            readonly property var rows: events.map(e => ({ event: e })).concat((root.tasksByDay[root.listDay] ?? []).map(t => ({ task: t })))
            // The most the list can take: a full page and the "more" line.
            readonly property real fullHeight: topPadding + root.listRowHeight * (root.listRows + 1)

            PopupText {
                visible: Agenda.loaded && Agenda.trouble !== ""
                width: parent.width
                text: Agenda.trouble
                color: Theme.warn
                font.pixelSize: Theme.footnoteSize
                wrapMode: Text.WordWrap
            }

            HoverHandler {
                id: listHover
                onHoveredChanged: if (!hovered)
                    letGo.restart()
            }

            // Wraps rather than elides: the one long thing that lands here
            // is the reconnect message, which is no use cut short.
            PopupText {
                visible: parent.rows.length === 0
                width: parent.width
                height: Math.max(root.listRowHeight, implicitHeight)
                verticalAlignment: Text.AlignVCenter
                text: !Agenda.loaded ? (Agenda.trouble !== "" ? Agenda.trouble : "Connecting…") : (root.listDay === Agenda.today ? "Nothing today" : "Nothing on")
                color: Theme.label3
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: parent.rows.slice(0, root.listRows)

                // A task row crosses its task out the way the tasks popup
                // does; an event row is only read.
                PopupRow {
                    id: entry

                    required property var modelData
                    readonly property var task: modelData.task ?? null
                    readonly property bool crossed: !!task && Tasks.isCrossed(task)

                    width: list.width
                    height: root.listRowHeight
                    name: task ? (crossed ? "Reopen " : "Complete ") + task.title : ""
                    acceptsTap: !!task
                    opacity: crossed ? 0.4 : 1
                    onTapped: if (task)
                        Tasks.complete(task)

                    PopupText {
                        visible: !entry.task
                        width: 42
                        height: root.listRowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: entry.task ? "" : Agenda.sayTime(entry.modelData.event)
                        color: entry.modelData.event?.allDay ? Theme.label3 : Theme.label2
                        font.pixelSize: Theme.captionSize
                    }

                    Glyph {
                        visible: !!entry.task
                        height: root.listRowHeight
                        text: Theme.glyph.tasks
                        fontSize: Theme.captionSize
                        color: Theme.label2
                    }

                    // The task popup's dot, so a late task reads as late here.
                    // At the end of the time column, so every title lines up.
                    Rectangle {
                        visible: !!entry.task
                        x: 42 - width
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: entry.task ? Tasks.dotColour(entry.task) : "transparent"
                    }

                    PopupText {
                        x: 50
                        width: list.width - x
                        height: root.listRowHeight
                        verticalAlignment: Text.AlignVCenter
                        text: entry.task ? entry.task.title : entry.modelData.event.title
                        font.strikeout: entry.crossed
                        elide: Text.ElideRight
                    }
                }
            }

            PopupText {
                visible: parent.rows.length > root.listRows
                height: root.listRowHeight
                verticalAlignment: Text.AlignVCenter
                text: `+${parent.rows.length - root.listRows} more`
                color: Theme.label3
                font.pixelSize: Theme.captionSize
            }
        }

        // The way back in when the sign-in needs you. Under the list, where
        // the reason it is empty is already written.
        ReconnectButton {
            height: 20
            textSize: Theme.footnoteSize
        }
    }
}
