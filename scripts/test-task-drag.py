#!/usr/bin/env python3
"""Verify vertical task slots and sideways indent previews through real drags."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("task_harness", Path(__file__).with_name("test-tasks.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

CASES = r'''
                const fixture = [
                    {id: "a", title: "Parent", listId: "home", parent: "", position: "10", notes: ""},
                    {id: "c", title: "Child", listId: "home", parent: "a", position: "10", notes: ""},
                    {id: "b", title: "Second task", listId: "home", parent: "", position: "20", notes: ""},
                    {id: "d", title: "Third task", listId: "home", parent: "", position: "30", notes: ""},
                    {id: "w", title: "Work task", listId: "work", parent: "", position: "10", notes: ""}
                ];
                const list = popup.auditList;
                const drag = popup.auditReorder;
                popup.springs = false;
                popup.growX = 1;
                popup.growY = 1;
                let heldY = 0;
                function reset() {
                    drag.finishDrop();
                    Tasks.pending = [];
                    Tasks.writing = 0;
                    Tasks.crossed = ({});
                    Tasks.calls = [];
                    Tasks.trouble = "";
                    Tasks.lists = [{id: "home", title: "Personal"}, {id: "work", title: "Work"}, {id: "empty", title: "Empty"}];
                    Tasks.tasks = fixture.map(t => Object.assign({}, t));
                    wait(200);
                    list.forceLayout();
                }
                function hold(id, x) {
                    const index = Tasks.rows.findIndex(r => r.id === id && r.kind !== "header");
                    const row = list.itemAtIndex(index);
                    heldY = row.y - list.contentY + 12;
                    mousePress(list, x, heldY);
                    wait(500);
                    check(drag.dragging, "hold starts drag for " + id);
                }
                function slot(index) {
                    return list.itemAtIndex(index).y - list.contentY + 12;
                }
                function release(x, y) {
                    mouseRelease(list, x, y);
                    wait(200);
                }
                function named(item, name) {
                    if (item.name === name) return item;
                    for (const child of item.children || []) {
                        const found = named(child, name);
                        if (found) return found;
                    }
                    return null;
                }

                reset();
                const task = Tasks.rows.findIndex(r => r.id === "d");
                const edit = named(list.itemAtIndex(task), "Edit Third task");
                check(edit !== null, "task edit button found");
                mouseMove(edit, 1, edit.height / 2);
                wait(30);
                check(edit.visible, "task edit button is visible");
                mousePress(edit, 1, edit.height / 2);
                wait(350);
                check(!drag.showing && popup.editing === null, "holding task edit neither lifts nor edits before release");
                mouseRelease(edit, 1, edit.height / 2);
                check(popup.editing?.id === "d" && !Tasks.isCrossed(Tasks.tasks.find(t => t.id === "d")),
                    "task edit edge opens the editor without completing the task");
                popup.cancelEdit();

                reset();
                hold("d", 60);
                mouseMove(list, 83, heldY);
                check(popup.dragIndent === 0, "23px right preserves top-level preview");
                mouseMove(list, 84, heldY);
                check(popup.dropDestination.parent === "b" && popup.dragIndent === popup.gutter, "24px right previews nesting under task above stationary slot");
                release(84, heldY);
                check(Tasks.calls.length === 1 && Tasks.calls[0].url.includes("parent=b") && Tasks.tasks.find(t => t.id === "d").parent === "b", "sideways-only drop saves previewed parent to Google");
                Tasks.calls[0].failed("Offline", 0);
                check(Tasks.tasks.find(t => t.id === "d").parent === "", "failed indent restores original depth");

                reset();
                hold("d", 60);
                mouseMove(list, 90, heldY);
                check(popup.dragIndent === popup.gutter, "rightward drag indents held row");
                mouseMove(list, 60, heldY);
                check(popup.dragIndent === 0 && popup.dropDestination.parent === "", "dragging back left removes indent preview");
                release(60, heldY);
                check(Tasks.calls.length === 0, "returning to starting slot and depth sends no move");

                reset();
                hold("c", 90);
                check(popup.dragIndent === popup.gutter, "existing child starts with indented preview");
                mouseMove(list, 66, heldY);
                check(popup.dragIndent === 0 && popup.dropDestination.parent === "", "24px left promotes existing child in preview");
                release(66, heldY);
                check(Tasks.calls.length === 1 && !Tasks.calls[0].url.includes("parent=") && Tasks.calls[0].url.includes("previous=a"), "sideways-only promotion saves top-level sibling coordinates");
                Tasks.calls[0].done({id: "c", position: "15"});

                reset();
                hold("c", 60);
                release(60, heldY);
                check(Tasks.calls.length === 0 && Tasks.tasks.find(t => t.id === "c").parent === "a", "stationary hold preserves an only child");

                reset();
                hold("d", 60);
                const y = slot(3);
                mouseMove(list, 60, y);
                check(drag.to === 3 && popup.dropDestination.parent === "", "vertical motion chooses slot without nesting on its task");
                check(drag.shift(3) === popup.rowHeight, "rows slide to make room at vertical slot");
                mouseMove(list, 84, y);
                check(drag.to === 3 && drag.shift(3) === popup.rowHeight, "horizontal motion preserves slot and row slide");
                check(popup.dropDestination.parent === "a" && popup.dropDestination.previous === "c", "slot after a child joins that child's parent at the correct sibling position");
                release(84, y);
                check(Tasks.calls[0].url.includes("parent=a") && Tasks.calls[0].url.includes("previous=c"), "combined drag saves the previewed slot and depth");
                Tasks.calls[0].done({id: "d", position: "20"});

                reset();
                hold("b", 60);
                const above = slot(1);
                mouseMove(list, 60, above);
                check(popup.dropDestination.parent === "", "hovering over the middle of a task never implicitly nests");
                release(60, above);
                check(Tasks.calls.length === 1 && !Tasks.calls[0].url.includes("parent="), "vertical-only drop stays top-level");
                Tasks.calls[0].done({id: "b", position: "05"});

                reset();
                hold("d", 60);
                const workSlot = slot(6);
                mouseMove(list, 84, workSlot);
                check(popup.dropDestination.list === "work" && popup.dropDestination.parent === "w", "rightward drag can nest at a slot in another task list");
                release(84, workSlot);
                check(Tasks.calls[0].url.includes("destinationTasklist=work") && Tasks.calls[0].url.includes("parent=w"), "cross-list drop saves both list and parent");
                Tasks.calls[0].done({id: "d", position: "10"});

                reset();
                drag.rows = Tasks.rows;
                const first = Tasks.rows.findIndex(r => r.id === "a");
                check(popup.destination(first, first, 24).parent === "", "first slot cannot indent under a list heading");
                check(popup.destination(first, 4, 24).parent === "", "parent with children cannot become a subtask");
                Tasks.crossed = ({ b: true });
                check(popup.destination(4, 4, 24).parent === "", "completed task cannot become an indentation target");
                Tasks.crossed = ({});
                Tasks.tasks = Tasks.tasks.map(t => t.id === "b" ? Object.assign({}, t, { assignmentInfo: {} }) : t);
                drag.rows = Tasks.rows;
                check(popup.destination(4, 4, 24).parent === "", "assigned task cannot become an indentation target");
'''

start = harness.SHELL.index("                Tasks.lists =")
end = harness.SHELL.index('                console.log("DONE: tasks");', start)
harness.SHELL = harness.SHELL[:start] + CASES + harness.SHELL[end:]

if __name__ == "__main__":
    raise SystemExit(harness.main())
