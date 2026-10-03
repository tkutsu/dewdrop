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
// months browsed to are fetched when the grid gets there and kept until a poll
// finds the grid has moved on — a month looked at once is not worth re-asking
// for every five minutes, and one still on screen must not lose its dots.
//
// Every calendar the account owns, not only the primary one — birthdays live
// in their own. Not the ones only subscribed to: the public holidays are a
// dot on every Sunday-ish day of the year, and a dot that means "nothing you
// wrote down" is a dot that stops being read.
GoogleService {
    id: root

    readonly property string api: "https://www.googleapis.com/calendar/v3"

    service: "Calendar"
    // Events are written on a phone or in the app, rarely, and a change lands
    // in the grid the next time it is opened — five minutes is plenty.
    pollMs: 5 * 60000

    // The list of calendars changes about once a year, so it is asked for once
    // and again only when it failed, went stale, or a month fetch found one of
    // them gone.
    onFetch: {
        if (!root.haveCalendars || Date.now() - root.calendarsAt > root.calendarsMaxAgeMs)
            root.fetchCalendars();
        else
            root.refreshMonths();
    }

    // --- state ---------------------------------------------------------------
    property var calendars: []
    // Whether the list of calendars has been heard back at all, which is not
    // the same as it being empty. The grid calls `ensure` before it is, and a
    // month fetched from no calendars would publish as a clean month.
    property bool haveCalendars: false
    property real calendarsAt: 0
    readonly property int calendarsMaxAgeMs: 60 * 60000
    // Month key ("2026-09") → the day map for it: day string → events on it.
    // Kept as one object and replaced whole, so a binding on it re-runs.
    property var months: ({})
    property string snapshot: ""

    // Whether a fetch is in the air for a month, so a grid stepping quickly
    // through the year does not ask twice for the same one.
    property var inflight: ({})
    // The month the grid last turned to. A poll keeps this one alongside the
    // current month and drops the rest: pruning it too took the dots off the
    // month being looked at, every five minutes.
    property string lastShown: ""

    // --- days ----------------------------------------------------------------
    function monthKey(date: var): string {
        return root.dayString(date).slice(0, 7);
    }

    readonly property string thisMonth: root.today.slice(0, 7)

    // --- reading -------------------------------------------------------------
    // The events on a day, soonest first, all-day ones ahead of the timed.
    function forDay(day: string, monthKey: var): var {
        const month = root.months[monthKey || day.slice(0, 7)];
        if (!month)
            return [];
        return month[day] ?? [];
    }

    function has(day: string, monthKey: var): bool {
        return root.forDay(day, monthKey).length > 0;
    }

    readonly property var todays: root.forDay(root.today)

    // What the grid calls when it turns to a month it has not seen. A no-op
    // for one already held, so it is safe to call on every render.
    function ensure(date: var): void {
        const key = root.monthKey(date);
        root.lastShown = key;
        if (!root.haveCalendars || root.months[key] || root.inflight[key])
            return;
        root.fetchMonth(date, false);
    }

    function fetchCalendars(): void {
        root.send("GET", `${root.api}/users/me/calendarList?minAccessRole=owner`, null, function (body) {
            root.calendars = (body.items ?? []).filter(c => c.selected === true && c.summary !== CalendarTimers.calendarName).map(c => ({
                id: c.id,
                title: c.summary ?? ""
            }));
            root.haveCalendars = true;
            root.calendarsAt = Date.now();
            root.refreshMonths();
        });
    }

    // Keep the browsed month fresh alongside the current month.
    function refreshMonths(): void {
        root.fetchMonth(Google.now, true);
        if (root.lastShown && root.lastShown !== root.thisMonth) {
            const [year, month] = root.lastShown.split("-").map(Number);
            root.fetchMonth(new Date(year, month - 1, 1), true);
        }
    }

    // One month, from every calendar, gathered and published in one go (see
    // GoogleService.gather): a grid whose dots appeared calendar by calendar
    // would flicker on every poll. `poll` says this is the five-minute pass,
    // which is the one allowed to drop months no longer being looked at.
    function fetchMonth(date: var, poll: bool): void {
        const key = root.monthKey(date);
        if (root.inflight[key])
            return;
        const first = new Date(date.getFullYear(), date.getMonth(), 1 - 7);
        const last = new Date(date.getFullYear(), date.getMonth() + 1, 1 + 14);

        const mark = Object.assign({}, root.inflight);
        mark[key] = true;
        root.inflight = mark;

        const query = `timeMin=${encodeURIComponent(first.toISOString())}&timeMax=${encodeURIComponent(last.toISOString())}&singleEvents=true&orderBy=startTime&maxResults=250`;
        const sources = root.calendars.map(c => ({
                    url: `${root.api}/calendars/${encodeURIComponent(c.id)}/events?${query}`,
                    cal: c
                }));
        root.gather(key, sources, (item, source) => item.status === "cancelled" ? null : root.normalise(item, source.cal), function (events, failed) {
            if (failed.length > 0) {
                // Left unpublished so the grid keeps what it had, and taken
                // out of `inflight` so `ensure` may ask again. A 404 is a
                // calendar that no longer exists: the list is stale, so the
                // next poll fetches it afresh.
                root.land(key);
                if (failed.includes(404))
                    root.haveCalendars = false;
                return;
            }
            root.publish(key, root.byDay(events), poll);
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

    // A month's fetch is over, one way or the other. Only the newest fetch for
    // a key ever gets here (older ones are stale in `gather`), so the flag is
    // the newest one's to clear.
    function land(key: string): void {
        const mark = Object.assign({}, root.inflight);
        delete mark[key];
        root.inflight = mark;
    }

    function publish(key: string, days: var, poll: bool): void {
        root.land(key);

        const next = ({});
        for (const held of Object.keys(root.months))
            if (!poll || held === root.thisMonth || held === root.lastShown)
                next[held] = root.months[held];
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

    // qs ipc call agenda …
    IpcHandler {
        target: "agenda"

        function refresh(): void {
            root.refresh();
        }

        function today(): string {
            if (!root.configured)
                return `Not connected. Run ${Google.setup}`;
            if (!root.loaded)
                return root.trouble !== "" ? root.trouble : "Connecting…";
            const out = root.todays.map(ev => `${root.sayTime(ev)}  ${ev.title}`);
            return out.length > 0 ? out.join("\n") : "Nothing today";
        }
    }
}
