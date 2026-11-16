pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core

// Google Calendar, for the clock's month view: which days have something on
// them, and what today's something is. The one thing written is an event made
// from the launcher's `,` line (insert).
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
    onThisMonthChanged: if (root.configured && root.polling && !Google.needsConsent) root.refresh()

    // --- reading -------------------------------------------------------------
    // The events on a day, soonest first, all-day ones ahead of the timed.
    function forDay(day: string, monthKey: var): var {
        // Fetches include adjacent days; use them while the new month loads.
        const month = root.months[monthKey || day.slice(0, 7)]
            ?? Object.values(root.months).find(days => days[day] !== undefined);
        if (!month)
            return [];
        return month[day] ?? [];
    }

    function has(day: string, monthKey: var): bool {
        return root.forDay(day, monthKey).length > 0;
    }

    readonly property var todays: root.forDay(root.today)

    // The first event to start on a day after `day`, from the months already
    // held, or null. An empty day asks it; nothing is fetched for it.
    function next(day: string): var {
        const [y, m, d] = day.split("-").map(Number);
        const from = new Date(y, m - 1, d + 1).getTime();
        let best = null;
        for (const month of Object.values(root.months))
            for (const events of Object.values(month))
                for (const ev of events)
                    if (ev.start >= from && (!best || ev.start < best.start))
                        best = ev;
        return best;
    }

    // What the grid calls when it turns to a month it has not seen. A no-op
    // for one already held, so it is safe to call on every render.
    function ensure(date: var): void {
        const key = root.monthKey(date);
        root.lastShown = key;
        if (!root.haveCalendars || root.months[key] || root.inflight[key])
            return;
        root.fetchMonth(date, false);
    }

    // --- colours -------------------------------------------------------------
    // The API still hands out Google's pre-2018 pastels, while the app draws
    // each one in its current shade: a calendar the API calls #9fe1e7 is
    // Peacock, #039be5, on screen. A calendar's 24 colours, old to current;
    // a custom colour comes back as itself and is left alone.
    readonly property var calendarShades: ({
            "#ac725e": "#795548", "#d06b64": "#e67c73", "#f83a22": "#d50000", "#fa573c": "#f4511e",
            "#ff7537": "#ef6c00", "#ffad46": "#f09300", "#42d692": "#009688", "#16a765": "#0b8043",
            "#7bd148": "#7cb342", "#b3dc6c": "#c0ca33", "#fbe983": "#e4c441", "#fad165": "#f6bf26",
            "#92e1c0": "#33b679", "#9fe1e7": "#039be5", "#9fc6e7": "#4285f4", "#4986e7": "#3f51b5",
            "#9a9cff": "#7986cb", "#b99aff": "#b39ddb", "#c2c2c2": "#616161", "#cabdbf": "#a79b8e",
            "#cca6ac": "#ad1457", "#f691b2": "#d81b60", "#cd74e6": "#8e24aa", "#a47ae2": "#9e69af"
        })
    // An event's own colour, by colorId: Lavender, Sage, Grape, Flamingo,
    // Banana, Tangerine, Peacock, Graphite, Blueberry, Basil, Tomato.
    readonly property var eventShades: ({
            "1": "#7986cb", "2": "#33b679", "3": "#8e24aa", "4": "#e67c73", "5": "#f6bf26", "6": "#f4511e",
            "7": "#039be5", "8": "#616161", "9": "#3f51b5", "10": "#0b8043", "11": "#d50000"
        })

    function calendarShade(hex: string): string {
        const key = hex.toLowerCase();
        return root.calendarShades[key] ?? key;
    }

    function fetchCalendars(): void {
        root.gather("calendars", [{url: `${root.api}/users/me/calendarList?minAccessRole=owner`}],
            c => c.selected === true ? {id: c.id, title: c.summary ?? "", colour: root.calendarShade(c.backgroundColor ?? "")} : null, function (calendars, failed) {
            if (failed.length) return;
            root.calendars = calendars;
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
            calendar: cal.title,
            // Its own colour where one was picked for it, as the app shows.
            colour: root.eventShades[item.colorId] ?? cal.colour ?? "",
            // The event's own page in Google Calendar.
            url: item.htmlLink ?? "",
            place: item.location ?? "",
            link: root.meetingLink(item)
        };
    }

    // Where to join a call: Meet's own field, a conference's video entry, a
    // web address given as the place, or a Meet, Zoom or Teams address pasted
    // into the description. The description itself is not kept.
    function meetingLink(item: var): string {
        if (item.hangoutLink)
            return item.hangoutLink;
        const video = (item.conferenceData?.entryPoints ?? []).find(e => e.entryPointType === "video" && e.uri);
        if (video)
            return video.uri;
        const place = (item.location ?? "").match(/https?:\/\/\S+/);
        if (place)
            return place[0];
        const pasted = (item.description ?? "").match(/https?:\/\/(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com)\/[^\s"'<>]+/);
        return pasted ? pasted[0] : "";
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

    // --- writing -------------------------------------------------------------
    // An event on the primary calendar, made from the launcher's `,` line (see
    // Tasks.plan), with the calendar's default reminders. No popup is open to
    // show `trouble` when this fails, so a failure is also sent as a notification.
    function insert(event: var): void {
        // An all-day event is a `date`, and its end is the day after.
        const at = date => event.allDay ? { date: root.dayString(date) } : { dateTime: root.stamp(date) };
        const body = {
            summary: event.title,
            start: at(event.start),
            end: at(event.end)
        };
        if (event.notes)
            body.description = event.notes;
        root.send("POST", `${root.api}/calendars/primary/events`, body, () => {
            // Fetched again even if a fetch is in the air: that one began
            // before the event existed.
            const key = root.monthKey(event.start);
            root.land(key);
            if (root.haveCalendars)
                root.fetchMonth(event.start, false);
        }, (why, status) => {
            root.fail(why, status);
            Notify.send("Event not added", `${event.title}: ${why}`);
        });
    }

    // A local time with its offset from UTC, the form Google reads as that
    // wall-clock time here: "2026-10-23T15:00:00+03:00".
    function stamp(date: var): string {
        const pad = n => n < 10 ? "0" + n : String(n);
        const offset = -date.getTimezoneOffset();
        const sign = offset < 0 ? "-" : "+";
        return `${root.dayString(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}:00${sign}${pad(Math.floor(Math.abs(offset) / 60))}:${pad(Math.abs(offset) % 60)}`;
    }

    // --- saying --------------------------------------------------------------
    function sayTime(ev: var): string {
        if (ev.allDay)
            return "all day";
        return Settings.sayTime(new Date(ev.start));
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
