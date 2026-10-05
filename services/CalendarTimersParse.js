.pragma library

// Calendar payloads and changes, kept independent of the network and clock.
function eventId() {
    return "pct" + Date.now().toString(16) + "0" + Array.from({length: 4}, () => Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, "0")).join("");
}

function recurring(entry) {
    return entry.kind === "alarm" && entry.days.length > 0;
}

function event(entry, timeZone) {
    const at = recurring(entry) ? entry.calendarStart : entry.endsAt;
    const body = {
        id: entry.calendarEventId,
        summary: entry.label || (entry.kind === "alarm" ? "PC alarm" : "PC timer"),
        description: "Set in Quickshell.",
        start: {dateTime: new Date(at).toISOString()},
        end: {dateTime: new Date(at + 60000).toISOString()},
        transparency: "transparent",
        visibility: "private",
        reminders: {useDefault: false, overrides: [{method: "popup", minutes: 0}]},
        extendedProperties: {private: {quickshellTimer: entry.id}}
    };
    if (recurring(entry)) {
        body.start.timeZone = timeZone;
        body.end.timeZone = timeZone;
        const days = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
        body.recurrence = ["RRULE:FREQ=WEEKLY;BYDAY=" + entry.days.map(day => days[day]).join(",")];
    }
    return body;
}

function calendar(entry) {
    return entry.phoneBackend === "calendar" && !!entry.calendarEventId;
}

// A one-off reminder outlives its timer while it rings, so the phone can still
// announce it; a repeating alarm's series stays for its next occurrence.
function lingers(entry) {
    return calendar(entry) && !recurring(entry);
}

function removal(id) {
    return {id: id, operation: "delete"};
}

// Natural expiry leaves the event for the ring to retire (see lingers); removal
// by the user deletes it, including a repeating alarm's future occurrences.
function changes(before, after, now, expired) {
    const jobs = [];
    for (const old of before) {
        if (!calendar(old) || !old.running)
            continue;
        const next = after.find(entry => entry.calendarEventId === old.calendarEventId);
        if ((!next || !next.running) && !expired)
            jobs.push(removal(old.calendarEventId));
    }
    for (const entry of after) {
        if (!calendar(entry) || !entry.running)
            continue;
        const old = before.find(item => item.calendarEventId === entry.calendarEventId);
        if (old && old.running && JSON.stringify(event(old, "")) === JSON.stringify(event(entry, "")))
            continue;
        if (!recurring(entry) && entry.endsAt <= now)
            continue;
        jobs.push({id: entry.calendarEventId, operation: "upsert", entry: entry});
    }
    return jobs;
}
