#!/usr/bin/env python3
"""Cancel linked alarm events with an isolated transport, including after restart."""
import re
import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env

BASE = Path(__file__).with_name("test-tasks.py").read_text().split("BASE = '''")[1].split("'''")[0]


SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function last() { return Timers.entries[Timers.entries.length - 1]; }
        function make(eventId) {
            Tasks.run("23:59 same name");
            const entry = last();
            Agenda.calls[Agenda.calls.length - 1].done({id: eventId});
            return entry.id;
        }
        function run() {
            tryVerify(() => Timers.restored && Google.configured, 2000);
            BODY
            console.log("DONE: alarm events");
        }
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
        Qt.quit();
    } }
}'''

CASES = '''
            const first = make("first/event");
            check(last().calendarEvent.id === "first/event", "Google event ID is saved on its alarm");
            Timers.toggle(first);
            Timers.toggle(first);
            check(Agenda.calls.length === 1, "turning an alarm off and on keeps its event");
            Timers.cancel(first);
            const removal = Agenda.calls[1];
            check(Timers.entries.length === 0 && removal.method === "DELETE"
                && removal.url.endsWith("/calendars/primary/events/first%2Fevent") && removal.body === null,
                "cancellation removes the exact linked event without a request body");
            removal.done(null);
            Timers.cancel(first);
            check(Agenda.calls.length === 2, "repeated cancellation does not delete again");

            Agenda.calls = [];
            Tasks.run("23:59 pending");
            const pending = last().id;
            Timers.cancel(pending);
            check(Agenda.calls.length === 1, "cancellation waits for pending event creation");
            Agenda.calls[0].done({id: "pending-event"});
            check(Agenda.calls.length === 2 && Agenda.calls[1].url.endsWith("/pending-event")
                && Agenda.calls[1].method === "DELETE" && !Object.keys(Tasks.pendingAlarmEvents).length,
                "late event creation is removed after its alarm was cancelled");

            Agenda.calls = [];
            Tasks.run("23:59 failed creation");
            Timers.cancel(last().id);
            Agenda.calls[0].failed("Offline", 0);
            check(Agenda.calls.length === 1 && !Object.keys(Tasks.pendingAlarmEvents).length,
                "failed creation clears pending cancellation without deleting another event");

            Agenda.calls = [];
            const a = make("same-name-a");
            const b = make("same-name-b");
            Timers.cancel(a);
            check(Agenda.calls[2].url.endsWith("/same-name-a") && last().id === b,
                "alarms with the same title keep separate event identities");
            Timers.cancel(b);

            Agenda.calls = [];
            Tasks.run("23:59");
            Timers.cancel(last().id);
            Tasks.run("25m tea");
            Timers.cancel(last().id);
            Timers.run("23:59 old alarm");
            Timers.cancel(last().id);
            Google.scopeMissing = true;
            Tasks.run("23:59 without consent");
            Timers.cancel(last().id);
            Google.scopeMissing = false;
            check(!Agenda.calls.length, "timers, untitled alarms and alarms without a link leave Calendar alone");

            const fired = make("fired-event");
            Timers.fire(last());
            Timers.hush();
            Timers.cancel(fired);
            check(Agenda.calls.length === 1, "firing and dismissing an alarm keeps the event");

            Agenda.calls = [];
            Tasks.run("23:59 fires while pending");
            Timers.fire(last());
            Timers.hush();
            Agenda.calls[0].done({id: "late-fired-event"});
            check(Agenda.calls.length === 1, "event creation after firing is kept");

            Agenda.calls = [];
            const offline = make("offline-event");
            Timers.cancel(offline);
            Agenda.auditNotifications = [];
            Agenda.calls[1].failed("No network", 0);
            check(!Timers.entries.length && Agenda.auditNotifications.length === 1
                && Agenda.auditNotifications[0][3] === "Event not removed"
                && Agenda.auditNotifications[0][4].includes("No network"),
                "failed deletion leaves the alarm cancelled and reports the remaining event");
            for (const status of [404, 410]) {
                Agenda.calls = [];
                Agenda.auditNotifications = [];
                const gone = make("already-gone");
                Timers.cancel(gone);
                Agenda.calls[1].failed("Already gone", status);
                check(!Agenda.auditNotifications.length, "an event already gone is harmless: " + status);
            }

            Agenda.calls = [];
            Tasks.run("tomorrow 23:59 event only");
            Agenda.calls[0].done({id: "standalone-event"});
            make("clear-a");
            Tasks.run("23:59 clear pending");
            Timers.auditIpc.clear();
            Agenda.calls[2].done({id: "clear-b"});
            check(!Timers.entries.length && Agenda.calls.filter(c => c.method === "DELETE").length === 2
                && !Agenda.calls.some(c => c.url.endsWith("/standalone-event")),
                "clearing alarms cancels linked and pending events while keeping standalone events");

            Agenda.calls = [];
            const cached = make("cached-event");
            const start = new Date(last().calendarEvent.start);
            const key = Agenda.monthKey(start);
            const day = Agenda.dayString(start);
            Agenda.months = { [key]: { [day]: [{id: "cached-event"}] } };
            Agenda.haveCalendars = true;
            Agenda.calendars = [{id: "primary", title: "Me"}];
            Timers.cancel(cached);
            Agenda.calls[1].done(null);
            check(Agenda.calls[2]?.method === "GET", "successful deletion refetches the affected calendar month");
            Agenda.calls[2].done({items: []});
            check(!Agenda.forDay(day).length, "calendar refresh removes the deleted event from the agenda");
            Agenda.haveCalendars = false;

            Agenda.calls = [];
            make("survives-restart");
            check(last().calendarEvent.id === "survives-restart", "linked alarm is ready for the restart check");
'''

RESTART = '''
            check(Timers.entries.length === 1 && last().calendarEvent.id === "survives-restart",
                "event link survives an actual shell restart");
            Timers.cancel(last().id);
            check(!Timers.entries.length && Agenda.calls.length === 1 && Agenda.calls[0].method === "DELETE"
                && Agenda.calls[0].url.endsWith("/survives-restart"),
                "restored alarm cancellation removes its event without opening Tasks");
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-alarm-events-") as folder:
        target = Path(folder)
        copy_shell(target)
        service = target / "services/GoogleService.qml"
        gather = re.search(r'^    function gather\(.*?^    }', service.read_text(), re.M | re.S).group()
        base = BASE.replace('Singleton {', 'Singleton {\n    id: base', 1)
        service.write_text(base.replace('    function gather(key, sources, map, done) {}', gather))
        (target / "data/quickshell").mkdir(parents=True)
        (target / "data/quickshell/gtasks.json").write_text(
            '{"client_id":"x","client_secret":"x","refresh_token":"x"}'
        )
        timer = target / "services/Timers.qml"
        source = timer.read_text().replace('id: root', 'id: root\n    property alias auditIpc: auditIpc', 1)
        source = source.replace('IpcHandler {', 'IpcHandler {\n        id: auditIpc', 1)
        timer.write_text(source.replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]'))
        agenda = target / "services/Agenda.qml"
        source = agenda.read_text().replace('id: root', '''id: root
    property var auditNotifications: []
    function auditNotify(command) { auditNotifications = auditNotifications.concat([command]); }''', 1)
        agenda.write_text(source.replace("Quickshell.execDetached(", "root.auditNotify("))
        env = shell_env(target)
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        for body in (CASES, RESTART):
            (target / "shell.qml").write_text(SHELL.replace("BODY", body))
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            print(output, end="")
            if result.returncode != 0 or "DONE: alarm events" not in output or any(e in output for e in errors):
                return 1
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
