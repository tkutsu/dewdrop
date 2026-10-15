#!/usr/bin/env python3
"""Exercise the real task service and popup with an isolated Google transport."""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from test_support import copy_shell, shell_env

BASE = '''import QtQuick
import Quickshell
Singleton {
    property string service: ""; property int pollMs: 0
    property bool loaded: true; property bool configured: true
    property bool polling: false; property bool loading: false; property int requests: 0; property bool retryable: false
    property bool stale: false; property string trouble: ""
    property string today: "2026-10-14"
    property var generations: ({})
    property var calls: []
    signal fetch()
    function dayString(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    function send(method, url, body, done, failed) {
        calls = calls.concat([{method: method, url: url, body: body, done: done, failed: failed}]);
    }
    function fail(why, status) { trouble = why; }
    function refresh() {} function retryNow() {}
    function gather(key, sources, map, done) {}
}'''

SHELL = '''import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    property bool live: false
    Process { id: pointerMotion }
    FloatingWindow { visible: true; title: "Quickshell task verification"; implicitWidth: 500; implicitHeight: 400
        property point windowOnScreen: Qt.point(0, 0)
        Item { id: anchor; width: 40; height: 20 }
        PopupKeyRelay { id: keyRelay
            input: popup.keyInput
            keyHandler: event => popup.key(event)
        }
        TestCase { id: test; when: false
            function check(ok, text) { if (!ok) throw Error(text); console.log("PASS: " + text); }
            function run() {
                Tasks.lists = [{id: "home", title: "To do"}, {id: "work", title: "Work"}, {id: "empty", title: "Later"}];
                Settings.set("defaultTaskList", "work");
                for (const line of ["work fri call x", "fri work call x"] ) {
                    const p = Tasks.parse(line);
                    check(p.ok && p.title === "call x" && p.list === "work" && p.day !== "", line);
                }
                check(Tasks.parse("call x").list === "work", "default task list");
                check(Tasks.parse("ToDo milk").list === "home", "case and spaces in list names");
                check(Tasks.parse("work").error === "No task, only a task list", "task list without title");
                check(!Tasks.parse("2026-02-30 work tax").ok, "invalid leading date");
                check(!Tasks.parse("work 2026-02-30 tax").ok, "invalid date after task list");
                check(!Tasks.parse("tomorrow").ok, "day without title");
                Settings.set("defaultTaskList", "missing");
                check(Tasks.parse("call x").list === "home", "unknown default falls back");

                // The `,` line: the more of a time it gives, the bigger the thing.
                const day = d => Tasks.dayString(d);
                const fri = Tasks.readDay("fri");
                const at = (p, d, h, m) => p.ok && p.kind === "event" && day(p.event.start) === d
                    && p.event.start.getHours() === h && p.event.start.getMinutes() === m
                    && p.event.end - p.event.start === 3600000;
                check(Tasks.plan("call bank").kind === "task" && Tasks.plan("call bank").task.list === "home", "plain line is a task");
                check(Tasks.plan("work call bank").task.list === "work", "task list word makes a task there");
                check(Tasks.plan("fri call bank").task.day === fri, "day word makes a dated task");
                check(Tasks.plan("25m tea").kind === "timer", "duration is only a timer");
                const alarm = Tasks.plan("15:00 call bank");
                const rings = new Date(Timers.occurrence(15, 0, [], Date.now()));
                check(alarm.kind === "alarm" && alarm.event.title === "call bank" && day(alarm.event.start) === day(rings)
                    && alarm.event.start.getHours() === 15 && alarm.event.reminders.useDefault === false
                    && alarm.event.reminders.overrides.length === 0, "clock time makes an alarm and a quiet event on its day");
                check(Tasks.plan("15:00").kind === "alarm" && Tasks.plan("15:00").event === null, "untitled alarm makes no event");
                check(at(Tasks.plan("today 15:00 call bank"), Tasks.today, 15, 0) && Tasks.plan("today 15:00 call bank").event.reminders === null, "today and a time make an event with default reminders");
                check(at(Tasks.plan("fri 15:00 call bank"), fri, 15, 0), "weekday and time make an event");
                check(at(Tasks.plan("2026-11-03 9:30 dentist"), "2026-11-03", 9, 30), "date and time make an event");
                for (const time of ["21:30", "9:30pm"])
                    check(at(Tasks.plan(`fri ${time} x`), fri, 21, 30), `event time ${time} reads as the alarm would`);
                check(at(Tasks.plan("fri 9pm x"), fri, 21, 0) && at(Tasks.plan("fri 9:30am x"), fri, 9, 30), "am and pm event times");
                const nine = Tasks.plan("fri 9 x");
                check(nine.kind === "task" && nine.task.day === fri && nine.task.title === "9 x", "bare number after a day stays in a task title");
                check(Tasks.plan("fri 15:00").error === "No event, only a time", "time with no title");
                check(Tasks.plan("fri 15:00 work call").event.title === "work call", "section word stays in an event title");
                check(!Tasks.plan("2026-02-30 9:30 x").ok, "invalid event date");

                // What Enter will make, said before it is made.
                const range = (a, b) => `${Timers.hhmm(a, 0)}–${Timers.hhmm(b, 0)}`;
                const preview = line => Launcher.taskResults(" " + line)[0];
                check(preview("15:00 call bank").subtitle === `alarm ${Timers.hhmm(15, 0)} ${Tasks.sayDay(day(rings))}  ·  event ${range(15, 16)}`, "alarm and event preview");
                check(preview("fri 15:00 call bank").subtitle === `event  ·  ${Tasks.sayDay(fri)} ${range(15, 16)}` && preview("fri 15:00 call bank").event, "event preview");
                check(preview("fri call bank").subtitle.startsWith("add  ·  ") && !preview("fri call bank").event, "task preview");
                Google.scopeMissing = true;
                check(preview("15:00 call bank").subtitle.endsWith("calendar needs reconnect") && preview("15:00 call bank").ok, "alarm still sets without the calendar");
                check(preview("fri 15:00 call bank").subtitle === "event  ·  calendar needs reconnect" && !preview("fri 15:00 call bank").ok, "event waits for reconnect");
                Google.scopeMissing = false;

                // A time already gone today rings tomorrow, and its event is
                // on the same day.
                const gone = new Date(Date.now() - 120000);
                if (gone.getDate() === new Date().getDate()) {
                    const line = `${Timers.pad(gone.getHours())}:${Timers.pad(gone.getMinutes())} stand up`;
                    Agenda.calls = [];
                    Tasks.run(line);
                    const entry = Timers.entries[Timers.entries.length - 1];
                    const call = Agenda.calls[0];
                    check(day(new Date(entry.endsAt)) === Tasks.tomorrow && call?.body.start.dateTime.startsWith(Tasks.tomorrow)
                        && call.url.endsWith("/calendars/primary/events") && call.body.summary === "stand up", "past time goes to tomorrow for alarm and event");
                    Timers.cancel(entry.id);
                }
                Agenda.calls = [];
                check(Tasks.run("fri 15:00 call bank").startsWith("Added call bank") && Agenda.calls.length === 1
                    && Agenda.calls[0].body.start.dateTime.startsWith(fri + "T15:00:00") && Agenda.calls[0].body.reminders === undefined, "event line inserts an event");
                Agenda.calls = [];
                Tasks.tasks = [
                    {id: "b", listId: "home", title: "Second", position: "20", due: "2026-10-01", parent: "", notes: ""},
                    {id: "a", listId: "home", title: "First", position: "10", due: "", parent: "", notes: "A note"},
                    {id: "c", listId: "home", title: "Child", position: "10", due: "", parent: "a", notes: ""},
                    {id: "d", listId: "work", title: "Work task", position: "10", due: "2026-12-01", parent: "", notes: ""}
                ];
                check(Tasks.rows.map(r => r.kind + ":" + r.id).join(",") === "header:home,task:a,subtask:c,task:b,header:work,task:d", "flat task list model and manual order");
                check(Tasks.groupedLists[0].tasks[0].children[0].id === "c", "parent children");
                check(Tasks.count === 2, "date based count excludes children and future tasks");
                check(Tasks.dragRows.some(r => r.kind === "header" && r.id === "empty"), "empty drag destinations");
                Tasks.run("work tomorrow new task");
                check(Tasks.calls[0].url.includes("/lists/work/tasks") && Tasks.calls[0].body.title === "new task", "add routed to task list");
                check(popup.auditList.count === Tasks.rows.length, "popup draws flat model");
                check(Launcher.taskResults("").filter(r => r.kind === "task").map(r => r.task.id).join(",") === "a,c,b,d", "launcher task list order");
                check(Launcher.taskResults("work fri call x")[0].subtitle.includes("Work"), "launcher add destination");
                Tasks.calls = [];
                const stableRows = Tasks.rows;
                Tasks.fetchLists();
                Tasks.calls[0].done({items: Tasks.lists});
                check(Tasks.rows === stableRows, "unchanged list poll preserves row model");
                Tasks.calls = [];
                popup.auditReorder.rows = Tasks.dragRows;
                const firstIndex = Tasks.dragRows.findIndex(r => r.id === "a");
                const workHeader = Tasks.dragRows.findIndex(r => r.kind === "header" && r.id === "work");
                popup.moveRow(firstIndex, workHeader);
                check(Tasks.groupedLists[1].tasks.map(t => t.id).join(",") === "a,d", "dragging a parent past its children lands under the header");
                Tasks.calls[0].failed("Test rollback", 400);
                Tasks.calls = [];
                popup.auditReorder.rows = Tasks.dragRows;
                const childIndex = Tasks.dragRows.findIndex(r => r.id === "c");
                popup.moveRow(childIndex, childIndex);
                check(Tasks.calls.length === 0 && Tasks.tasks.find(t => t.id === "c").parent === "a", "stationary hold preserves a subtask");
                Tasks.move(Tasks.tasks.find(t => t.id === "b"), {list: "work", previous: "d"});
                check(Tasks.groupedLists[1].tasks.map(t => t.id).join(",") === "d,b", "optimistic cross task list order");
                check(Tasks.calls[0].method === "POST" && Tasks.calls[0].body === null && Tasks.calls[0].url.includes("destinationTasklist=work") && Tasks.calls[0].url.includes("previous=d"), "move query and empty body");
                Tasks.calls[0].failed("Recurring task cannot change lists", 400);
                check(Tasks.ordered.map(t => t.id).join(",") === "a,c,b,d" && Tasks.trouble.includes("Recurring"), "failed move rolls back with trouble");
                Tasks.trouble = "";
                Tasks.calls = [];
                Tasks.move(Tasks.tasks.find(t => t.id === "b"), {list: "home", parent: "a", previous: "c"});
                check(Tasks.ordered.map(t => t.id + ":" + (t.parent || "")).join(",") === "a:,c:a,b:a,d:", "nesting position");
                Tasks.calls[0].done({id: "b", position: "20"});
                Tasks.calls = [];
                Tasks.move(Tasks.tasks.find(t => t.id === "c"), {list: "home", parent: "", previous: "a"});
                check(Tasks.groupedLists[0].tasks.map(t => t.id).join(",") === "a,c", "subtask lifted to top level");
                Tasks.calls[0].done({id: "c", position: "20"});
                Tasks.calls = [];
                Tasks.move(Tasks.tasks.find(t => t.id === "a"), {list: "home", parent: "c"});
                check(Tasks.calls.length === 0, "parent with children cannot nest");
                Tasks.move(Tasks.tasks.find(t => t.id === "a"), {list: "work"});
                check(Tasks.tasks.find(t => t.id === "b").listId === "work", "parent moves its children");
                Tasks.calls[0].done({id: "a", position: "05"});
                Tasks.calls = [];
                const a = Tasks.ordered.find(t => t.id === "a");
                Tasks.complete(a);
                check(Tasks.isCrossed(a) && Tasks.isCrossed(Tasks.tasks.find(t => t.id === "b")), "parent cross out includes children");
                check(Tasks.calls.length === 0 && Tasks.ordered.some(t => t.id === "a"), "cross out stays visible with no request");
                check(Launcher.taskResults("").find(r => r.task?.id === "a").crossed, "launcher uses crossed state");
                Tasks.complete(a);
                Tasks.commit();
                check(!Tasks.isCrossed(a) && Tasks.calls.length === 0, "tap twice then close commits nothing");
                Tasks.complete(a);
                popup.requestedVisible = false;
                check(Tasks.calls.length === 1 && Tasks.calls[0].url.includes("/tasks/b"), "close commits child first");
                Tasks.calls[0].done({});
                check(Tasks.calls.length === 2 && Tasks.calls[1].url.includes("/tasks/a"), "parent follows child commit");
                Tasks.calls[1].done({});
                check(!Tasks.tasks.some(t => ["a", "b"].includes(t.id)), "commit removes completed rows");
                popup.requestedVisible = true;
                Tasks.calls = [];
                const c = Tasks.tasks.find(t => t.id === "c");
                Tasks.complete(c);
                wait(5500);
                check(Tasks.calls.length === 0, "completion waits ten seconds");
                Tasks.complete(c);
                Tasks.complete(c);
                wait(5000);
                check(Tasks.calls.length === 0, "last tap restarts completion delay");
                wait(5100);
                check(Tasks.calls.length === 1, "ten second idle commit while open");
                Tasks.calls[0].failed("Offline", 0);
                check(Tasks.tasks.some(t => t.id === "c") && !Tasks.isCrossed(c), "failed completion restores open state");
                Tasks.calls = [];
                popup.beginEdit(c);
                wait(50);
                check(popup.editing.id === "c", "edit begins");
                const row = popup.auditList.itemAtIndex(Tasks.rows.findIndex(r => r.id === "c"));
                const editor = row.children[0].children.find(child => child.objectName === "taskEditor");
                if (!live) anchor.Window.window.requestActivate();
                keyRelay.forceActiveFocus();
                wait(100);
                check(editor && editor.focus && popup.keyInput === editor, "inline editor receives forwarded keys");
                editor.selectAll();
                for (const ch of "Edited title") keyClick(ch);
                keyClick(Qt.Key_Return, Qt.ShiftModifier);
                for (const ch of "Notes on phone") keyClick(ch);
                keyClick(Qt.Key_Return);
                check(Tasks.calls.length === 1 && Tasks.calls[0].body.title === "Edited title" && Tasks.calls[0].body.notes === "Notes on phone", "Enter saves title and Shift Enter notes");
                Tasks.calls[0].done({});
                Tasks.calls = [];
                popup.auditList.forceLayout();
                const editRow = popup.auditList.itemAtIndex(Tasks.rows.findIndex(r => r.id === "c"));
                popup.setKey(editRow);
                check(popup.key({key: Qt.Key_E}), "e edits focused row");
                wait(30);
                keyRelay.forceActiveFocus();
                wait(100);
                keyClick(Qt.Key_Escape);
                check(popup.editing === null && Tasks.calls.length === 0, "Escape cancels without writing");
                if (live) {
                    const local = editRow.mapToItem(popup.contentItem, 25, 10);
                    const point = {x: local.x + popup.windowOnScreen.x, y: local.y + popup.windowOnScreen.y};
                    pointerMotion.command = ["hyprctl", "dispatch", "hl.dsp.cursor.move({x=" + Math.round(point.x) + ",y=" + Math.round(point.y) + "})"];
                    pointerMotion.running = true;
                    wait(100);
                } else mouseMove(editRow, 25, 10);
                wait(30);
                check(editRow.hovered, "hover works after editing");
                const rowIndex = Tasks.rows.findIndex(r => r.id === "c");
                const y = editRow.y - popup.auditList.contentY + 12;
                mouseClick(popup.auditList, 25, y);
                check(Tasks.isCrossed(c), "pointer tap crosses exactly once");
                mouseClick(popup.auditList, 25, y);
                check(!Tasks.isCrossed(c), "second pointer tap uncrosses");
                mousePress(popup.auditList, 25, y);
                wait(550);
                check(popup.auditReorder.dragging, "hold lifts task");
                check(popup.auditReorder.rows.some(r => r.kind === "header" && r.id === "empty"), "hold reveals empty task lists");
                check(popup.auditList.itemAtIndex(popup.auditReorder.from).height === popup.rowHeight, "held rows collapse to one line");
                mouseMove(popup.auditList, 25, popup.auditList.height - 2);
                wait(50);
                mouseRelease(popup.auditList, 25, popup.auditList.height - 2);
                wait(200);
                check(Tasks.calls.length === 1 && Tasks.calls[0].url.includes("/move"), "pointer drop sends move");
                Tasks.calls[0].failed("Refused move", 400);
                wait(200);
                check(!popup.auditReorder.showing && Tasks.tasks.find(t => t.id === "c").listId === "home", "refused pointer move settles and rolls back");
                console.log("DONE: tasks");
            }
        }
    }
    TasksPopup { id: popup; visible: true; anchorItem: anchor }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-tasks-") as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / "services/GoogleService.qml").read_text()
        gather = re.search(r'^    function gather\(.*?^    }', source, re.M | re.S).group()
        base = BASE.replace('Singleton {', 'Singleton {\n    id: base', 1)
        base = base.replace('    function gather(key, sources, map, done) {}', gather)
        (target / "services/GoogleService.qml").write_text(base)
        # Signed in, so the calendar is offered; nothing reaches Google.
        (target / "data/quickshell").mkdir(parents=True)
        (target / "data/quickshell/gtasks.json").write_text('{"client_id": "x", "client_secret": "x", "refresh_token": "x"}')
        p = target / "components/TasksPopup.qml"
        p.write_text(p.read_text().replace("id: root", "id: root\n    property alias auditList: list\n    property alias auditReorder: reorder", 1))
        shell = SHELL
        if "--live" in sys.argv:
            shell = shell.replace("property bool live: false", "property bool live: true")
            shell = shell.replace('FloatingWindow { visible: true; title: "Quickshell task verification"; implicitWidth: 500; implicitHeight: 400',
                'PanelWindow { anchors.top: true; anchors.left: true; anchors.right: true; implicitHeight: 50; exclusionMode: ExclusionMode.Ignore; WlrLayershell.namespace: "quickshell-task-verification"; WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive')
        (target / "shell.qml").write_text(shell)
        env = shell_env(target)
        if "--live" in sys.argv:
            env.pop("QT_QUICK_BACKEND", None)
            env.update(QT_QPA_PLATFORM="wayland", XDG_RUNTIME_DIR=os.environ["XDG_RUNTIME_DIR"],
                       WAYLAND_DISPLAY=os.environ["WAYLAND_DISPLAY"],
                       HYPRLAND_INSTANCE_SIGNATURE=os.environ["HYPRLAND_INSTANCE_SIGNATURE"])
        pointer = json.loads(subprocess.check_output(["hyprctl", "cursorpos", "-j"], text=True)) if "--live" in sys.argv else None
        try:
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=40)
        finally:
            if pointer:
                subprocess.run(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{x={pointer['x']},y={pointer['y']}}})"], capture_output=True)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign", "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines() if any(marker in line for marker in ("PASS:", "DONE:", *errors, "caused by"))))
        return 0 if result.returncode == 0 and "DONE: tasks" in output and not any(e in output for e in errors) else 1

if __name__ == "__main__":
    raise SystemExit(main())
