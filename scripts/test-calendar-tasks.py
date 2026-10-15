#!/usr/bin/env python3
"""Dated tasks on the calendar popover, events written to Google, and right-click to add."""
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
import qs.services
ShellRoot {
    FloatingWindow { visible: true; implicitWidth: 400; implicitHeight: 400
        Item { id: anchor; width: 40; height: 20 }
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
                const fri = Tasks.readDay("fri");
                Tasks.lists = [{id: "home", title: "To do"}];
                Tasks.tasks = [
                    {id: "a", listId: "home", title: "Call bank", position: "1", due: fri + "T00:00:00.000Z", parent: "", notes: ""},
                    {id: "b", listId: "home", title: "Bring forms", position: "1", due: fri + "T00:00:00.000Z", parent: "a", notes: ""},
                    {id: "c", listId: "home", title: "Someday", position: "2", due: "", parent: "", notes: ""}
                ];
                wait(50);
                const cell = find(popup.contentItem, i => i.dayKey === fri);
                check(cell && !cell.busy, "a day with only tasks has no dot");
                check(popup.tasksByDay[fri].map(t => t.id).join(",") === "a", "subtasks stay off the calendar");
                const list = find(popup.contentItem, i => i.rows !== undefined && i.events !== undefined);
                mouseMove(cell, 14, 14);
                wait(50);
                check(list.rows.length === 1 && list.rows[0].task.id === "a", "the day's list shows its task");
                // Off the day and onto the list: the list stays that day's.
                mouseMove(list, 60, list.height - 10);
                wait(250);
                check(popup.listDay === fri, "moving to the list keeps the day");
                const row = find(list, i => i.task?.id === "a");
                mouseClick(row, 60, 10);
                check(Tasks.isCrossed(Tasks.tasks[0]), "tapping a task row crosses it out");
                mouseClick(row, 60, 10);
                check(!Tasks.isCrossed(Tasks.tasks[0]), "a second tap reopens it");
                const title = find(popup.contentItem, i => i.font?.weight === Font.DemiBold && /\\d{4}$/.test(i.text ?? ""));
                mouseMove(title, 5, 5);
                wait(250);
                check(popup.listDay === Agenda.today, "leaving the list returns to today");
                Tasks.tasks = Tasks.tasks.filter(t => t.id === "c");
                wait(50);
                check(!cell.busy && !popup.tasksByDay[fri], "a task completed elsewhere leaves at the next poll");

                // Writing an event.
                Agenda.haveCalendars = true;
                Agenda.calendars = [{id: "primary", title: "Me"}];
                Agenda.calls = [];
                const start = new Date(2026, 9, 23, 15, 0);
                Agenda.insert({title: "Call bank", start: start, end: new Date(start.getTime() + 3600000), reminders: null});
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
                Agenda.insert({title: "Dentist", start: start, end: start, reminders: null});
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
