#!/usr/bin/env python3
"""Reproduce task draft, landing, hierarchy and in-flight input regressions."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("task_harness", Path(__file__).with_name("test-tasks.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

CASES = r'''
                let failures = 0;
                function probe(name, run) {
                    try { run(); } catch (error) {
                        console.log("FAIL: " + name + ": " + error.message);
                        failures++;
                    }
                }
                const fixture = [
                    {id: "a", listId: "home", title: "A long task title that wraps over several lines in the popup", position: "10", parent: "", notes: "A long note with a second line\nMore notes here"},
                    {id: "b", listId: "home", title: "First child", position: "10", parent: "a", notes: ""},
                    {id: "c", listId: "home", title: "Second child", position: "20", parent: "a", notes: ""},
                    {id: "d", listId: "work", title: "Work task", position: "10", parent: "", notes: ""}
                ];
                function reset() {
                    popup.cancelEdit();
                    popup.auditReorder.finishDrop();
                    Tasks.pending = [];
                    Tasks.writing = 0;
                    Tasks.commitWanted = false;
                    Tasks.crossed = ({});
                    Tasks.calls = [];
                    Tasks.trouble = "";
                    Tasks.lists = [{id: "home", title: "Home"}, {id: "work", title: "Work"}];
                    Tasks.tasks = fixture.map(t => Object.assign({}, t));
                    popup.requestedVisible = true;
                    popup.auditReorder.rows = Tasks.dragRows;
                    wait(60);
                    popup.auditList.forceLayout();
                }
                probe("close saves draft", () => {
                    reset();
                    popup.beginEdit(Tasks.tasks[3]);
                    wait(30);
                    popup.draft = "Changed title\nPasted link";
                    popup.requestedVisible = false;
                    check(Tasks.calls.length === 1 && Tasks.calls[0].body.title === "Changed title", "closing saves changed draft");
                    Tasks.calls[0].done({});
                    reset();
                    popup.beginEdit(Tasks.tasks[3]);
                    popup.requestedVisible = false;
                    check(Tasks.calls.length === 0 && popup.editing === null, "closing unchanged draft does not write");
                });
                probe("upward header landing", () => {
                    reset();
                    popup.moveRow(5, 4);
                    check(Tasks.tasks.find(t => t.id === "d").listId === "home", "gap above header uses preceding task list");
                    check(Tasks.calls[0].url.includes("previous=a"), "top level drop follows the entire preceding family");
                    Tasks.calls[0].failed("rollback", 400);
                    reset();
                    popup.moveRow(5, 0);
                    check(Tasks.tasks.find(t => t.id === "d").listId === "home" && !Tasks.calls[0].url.includes("previous="), "index zero starts first task list");
                    Tasks.calls[0].failed("rollback", 400);
                });
                probe("sibling landing", () => {
                    reset();
                    popup.moveRow(3, 2);
                    check(Tasks.tasks.find(t => t.id === "c").parent === "a", "reordering children preserves nesting");
                    check(Tasks.groupedLists[0].tasks[0].children.map(t => t.id).join(",") === "c,b", "upward sibling order matches gap");
                    Tasks.calls[0].failed("rollback", 400);
                    reset();
                    popup.moveRow(2, 3);
                    check(Tasks.calls[0].url.includes("parent=a") && Tasks.calls[0].url.includes("previous=c"), "downward sibling order matches gap");
                    Tasks.calls[0].failed("rollback", 400);
                });
                probe("hold geometry", () => {
                    reset();
                    const list = popup.auditList;
                    const item = list.itemAtIndex(5);
                    const height = list.height;
                    const y = item.y - list.contentY + 12;
                    mousePress(list, 25, y);
                    wait(550);
                    check(popup.auditReorder.dragging, "task held");
                    check(Math.abs(list.height - height) < 1, "hold preserves short list height");
                    check(Math.abs(popup.auditReorder.liftedY + popup.auditReorder.grabOffset - y) < 1, "held row stays under pointer");
                    mouseRelease(list, 25, y);
                    wait(200);
                });
                probe("input during save", () => {
                    reset();
                    Tasks.edit(Tasks.tasks[0], "Saved parent");
                    const child = Tasks.tasks[1];
                    const row = popup.auditList.itemAtIndex(2);
                    mouseClick(popup.auditList, 25, row.y - popup.auditList.contentY + 12);
                    popup.beginEdit(Tasks.tasks[3]);
                    check(popup.editing?.id === "d", "editing can begin during another save");
                    popup.draft = "Queued title";
                    popup.requestedVisible = false;
                    Tasks.calls[0].done({});
                    wait(80);
                    check(Tasks.isCrossed(child), "tap during save is retained");
                    check(Tasks.calls.some(c => c.body?.title === "Queued title"), "closed draft saves after pending request");
                    const queued = Tasks.calls.find(c => c.body?.title === "Queued title");
                    queued.done({});
                    wait(80);
                    check(Tasks.calls.some(c => c.body?.status === "completed"), "close commits queued completion after edit");
                    Tasks.calls.find(c => c.body?.status === "completed").done({});
                });
                probe("move behind write", () => {
                    reset();
                    Tasks.edit(Tasks.tasks[0], "Saved parent");
                    Tasks.move(Tasks.tasks[3], {list: "home", previous: "a"});
                    check(Tasks.calls.length === 1 && Tasks.pending.length === 1, "move waits behind active save");
                    Tasks.calls[0].failed("Offline", 0);
                    wait(80);
                    check(Tasks.calls.length === 2 && Tasks.calls[1].url.includes("/move"), "queued move runs after failed save");
                    Tasks.calls[1].done({id: "moved-d", position: "30"});
                    wait(80);
                    check(Tasks.tasks.find(t => t.id === "moved-d").listId === "home", "queued move uses restored task state");
                });
                probe("edit behind id-changing move", () => {
                    reset();
                    const task = Tasks.tasks[3];
                    Tasks.move(task, {list: "home", previous: "a"});
                    check(Tasks.edit(task, "After move"), "edit is accepted while move is pending");
                    Tasks.calls[0].done({id: "new-d", position: "30"});
                    wait(80);
                    check(Tasks.calls[1].url.includes("/lists/home/tasks/new-d") && Tasks.calls[1].body.title === "After move", "queued edit resolves new server id and task list");
                    Tasks.calls[1].failed("Offline", 0);
                    check(Tasks.tasks.find(t => t.id === "new-d").title === "Work task", "failed queued edit preserves completed move");
                });
                probe("invalid draft on close", () => {
                    reset();
                    popup.beginEdit(Tasks.tasks[3]);
                    popup.draft = "\nKeep these notes";
                    popup.requestedVisible = false;
                    check(popup.editing?.id === "d" && popup.draft.includes("Keep these notes") && Tasks.calls.length === 0 && Tasks.trouble !== "", "invalid draft survives close with an explanation");
                });
                probe("copy and edit controls", () => {
                    reset();
                    const row = popup.auditList.itemAtIndex(5);
                    popup.setKey(row);
                    wait(30);
                    const targets = popup.keyTargets();
                    const copy = targets.find(t => t.name === "Copy Work task");
                    const edit = targets.find(t => t.name === "Edit Work task");
                    check(copy && edit, "copy and edit are both reachable on task row");
                    const point = edit.mapToItem(popup.auditList, 2, 10);
                    mouseClick(popup.auditList, point.x, point.y);
                    wait(30);
                    check(popup.editing?.id === "d" && !Tasks.isCrossed(Tasks.tasks[3]), "edit button takes pointer press without completing task");
                });
                probe("single list launcher", () => {
                    reset();
                    Tasks.lists = [Tasks.lists[0]];
                    check(Launcher.taskResults("new task")[0].subtitle === "add", "single list add preview omits task list name");
                });
                probe("orphans stay visible", () => {
                    reset();
                    Tasks.tasks = [{id: "orphan", listId: "home", title: "Left behind", parent: "missing", position: "10", notes: ""}];
                    check(Tasks.rows.some(r => r.id === "orphan") && Tasks.count === 1, "missing parent does not hide task or badge");
                });
                reset();
                if (failures) throw Error(failures + " regression(s)");
'''

start = harness.SHELL.index("                Tasks.lists =")
end = harness.SHELL.index('                console.log("DONE: tasks");', start)
harness.SHELL = harness.SHELL[:start] + CASES + harness.SHELL[end:]
if __name__ == "__main__":
    raise SystemExit(harness.main())
