#!/usr/bin/env python3
"""Check paged lists and task creation through the real GoogleService callbacks."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


GOOGLE = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool configured: true
    property bool needsConsent: false
    property string reconnect: "Google needs reconnecting"
    property string today: "2026-10-15"
    property date now: new Date(2026, 9, 15, 12)
    property var calls: []
    signal ready
    function dayString(date) { return Qt.formatDate(date, "yyyy-MM-dd"); }
    function authorised(done, failed) { done(); }
    function send(method, url, body, done, failed) {
        calls = calls.concat([{method, url, body, done, failed}]);
    }
}'''

QML = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    function check(ok, why) { if (!ok) throw Error(why); console.log("PASS: " + why); }
    function finishReads() {
        for (let i = 0; i < Google.calls.length; i++) {
            const call = Google.calls[i];
            if (call.method === "GET" && (call.url.includes("/tasks?") || call.url.includes("/events?")))
                call.done({items: []});
        }
        Google.calls = [];
    }
    function run() {
        Tasks.lists = [{id: "old", title: "Previous"}];
        Tasks.fetchLists();
        Google.calls[0].done({items: [{id: "home", title: "Home"}], nextPageToken: "next &?"});
        check(Tasks.lists[0].id === "old" && Google.calls.length === 2,
            "task lists wait for all pages before publishing");
        check(Google.calls[1].url.includes("?maxResults=100&pageToken=next%20%26%3F"),
            "task list page token is encoded after a query separator");
        Google.calls[1].done({items: [{id: "work", title: "Work"}]});
        check(Tasks.lists.map(l => l.id).join(",") === "home,work",
            "task lists from every page retain their order");
        check(Google.calls.filter(c => c.url.includes("/tasks?")).length === 2,
            "tasks are fetched from lists on later pages too");
        finishReads();
        check(!Tasks.loading, "paged task refresh settles its request count");

        const held = Tasks.lists;
        Tasks.fetchLists();
        Google.calls[0].done({items: [{id: "partial", title: "Partial"}], nextPageToken: "more"});
        Google.calls[1].failed("Offline", 0);
        check(Tasks.lists === held && Tasks.trouble === "Offline" && !Tasks.loading,
            "a failed later task-list page preserves the published lists");
        Google.calls = [];

        Tasks.fetchLists();
        Google.calls[0].done({items: [], nextPageToken: "stale"});
        const stale = Google.calls[1];
        Tasks.invalidate();
        stale.done({items: [{id: "stale", title: "Stale"}]});
        check(Tasks.lists === held && !Tasks.loading,
            "invalidated task-list pages cannot overwrite current state");
        Google.calls = [];

        Agenda.calendars = [{id: "previous", title: "Previous"}];
        Agenda.fetchCalendars();
        Google.calls[0].done({items: [{id: "hidden", selected: false}], nextPageToken: "next &?"});
        check(Agenda.calendars[0].id === "previous" && !Agenda.haveCalendars && Google.calls.length === 2,
            "calendar lists wait through an unselected first page");
        check(Google.calls[1].url.endsWith("&pageToken=next%20%26%3F"),
            "calendar list page token is encoded");
        Google.calls[1].done({items: [{id: "first", summary: "First", selected: true},
            {id: "second", selected: true}, {id: "hidden-two", selected: false}]});
        check(Agenda.haveCalendars && Agenda.calendars.map(c => c.id).join(",") === "first,second"
            && Agenda.calendars[1].title === "", "selected calendars from later pages are published");
        check(Google.calls.filter(c => c.url.includes("/events?")).length === 2,
            "events are fetched from calendars on later pages too");
        finishReads();
        check(!Agenda.loading, "paged calendar refresh settles its request count");

        const calendars = Agenda.calendars, at = Agenda.calendarsAt;
        Agenda.fetchCalendars();
        Google.calls[0].done({items: [{id: "partial", selected: true}], nextPageToken: "more"});
        Google.calls[1].failed("Offline", 0);
        check(Agenda.calendars === calendars && Agenda.calendarsAt === at && Agenda.trouble === "Offline"
            && !Agenda.loading, "a failed later calendar page preserves the previous complete list");
        Google.calls = [];

        const draft = "work tomorrow call bank";
        const said = Tasks.run(draft);
        const post = Google.calls[0];
        check(said.startsWith("Adding call bank") && !said.startsWith("Added") && post.method === "POST",
            "task submission is not reported as confirmed creation");
        post.failed("Offline", 0);
        check(Tasks.trouble === "Offline" && Tasks.auditNotifications.length === 1,
            "failed task creation sends a notification after the launcher has closed");
        const notification = Tasks.auditNotifications[0];
        check(notification.includes("Task not added") && notification[notification.length - 1].includes("call bank")
            && notification[notification.length - 1].includes("2026-10-16")
            && notification[notification.length - 1].includes("Work"),
            "failure notification retains the task title, due day and list");
        Google.calls = [];

        Tasks.add("Read <report> & notes", "", "work", "Line one\\nLine two");
        Google.calls[0].failed("Google said 403", 403);
        const body = Tasks.auditNotifications[1].slice(-1)[0];
        check(body.includes("Read &lt;report&gt; &amp; notes") && body.includes("Line one\\nLine two")
            && body.includes("Google said 403"), "failure notification preserves notes and escapes markup");
        Google.calls = [];

        Tasks.add("Saved", "", "work", "");
        Google.calls[0].done({id: "saved"});
        check(Tasks.auditNotifications.length === 2 && Google.calls.some(c => c.url.includes("/tasks?")),
            "successful task creation refreshes tasks without a failure notification");
        finishReads();
        console.log("PASS: Google lists and task creation");
    }
    Timer { interval: 50; running: true; onTriggered: {
        try { run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-google-lists-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/Google.qml").write_text(GOOGLE)
        (target / "services/Network.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property bool online: false }')
        (target / "services/WallClock.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property double now: Date.now(); signal wokeUp }')
        (target / "services/Retry.qml").write_text('import QtQuick\nQtObject { '
            'property bool active: false; property bool pending: false; signal triggered; '
            'function reset() { pending = false; } function cancel() { pending = false; } '
            'function schedule() { pending = true; } }')
        for name in ("Tasks", "Agenda"):
            path = target / f"services/{name}.qml"
            source = path.read_text().replace('id: root', 'id: root\n    polling: false', 1)
            if name == "Tasks":
                source = source.replace('id: root', 'id: root\n    property var auditNotifications: []\n'
                    '    function auditNotify(command) { auditNotifications = auditNotifications.concat([command]); }', 1)
                source = source.replace('Quickshell.execDetached(', 'root.auditNotify(')
            path.write_text(source)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "Failed to load configuration")
        return 0 if result.returncode == 0 and "PASS: Google lists and task creation" in output and not any(e in output for e in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
