#!/usr/bin/env python3
"""Calendar events without task rows, today's tooltip, and right-click to add."""
import subprocess
import tempfile
from pathlib import Path
from test_support import fixture_root
from test_support import copy_shell, shell_env

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "tests/test-tasks.py").read_text().split("BASE = '''")[1].split("'''")[0]

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.modules
import qs.src.services
ShellRoot {
    FloatingWindow { visible: true; implicitWidth: 400; implicitHeight: 400
        Item { id: anchor; width: 40; height: 20 }
        Clock { id: clock; y: 30; height: 30 }
        TestCase { id: test; when: false
            function check(ok, text) { if (!ok) throw Error(text); console.log("PASS: " + text); }
            function find(item, test) {
                if (test(item)) return item;
                for (const child of item.children) {
                    const found = find(child, test);
                    if (found) return found;
                }
                return null;
            }
            function run() {
                // A Friday in the fixture's fixed month, not the real next one.
                const fri = "2026-10-16";
                Tasks.lists = [{id: "home", title: "To do"}];
                Tasks.tasks = [
                    {id: "a", listId: "home", title: "Call bank", position: "1", due: fri + "T00:00:00.000Z", parent: "", notes: ""},
                    {id: "b", listId: "home", title: "Bring forms", position: "1", due: fri + "T00:00:00.000Z", parent: "a", notes: ""},
                    {id: "c", listId: "home", title: "Someday", position: "2", due: "", parent: "", notes: ""}
                ];
                wait(50);
                const cell = find(popup.contentItem, i => i.dayKey === fri);
                check(cell && !cell.busy, "a day with only tasks has no dot");
                const list = find(popup.contentItem, i => i.events !== undefined);
                mouseClick(cell, 14, 14);
                wait(50);
                check(popup.selected === fri, "clicking a day selects it");
                check(list.events.length === 0 && !find(list, i => i.text === "Call bank" || i.text === "Bring forms"), "dated tasks and subtasks stay off the calendar list");
                const now = new Date(2026, 9, 14, 12).getTime();
                WallClock.now = now;
                const events = [
                    {title: "Holiday", allDay: true, start: now - 43200000, end: now + 43200000},
                    {title: "Breakfast", allDay: false, start: now - 7200000, end: now - 3600000},
                    {title: "Lunch", allDay: false, start: now - 60000, end: now + 60000},
                    {title: "Dinner", allDay: false, start: now + 7200000, end: now + 10800000},
                    {title: "Walk", allDay: false, start: now + 14400000, end: now + 18000000}
                ];
                const days = ({});
                days[Agenda.today] = events;
                days[fri] = [{title: "Appointment", allDay: false, start: now, end: now + 3600000}];
                Agenda.months = ({[Agenda.thisMonth]: days});
                wait(50);
                const dateLine = Qt.formatDate(new Date(now), "dddd d MMMM yyyy");
                check(clock.tooltip === dateLine + "\\n14:00 · Dinner\\n16:00 · Walk", "tooltip shows the date, then each upcoming event on its own line without past, ongoing or all-day events");
                check(!clock.tooltip.includes("Call bank"), "tooltip excludes tasks");
                WallClock.now = events[3].start - 1;
                wait(20);
                check(clock.tooltip === dateLine + "\\n14:00 · Dinner\\n16:00 · Walk", "an event remains visible just before its start");
                WallClock.now = events[3].start;
                wait(20);
                check(clock.tooltip === dateLine + "\\n16:00 · Walk", "an event leaves the tooltip when it starts, keeping later events");
                WallClock.now = events[4].start;
                wait(20);
                check(clock.tooltip === dateLine, "the date stays visible after the last event starts");
                WallClock.now = new Date(2026, 9, 15).getTime();
                wait(20);
                check(clock.tooltip === Qt.formatDate(new Date(WallClock.now), "dddd d MMMM yyyy"), "tooltip date updates at midnight");
                WallClock.now = now;
                check(cell.busy && list.events.length === 1 && find(list, i => i.text === "Appointment"), "the selected day shows its event beside no task rows");
                // Off the day and onto the list: the list stays that day's.
                mouseMove(list, 60, list.height - 10);
                wait(250);
                check(popup.selected === fri, "moving to the list keeps the day");
                const row = find(list, i => i.modelData?.title === "Appointment");
                mouseClick(row, 60, 10);
                check(!Tasks.isCrossed(Tasks.tasks[0]), "event rows leave tasks unchanged");
                const heading = find(popup.contentItem, i => i.text === "Friday 16 October" && i.font?.weight === Font.DemiBold);
                check(heading && heading.visible, "the list is headed by the selected day");
                check(!find(popup.contentItem, i => i.name === "Today" && i.tapped !== undefined), "the header has no today button");
                // What every open does.
                popup.goToday();
                wait(50);
                check(popup.selected === Agenda.today && popup.offset === 0, "going back to today clears the pick and the month");
                check(list.events.length === 5 && find(popup.contentItem, i => i.text === "Today" && i.font?.weight === Font.DemiBold), "today's events are back under a Today heading");
                // Now, over and next, on today.
                const rowOf = title => find(popup.contentItem, i => i.ev !== undefined && i.ev.title === title && i.visible);
                const leadOf = title => find(rowOf(title), i => i.textFormat === Text.PlainText && i.x === Theme.popupInset);
                check(rowOf("Breakfast").opacity < 0.5 && rowOf("Holiday").opacity === 1, "a timed event that is over is faint, an all-day one never");
                check(leadOf("Lunch")?.text === "now" && find(rowOf("Lunch"), i => i.height === 2 && i.visible), "the event under way says now and draws its progress");
                WallClock.now = events[3].start - 25 * 60000;
                wait(50);
                check(leadOf("Dinner")?.text === "in 25m", "the next event inside the hour counts down");
                WallClock.now = now;
                wait(50);
                // More than a page scrolls rather than growing the popup.
                const rows = find(list, i => i.positionViewAtIndex !== undefined);
                const many = [];
                for (let h = 0; h < 8; h++)
                    many.push({id: "m" + h, title: "Slot " + h, allDay: false, start: now + h * 600000, end: now + h * 600000 + 300000});
                Agenda.months = ({[Agenda.thisMonth]: Object.assign({}, days, {[Agenda.today]: many})});
                wait(50);
                check(rows.count === 8 && rows.height === popup.listRows * popup.listRowHeight && rows.interactive, "eight events show five rows and scroll");
                Agenda.months = ({[Agenda.thisMonth]: days});
                wait(50);
                // An empty day says what comes next, and goes there.
                const dentist = new Date(2026, 9, 16, 15).getTime();
                Agenda.months = ({[Agenda.thisMonth]: Object.assign({}, days, {[fri]: [{id: "d", title: "Dentist", allDay: false, start: dentist, end: dentist + 1800000}]})});
                Agenda.loaded = true;
                popup.picked = "2026-10-15";
                wait(50);
                const nextRow = find(popup.contentItem, i => i.upcoming !== undefined);
                check(nextRow.visible && nextRow.ev.title === "Dentist" && nextRow.aside.indexOf("16") >= 0, "an empty day shows the next event");
                mouseClick(nextRow, 120, 10);
                wait(50);
                check(popup.selected === fri, "tapping the next event goes to its day");
                Agenda.months = ({[Agenda.thisMonth]: days});
                popup.goToday();
                wait(50);
                // Where a call is joined from.
                const cal = {title: "Me", colour: "#7986cb"};
                const at = {dateTime: "2026-10-14T10:00:00+03:00"};
                const meet = Agenda.normalise({id: "1", start: at, end: at, hangoutLink: "https://meet.google.com/abc-defg-hij", htmlLink: "https://www.google.com/calendar/event?eid=x"}, cal);
                const zoom = Agenda.normalise({id: "2", start: at, end: at, location: "https://example.zoom.us/j/123"}, cal);
                const pasted = Agenda.normalise({id: "3", start: at, end: at, location: "Room 4", description: "Join: https://teams.microsoft.com/l/meetup/42 thanks"}, cal);
                const none = Agenda.normalise({id: "4", start: at, end: at, description: "see https://example.com/doc"}, cal);
                check(meet.link === "https://meet.google.com/abc-defg-hij" && meet.url.indexOf("eid=x") > 0 && meet.colour === "#7986cb", "Meet links, the event page and the calendar colour are kept");
                check(zoom.link === "https://example.zoom.us/j/123" && pasted.link === "https://teams.microsoft.com/l/meetup/42" && pasted.place === "Room 4" && none.link === "", "a call address in the place or description is found, other links are not");
                // Colours as the app draws them, not the API's old pastels.
                const tomato = Agenda.normalise({id: "5", colorId: "11", start: at, end: at}, cal);
                check(Agenda.calendarShade("#9FE1E7") === "#039be5" && Agenda.calendarShade("#123456") === "#123456", "a calendar's palette colour is drawn in the app's shade, a custom one as itself");
                check(tomato.colour === "#d50000" && none.colour === "#7986cb", "an event's own colour wins over its calendar's");
                // A faint day from the next month turns the grid to it.
                const faint = find(popup.contentItem, i => i.dayKey !== undefined && !i.thisMonth && i.index > 27);
                const faintKey = faint.dayKey;
                mouseClick(faint, 14, 14);
                wait(50);
                check(popup.offset === 1 && popup.selected === faintKey, "a faint day selects it and turns the month");
                popup.goToday();
                wait(50);
                Agenda.months = ({});
                wait(50);
                check(!cell.busy && list.events.length === 0 && clock.tooltip === dateLine, "empty calendar clears dots and rows, keeping only the tooltip date despite remaining tasks");
                Agenda.stale = true;
                wait(50);
                check(clock.tooltip === dateLine, "a calendar it could not read still shows the date without claiming a free day");
                Agenda.stale = false;

                // Title wheels turn months; the grid wheels the selected day.
                const month = find(popup.contentItem, i => i.text === "October 2026");
                mouseWheel(month, month.width / 2, month.height / 2, 0, -60);
                check(popup.offset === 0, "partial title scrolling waits for a full notch");
                mouseWheel(month, month.width / 2, month.height / 2, 0, -60);
                check(popup.offset === 1 && popup.selected === Agenda.today, "title scroll down turns to the next month without changing the selected day");
                mouseWheel(month, month.width / 2, month.height / 2, 0, 240);
                check(popup.offset === -1, "title scroll up turns back by multiple months");
                popup.goToday();
                const wheelDay = delta => mouseWheel(cell, 14, 14, 0, delta);
                wheelDay(-60);
                check(popup.selected === Agenda.today, "partial grid scrolling waits for a full notch");
                wheelDay(-60);
                check(popup.selected === "2026-10-15", "grid scroll down selects the next day");
                wheelDay(120);
                check(popup.selected === Agenda.today && popup.picked === "", "grid scroll up selects the previous day");
                for (const [from, to] of [["2026-12-31", "2027-01-01"], ["2028-02-28", "2028-02-29"], ["2026-03-29", "2026-03-30"]]) {
                    popup.select(popup.dateOf(from));
                    const offset = popup.offset;
                    wheelDay(-120);
                    check(popup.selected === to && Agenda.monthKey(popup.shown) === to.slice(0, 7), "day scrolling follows the date across year, leap day and DST boundaries: " + from);
                    wheelDay(120);
                    check(popup.selected === from && popup.offset === offset, "day scrolling reverses across the same boundary: " + from);
                }
                popup.goToday();

                // Writing an event.
                Agenda.haveCalendars = true;
                Agenda.calendars = [{id: "primary", title: "Me"}];
                Agenda.calls = [];
                const start = new Date(2026, 9, 23, 15, 0);
                Agenda.insert({title: "Call bank", start: start, end: new Date(start.getTime() + 3600000)});
                const post = Agenda.calls[0];
                const offset = -start.getTimezoneOffset();
                const zone = (offset < 0 ? "-" : "+") + Timers.pad(Math.floor(Math.abs(offset) / 60)) + ":" + Timers.pad(Math.abs(offset) % 60);
                check(post.method === "POST" && post.url.endsWith("/calendars/primary/events") && post.body.summary === "Call bank"
                    && post.body.start.dateTime === "2026-10-23T15:00:00" + zone && post.body.end.dateTime === "2026-10-23T16:00:00" + zone, "insert posts local times with their offset");
                // A fetch already in the air began before the event existed:
                // the month is fetched again rather than waited on.
                const before = ({"2026-10": true});
                Agenda.inflight = before;
                post.done({});
                check(Agenda.inflight !== before && Agenda.inflight["2026-10"] === true, "an inserted event refetches its month");
                Agenda.calls = [];
                Agenda.insert({title: "Dentist", start: start, end: start});
                Agenda.calls[0].failed(Google.reconnect, 403);
                check(Agenda.trouble === Google.reconnect, "a failed insert is visible");

                // New, in the header: the launcher on the selected day.
                popup.visible = true;
                popup.picked = fri;
                const add = find(popup.contentItem, i => i.name === "New task or event" && i.tapped !== undefined);
                check(add && add.visible && add.label === "New", "the header has a New button");
                check(find(popup.contentItem, i => i.name === "Open Google Calendar" && i.glyph === Theme.glyph.openApp), "the header opens the app from its far right");
                add.tapped();
                check(Launcher.query === ", " + fri + " ", "New opens the launcher on the selected day");
                popup.picked = "";

                // Right-click a day: the launcher, with that day typed in.
                popup.visible = true;
                const day = find(popup.contentItem, i => i.dayKey === "2026-10-23") ?? cell;
                mouseClick(day, 14, 14, Qt.RightButton);
                check(Launcher.query === ", " + day.dayKey + " ", "right-click opens the launcher on that day");
                console.log("DONE: calendar tasks");
            }
        }
    }
    Calendar { id: popup; visible: true; anchorItem: anchor }
    Timer { interval: 200; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-calendar-tasks-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/services/GoogleService.qml").write_text(BASE)
        (target / "data/quickshell").mkdir(parents=True, exist_ok=True)
        (target / "data/quickshell/gtasks.json").write_text('{"client_id": "x", "client_secret": "x", "refresh_token": "x"}')
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=40)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign", "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines() if any(marker in line for marker in ("PASS:", "DONE:", *errors, "caused by"))))
        return 0 if result.returncode == 0 and "DONE: calendar tasks" in output and not any(e in output for e in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
