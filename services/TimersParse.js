.pragma library

// Reading what was typed into a timer, for services/Timers.qml.
//
// One grammar for the IPC call and the prompt box, because they are the same
// act: "25m", "1h30", "7:30 wake up". What is not a duration and not a time
// of day is not a timer, and says so rather than guessing. Pure functions of
// their input, which is why they live here and not in the singleton: nothing
// in them reads the list or the clock.

// What can be written here, for the grey line under the launcher's query.
// Forms, not sentences: the label is whatever you write after the time and
// needs no example. These are the shapes the time itself can take, which is
// the part that has to be remembered rather than guessed.
const syntax = ["25m", "1h30", "90s", "7:30", "8pm"].join("   ");

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function hhmm(h, m) {
    return pad(h) + ":" + pad(m);
}

// Plain words for a duration, for the notification that announces it: "25
// minutes" rather than "25:00", which is a readout and not a sentence.
function spell(ms) {
    const t = Math.round(ms / 1000);
    const h = Math.floor(t / 3600);
    const m = Math.floor((t % 3600) / 60);
    const s = t % 60;
    const parts = [];
    if (h > 0)
        parts.push(h === 1 ? "1 hour" : `${h} hours`);
    if (m > 0)
        parts.push(m === 1 ? "1 minute" : `${m} minutes`);
    // Seconds only while they are still most of what was asked for. "45
    // seconds" and "1 minute 30 seconds" are what someone said; "1 hour 30
    // minutes 4 seconds" is a readout being spelled out loud, and the four
    // seconds at the end of it are not why the timer was set.
    if (s > 0 && h === 0 && m < 5)
        parts.push(s === 1 ? "1 second" : `${s} seconds`);
    return parts.length > 0 ? parts.join(" ") : "no time at all";
}

// The next time this hour and minute comes round, in local wall-clock terms
// — built out of a Date for that calendar day rather than by adding 24 hours,
// so the two days a year that are not 24 hours long land on the time that was
// asked for rather than an hour either side of it.
function occurrence(hour, minute, days, from) {
    const base = new Date(from);
    for (let i = 0; i <= 8; i++) {
        const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i, hour, minute, 0, 0);
        if (d.getTime() <= from)
            continue;
        if (days && days.length > 0 && days.indexOf(d.getDay()) < 0)
            continue;
        return d.getTime();
    }
    return from + 86400000;
}

// Which day a plain alarm lands on is the one thing about it that is not in
// what was typed, and the one thing worth getting wrong about at half past
// seven in the morning.
function dayWord(hour, minute) {
    const at = occurrence(hour, minute, [], Date.now());
    return new Date().toDateString() === new Date(at).toDateString() ? "today" : "tomorrow";
}

// "90" (minutes, because that is what a bare number means when you are
// setting a timer), "90s", "1h30m", "1h30", "2h".
function duration(word) {
    const bare = word.match(/^(\d+(?:\.\d+)?)$/);
    if (bare)
        return Math.round(parseFloat(bare[1]) * 60000);

    const hm = word.match(/^(\d+)h(\d+)$/);
    if (hm)
        return (parseInt(hm[1]) * 60 + parseInt(hm[2])) * 60000;

    const parts = word.match(/(\d+(?:\.\d+)?)(h|m|s)/g);
    if (!parts)
        return 0;
    // Only a run of unit-suffixed numbers and nothing else: "1h30m" counts,
    // "at1h" does not.
    if (parts.join("") !== word)
        return 0;
    let total = 0;
    for (const part of parts) {
        const n = parseFloat(part);
        const unit = part.slice(-1);
        total += n * (unit === "h" ? 3600000 : unit === "m" ? 60000 : 1000);
    }
    return Math.round(total);
}

// Returns { ok, kind, ms, hour, minute, label, error }.
function parse(text) {
    const raw = (text ?? "").trim();
    if (raw === "")
        return {
            ok: false,
            error: "Nothing to set"
        };

    const head = raw.split(/\s+/)[0].toLowerCase();
    const rest = raw.slice(raw.split(/\s+/)[0].length).trim();

    // A time of day, which is what a colon means when the number before it
    // could be an hour. "7:30" is half past seven; durations use units
    // instead, so ninety minutes is "90m", not "90:00".
    // "7am" and "7pm" carry no minutes at all.
    const at = head.match(/^(\d{1,2}):(\d{2})(am|pm)?$/) ?? head.match(/^(\d{1,2})()(am|pm)$/);
    if (at) {
        let hour = parseInt(at[1]);
        const minute = at[2] === "" ? 0 : parseInt(at[2]);
        if (at[3] === "pm" && hour < 12)
            hour += 12;
        if (at[3] === "am" && hour === 12)
            hour = 0;
        if (hour < 24 && minute < 60)
            return {
                ok: true,
                kind: "alarm",
                ms: 0,
                hour: hour,
                minute: minute,
                label: rest
            };
    }

    const ms = duration(head);
    if (ms > 0)
        return {
            ok: true,
            kind: "countdown",
            ms: ms,
            hour: 0,
            minute: 0,
            label: rest
        };

    return {
        ok: false,
        error: `Not a time: ${head}`
    };
}

// The parsed time without the label, which the launcher row already shows.
function brief(text) {
    const p = parse(text);
    if (!p.ok)
        return p.error;
    if (p.kind === "alarm")
        return `alarm  ·  ${hhmm(p.hour, p.minute)} ${dayWord(p.hour, p.minute)}`;
    return `timer  ·  ${spell(p.ms)}`;
}
