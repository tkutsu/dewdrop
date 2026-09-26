pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Countdowns and alarms — one list, one clock, one place they are
// written down.
//
// Everything that is running is stored as the wall-clock instant it ends at
// rather than as a number of seconds left to decrement. A counter would have
// to be right about every second that passed to be right at the end, and this
// machine suspends: the seconds between the lid closing and opening are ones
// nothing here is awake to count. An instant is simply compared against the
// clock, so a timer that ran out during a suspend has run out, and one that
// did not is still exactly as far from the end as it should be. It is also
// what makes the list worth saving — see the FileView at the foot of this
// file, which restores a timer rather than restarting it.
Singleton {
    id: root

    // How long an unanswered timer keeps making noise before it gives up and
    // leaves the notification to speak for it. Long enough to be come back to
    // from another room, short enough not to be the thing that empties a
    // meeting room.
    readonly property int ringMs: 60000
    readonly property int beatMs: 3000
    readonly property int snoozeMs: 5 * 60000

    // How overdue a restored countdown may be and still be worth announcing.
    // The shell coming back up an hour later should not fire a timer set for a
    // kettle that has long since boiled; one coming back after a crash a
    // minute ago should.
    readonly property int graceMs: 5 * 60000

    // Measured rather than picked by name: it has to finish inside `beatMs` or
    // the next beat starts over the tail of the last one, which is what made
    // the freedesktop set harsh (alarm-clock-elapsed ran 6.1 seconds against a
    // three second beat, so two and often three copies sounded at once). This
    // one is 2.0 seconds, so a beat is a beat rather than a pile. Swap the path
    // if you would rather have something of your own; nothing else depends on
    // it, except that pw-play has to be able to read it — mp3 included, via
    // libsndfile.
    //
    // Kept beside the shell rather than pointed at from it: a path into a media
    // folder is a path someone tidies one day, and the first anyone would hear
    // of that is an alarm that goes off in silence. The file itself is
    // universfield's "new notification 054".
    readonly property string alarmSound: Quickshell.shellPath("sounds/alarm.mp3")

    // --- state ---------------------------------------------------------------
    // Timers and alarms, in the order they were added. Plain objects in a plain
    // array, replaced whole on every change: this list is short and is written
    // to disk each time it moves, so there is nothing to be gained by mutating
    // it in place and a stale binding to be lost by it.
    property var entries: []

    // The ones that have gone off and have not been answered. They leave
    // `entries` when they fire, so nothing is ever in both — which is what lets
    // the bar show a ring without having to ask whether the timer behind it is
    // also still counting.
    property var ringing: []

    // The clock the whole file is read against, moved by the tick below rather
    // than by each reader calling Date.now() for itself. One value per tick
    // means the bar's label, its progress arc and the expiry check are all
    // answering for the same instant.
    property real now: Date.now()

    // Guards the first write. The file loads asynchronously, so there is a
    // window at startup where `entries` is empty because nothing has been read
    // yet rather than because there is nothing to read — saving in it would
    // overwrite the very thing being restored.
    property bool restored: false
    property int nextId: 1

    // --- derived -------------------------------------------------------------
    readonly property var timers: root.entries.filter(e => e.kind !== "alarm")
    readonly property var alarms: root.entries.filter(e => e.kind === "alarm")

    // The one the bar shows. A running timer beats a paused one, and among
    // several the one about to go off wins — that is the one the next glance at
    // the bar is asking about.
    readonly property var focus: {
        const live = root.timers.filter(e => e.running).sort((a, b) => a.endsAt - b.endsAt);
        if (live.length > 0)
            return live[0];
        return root.timers.length > 0 ? root.timers[0] : null;
    }

    readonly property var nextAlarm: {
        const sorted = root.alarms.filter(e => e.running).sort((a, b) => a.endsAt - b.endsAt);
        return sorted.length > 0 ? sorted[0] : null;
    }

    // Whether the bar carries a pill at all. Nothing set, nothing shown — the
    // module is an island of its own for exactly this reason.
    readonly property bool loaded: root.ringing.length > 0 || root.focus !== null || root.nextAlarm !== null

    readonly property real leftMs: root.focus ? root.remaining(root.focus) : 0

    // How far through the current run, for the pill's outline. Elapsed rather
    // than remaining, the same way round as the music pill's track: a line that
    // grows as the thing it measures proceeds. -1 for a pill with nothing
    // running behind it, which is what Pill reads as "draw your own outline".
    readonly property real progress: {
        if (root.ringing.length > 0 || !root.focus || root.focus.total <= 0)
            return -1;
        return Math.max(0, Math.min(1, 1 - root.leftMs / root.focus.total));
    }

    readonly property string glyph: {
        if (root.ringing.length > 0)
            return Theme.glyph.timerRing;
        if (!root.focus)
            return Theme.glyph.alarm;
        return root.focus.running ? Theme.glyph.timer : Theme.glyph.timerPaused;
    }

    readonly property string label: {
        if (root.ringing.length > 0)
            return root.ringTitle(root.ringing[0]);
        if (root.focus)
            return root.clock(root.leftMs);
        if (root.nextAlarm)
            return root.hhmm(root.nextAlarm.hour, root.nextAlarm.minute);
        return "";
    }

    readonly property string tooltip: {
        if (root.ringing.length > 0)
            return root.ringing.map(e => root.ringTitle(e) + " — click to dismiss, right-click to snooze").join("\n");
        const lines = [];
        for (const e of root.timers)
            lines.push(root.describe(e));
        for (const e of root.alarms)
            lines.push(root.describe(e));
        return lines.length > 0 ? lines.join("\n") : "No timers";
    }

    // --- formatting ----------------------------------------------------------
    function pad(n: int): string {
        return n < 10 ? "0" + n : String(n);
    }

    function hhmm(h: int, m: int): string {
        return root.pad(h) + ":" + root.pad(m);
    }

    // Rounded up, so a 25 minute timer reads 25:00 for its first second rather
    // than starting a second in the hole, and only shows 0:00 in the moment it
    // actually has left.
    function clock(ms: real): string {
        const t = Math.max(0, Math.ceil(ms / 1000));
        const h = Math.floor(t / 3600);
        const m = Math.floor((t % 3600) / 60);
        const s = t % 60;
        return h > 0 ? `${h}:${root.pad(m)}:${root.pad(s)}` : `${m}:${root.pad(s)}`;
    }

    // Plain words for a duration, for the notification that announces it: "25
    // minutes" rather than "25:00", which is a readout and not a sentence.
    function spell(ms: real): string {
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

    // What a ring is called. A timer that has gone off keeps only enough of
    // itself to be named — it left the list at the moment it fired — so it
    // cannot be put through describe(), which reads a countdown's remaining
    // time off fields a ring no longer carries. Doing it anyway is how the
    // tooltip came to say "NaN:00 · paused".
    function ringTitle(e: var): string {
        if (e.label !== "")
            return e.label;
        return e.kind === "alarm" ? root.hhmm(e.hour, e.minute) : "Time's up";
    }

    function describe(e: var): string {
        const name = e.label !== "" ? e.label : "";
        if (e.kind === "alarm") {
            const when = root.hhmm(e.hour, e.minute);
            const days = e.days.length > 0 ? " " + e.days.map(d => Qt.locale().dayName(d, Locale.ShortFormat)).join(" ") : "";
            return `${when}${days}${name !== "" ? "  ·  " + name : ""}`;
        }
        const left = root.clock(root.remaining(e));
        return `${left}${name !== "" ? "  ·  " + name : ""}${e.running ? "" : "  ·  paused"}`;
    }

    // Reads the wall clock and publishes it, for the handful of places that are
    // about to work out an instant from "now" rather than draw one.
    //
    // This exists because `now` is deliberately not live: the tick below only
    // runs while there is something to count, so between the last timer being
    // cleared and the next one being set, `now` is frozen at whenever that was.
    // Setting a two minute timer after forty seconds of an empty list therefore
    // gave a timer of one minute twenty — the missing forty seconds had already
    // been spent against a clock that had stopped. Anything that computes an
    // end from a start has to stamp first; anything that only displays can go on
    // reading `now`, which is what keeps every row on a frame agreeing.
    function stamp(): real {
        root.now = Date.now();
        return root.now;
    }

    function remaining(e: var): real {
        if (!e)
            return 0;
        return e.running ? Math.max(0, e.endsAt - root.now) : e.left;
    }

    // --- the list ------------------------------------------------------------
    function _commit(list: var): void {
        root.entries = list;
        root.save();
    }

    function _patch(id: string, changes: var): void {
        root._commit(root.entries.map(e => e.id === id ? Object.assign({}, e, changes) : e));
    }

    function _drop(id: string): void {
        root._commit(root.entries.filter(e => e.id !== id));
    }

    function _add(entry: var): void {
        entry.id = String(root.nextId++);
        root._commit(root.entries.concat([entry]));
    }

    // --- making them ---------------------------------------------------------
    function startCountdown(ms: real, label: string): void {
        root._add({
            id: "",
            kind: "countdown",
            label: label ?? "",
            total: ms,
            endsAt: root.stamp() + ms,
            left: ms,
            running: true,
            hour: 0,
            minute: 0,
            days: []
        });
        root.tick();
    }


    function addAlarm(hour: int, minute: int, label: string, days: var): void {
        root._add({
            id: "",
            kind: "alarm",
            label: label ?? "",
            total: 0,
            endsAt: root.occurrence(hour, minute, days ?? [], root.stamp()),
            left: 0,
            running: true,
            hour: hour,
            minute: minute,
            days: days ?? []
        });
        root.tick();
    }

    // The next time this hour and minute comes round, in local wall-clock terms
    // — built out of a Date for that calendar day rather than by adding 24
    // hours, so the two days a year that are not 24 hours long land on the time
    // that was asked for rather than an hour either side of it.
    function occurrence(hour: int, minute: int, days: var, from: real): real {
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

    // --- changing them -------------------------------------------------------
    function pause(id: string): void {
        const e = root.entries.find(x => x.id === id);
        if (!e || !e.running || e.kind === "alarm")
            return;
        root._patch(id, {
            running: false,
            left: Math.max(0, e.endsAt - root.stamp())
        });
    }

    function resume(id: string): void {
        const e = root.entries.find(x => x.id === id);
        if (!e || e.running)
            return;
        root._patch(id, {
            running: true,
            endsAt: root.stamp() + e.left
        });
    }

    function toggle(id: string): void {
        const e = root.entries.find(x => x.id === id);
        if (!e)
            return;
        // An alarm has nothing to pause, so the toggle turns it off and on
        // instead — the same gesture, and the only one it has room for.
        if (e.kind === "alarm")
            root._patch(id, {
                running: !e.running,
                endsAt: !e.running ? root.occurrence(e.hour, e.minute, e.days, root.stamp()) : e.endsAt
            });
        else if (e.running)
            root.pause(id);
        else
            root.resume(id);
    }

    function cancel(id: string): void {
        root._drop(id);
    }

    // Scrolling the pill. The run gets longer rather than the clock jumping
    // forward: `total` moves with `endsAt`, so the arc stays where it was and
    // the minute is added on the end rather than taken off the part already
    // served.
    function bump(id: string, deltaMs: real): void {
        const e = root.entries.find(x => x.id === id);
        if (!e || e.kind === "alarm")
            return;
        root.stamp();
        const left = root.remaining(e);
        // Never down to nothing: a timer scrolled to zero would fire, which is
        // not what a scroll is for. A second is the floor, and reaching it is
        // the cue to cancel instead.
        const delta = Math.max(deltaMs, 1000 - left);
        if (delta === 0)
            return;
        root._patch(id, {
            total: Math.max(1000, e.total + delta),
            endsAt: e.endsAt + delta,
            left: Math.max(1000, e.left + delta)
        });
    }

    // --- going off -----------------------------------------------------------
    function tick(): void {
        root.now = Date.now();
        root.expire();
    }

    function expire(): void {
        const due = root.entries.filter(e => e.running && e.endsAt <= root.now);
        for (const e of due)
            root.fire(e);
        if (root.ringing.length > 0 && root.now - root.ringing[0].firedAt > root.ringMs)
            root.hush();
    }

    function fire(e: var): void {
        // Out of the list and into the ring. An alarm that repeats goes back in
        // straight away at its next occurrence, which is what keeps a weekday
        // alarm from needing to be re-set every morning.
        if (e.kind === "alarm" && e.days.length > 0)
            root._patch(e.id, {
                endsAt: root.occurrence(e.hour, e.minute, e.days, root.now + 1000)
            });
        else
            root._drop(e.id);

        root.ringing = root.ringing.concat([
            {
                id: e.id,
                kind: e.kind,
                label: e.label,
                hour: e.hour,
                minute: e.minute,
                firedAt: root.now
            }
        ]);

        const title = e.kind === "alarm" ? "Alarm" : "Timer";
        const body = e.label !== "" ? e.label : (e.kind === "alarm" ? root.hhmm(e.hour, e.minute) : root.spell(e.total));
        root.notify(title, body, true);
        root.beat();
    }


    // Stop the noise. The notifications stay where they are — the centre keeps
    // them, and an alarm that went off while the room was empty is worth
    // finding afterwards.
    function hush(): void {
        root.ringing = [];
    }

    // Whatever emptied the ring — dismissed, snoozed, or the whole list thrown
    // away — the sound stops with it. As a handler on the list rather than a
    // line inside hush(), because there are three ways for it to empty and only
    // one of them went through hush; clearing the timers used to leave the rest
    // of the alarm playing to itself.
    onRingingChanged: if (root.ringing.length === 0)
        ring.running = false

    function snooze(minutes: int): void {
        if (root.ringing.length === 0)
            return;
        const e = root.ringing[0];
        const ms = (minutes > 0 ? minutes : 5) * 60000;
        root.ringing = root.ringing.slice(1);
        root._add({
            id: "",
            kind: "countdown",
            label: e.label !== "" ? e.label : "snoozed",
            total: ms,
            endsAt: root.stamp() + ms,
            left: ms,
            running: true,
            hour: 0,
            minute: 0,
            days: []
        });
    }

    function notify(title: string, body: string, urgent: bool): void {
        Quickshell.execDetached(["notify-send", "-a", "quickshell", "-u", urgent ? "critical" : "normal", title, body]);
    }

    // One sound at a time, and one this file can still stop. execDetached sets
    // a process loose with no handle on it, so an alarm answered mid-note went
    // on sounding until the file ran out; a Process can be told to stop, which
    // is what `running = false` does.
    function beat(): void {
        if (!ring.running)
            ring.running = true;
    }

    Process {
        id: ring

        command: ["pw-play", root.alarmSound]
        // A reload would otherwise leave this one behind still playing, one
        // orphan per reload — the same care the pactl feed takes.
        Component.onDestruction: running = false
    }

    // --- reading what was typed ----------------------------------------------
    // One grammar for the IPC call and the prompt box, because they are the
    // same act: "25m", "1h30", "7:30 wake up". What is not a duration
    // and not a time of day is not a timer, and says so rather than guessing.
    //
    // Returns { ok, kind, ms, hour, minute, label, error }.
    function parse(text: string): var {
        const raw = (text ?? "").trim();
        if (raw === "")
            return {
                ok: false,
                error: "Nothing to set"
            };

        const head = raw.split(/\s+/)[0].toLowerCase();
        const rest = raw.slice(raw.split(/\s+/)[0].length).trim();

        // A time of day, which is what a colon means when the number before it
        // could be an hour. "7:30" is half past seven; "90:00" is not a time,
        // so it falls through to the duration reading below and is ninety
        // minutes.
        const at = head.match(/^(\d{1,2}):(\d{2})(am|pm)?$/);
        if (at) {
            let hour = parseInt(at[1]);
            const minute = parseInt(at[2]);
            const suffix = at[3];
            if (suffix === "pm" && hour < 12)
                hour += 12;
            if (suffix === "am" && hour === 12)
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

        // "7am" / "7pm" with no minutes at all.
        const oclock = head.match(/^(\d{1,2})(am|pm)$/);
        if (oclock) {
            let hour = parseInt(oclock[1]);
            if (oclock[2] === "pm" && hour < 12)
                hour += 12;
            if (oclock[2] === "am" && hour === 12)
                hour = 0;
            if (hour < 24)
                return {
                    ok: true,
                    kind: "alarm",
                    ms: 0,
                    hour: hour,
                    minute: 0,
                    label: rest
                };
        }

        const ms = root.duration(head);
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

    // "90" (minutes, because that is what a bare number means when you are
    // setting a timer), "90s", "1h30m", "1h30", "2h".
    function duration(word: string): real {
        const bare = word.match(/^(\d+(?:\.\d+)?)$/);
        if (bare)
            return Math.round(parseFloat(bare[1]) * 60000);

        const hm = word.match(/^(\d+)h(\d+)$/);
        if (hm)
            return (parseInt(hm[1]) * 60 + parseInt(hm[2])) * 60000;

        let total = 0;
        let seen = false;
        const parts = word.match(/(\d+(?:\.\d+)?)(h|m|s)/g);
        if (!parts)
            return 0;
        // Only a run of unit-suffixed numbers and nothing else: "1h30m" counts,
        // "at1h" does not.
        if (parts.join("") !== word)
            return 0;
        for (const part of parts) {
            const n = parseFloat(part);
            const unit = part.slice(-1);
            total += n * (unit === "h" ? 3600000 : unit === "m" ? 60000 : 1000);
            seen = true;
        }
        return seen ? Math.round(total) : 0;
    }

    // What `run` would do, without doing it. The prompt box shows this under
    // the line as it is typed, which is what saves the box from needing a
    // confirmation step: the answer to "did it understand me" is already on
    // screen before Enter is pressed.
    function preview(text: string): string {
        const p = root.parse(text);
        if (!p.ok)
            return (text ?? "").trim() === "" ? "" : p.error;

        if (p.kind === "alarm") {
            // Which day it lands on is the one thing about an alarm that is
            // not in what was typed, and the one thing worth getting wrong
            // about at half past seven in the morning.
            const at = root.occurrence(p.hour, p.minute, [], Date.now());
            const today = new Date().toDateString() === new Date(at).toDateString();
            return `Alarm ${root.hhmm(p.hour, p.minute)} ${today ? "today" : "tomorrow"}${p.label !== "" ? "  ·  " + p.label : ""}`;
        }

        return `Timer ${root.spell(p.ms)}${p.label !== "" ? "  ·  " + p.label : ""}`;
    }

    // What can be written here, for the grey line under the launcher's query.
    // Kept beside parse() rather than in the launcher, because it is a
    // description of parse() and nothing else — a form added there and not
    // here is a form nobody ever finds.
    //
    // Forms, not sentences: the label is whatever you write after the time and
    // needs no example. These are the six shapes the time itself can take,
    // which is the part that has to be remembered rather than guessed.
    readonly property string syntax: ["25m", "1h30", "90s", "7:30", "8pm"].join("   ")

    // The same reading as preview(), without the label echoed back. For a row
    // that is already showing what was typed — see the launcher's timer mode.
    function brief(text: string): string {
        const p = root.parse(text);
        if (!p.ok)
            return p.error;
        if (p.kind === "alarm") {
            const at = root.occurrence(p.hour, p.minute, [], Date.now());
            const today = new Date().toDateString() === new Date(at).toDateString();
            return `alarm  ·  ${root.hhmm(p.hour, p.minute)} ${today ? "today" : "tomorrow"}`;
        }
        return `timer  ·  ${root.spell(p.ms)}`;
    }

    // Parse and act. The one entry point the prompt and the IPC both use, so
    // there is one answer to "what does typing this do".
    function run(text: string): string {
        const p = root.parse(text);
        if (!p.ok)
            return p.error;

        if (p.kind === "alarm") {
            root.addAlarm(p.hour, p.minute, p.label, []);
            return `Alarm set for ${root.hhmm(p.hour, p.minute)}`;
        }
        root.startCountdown(p.ms, p.label);
        return `Timer set for ${root.spell(p.ms)}`;
    }

    // --- the clock -----------------------------------------------------------
    // One second while something is counting down in front of someone, five
    // while the only thing pending is an alarm hours away. A countdown's label
    // changes every second and has to; an alarm's does not change at all until
    // it goes off, and a per-second wakeup for it would be the bar redrawing
    // all night to show the same four digits.
    readonly property bool counting: root.timers.some(e => e.running) || root.ringing.length > 0

    Timer {
        interval: root.counting ? 1000 : 5000
        running: root.entries.length > 0 || root.ringing.length > 0
        repeat: true
        onTriggered: root.tick()
    }

    // The ring, on its own timer rather than one sound per tick: the file is
    // about a second long and a beat a second would be a siren.
    Timer {
        interval: root.beatMs
        running: root.ringing.length > 0
        repeat: true
        onTriggered: root.beat()
    }

    // --- written down --------------------------------------------------------
    // No watchChanges: nothing else writes this file, and a watcher on a file
    // we save on every change is a reload for every keystroke that reaches it.
    FileView {
        id: file

        path: Quickshell.env("HOME") + "/.local/state/quickshell/timers.json"
        printErrors: false

        onLoaded: root.adopt()
        // First run: there is no file because there has never been a timer.
        // Write the empty one now so the save path is known to work before it
        // is needed at the other end of a 25 minute wait.
        onLoadFailed: {
            root.restored = true;
            file.writeAdapter();
        }

        JsonAdapter {
            id: adapter

            property list<var> entries: []
        }
    }

    function save(): void {
        if (!root.restored)
            return;
        adapter.entries = root.entries;
        file.writeAdapter();
    }

    // What survives a restart, and what does not.
    //
    // An alarm is a standing instruction and comes back as one, re-aimed at its
    // next occurrence. A paused timer is untouched — it was not counting while
    // the shell was down either. A running one is judged on how overdue it is:
    // still to come, it carries on to the same instant it was always going to
    // end at; a few minutes past, it goes off now, late but not useless; long
    // past, it is dropped without a sound, because a timer for something that
    // finished an hour ago has nothing left to say.
    function adopt(): void {
        const stored = adapter.entries ?? [];
        const now = Date.now();
        const kept = [];
        const late = [];
        let top = 0;

        for (const raw of stored) {
            const e = Object.assign({}, raw);
            top = Math.max(top, parseInt(e.id) || 0);

            if (e.kind === "alarm") {
                e.days = e.days ?? [];
                e.endsAt = root.occurrence(e.hour, e.minute, e.days, now);
                kept.push(e);
                continue;
            }
            if (!e.running) {
                kept.push(e);
                continue;
            }
            if (e.endsAt > now) {
                kept.push(e);
                continue;
            }
            if (now - e.endsAt <= root.graceMs)
                late.push(e);
        }

        root.nextId = top + 1;
        root.entries = kept.concat(late);
        root.restored = true;
        root.tick();
        root.save();
    }

    // qs ipc call timer …
    IpcHandler {
        target: "timer"

        // Everything the grammar takes: "25m", "1h30 bread", "7:30 wake up",
        // "7:30 wake up".
        function set(spec: string): string {
            return root.run(spec);
        }

        // The pill's own actions, for a keybind that does not want to go
        // through the pointer.
        function toggle(): void {
            if (root.focus)
                root.toggle(root.focus.id);
        }

        function cancel(): void {
            if (root.ringing.length > 0)
                root.hush();
            else if (root.focus)
                root.cancel(root.focus.id);
        }

        function snooze(minutes: int): void {
            root.snooze(minutes);
        }

        function clear(): void {
            root.hush();
            root._commit([]);
        }

        function list(): string {
            return root.tooltip;
        }
    }
}
