#!/usr/bin/env python3
"""Exercise the real QML timer services with Google and state isolated."""

import os
import json
import time
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

GOOGLE = """pragma Singleton
import QtQuick
import Quickshell
Singleton {
    id: root
    property bool configured: true
    property bool needsConsent: false
    property string reconnect: "Google needs reconnecting"
    property string today: "2026-10-03"
    signal ready
    property var calls: []
    property var pending: []
    function authorised(then, fail) { then(); }
    function send(method, url, body, then, fail) {
        calls = calls.concat([{method, url, body}]);
        pending = pending.concat([{then, fail}]);
    }
    function reply(body, status) {
        const request = pending[0];
        pending = pending.slice(1);
        if (status >= 400) request.fail("Google said " + status, status);
        else request.then(body);
    }
}
"""

RETRY = """import QtQuick
QtObject {
    property bool active: true
    property bool pending: false
    signal triggered
    function cancel() { pending = false; }
    function reset() { pending = false; }
    function schedule() { pending = true; }
    function retryNow() { reset(); triggered(); }
}
"""

TEST = """import QtQuick
import Quickshell
import qs
import qs.services
import "services/CalendarTimersParse.js" as Parse
ShellRoot {
    property var timerService: Timers
    property var calendarService: CalendarTimers
    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    function last() { return Google.calls[Google.calls.length - 1]; }
    function run() {
        try {
            check(Timers.restored && CalendarTimers.restored, "state restored");
            check(Timers.phoneBackend === "pushover", "Pushover remains default");
            const instant = Date.now();
            const overdue = (id, age, kind, days) => ({id, kind, days, running: true,
                endsAt: instant - age, hour: 7, minute: 30, label: id, total: 1500000,
                phoneBackend: "pushover"});
            Timers.entries = [overdue("ancient", 3600000, "countdown", [])];
            Timers.now = instant;
            Timers.expire();
            check(Timers.ringing.length === 0 && Timers.entries.length === 0,
                "wake drops old countdown without ringing");
            Timers.entries = [overdue("repeat", 3600000, "alarm", [1, 2, 3, 4, 5])];
            Timers.expire();
            check(Timers.ringing.length === 0 && Timers.entries[0].endsAt > instant,
                "wake rearms old repeating alarm without ringing");
            Timers.entries = [overdue("boundary", Timers.graceMs, "countdown", [])];
            Timers.expire();
            check(Timers.ringing.some(e => e.id === "boundary"), "five-minute grace remains inclusive");
            Timers.hush();
            Timers.entries = [];
            Timers.startCountdown(3600000, "existing Pushover timer");
            check(Google.calls.length === 0, "Pushover does not call Google");
            const pushover = Timers.entries[0];

            Timers.selectPhoneBackend("calendar");
            check(last().url.includes("showHidden=true"), "hidden calendars searched");
            Google.reply({items: [], nextPageToken: "second-page"}, 200);
            check(last().url.includes("pageToken=second-page"), "calendar pagination");
            Google.reply({items: [{id: "pc-test", summary: "pc_timers"}]}, 200);
            check(CalendarTimers.calendarId === "pc-test", "existing calendar reused");
            check(Timers.entries[0].phoneBackend === "pushover", "existing timers keep backend");
            Timers.cancel(pushover.id);

            Timers.startCountdown(3600000, "bread");
            let entry = Timers.entries[0];
            const firstId = entry.calendarEventId;
            check(/^[0-9a-v]{5,1024}$/.test(firstId), "valid client event ID");
            check(last().method === "POST", "calendar timer inserted ahead of expiry");
            check(last().body.start.dateTime === new Date(entry.endsAt).toISOString(), "exact deadline");
            check(last().body.reminders.overrides[0].minutes === 0, "remind at expiry");
            check(last().body.reminders.overrides[0].method === "popup", "popup reminder");
            check(last().body.transparency === "transparent", "does not block calendar");
            Google.reply(null, 409);
            check(last().method === "PUT" && last().body.id === firstId, "duplicate insert becomes update");
            Google.reply({}, 200);
            check(CalendarTimers.jobs.length === 0, "accepted job retired");

            Timers.bump(entry.id, 60000);
            check(last().body.id === firstId, "adjustment keeps event ID");
            Timers.pause(entry.id);
            check(CalendarTimers.jobs[0].operation === "delete", "pause queued while adjustment in flight");
            Google.reply({}, 200);
            check(last().method === "DELETE", "in-flight reply preserves pending pause");
            Google.reply(null, 410);
            check(CalendarTimers.jobs.length === 0, "already deleted is success");

            Timers.resume(entry.id);
            entry = Timers.entries[0];
            check(entry.calendarEventId !== firstId, "resume uses fresh ID after delete");
            Google.reply({}, 200);
            Timers.cancel(entry.id);
            check(last().method === "DELETE", "cancel deletes reminder");
            Google.reply(null, 204);

            Timers.startCountdown(3600000, "expires");
            entry = Timers.entries[0];
            Google.reply({}, 200);
            const callsBeforeExpiry = Google.calls.length;
            Timers.fire(entry);
            check(Google.calls.length === callsBeforeExpiry, "natural expiry preserves phone reminder");
            check(Pushover.phoneAlerts.length === 0, "calendar expiry does not send Pushover");
            Timers.hush();

            CalendarTimers.timeZone = "Europe/Athens";
            Timers.addAlarm(7, 30, "weekday", [1, 2, 3, 4, 5]);
            entry = Timers.entries[0];
            check(last().body.recurrence[0] === "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "weekday recurrence");
            check(last().body.start.timeZone === "Europe/Athens", "DST-aware recurrence");
            Google.reply({}, 200);
            const beforeRepeat = Google.calls.length;
            Timers.fire(entry);
            check(Google.calls.length === beforeRepeat, "local repeat does not reschedule server recurrence");
            Timers.hush();
            Timers.toggle(entry.id);
            check(last().method === "DELETE", "disable repeating alarm deletes series");
            Google.reply({}, 200);
            Timers.toggle(entry.id);
            check(Timers.entries[0].calendarEventId !== entry.calendarEventId, "reenable alarm has fresh ID");
            Google.reply({}, 200);
            Timers.cancel(entry.id);
            Google.reply({}, 200);

            CalendarTimers.calendarId = "";
            CalendarTimers.prepare();
            Google.reply({items: []}, 200);
            check(last().method === "POST" && last().body.summary === "pc_timers", "missing calendar created");
            Google.reply({id: "new-calendar"}, 200);

            Timers.startCountdown(3600000, "network failure");
            entry = Timers.entries[0];
            Google.reply(null, 503);
            check(CalendarTimers.jobs.length === 1 && CalendarTimers.trouble !== "", "failed job retained visibly");
            CalendarTimers.retryNow();
            check(last().body.id === entry.calendarEventId, "retry keeps event ID");
            Google.reply({}, 200);
            check(CalendarTimers.trouble === "", "successful retry clears trouble");
            Timers.cancel(entry.id);
            Google.reply({}, 200);
            check(CalendarTimers.jobs.length === 0 && !CalendarTimers.polling, "idle queue stops polling");
            const calendar = CalendarTimers.calendarId;
            CalendarTimers.calendarId = "";
            CalendarTimers.prepare();
            Google.reply(null, 503);
            check(CalendarTimers.trouble !== "" && CalendarTimers.polling, "failed lookup with an empty queue keeps retry live");
            CalendarTimers.retryNow();
            Google.reply({items: [{id: calendar, summary: "pc_timers"}]}, 200);
            check(CalendarTimers.calendarId === calendar && CalendarTimers.trouble === "" && !CalendarTimers.polling, "recovered lookup stops polling");

            const stale = {id: "stale", operation: "upsert", entry: {kind: "countdown", endsAt: Date.now() - 1000}};
            const beforeStale = Google.calls.length;
            CalendarTimers.enqueue([stale]);
            check(CalendarTimers.jobs.length === 0 && Google.calls.length === beforeStale, "expired offline job discarded");

            Google.needsConsent = true;
            Timers.startCountdown(3600000, "unsynced expiry");
            const unsynced = Timers.entries[0];
            Timers.fire(unsynced);
            check(Timers.testWarnings.includes("Calendar reminder was never synced"), "unsynced expiry warns about missing phone reminder");
            Timers.hush();
            CalendarTimers.jobs = [];
            Timers.startCountdown(3600000, "persisted offline");
            check(CalendarTimers.jobs.length === 1, "offline reminder queued");
            console.log("PASS: calendar timer lifecycle, races, recurrence and retries");
            finish.restart();
        } catch (error) {
            console.log("FAIL: " + error + "\n" + error.stack);
            Qt.quit();
        }
    }
    Timer { interval: 100; running: true; onTriggered: run() }
    Timer { id: finish; interval: 250; onTriggered: Qt.quit() }
}
"""

