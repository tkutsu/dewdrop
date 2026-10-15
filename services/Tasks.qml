pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Google Tasks, as a list the bar can show and tick things off.
//
// The REST API directly: no packaged client talks to Tasks, and the protocol
// is a token refresh and three GETs. Sign-in is services/Google.qml, polling
// and gathering GoogleService.qml, both shared with the calendar.
GoogleService {
    id: root

    readonly property string api: "https://tasks.googleapis.com/tasks/v1"

    service: "Tasks"
    // Tasks mostly arrive from the phone; two minutes is current enough and
    // nothing against a quota of 50,000 requests a day.
    pollMs: 2 * 60000

    onFetch: root.fetchLists()

    // --- state ---------------------------------------------------------------
    property var lists: []
    property var tasks: []
    // The last list as text, for telling a poll that changed something from one
    // that only proved nothing had. See fetchTasks.
    property string snapshot: ""

    property var crossed: ({})
    property int writing: 0
    property bool commitWanted: false
    property var pending: []
    onWritingChanged: if (writing === 0) Qt.callLater(root.flushPending)

    // Serialize gestures behind a write rather than losing clicks. Resolve
    // each task again: an earlier move may have changed its list or server id.
    function flushPending(): void {
        while (root.writing === 0 && root.pending.length) {
            const action = root.pending[0];
            root.pending = root.pending.slice(1);
            if (action.kind === "renameList") {
                root.renameList(action.id, action.title);
                continue;
            }
            const task = root.tasks.find(t => t.id === action.id);
            if (!task) {
                root.trouble = "Task is no longer available";
                continue;
            }
            if (action.kind === "complete") root.complete(task);
            else if (action.kind === "move") root.move(task, action.destination);
            else root.edit(task, action.text);
        }
        if (root.writing === 0 && root.commitWanted) root.commit();
    }

    function enqueue(kind: string, task: var, extra: var): void {
        root.pending = root.pending.concat([Object.assign({ kind: kind, id: task.id }, extra)]);
    }
    signal committed()

    // --- days ----------------------------------------------------------------
    // Google stores a due date as midnight UTC but means a calendar day. Read
    // as an instant, every task sits a day early west of Greenwich, so the day
    // is taken off the front of the string and compared as text (see
    // Google.dayString).
    function dayOf(task: var): string {
        return task.due ? String(task.due).slice(0, 10) : "";
    }

    readonly property string tomorrow: root.dayString(new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() + 1))

    // Task lists keep Google's list order and each sibling group's manual order.
    function byPosition(a: var, b: var): int {
        const pa = String(a.position ?? "");
        const pb = String(b.position ?? "");
        return pa === pb ? 0 : (pa < pb ? -1 : 1);
    }

    function byDay(a: var, b: var): int {
        const da = root.dayOf(a), db = root.dayOf(b);
        return da === db ? root.byPosition(a, b) : da < db ? -1 : 1;
    }

    // A missing parent must not make a server task disappear from the shell.
    function isTopLevel(task: var): bool {
        return !task.parent || !root.tasks.some(t => t.id === task.parent && t.listId === task.listId);
    }

    readonly property var groupedLists: root.lists.map(l => ({
        id: l.id, title: l.title,
        tasks: root.tasks.filter(t => t.listId === l.id && root.isTopLevel(t)).sort(root.byPosition).map(t =>
            Object.assign({}, t, { children: root.tasks.filter(c => c.listId === l.id && c.parent === t.id).sort(root.byPosition) }))
    }))

    // Empty task lists stay out of the popup; a drag adds them back as places
    // to drop.
    function flatRows(includeEmpty: bool): var {
        const out = [];
        for (const list of root.groupedLists) {
            if (!includeEmpty && !list.tasks.length)
                continue;
            out.push({ kind: "header", id: list.id, title: list.title, listId: list.id });
            for (const task of list.tasks) {
                out.push(Object.assign({}, task, { kind: "task" }));
                task.children.forEach((child, i) =>
                    out.push(Object.assign({}, child, { kind: "subtask", children: [], number: i + 1 })));
            }
        }
        return out;
    }

    readonly property var rows: root.flatRows(false)
    readonly property var dragRows: root.flatRows(true)
    readonly property var ordered: root.rows.filter(r => r.kind !== "header")
    readonly property var topLevel: root.tasks.filter(root.isTopLevel)
    readonly property var overdue: root.topLevel.filter(t => root.dayOf(t) !== "" && root.dayOf(t) < root.today).sort(root.byDay)
    readonly property var due: root.topLevel.filter(t => root.dayOf(t) === root.today).sort(root.byDay)
    readonly property var soon: root.topLevel.filter(t => root.dayOf(t) > root.today).sort(root.byDay)
    readonly property var undated: root.topLevel.filter(t => root.dayOf(t) === "").sort(root.byDay)
    readonly property var defaultList: root.lists.find(l => l.id === Settings.defaultTaskList) ?? root.lists[0] ?? { id: "@default", title: "" }

    // How pressing a task is, as one of four words, drawn as a dot's colour:
    // taken in without reading.
    function urgency(task: var): string {
        const day = root.dayOf(task);
        if (day === "")
            return "none";
        if (day < root.today)
            return "late";
        if (day === root.today)
            return "now";
        return "soon";
    }

    function dotColour(task: var): color {
        switch (root.urgency(task)) {
        case "late": return Theme.taskLate;
        case "now": return Theme.taskToday;
        case "soon": return Theme.taskSoon;
        }
        return Theme.taskUndated;
    }

    // Count overdue, due today, and undated tasks; future-dated tasks stay in
    // the popup until their due day.
    readonly property int count: root.overdue.length + root.due.length + root.undated.length

    readonly property string icon: Theme.glyph.tasks

    // One icon in one colour, however late things are: a list kept for months
    // is mostly overdue, so a warning colour would always be on. The badge,
    // tooltip and popup say what is late.
    readonly property string label: !root.loaded || root.count === 0 ? "" : String(Math.min(root.count, 99))

    readonly property string tooltip: {
        if (!root.configured)
            return `Google Tasks not connected\nRun ${Google.setup}`;
        if (root.trouble !== "")
            return root.trouble;
        if (!root.loaded)
            return "Connecting…";
        const parts = [];
        if (root.overdue.length > 0)
            parts.push(`${root.overdue.length} overdue`);
        if (root.due.length > 0)
            parts.push(`${root.due.length} due today`);
        if (root.undated.length > 0)
            parts.push(`${root.undated.length} undated`);
        // Match the badge count; future-dated tasks are shown in the popup.
        if (parts.length === 0)
            parts.push(root.tasks.length === 0 ? "Nothing on the list" : "Nothing due today");
        return parts.join("  ·  ");
    }

    // Near days by name, far ones by date: "Fri" means something for a week.
    function sayDay(day: string): string {
        if (day === "")
            return "";
        if (day === root.today)
            return "today";
        if (day === root.tomorrow)
            return "tomorrow";
        // A past day as its date; the dot already says "overdue".
        if (day < root.today)
            return Qt.formatDate(new Date(day + "T12:00:00"), "d MMM");
        const at = new Date(day + "T12:00:00");
        const week = new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() + 7);
        if (at < week)
            return Qt.locale().dayName(at.getDay(), Locale.ShortFormat).toLowerCase();
        return Qt.formatDate(at, "d MMM");
    }

    // --- reading -------------------------------------------------------------
    function fetchLists(): void {
        if (root.writing > 0 || root.pending.length || root.commitWanted) return;
        root.gather("lists", [{url: `${root.api}/users/@me/lists?maxResults=100`}],
            l => ({id: l.id, title: l.title}), function (lists, failed) {
            if (failed.length || root.writing > 0) return;
            if (JSON.stringify(lists) !== JSON.stringify(root.lists)) root.lists = lists;
            root.fetchTasks();
        });
    }

    // Every list, not only the default. Gathered and published in one go (see
    // GoogleService.gather); if any list fails, what is on screen stays and
    // `trouble` says so.
    function fetchTasks(): void {
        if (root.writing > 0 || root.pending.length || root.commitWanted) return;
        const sources = root.lists.map(l => ({
                    url: `${root.api}/lists/${l.id}/tasks?showCompleted=false&showHidden=false&maxResults=100`,
                    list: l
                }));
        root.gather("tasks", sources, function (item, source) {
            return {
                id: item.id,
                parent: item.parent ?? "",
                assignmentInfo: item.assignmentInfo ?? null,
                listId: source.list.id,
                listTitle: source.list.title,
                title: item.title ?? "",
                notes: item.notes ?? "",
                due: item.due ?? "",
                position: item.position ?? ""
            };
        }, function (gathered, failed) {
            if (failed.length > 0)
                return;
            const kept = gathered;
            // A fixed order, whatever order the replies came back in.
            kept.sort((a, b) => a.listId !== b.listId ? (a.listId < b.listId ? -1 : 1) : a.position === b.position ? 0 : (a.position < b.position ? -1 : 1));

            // Replaced only when something moved: a new array is a new model,
            // the popup's rows are rebuilt, and Qt leaves the hover on
            // whichever row took the pointer's place until it moves.
            const next = JSON.stringify(kept);
            if (next !== root.snapshot) {
                root.snapshot = next;
                root.tasks = kept;
            }
            root.loaded = true;
        });
    }

    // --- writing -------------------------------------------------------------
    // Cross-outs stay editable until the popup closes or the last tap ages out.
    function isCrossed(task: var): bool {
        return !!root.crossed[task.id];
    }

    function complete(task: var): void {
        if (root.writing > 0) {
            root.enqueue("complete", task, {});
            return;
        }
        const marks = Object.assign({}, root.crossed);
        const checked = !root.isCrossed(task);
        const affected = root.tasks.filter(t => t.id === task.id || (t.listId === task.listId && t.parent === task.id));
        for (const t of affected) {
            if (checked) marks[t.id] = true;
            else delete marks[t.id];
        }
        // Reopening a child also reopens its parent so a parent PATCH cannot
        // silently complete a child that was just uncrossed.
        if (!checked && task.parent) delete marks[task.parent];
        root.crossed = marks;
        if (Object.keys(marks).length) commitDelay.restart();
        else commitDelay.stop();
    }

    function invalidate(): void {
        root.snapshot = "";
        root.generations.tasks = (root.generations.tasks ?? 0) + 1;
        root.generations.lists = (root.generations.lists ?? 0) + 1;
    }

    // Rename the Google list, keeping the selected default attached to its ID.
    function renameList(id: string, text: string): bool {
        const title = text.trim();
        if (!title || title.length > 1024 || /[\r\n]/.test(title)) {
            root.trouble = "Task list name must be one line of 1 to 1024 characters";
            return false;
        }
        const current = root.lists.find(l => l.id === id);
        if (!current) {
            root.trouble = "Task list is no longer available";
            return false;
        }
        if (root.writing > 0) {
            root.pending = root.pending.concat([{ kind: "renameList", id: id, title: title }]);
            return true;
        }
        if (title === current.title) return true;
        const oldLists = root.lists;
        const oldTasks = root.tasks;
        root.writing++;
        root.trouble = "";
        root.invalidate();
        const update = name => {
            root.lists = root.lists.map(l => l.id === id ? Object.assign({}, l, { title: name }) : l);
            root.tasks = root.tasks.map(t => t.listId === id ? Object.assign({}, t, { listTitle: name }) : t);
        };
        update(title);
        root.send("PATCH", `${root.api}/users/@me/lists/${encodeURIComponent(id)}`, { title: title }, body => {
            if (body.title && body.title !== title) update(body.title);
            root.writing--;
            root.fetchTasks();
        }, (why, status) => {
            root.lists = oldLists;
            root.tasks = oldTasks;
            root.writing--;
            root.fail(why, status);
        });
        return true;
    }

    function commit(): void {
        if (root.writing > 0 || root.pending.length) {
            root.commitWanted = true;
            if (root.writing === 0) Qt.callLater(root.flushPending);
            return;
        }
        root.commitWanted = false;
        commitDelay.stop();
        const selected = root.tasks.filter(t => root.isCrossed(t));
        if (!selected.length) return;
        root.writing++;
        root.trouble = "";
        root.invalidate();
        // Children go first: if a child fails, its parent must remain open.
        const children = selected.filter(t => t.parent);
        const parents = selected.filter(t => !t.parent);
        const succeeded = [];
        const blocked = new Set();
        let failed = false;
        const finish = () => {
            const marks = Object.assign({}, root.crossed);
            for (const task of selected) delete marks[task.id];
            root.crossed = marks;
            root.tasks = root.tasks.filter(t => !succeeded.includes(t.id));
            root.writing--;
            root.committed();
            if (!failed) root.fetchTasks();
        };
        const write = (items, next) => {
            let remaining = items.length;
            if (!remaining) { next(); return; }
            const settled = () => { if (--remaining === 0) next(); };
            for (const task of items) {
                if (blocked.has(task.id)) { settled(); continue; }
                root.send("PATCH", `${root.api}/lists/${task.listId}/tasks/${task.id}`, { status: "completed" }, () => {
                    succeeded.push(task.id);
                    settled();
                }, (why, status) => {
                    failed = true;
                    if (task.parent) blocked.add(task.parent);
                    root.fail(why, status);
                    settled();
                });
            }
        };
        write(children, () => write(parents, finish));
    }

    // Optimistic sibling positions are replaced by Google's positions on sync.
    function move(task: var, destination: var): void {
        if (root.writing > 0) {
            root.enqueue("move", task, { destination: destination });
            return;
        }
        if (root.isCrossed(task)) return;
        const current = root.tasks.find(t => t.id === task.id && t.listId === task.listId);
        if (!current) return;
        const list = destination.list || current.listId;
        const parent = destination.parent || "";
        const previous = destination.previous || "";
        const children = root.tasks.filter(t => t.listId === current.listId && t.parent === current.id);
        const target = root.tasks.find(t => t.id === parent && t.listId === list);
        if (parent && (!target || target.parent || target.id === current.id || children.length || target.assignmentInfo || current.assignmentInfo)) return;
        const siblings = root.tasks.filter(t => t.listId === list && (t.parent || "") === parent && t.id !== current.id).sort(root.byPosition);
        const at = previous === "" ? 0 : siblings.findIndex(t => t.id === previous) + 1;
        if (previous && at === 0) return;
        const old = root.tasks;
        const moved = Object.assign({}, current, { listId: list, listTitle: root.lists.find(l => l.id === list)?.title ?? "", parent: parent });
        siblings.splice(at, 0, moved);
        const positions = new Map(siblings.map((t, i) => [t.id, String(i).padStart(20, "0")]));
        root.writing++;
        root.trouble = "";
        root.invalidate();
        root.tasks = old.map(t => {
            if (t.id === current.id) return Object.assign({}, moved, { position: positions.get(t.id) });
            if (t.listId === current.listId && t.parent === current.id)
                return Object.assign({}, t, { listId: list, listTitle: moved.listTitle });
            if (t.listId === list && (t.parent || "") === parent && positions.has(t.id))
                return Object.assign({}, t, { position: positions.get(t.id) });
            return t;
        });
        const query = [];
        if (parent) query.push("parent=" + encodeURIComponent(parent));
        if (previous) query.push("previous=" + encodeURIComponent(previous));
        if (list !== current.listId) query.push("destinationTasklist=" + encodeURIComponent(list));
        root.send("POST", `${root.api}/lists/${current.listId}/tasks/${current.id}/move${query.length ? "?" + query.join("&") : ""}`, null, body => {
            root.tasks = root.tasks.map(t => {
                if (t.id === current.id) return Object.assign({}, t, { id: body.id ?? t.id, position: body.position ?? t.position });
                if (t.parent === current.id && t.listId === list) return Object.assign({}, t, { parent: body.id ?? current.id });
                return t;
            });
            if (body.id && body.id !== current.id) {
                root.pending = root.pending.map(action => Object.assign({}, action, {
                    id: action.id === current.id ? body.id : action.id,
                    destination: action.destination ? Object.assign({}, action.destination, {
                        parent: action.destination.parent === current.id ? body.id : action.destination.parent,
                        previous: action.destination.previous === current.id ? body.id : action.destination.previous
                    }) : undefined
                }));
            }
            root.writing--;
            root.fetchTasks();
        }, (why, status) => {
            root.tasks = old;
            root.writing--;
            root.fail(why, status);
        });
    }

    // Editing preserves the row while the server confirms the new text.
    function edit(task: var, text: string): bool {
        const lines = text.replace(/\r/g, "").split("\n");
        const title = lines.shift().trim();
        const notes = lines.join("\n");
        if (!title) {
            root.trouble = "Task title cannot be empty";
            return false;
        }
        if (title.length > 1024 || notes.length > 8192) {
            root.trouble = "Title or notes too long";
            return false;
        }
        if (root.writing > 0) {
            root.enqueue("edit", task, { text: text });
            return true;
        }
        const current = root.tasks.find(t => t.id === task.id);
        if (!current) return false;
        const old = root.tasks;
        root.writing++;
        root.trouble = "";
        root.invalidate();
        root.tasks = old.map(t => t.id === task.id ? Object.assign({}, t, { title: title, notes: notes }) : t);
        root.send("PATCH", `${root.api}/lists/${current.listId}/tasks/${current.id}`, { title: title, notes: notes }, () => {
            root.writing--;
            root.fetchTasks();
        }, (why, status) => {
            root.tasks = old;
            root.writing--;
            root.fail(why, status);
        });
        return true;
    }

    function add(title: string, day: string, list: string, notes: string): void {
        if (title.trim() === "")
            return;
        list = list || root.defaultList.id;
        const body = {
            title: title.trim()
        };
        if (day !== "")
            body.due = day + "T00:00:00.000Z";
        if (notes !== "")
            body.notes = notes;
        root.send("POST", `${root.api}/lists/${list}/tasks`, body, () => root.fetchTasks(), (why, status) => {
            root.fail(why, status);
            const details = [body.title, root.lists.find(l => l.id === list)?.title ?? "",
                day, notes, why].filter(s => s !== "").join("\n");
            const escaped = details.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            Quickshell.execDetached(["notify-send", "-a", "quickshell", "Task not added", escaped]);
        });
    }

    // A leading day and task list name can appear in either order.
    function parse(text: string): var {
        const words = (text ?? "").trim().split(/\s+/).filter(w => w !== "");
        let day = "", list = null, error = "";
        function takeDay() {
            if (!words.length) return false;
            const parsed = root.readDay(words[0].toLowerCase());
            if (/^\d{4}-\d{2}-\d{2}$/.test(words[0]) && parsed === "") {
                error = "Invalid date";
                return false;
            }
            if (parsed === "") return false;
            day = parsed;
            words.shift();
            return true;
        }
        const leadingDay = takeDay();
        if (!error && words.length) {
            list = root.lists.find(l => l.title.toLowerCase().replace(/\s+/g, "") === words[0].toLowerCase());
            if (list) {
                words.shift();
                if (!leadingDay) takeDay();
            }
        }
        const title = words.join(" ");
        if (!error && title === "")
            error = list ? "No task, only a task list" : day ? "No task, only a day" : "";
        return { ok: title !== "" && error === "", title: title, day: day,
            list: (list ?? root.defaultList).id, error: error };
    }

    // Date keywords for the first word; the task title follows them.
    function readDay(word: string): string {
        if (word === "today")
            return root.today;
        if (word === "tomorrow")
            return root.tomorrow;
        if (/^\d{4}-\d{2}-\d{2}$/.test(word)) {
            const at = new Date(word + "T00:00:00Z");
            return !isNaN(at.getTime()) && at.toISOString().slice(0, 10) === word ? word : "";
        }

        // A weekday means the next one, never today: "mon" on a Monday is
        // next week.
        const locale = Qt.locale();
        for (let ahead = 1; ahead <= 7; ahead++) {
            const at = new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() + ahead);
            const short = locale.dayName(at.getDay(), Locale.ShortFormat).toLowerCase();
            const long = locale.dayName(at.getDay(), Locale.LongFormat).toLowerCase();
            if (word === short || word === long || short.startsWith(word) && word.length >= 3)
                return root.dayString(at);
        }
        return "";
    }

    // The whole `,` line, which makes one of four things: the more of a time
    // it gives, the bigger the thing. In this order:
    //   1. a duration or a clock time first: a timer, or an alarm, which with
    //      a title is also an hour's event on the day it rings;
    //   2. a day, then a clock time and a title: an event, with no alarm;
    //   3. anything else: a task, with its day and task list (parse).
    // Times come from TimersParse.js and days from readDay, so "9:30", "9pm"
    // and "21:30" mean the same here as for alarms, and a bare "9" stays a
    // nine-minute timer: "fri 9 x" is a task due Friday. See calendar-events.md.
    function plan(text: string): var {
        const typed = (text ?? "").trim();
        const timer = Timers.parse(typed);
        if (timer.ok && timer.kind === "countdown")
            return { ok: true, kind: "timer", timer: timer };
        if (timer.ok) {
            // The day the alarm rings, so the two never disagree at midnight.
            const start = new Date(Timers.occurrence(timer.hour, timer.minute, [], Date.now()));
            // The alarm is the ring, already sent to the phone; a calendar
            // reminder on top would ring twice.
            return { ok: true, kind: "alarm", timer: timer,
                event: timer.label ? root.event(timer.label, start, { useDefault: false, overrides: [] }) : null };
        }
        const words = typed.split(/\s+/);
        const day = words.length > 1 ? root.readDay(words[0].toLowerCase()) : "";
        const at = day !== "" ? Timers.parse(words.slice(1).join(" ")) : null;
        if (at?.ok && at.kind === "alarm") {
            if (!at.label)
                return { ok: false, kind: "event", error: "No event, only a time" };
            const [y, m, d] = day.split("-").map(Number);
            return { ok: true, kind: "event", event: root.event(at.label, new Date(y, m - 1, d, at.hour, at.minute), null) };
        }
        const task = root.parse(typed);
        return { ok: task.ok, kind: "task", task: task, error: task.error };
    }

    // Events last an hour.
    function event(title: string, start: var, reminders: var): var {
        return { title: title, start: start, end: new Date(start.getTime() + 3600000), reminders: reminders };
    }

    // What the line makes, said once it is done. The one entry point the
    // launcher and the IPC both use.
    function run(text: string): string {
        const p = root.plan(text);
        if (!p.ok)
            return p.error;
        if (p.kind === "timer")
            return Timers.run(text);
        if (p.kind === "alarm") {
            const said = Timers.run(text);
            // Without the calendar the alarm still rings; the launcher said so.
            if (!p.event || Google.needsConsent)
                return said;
            Agenda.insert(p.event);
            return `${said}, and an event`;
        }
        if (p.kind === "event") {
            Agenda.insert(p.event);
            return `Added ${p.event.title} for ${root.sayDay(root.dayString(p.event.start))} at ${Timers.hhmm(p.event.start.getHours(), p.event.start.getMinutes())}`;
        }
        root.add(p.task.title, p.task.day, p.task.list, "");
        return p.task.day === "" ? `Adding ${p.task.title}` : `Adding ${p.task.title} for ${root.sayDay(p.task.day)}`;
    }

    Timer {
        id: commitDelay
        interval: 10000
        onTriggered: root.commit()
    }

    // qs ipc call tasks …
    IpcHandler {
        target: "tasks"

        function add(line: string): string {
            return root.run(line);
        }

        function refresh(): void {
            root.refresh();
        }

        function list(): string {
            if (!root.configured)
                return `Not connected. Run ${Google.setup}`;
            if (!root.loaded)
                return root.trouble !== "" ? root.trouble : "Connecting…";
            const out = [];
            for (const row of root.rows) {
                if (row.kind === "header") {
                    out.push(row.title + ":");
                    continue;
                }
                const when = root.sayDay(root.dayOf(row));
                const title = (row.kind === "subtask" ? "  " : "") + row.title;
                out.push(when === "" ? title : `${title}  ·  ${when}`);
            }
            return out.length > 0 ? out.join("\n") : "Nothing on the list";
        }
    }
}
