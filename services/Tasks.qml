pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Google Tasks, as a list the bar can show and tick things off.
//
// The bar speaks the REST API directly rather than shelling out to a client,
// because there is no client to shell out to: nothing packaged here talks to
// Tasks, and the whole protocol is a token refresh and three GETs. The sign-in
// itself lives in services/Google.qml, shared with the calendar, and the
// polling and gathering in GoogleService.qml, likewise.
GoogleService {
    id: root

    readonly property string api: "https://tasks.googleapis.com/tasks/v1"

    service: "Tasks"
    // Every two minutes. Tasks arrive from a phone rather than from this
    // machine, so the bar is watching someone else's typing — often enough to
    // be current when you look, far enough apart to be nothing on a quota of
    // 50,000 requests a day.
    pollMs: 2 * 60000
    polling: Settings.moduleOn("tasks") || (Launcher.shown && Launcher.taskMode)

    onFetch: root.fetchLists()

    // --- state ---------------------------------------------------------------
    property var lists: []
    property var tasks: []
    // The last list as text, for telling a poll that changed something from one
    // that only proved nothing had. See fetchTasks.
    property string snapshot: ""

    // What has just been ticked off, keyed by task id, each with the moment it
    // went. This is what the popup's undo is offered from.
    //
    // Held on a clock rather than cleared when the refetch lands: the refetch
    // is a couple of hundred milliseconds behind the tick, which is not long
    // enough to notice the wrong row went, let alone reach for the undo. Ten
    // seconds is about how long it takes to see it and act.
    property var undoable: ({})
    readonly property int undoMs: 10000

    // --- days ----------------------------------------------------------------
    // Google stores a due date as an RFC 3339 instant pinned to midnight UTC,
    // but it means a calendar day: "due Saturday" and nothing about what time.
    // Reading it as an instant is the bug this comment exists to prevent —
    // anywhere west of Greenwich, midnight UTC on the 26th is the evening of
    // the 25th, and every task in the list would sit a day early. So the day is
    // taken off the front of the string and compared as text, which is also why
    // these are strings rather than dates (see Google.dayString).
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

    // One list, soonest first, undated last. The four groups above are still
    // how the day is counted, but they are no longer how it is shown: headings
    // spent a row each saying what the dates underneath already said, and a
    // list read top to bottom is the same information without them.
    readonly property var ordered: root.overdue.concat(root.due).concat(root.soon).concat(root.undated)

    // How pressing a task is, as one of four words. The popup draws this as the
    // colour of a dot rather than as text: it is the one thing about a row that
    // has to be taken in without reading, and every row has it, so spelling it
    // out puts the same word down the side of the list.
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

    // Deliberately one icon in one colour, however late things are. Warming it
    // for "something is overdue" was the plan and is wrong in practice: a list
    // kept over months is mostly overdue most of the time, so the warm state
    // would be the resting state, and a colour that is always on points at
    // nothing. The badge already counts what is late, the tooltip says how
    // many, and the popup groups them under a heading in the warn colour —
    // which is the one place there is room to read it rather than only notice
    // it.
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

    // How a day is said in a row: near ones by name, far ones by date. "Fri"
    // means something for about a week and then stops — past that the number is
    // the only thing that says how far off it really is.
    function sayDay(day: string): string {
        if (day === "")
            return "";
        if (day === root.today)
            return "today";
        if (day === root.tomorrow)
            return "tomorrow";
        // A day gone by says which day it was, not that it has gone by. "12
        // Sep" is a fact about the task; "overdue" is a judgement the dot
        // beside it is already making, and written out down a whole column it
        // stops being read at all.
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

    // Every list, not only the default one: a list is how people separate work
    // from the shopping, and a bar that showed one of the two would be wrong
    // about the day in a way that is hard to notice.
    //
    // Gathered and published in one go (see GoogleService.gather); a list that
    // could not be read keeps what was on screen rather than publishing a day
    // with a whole list missing from it, and says so in `trouble`.
    function fetchTasks(): void {
        const sources = root.lists.map(l => ({
                    url: `${root.api}/lists/${l.id}/tasks?showCompleted=false&showHidden=false&maxResults=100`,
                    list: l
                }));
        root.gather("tasks", sources, function (item, source) {
            // Google keeps subtasks in the same list with a parent id. They
            // belong under their parent, and the bar has no room to draw a
            // tree, so they stay out of it rather than appearing as loose tasks
            // with no context.
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
            // A row just ticked off may still be in a reply that Google built
            // before the PATCH reached it. It is gone from the bar already;
            // keeping it out until the undo window closes stops it flickering
            // back for a poll.
            const kept = gathered.filter(t => !root.undoable[t.id]);
            // Sorted into a fixed order first, because the replies come back
            // in whatever order the network gives them and the same list must
            // not look different for that reason alone.
            kept.sort((a, b) => a.listId !== b.listId ? (a.listId < b.listId ? -1 : 1) : a.position === b.position ? 0 : (a.position < b.position ? -1 : 1));

            // Replaced only when something actually moved. Every poll builds a
            // new array whether or not anything changed, and a new array is a
            // new model: the popup's rows are destroyed and rebuilt, which
            // drops whatever the pointer was hovering — and Qt does not work
            // out what is under the pointer again until it moves, so the hover
            // is left on whichever row took that position. Same fault the
            // timer popup had once a second; here it would have been once
            // every two minutes, which is rarer and no less baffling.
            const next = JSON.stringify(kept);
            if (next !== root.snapshot) {
                root.snapshot = next;
                root.tasks = kept;
            }
            root.loaded = true;
        });
    }

    // --- writing -------------------------------------------------------------
    // Ticked off here and then confirmed by the refetch. The row disappears at
    // once rather than a second and a half later when Google gets back: the
    // whole reason to tick something off from the bar is not to wait for it.
    function complete(task: var): void {
        const mark = Object.assign({}, root.undoable);
        mark[task.id] = {
            task: task,
            at: Date.now()
        };
        root.undoable = mark;
        root.tasks = root.tasks.filter(t => t.id !== task.id);
        // The list on screen no longer matches the snapshot, so the next fetch
        // must publish whatever it gets. Otherwise a PATCH that failed would
        // refetch the same list, read as "nothing moved", and leave the row
        // gone from the bar while it is still open on Google's side.
        root.snapshot = "";

        const failed = function (why, status) {
            root.fail(why, status);
            root.forget(task.id);
            if (!root.tasks.some(t => t.id === task.id))
                root.tasks = root.tasks.concat([task]);
            root.snapshot = "";
        };
        root.authorised(() => root.send("PATCH", `${root.api}/lists/${task.listId}/tasks/${task.id}`, {
            status: "completed"
        }, () => root.fetchTasks(), failed), failed);
    }

    // The counterpart, for the tick that was meant for the row above. Google
    // clears the completion date itself when the status goes back, but it does
    // not clear `hidden`, and a task left hidden is one that never comes back
    // into the list — so that goes too.
    function restore(task: var): void {
        root.authorised(() => root.send("PATCH", `${root.api}/lists/${task.listId}/tasks/${task.id}`, {
            status: "needsAction",
            completed: null,
            hidden: false
        }, () => {
            root.forget(task.id);
            root.fetchTasks();
        }));
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
        root.authorised(() => root.send("POST", `${root.api}/lists/${list}/tasks`, body, () => root.fetchTasks()));
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

        // A weekday name means the next one of those, and never today: "mon"
        // typed on a Monday is about the week coming, not the day that is
        // nearly over.
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

    // Ages the undos out. One second is finer than it needs to be, but it only
    // runs while something is actually undoable, which is ten seconds after a
    // tick and never otherwise.
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
