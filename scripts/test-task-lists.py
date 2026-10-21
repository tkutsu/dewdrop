#!/usr/bin/env python3
"""Exercise list renaming and the default-list dropdown with isolated transport."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("task_harness", Path(__file__).with_name("test-tasks.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

settings = (Path(__file__).resolve().parents[1] / "modules/SettingsMenu.qml").read_text()
setting = next(line.strip() for line in settings.splitlines() if 'id: "defaultTaskList"' in line)
harness.SHELL = harness.SHELL.replace(
    'Item { id: anchor; width: 40; height: 20 }',
    'Item { id: anchor; width: 40; height: 20 }\n'
    '        SettingRow { id: defaultRow; x: 40; y: 60; width: 420; setting: (' + setting + ') }',
)

CASES = r'''
                Tasks.lists = [{id: "home", title: "Personal"}, {id: "work", title: "Work"}, {id: "empty", title: "Later"}];
                Tasks.tasks = [{id: "a", listId: "home", listTitle: "Personal", title: "Buy milk", parent: "", notes: "", position: "10"}];
                Settings.set("defaultTaskList", "home");
                wait(100);
                const loader = defaultRow.children.find(c => c.toString().startsWith("QQuickLoader"));
                const dropdown = loader.item;
                check(dropdown && dropdown.count === 3 && dropdown.currentText === "Personal", "default task list renders as dropdown from Google lists");
                mouseClick(dropdown, dropdown.width / 2, dropdown.height / 2);
                wait(50);
                check(dropdown.popup.visible, "click opens task list dropdown");
                const choices = dropdown.popup.contentItem;
                choices.forceLayout();
                const work = choices.itemAtIndex(1);
                mouseClick(work, work.width / 2, work.height / 2);
                wait(60);
                check(Settings.defaultTaskList === "work" && Tasks.parse("call x").list === "work", "dropdown selection stores list ID and routes new tasks");
                check(!dropdown.popup.visible, "choosing a task list closes dropdown");
                Tasks.lists = [Tasks.lists[2], Tasks.lists[0], Tasks.lists[1]];
                wait(50);
                check(dropdown.currentIndex === 2 && dropdown.currentText === "Work", "dropdown selection follows list ID after model reorder");

                Tasks.calls = [];
                const headerIndex = Tasks.rows.findIndex(r => r.kind === "header" && r.id === "home");
                popup.auditList.forceLayout();
                const header = popup.auditList.itemAtIndex(headerIndex);
                const headerY = header.y - popup.auditList.contentY + 12;
                mouseClick(popup.auditList, 28, headerY);
                wait(60);
                check(popup.editing === null, "clicking a task list heading does not edit it");
                check(Tasks.calls.length === 0 && Object.keys(Tasks.crossed).length === 0, "heading click neither completes tasks nor writes");
                wait(400);
                const milk = popup.auditList.itemAtIndex(headerIndex + 1);
                check(Tasks.isFolded("home") && !milk.visible && milk.height === 0, "heading click folds its task list");
                check(header.dayText === "1", "folded heading shows its task count");
                mouseClick(popup.auditList, 28, headerY);
                wait(400);
                check(!Tasks.isFolded("home") && milk.visible && milk.height > 0, "second heading click unfolds it");
                // The edit button sits under the header's plus, 10 in from the edge.
                mouseMove(popup.auditList, popup.auditList.width - 10, headerY);
                wait(30);
                mouseClick(popup.auditList, popup.auditList.width - 10, headerY);
                wait(60);
                check(popup.editing?.kind === "header" && popup.keyInput, "heading edit button opens inline editor");
                popup.keyInput.selectAll();
                if (!live) anchor.Window.window.requestActivate();
                keyRelay.forceActiveFocus();
                wait(60);
                for (const ch of "Home") keyClick(ch);
                keyClick(Qt.Key_Return);
                wait(30);
                const rename = Tasks.calls[0];
                check(popup.editing === null && rename.method === "PATCH" && rename.url.endsWith("/users/@me/lists/home") && rename.body.title === "Home", "Enter sends Google task list rename");
                check(Tasks.lists.find(l => l.id === "home").title === "Home" && Tasks.tasks[0].listTitle === "Home", "rename updates headings and task metadata");
                check(Tasks.parse("home milk").list === "home", "renamed task list is available to launcher parser");
                rename.done({title: "Home"});
                wait(30);

                Settings.set("defaultTaskList", "home");
                Tasks.calls = [];
                Tasks.renameList("home", "Household");
                wait(30);
                check(dropdown.currentText === "Household" && Settings.defaultTaskList === "home", "renaming default task list updates dropdown while preserving selection");
                Tasks.calls[0].failed("Offline", 0);
                wait(30);
                check(dropdown.currentText === "Home" && Tasks.tasks[0].listTitle === "Home" && Tasks.trouble === "Offline", "failed rename restores list and task titles with an error");

                Tasks.calls = [];
                popup.beginEdit(Tasks.rows.find(r => r.kind === "header" && r.id === "home"));
                wait(30);
                popup.draft = "Cancelled";
                keyRelay.forceActiveFocus();
                keyClick(Qt.Key_Escape);
                check(popup.editing === null && Tasks.calls.length === 0, "Escape cancels task list rename");
                popup.beginEdit(Tasks.rows.find(r => r.kind === "header" && r.id === "home"));
                popup.draft = "   ";
                popup.saveEdit();
                check(popup.editing !== null && Tasks.calls.length === 0 && Tasks.trouble.includes("Task list name"), "empty list name keeps editor and explains validation");
                popup.cancelEdit();
                check(!Tasks.renameList("home", "x".repeat(1025)) && !Tasks.renameList("home", "two\nlines"), "invalid list names never reach Google");

                Tasks.calls = [];
                Tasks.edit(Tasks.tasks[0], "Buy tea");
                popup.beginEdit(Tasks.rows.find(r => r.kind === "header" && r.id === "home"));
                popup.draft = "Personal again";
                popup.requestedVisible = false;
                check(popup.editing === null && Tasks.pending[0]?.kind === "renameList", "closing queues list rename behind active task save");
                Tasks.calls[0].done({});
                wait(60);
                const queued = Tasks.calls.find(c => c.url.endsWith("/users/@me/lists/home"));
                check(queued?.body.title === "Personal again", "queued rename resolves list independently from task IDs");
                queued.done({title: "Personal again"});
                wait(50);
                popup.requestedVisible = true;

                Tasks.calls = [];
                Tasks.fetchLists();
                const poll = Tasks.calls[0];
                const oldLists = Tasks.lists;
                Tasks.renameList("home", "Current name");
                const saving = Tasks.calls[1];
                saving.done({title: "Current name"});
                poll.done({items: oldLists});
                check(Tasks.lists.find(l => l.id === "home").title === "Current name", "stale list poll cannot undo a confirmed rename");

                Tasks.lists = [{id: "empty", title: "Empty list"}];
                Tasks.tasks = [];
                wait(50);
                check(Tasks.rows.length === 0, "empty task list stays out of the popup");
                check(Tasks.dragRows.length === 1 && Tasks.dragRows[0].kind === "header", "empty task list is still a drop destination");
                check(dropdown.currentText === "Empty list" && Tasks.defaultList.id === "empty", "deleted default falls back to first available task list");
                Tasks.lists = [];
                wait(30);
                check(!dropdown.enabled && dropdown.count === 0 && dropdown.contentItem.text === "No task lists available", "dropdown handles disconnected or empty list model");
'''

start = harness.SHELL.index("                Tasks.lists =")
end = harness.SHELL.index('                console.log("DONE: tasks");', start)
harness.SHELL = harness.SHELL[:start] + CASES + harness.SHELL[end:]

if __name__ == "__main__":
    raise SystemExit(harness.main())
