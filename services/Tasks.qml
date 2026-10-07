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
    polling: Settings.moduleOn("tasks") || (Launcher.shown && Launcher.taskMode)

    onFetch: root.fetchLists()

    // --- state ---------------------------------------------------------------
    property var lists: []
    property var tasks: []
    // The last list as text, for telling a poll that changed something from one
    // that only proved nothing had. See fetchTasks.
    property string snapshot: ""

    // Just ticked off, by task id with the moment it went: what the popup
    // offers undo for. Held for ten seconds, long enough to notice the wrong
    // row went, rather than cleared when the refetch lands.
    property var undoable: ({})
    readonly property int undoMs: 10000
    // Completions still on their way to Google, keyed by task id, each holding
    // the undo tapped meanwhile (or null). Two PATCHes for one task in flight
    // at once can land in either order, and an undo that lands first leaves
    // the task completed with nothing left to undo it, so restore waits here.
    property var completing: ({})

    // --- days ----------------------------------------------------------------
    // Google stores a due date as midnight UTC but means a calendar day. Read
    // as an instant, every task sits a day early west of Greenwich, so the day
    // is taken off the front of the string and compared as text (see
    // Google.dayString).
    function dayOf(task: var): string {
        return task.due ? String(task.due).slice(0, 10) : "";
    }

    readonly property string tomorrow: root.dayString(new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() + 1))

    // --- the groups ----------------------------------------------------------
    // Sorted by day, then by the order they sit in on Google's side, so a list
    // reordered on the phone reads the same here.
    function byDay(a: var, b: var): int {
        const da = root.dayOf(a);
        const db = root.dayOf(b);
        if (da !== db)
            return da < db ? -1 : 1;
        const pa = String(a.position ?? "");
        const pb = String(b.position ?? "");
        return pa === pb ? 0 : (pa < pb ? -1 : 1);
    }

    readonly property var overdue: root.tasks.filter(t => root.dayOf(t) !== "" && root.dayOf(t) < root.today).sort(root.byDay)
    readonly property var due: root.tasks.filter(t => root.dayOf(t) === root.today).sort(root.byDay)
    readonly property var soon: root.tasks.filter(t => root.dayOf(t) > root.today).sort(root.byDay)
    readonly property var undated: root.tasks.filter(t => root.dayOf(t) === "").sort(root.byDay)

    // One list, soonest first, undated last; the groups count, they are not
    // drawn as headings.
    readonly property var ordered: root.overdue.concat(root.due).concat(root.soon).concat(root.undated)

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
        root.send("GET", `${root.api}/users/@me/lists`, null, function (body) {
            root.lists = (body.items ?? []).map(l => ({
                id: l.id,
                title: l.title
            }));
            root.fetchTasks();
        });
    }

    // Every list, not only the default. Gathered and published in one go (see
    // GoogleService.gather); if any list fails, what is on screen stays and
    // `trouble` says so.
    function fetchTasks(): void {
        const sources = root.lists.map(l => ({
                    url: `${root.api}/lists/${l.id}/tasks?showCompleted=false&showHidden=false&maxResults=100`,
                    list: l
                }));
        root.gather("tasks", sources, function (item, source) {
            // Subtasks share the list with a parent id; the bar draws no tree,
            // so they stay out.
            if (item.parent)
                return null;
            return {
                id: item.id,
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
            // A reply built before the PATCH landed may still hold a ticked
            // row; kept out until the undo window closes so it cannot flicker.
            const kept = gathered.filter(t => !root.undoable[t.id]);
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
    // The row goes at once and the refetch confirms it.
    function complete(task: var): void {
        const mark = Object.assign({}, root.undoable);
        mark[task.id] = {
            task: task,
            at: Date.now()
        };
        root.undoable = mark;
        root.tasks = root.tasks.filter(t => t.id !== task.id);
        // The screen no longer matches the snapshot, so the next fetch must
        // publish, or a failed PATCH would read as "nothing moved".
        root.snapshot = "";

        root.completing[task.id] = null;
        const settle = function () {
            const undo = root.completing[task.id];
            delete root.completing[task.id];
            return undo;
        };
        const failed = function (why, status) {
            settle();
            root.fail(why, status);
            root.forget(task.id);
            if (!root.tasks.some(t => t.id === task.id))
                root.tasks = root.tasks.concat([task]);
            root.snapshot = "";
        };
        root.send("PATCH", `${root.api}/lists/${task.listId}/tasks/${task.id}`, {
            status: "completed"
        }, () => {
            const undo = settle();
            if (undo)
                undo();
            else
                root.fetchTasks();
        }, failed);
    }

    // Undo. Google clears the completion date itself but not `hidden`, and a
    // hidden task never comes back into the list.
    function restore(task: var): void {
        if (task.id in root.completing) {
            root.completing[task.id] = () => root.restore(task);
            return;
        }
        root.send("PATCH", `${root.api}/lists/${task.listId}/tasks/${task.id}`, {
            status: "needsAction",
            completed: null,
            hidden: false
        }, () => {
            root.forget(task.id);
            root.fetchTasks();
        });
    }

    function forget(id: string): void {
        const left = ({});
        for (const key of Object.keys(root.undoable))
            if (key !== id)
                left[key] = root.undoable[key];
        root.undoable = left;
    }

    function add(title: string, day: string): void {
        if (title.trim() === "")
            return;
        const list = root.lists.length > 0 ? root.lists[0].id : "@default";
        const body = {
            title: title.trim()
        };
        if (day !== "")
            body.due = day + "T00:00:00.000Z";
        root.send("POST", `${root.api}/lists/${list}/tasks`, body, () => root.fetchTasks());
    }

    // --- reading what was typed ----------------------------------------------
    // A recognised first word schedules the task, just as a time sets a timer.
    // "milk", "tomorrow milk", "fri call the dentist", "2026-10-01 tax".
    function parse(text: string): var {
        const raw = (text ?? "").trim();
        if (raw === "")
            return {
                ok: false,
                title: "",
                day: "",
                error: ""
            };

        const head = raw.split(/\s+/)[0];
        const day = root.readDay(head.toLowerCase());
        if (day === "")
            return {
                ok: true,
                title: raw,
                day: "",
                error: ""
            };

        const title = raw.slice(head.length).trim();
        if (title === "")
            return {
                ok: false,
                title: "",
                day: day,
                error: "No task, only a day"
            };
        return {
            ok: true,
            title: title,
            day: day,
            error: ""
        };
    }

    // Date keywords for the first word; the task title follows them.
    readonly property string syntax: ["today", "tomorrow", "fri", "2026-10-01"].join("   ")

    function readDay(word: string): string {
        if (word === "today")
            return root.today;
        if (word === "tomorrow" || word === "tom")
            return root.tomorrow;
        if (/^\d{4}-\d{2}-\d{2}$/.test(word))
            return word;

        // A weekday means the next one, never today: "mon" on a Monday is
        // next week.
        const locale = Qt.locale();
        for (let ahead = 1; ahead <= 7; ahead++) {
            const at = new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() + ahead);
            const short = locale.dayName(at.getDay(), Locale.ShortFormat).toLowerCase();
            const long = locale.dayName(at.getDay(), Locale.LongFormat).toLowerCase();
            if (word === short || word === long || short.startsWith(word) && word.length >= 2)
                return root.dayString(at);
        }
        return "";
    }

    function run(text: string): string {
        const p = root.parse(text);
        if (!p.ok)
            return p.error;
        root.add(p.title, p.day);
        return p.day === "" ? `Added ${p.title}` : `Added ${p.title} for ${root.sayDay(p.day)}`;
    }

    // Ages the undos out; runs only while something is undoable.
    Timer {
        interval: 1000
        running: Object.keys(root.undoable).length > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const key of Object.keys(root.undoable))
                if (now - root.undoable[key].at > root.undoMs)
                    root.forget(key);
        }
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
            for (const group of [root.overdue, root.due, root.soon, root.undated])
                for (const t of group) {
                    const when = root.sayDay(root.dayOf(t));
                    out.push(when === "" ? t.title : `${t.title}  ·  ${when}`);
                }
            return out.length > 0 ? out.join("\n") : "Nothing on the list";
        }
    }
}