RESTORE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    property var timerService: Timers
    property var calendarService: CalendarTimers
    Timer {
        interval: 100
        running: true
        onTriggered: {
            Google.needsConsent = true;
            const ok = Timers.restored && Timers.phoneBackend === "calendar"
                && Timers.entries.length === 1 && CalendarTimers.jobs.length === 1
                && CalendarTimers.jobs[0].id === Timers.entries[0].calendarEventId;
            Google.needsConsent = false;
            CalendarTimers.refresh();
            Google.reply({}, 200);
            const sentOnce = Google.calls.length === 1 && CalendarTimers.jobs.length === 0;
            console.log(ok && sentOnce ? "PASS: timer backend and pending reminder survive restart without duplicate delivery" : "FAIL: restart persistence or duplicate restored job");
            Qt.quit();
        }
    }
}
"""


RESTORE_ALARMS = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    property var timers: Timers
    property var calendar: CalendarTimers
    Timer {
        interval: 100
        running: true
        onTriggered: {
            try {
                const ahead = Timers.entries.find(e => e.label === "ahead");
                if (!ahead || ahead.endsAt !== EXPECTED_END)
                    throw Error("future one-shot alarm keeps its original deadline");
                if (!Timers.ringing.some(e => e.label === "recent"))
                    throw Error("recently missed one-shot alarm rings at startup");
                if (Timers.entries.some(e => e.label === "ancient") || Timers.ringing.some(e => e.label === "ancient"))
                    throw Error("old one-shot alarm is dropped instead of moving to tomorrow");
                if (!Timers.entries.some(e => e.label === "disabled" && !e.running))
                    throw Error("disabled alarm is retained without firing");
                if (!Timers.entries.some(e => e.label === "repeat" && e.endsAt > Date.now()))
                    throw Error("recurring alarm is rearmed");
                if (Google.calls.length !== 0)
                    throw Error("synced timers are not reuploaded at startup");
                console.log("PASS: missed one-shot alarms and synced startup");
            } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}
"""

