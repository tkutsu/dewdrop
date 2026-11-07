#!/usr/bin/env python3
"""Calendar events without task rows, today's tooltip, and right-click to add."""
import subprocess
import tempfile
from pathlib import Path
from test_support import copy_shell, shell_env

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "scripts/test-tasks.py").read_text().split("BASE = '''")[1].split("'''")[0]

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
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
                mouseMove(cell, 14, 14);
                wait(50);
                check(list.events.length === 0 && !find(list, i => i.text === "Call bank" || i.text === "Bring forms"), "dated tasks and subtasks stay off the calendar list");
                const now = new Date(2026, 9, 14, 12).getTime();
                WallClock.now = now;
                const events = [
                    {title: "Holiday", allDay: true, start: now - 43200000, end: now + 43200000},
                    {title: "Breakfast", allDay: false, start: now - 7200000, end: now - 3600000},
                    {title: "Lunch", allDay: false, start: now - 60000, end: now + 60000},
                    {title: "Dinner", allDay: false, start: now + 7200000, end: now + 10800000}
                ];
                const days = ({});
                days[Agenda.today] = events;
                days[fri] = [{title: "Appointment", allDay: false, start: now, end: now + 3600000}];
                Agenda.months = ({[Agenda.thisMonth]: days});
                wait(50);
                check(clock.tooltip === "All day · Holiday\\n10:00 · Breakfast\\nNow · Lunch\\n14:00 · Dinner", "tooltip lists all today's events on separate lines, including past events");
                check(!clock.tooltip.includes("Call bank"), "tooltip excludes tasks");
                check(cell.busy && list.events.length === 1 && find(list, i => i.text === "Appointment"), "hovered day shows its event beside no task rows");
                // Off the day and onto the list: the list stays that day's.
                mouseMove(list, 60, list.height - 10);
                wait(250);
                check(popup.listDay === fri, "moving to the list keeps the day");
                const row = find(list, i => i.modelData?.title === "Appointment");
                mouseClick(row, 60, 10);
                check(!Tasks.isCrossed(Tasks.tasks[0]), "event rows leave tasks unchanged");
                const title = find(popup.contentItem, i => i.font?.weight === Font.DemiBold && /\\d{4}$/.test(i.text ?? ""));
                mouseMove(title, 5, 5);
                wait(250);
                check(popup.listDay === Agenda.today, "leaving the list returns to today");
                check(list.events.length === 4, "leaving the list restores today's events");
                Agenda.months = ({});
                wait(50);
                check(!cell.busy && list.events.length === 0 && clock.tooltip === "No events today", "empty calendar clears dots and rows, and the tooltip says so despite remaining tasks");
                Agenda.stale = true;
                wait(50);
                check(clock.tooltip === "", "a calendar it could not read does not claim a free day");
                Agenda.stale = false;

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
        target = Path(folder)
        copy_shell(target)
        (target / "services/GoogleService.qml").write_text(BASE)
        (target / "data/quickshell").mkdir(parents=True)
        (target / "data/quickshell/gtasks.json").write_text('{"client_id": "x", "client_secret": "x", "refresh_token": "x"}')
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=40)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign", "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines() if any(marker in line for marker in ("PASS:", "DONE:", *errors, "caused by"))))
        return 0 if result.returncode == 0 and "DONE: calendar tasks" in output and not any(e in output for e in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
