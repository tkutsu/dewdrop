pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Google Calendar, read-only, for the clock's month view: which days have
// something on them, and what today's something is.
//
// Events are fetched a month at a time, in a window a week wider either side
// than the month itself so the faint days from the neighbouring months in the
// grid get their dots too. The month on the bar is kept fresh by the poll;
// months browsed to are fetched when the grid gets there and kept until the
// next poll, which drops them — a month looked at once is not worth re-asking
// for every five minutes.
//
// Every calendar the account owns, not only the primary one — birthdays live
// in their own. Not the ones only subscribed to: the public holidays are a
// dot on every Sunday-ish day of the year, and a dot that means "nothing you
// wrote down" is a dot that stops being read.
Singleton {
    id: root

    readonly property string api: "https://www.googleapis.com/calendar/v3"

    // Events are written on a phone or in the app, rarely, and a change lands
    // in the grid the next time it is opened — five minutes is plenty.
    readonly property int pollMs: 5 * 60000

    // --- state ---------------------------------------------------------------
    property var calendars: []
    // Whether the list of calendars has been heard back at all, which is not
    // the same as it being empty. The grid calls `ensure` before it is, and a
    // month fetched from no calendars would publish as a clean month.
    property bool haveCalendars: false
    // Month key ("2026-09") → the day map for it: day string → events on it.
    // Kept as one object and replaced whole, so a binding on it re-runs.
    property var months: ({})
    property string snapshot: ""

    property bool loaded: false
    property string trouble: ""

    readonly property bool configured: Google.configured

    // Whether a fetch is in the air for a month, so a grid stepping quickly
    // through the year does not ask twice for the same one.
    property var inflight: ({})

    // --- days ----------------------------------------------------------------
    function dayString(date: var): string {
        const pad = n => n < 10 ? "0" + n : String(n);
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    function monthKey(date: var): string {
        return root.dayString(date).slice(0, 7);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }

    readonly property string today: root.dayString(clock.date)
    readonly property string thisMonth: root.today.slice(0, 7)

    // --- reading -------------------------------------------------------------
    // The events on a day, soonest first, all-day ones ahead of the timed.
    function forDay(day: string): var {
        const month = root.months[day.slice(0, 7)];
        if (!month)
            return [];
        return month[day] ?? [];
    }

    function has(day: string): bool {
        return root.forDay(day).length > 0;
    }

    readonly property var todays: root.forDay(root.today)

    // What the grid calls when it turns to a month it has not seen. A no-op
    // for one already held, so it is safe to call on every render.
    function ensure(date: var): void {
        const key = root.monthKey(date);
        if (!root.haveCalendars || root.months[key] || root.inflight[key])
            return;
        root.fetchMonth(date, false);
    }

    function refresh(): void {
        root.authorised(() => root.fetchCalendars());
    }

    function fetchCalendars(): void {
        root.send("GET", `${root.api}/users/me/calendarList?minAccessRole=owner`, null, function (body) {
            root.calendars = (body.items ?? []).filter(c => c.selected === true).map(c => ({
                id: c.id,
                title: c.summary ?? ""
            }));
            root.haveCalendars = true;
            // Only the month on the bar survives a poll; the rest are fetched
            // again if the grid goes back to them.
            root.inflight = ({});
            root.fetchMonth(clock.date, true);
        });
    }

    // One month, from every calendar, gathered and published in one go: the
    // replies arrive in whatever order the network gives them, and a grid whose
    // dots appeared calendar by calendar would flicker on every poll.
    function fetchMonth(date: var, prune: bool): void {
        const key = root.monthKey(date);
        const first = new Date(date.getFullYear(), date.getMonth(), 1 - 7);
        const last = new Date(date.getFullYear(), date.getMonth() + 1, 1 + 14);
        const wanted = root.calendars.slice();

        const mark = Object.assign({}, root.inflight);
        mark[key] = true;
        root.inflight = mark;

        if (wanted.length === 0) {
            root.publish(key, {}, prune);
            return;
        }

        const gathered = [];
        let outstanding = wanted.length;
        const query = `timeMin=${encodeURIComponent(first.toISOString())}&timeMax=${encodeURIComponent(last.toISOString())}&singleEvents=true&orderBy=startTime&maxResults=250`;

        for (const cal of wanted)
            root.send("GET", `${root.api}/calendars/${encodeURIComponent(cal.id)}/events?${query}`, null, function (body) {
                for (const item of body.items ?? []) {
                    if (item.status === "cancelled")
                        continue;
                    gathered.push(root.normalise(item, cal));
                }
                outstanding--;
                if (outstanding === 0)
                    root.publish(key, root.byDay(gathered), prune);
            });
    }

    // An event as the grid wants it. Google gives an all-day event as a `date`
    // with an exclusive end, and a timed one as a `dateTime` with an offset.
    // Both are turned into local instants once here so nothing downstream has
    // to know which it was — the days are counted off the local clock, which
    // is the only reading under which "Saturday" means Saturday.
    function normalise(item: var, cal: var): var {
        const allDay = item.start.date !== undefined;
        const start = allDay ? new Date(item.start.date + "T00:00:00") : new Date(item.start.dateTime);
        const end = allDay ? new Date(item.end.date + "T00:00:00") : new Date(item.end.dateTime);
        return {
            id: item.id,
            title: item.summary ?? "(untitled)",
            allDay: allDay,
            start: start.getTime(),
            end: end.getTime(),
            calendar: cal.title
        };
    }

    // The events spread over every day they touch. A stay from Friday to
    // Monday is on Saturday too, and the dot is what says so.
    function byDay(events: var): var {
        const map = ({});
        for (const ev of events) {
            // The last instant of the event, not its end: an end at midnight
            // is the day before, and an all-day end is exclusive anyway.
            const lastDay = new Date(Math.max(ev.start, ev.end - 1));
            for (let d = new Date(ev.start); d <= lastDay; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
                const day = root.dayString(d);
                if (!map[day])
                    map[day] = [];
                map[day].push(ev);
            }
        }
        for (const day of Object.keys(map))
            map[day].sort((a, b) => a.allDay !== b.allDay ? (a.allDay ? -1 : 1) : a.start - b.start);
        return map;
    }

    function publish(key: string, days: var, prune: bool): void {
        const mark = Object.assign({}, root.inflight);
        delete mark[key];
        root.inflight = mark;

        const next = prune ? ({}) : Object.assign({}, root.months);
        next[key] = days;
        // Replaced only when something moved — a new object is a new model,
        // and the grid's hover strands on a rebuilt Repeater (see Tasks).
        const text = JSON.stringify(next);
        if (text !== root.snapshot) {
            root.snapshot = text;
            root.months = next;
        }
        root.loaded = true;
    }

    // --- saying --------------------------------------------------------------
    function sayTime(ev: var): string {
        if (ev.allDay)
            return "all day";
        return Qt.formatTime(new Date(ev.start), "HH:mm");
    }

    // --- talking to Google ---------------------------------------------------
    function send(method: string, url: string, body: var, then: var): void {
        Google.send(method, url, body, function (parsed) {
            root.trouble = "";
            then(parsed);
        }, root.fail);
    }

    function fail(why: string): void {
        // 403 is the one failure with a specific cause here: the Calendar API
        // is not enabled on the project, or the token was granted before the
        // calendar scope was added to it.
        root.trouble = why === "Google said 403" ? "Calendar not granted: enable the API and re-run ~/_scripts/gtasks-setup" : why;
    }

    function authorised(then: var): void {
        Google.authorised(function () {
            root.trouble = "";
            then();
        }, root.fail);
    }

    Component.onCompleted: if (root.configured)
        root.refresh()

    Connections {
        target: Google

        function onReady(): void {
            root.refresh();
        }
    }

    Timer {
        interval: root.pollMs
        running: root.configured
        repeat: true
        onTriggered: root.refresh()
    }

    // qs ipc call agenda …
    IpcHandler {
        target: "agenda"

        function refresh(): void {
            root.refresh();
        }

        function today(): string {
            if (!root.configured)
                return "Not connected. Run ~/_scripts/gtasks-setup";
            if (!root.loaded)
                return root.trouble !== "" ? root.trouble : "Connecting…";
            const out = root.todays.map(ev => `${root.sayTime(ev)}  ${ev.title}`);
            return out.length > 0 ? out.join("\n") : "Nothing today";
        }
    }
}