def main():
    """Launch offscreen against mocks, then restart using the saved state."""
    with tempfile.TemporaryDirectory(prefix="quickshell-calendar-test-") as folder:
        target = Path(folder)
        services = target / "services"
        services.mkdir()
        for name in ("Timers.qml", "Pushover.qml", "Http.qml", "TimersParse.js", "CalendarTimers.qml", "CalendarTimersParse.js", "GoogleService.qml", "WallClock.qml"):
            source = (ROOT / "services" / name).read_text()
            if name == "Timers.qml":
                source = source.replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]')
                source = source.replace('    function notify(title: string, body: string, urgent: bool): void {', '    property var testWarnings: []\n    function notify(title: string, body: string, urgent: bool): void {\n        root.testWarnings = root.testWarnings.concat([body]);\n        return;')
            (services / name).write_text(source)
        (services / "Google.qml").write_text(GOOGLE)
        (services / "Retry.qml").write_text(RETRY)
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var glyph: ({timer: "", alarm: "", timerRing: "", timerPaused: ""}) }\n')
        (target / "Paths.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function state(name) { return Quickshell.shellPath("state/" + name); } function data(name) { return Quickshell.shellPath("data/" + name); } }\n')
        (target / "state").mkdir()
        (target / "data").mkdir()
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime), XDG_DATA_HOME=str(target / "data"), XDG_STATE_HOME=str(target / "state"))
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        for content, expected in ((TEST, "PASS: calendar timer lifecycle"), (RESTORE, "PASS: timer backend")):
            (target / "shell.qml").write_text(content)
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            print(output, end="")
            if result.returncode != 0 or expected not in output or "FAIL:" in output:
                return 1
        now = int(time.time() * 1000)
        ends = now + 3600000
        entries = []
        for index, (label, at, days, running) in enumerate([
            ("ahead", ends, [], True), ("recent", now - 60000, [], True),
            ("ancient", now - 3600000, [], True), ("disabled", now - 3600000, [], False),
            ("repeat", now - 3600000, [1, 2, 3, 4, 5], True)
        ]):
            entries.append(dict(id=str(index + 1), kind="alarm", label=label, endsAt=at, days=days,
                                running=running, hour=7, minute=30, phoneBackend="calendar", calendarEventId="pct12345" + str(index), calendarStart=at))
        (target / "state/timers.json").write_text(json.dumps(dict(entries=entries, phoneBackend="calendar")))
        (target / "state/calendar-timers.json").write_text(json.dumps(dict(calendarId="pc-test", jobs=[])))
        (target / "shell.qml").write_text(RESTORE_ALARMS.replace("EXPECTED_END", str(ends)))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        if result.returncode != 0 or "PASS: missed one-shot" not in output or "FAIL:" in output:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
