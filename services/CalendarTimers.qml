pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "CalendarTimersParse.js" as Parse

// Schedule phone reminders ahead of expiry, with a persistent, serial queue.
GoogleService {
    id: root

    service: "Calendar"
    pollMs: 60000
    polling: false
    onFetch: root.calendarId === "" ? root.findCalendar() : root.drain()

    readonly property string api: "https://www.googleapis.com/calendar/v3"
    readonly property string calendarName: "pc_timers"
    property string calendarId: ""
    property var jobs: []
    signal missedReminder(id: string)
    property bool restored: false
    onRestoredChanged: root.updatePolling()
    onJobsChanged: root.updatePolling()
    onTroubleChanged: root.updatePolling()
    property string timeZone: ""
    readonly property string status: {
        if (Google.needsConsent)
            return "Reconnect Google to schedule calendar reminders.";
        if (root.trouble !== "")
            return root.trouble;
        if (root.loading || root.jobs.length > 0)
            return "Syncing pc_timers...";
        return root.loaded ? "pc_timers synced. Enable its notifications on your phone." : "Calendar reminders have not connected yet.";
    }

    // Recurrences need the PC's IANA zone so weekday alarms survive DST.
    Process {
        command: ["readlink", "-f", "/etc/localtime"]
        running: root.timeZone === ""
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim().split("/zoneinfo/");
                if (path.length === 2)
                    root.timeZone = path[1];
            }
        }
    }

    function prepare(): void {
        if (root.restored && root.calendarId === "" && !Google.needsConsent)
            root.refresh();
    }

    // Poll while there is work queued or trouble to recover from: Retry only
    // runs while polling, so an empty queue with an error would otherwise leave
    // the popup's retry button doing nothing.
    //
    // Set this explicitly: a synchronous stale-job cleanup can change the
    // queue during a refresh, which would loop a binding on its length.
    function updatePolling(): void {
        root.polling = root.restored && (root.jobs.length > 0 || root.trouble !== "");
    }

    // Replace a pending operation for the same event, retaining its ID on retry.
    function enqueue(changes: var): void {
        if (changes.length === 0)
            return;
        let next = root.jobs.slice();
        for (const job of changes) {
            next = next.filter(held => held.id !== job.id);
            next.push(job);
        }
        root.jobs = next;
        root.save();
        if (!root.loading && !Google.needsConsent)
            root.refresh();
    }

    // Search all pages, including hidden calendars, before creating one.
    function findCalendar(): void {
        root.gather("calendars", [{url: `${root.api}/users/me/calendarList?minAccessRole=owner&showHidden=true&maxResults=250`}], (item, source) => item.summary === root.calendarName ? item : null, function (calendars, failed) {
            if (failed.length > 0)
                return;
            if (calendars.length > 1) {
                root.fail("More than one pc_timers calendar exists. Rename one and retry.", 409);
                return;
            }
            if (calendars.length === 1) {
                root.useCalendar(calendars[0]);
                return;
            }
            const body = {summary: root.calendarName};
            if (root.timeZone !== "")
                body.timeZone = root.timeZone;
            root.send("POST", `${root.api}/calendars`, body, calendar => root.useCalendar(calendar));
        });
    }

    function useCalendar(calendar: var): void {
        root.calendarId = calendar.id;
        root.loaded = true;
        root.save();
        root.drain();
    }

    // Only retire the exact job sent: a pause or adjustment can replace it
    // while its reply is in flight, and the replacement must still run.
    function complete(job: var): void {
        root.jobs = root.jobs.filter(held => held !== job);
        root.save();
        root.loaded = true;
        root.drain();
    }

    function requestFailed(why: string, status: int): void {
        if (status === 404) {
            root.calendarId = "";
            root.save();
        }
        root.fail(why, status);
    }

    // Insert with a client ID; an ambiguous success retried as 409 becomes an
    // update, so a timeout cannot create a second reminder.
    function drain(): void {
        if (root.jobs.length === 0)
            return;
        const job = root.jobs[0];
        const url = `${root.api}/calendars/${encodeURIComponent(root.calendarId)}/events`;
        if (job.operation === "delete") {
            root.send("DELETE", `${url}/${job.id}`, null, () => root.complete(job), function (why, status) {
                if (status === 404 || status === 410)
                    root.complete(job);
                else
                    root.requestFailed(why, status);
            });
            return;
        }
        // A timer that expired while offline has nothing left to schedule.
        if (!Parse.recurring(job.entry) && job.entry.endsAt <= Date.now()) {
            root.missedReminder(job.id);
            root.complete(job);
            return;
        }
        if (Parse.recurring(job.entry) && root.timeZone === "") {
            root.fail("Could not read the PC time zone for a repeating alarm.", 400);
            return;
        }
        const body = Parse.event(job.entry, root.timeZone);
        root.send("POST", url, body, () => root.complete(job), function (why, status) {
            if (status === 409)
                root.send("PUT", `${url}/${job.id}`, body, () => root.complete(job), (reason, code) => root.requestFailed(reason, code));
            else
                root.requestFailed(why, status);
        });
    }

    FileView {
        id: file
        path: Paths.state("calendar-timers.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.calendarId = adapter.calendarId;
            root.jobs = adapter.jobs.map(job => Object.assign({}, job));
            root.loaded = root.calendarId !== "";
            root.restored = true;
        }
        onLoadFailed: root.restored = true
        JsonAdapter {
            id: adapter
            property string calendarId: ""
            property list<var> jobs: []
        }
    }

    function save(): void {
        if (!root.restored)
            return;
        adapter.calendarId = root.calendarId;
        adapter.jobs = root.jobs;
        file.writeAdapter();
    }
}
