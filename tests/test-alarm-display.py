#!/usr/bin/env python3
"""Render alarm times in the real bar module and popup with isolated state."""

from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.modules
import qs.src.services
ShellRoot {
    id: test
    property int phase: 0
    function check(ok, why) { if (!ok) throw Error(why); }
    function named(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const found = named(child, name);
            if (found) return found;
        }
        return null;
    }
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 200
        Countdown { id: pill; height: 30 }
        TimerPopup { id: popup; y: 50 }
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (test.phase === 0) {
                    Settings.set("timeFormat", "h:mm AP");
                    Settings.set("timeCase", "lowercase");
                    Settings.set("smallAmPm", true);
                    Settings.set("reduceMotion", true);
                    Timers._commit([{id: "alarm", kind: "alarm", hour: 20, minute: 5, label: "Dinner", running: true, days: [], endsAt: Timers.now + 86400000}]);
                } else if (test.phase === 1) {
                    check(pill.shownLabel === "8:05pm" && pill.shownSmallRanges.length === 1, "bar alarm shares formatter and size ranges");
                    check(named(pill, "rolling").visible && !named(pill, "words").visible, "bar alarm uses smaller AM/PM renderer");
                    const readout = named(popup, "readout");
                    check(readout.text === "8:05 pm", "popup keeps readable spacing and selected case");
                    check(readout.font.pixelSize === Theme.popupTextSize && !named(popup, "readoutAmPm"), "popup keeps the entire time at full size");
                    Settings.set("timeCase", "uppercase");
                    Settings.set("smallAmPm", false);
                } else if (test.phase === 2) {
                    check(pill.shownLabel === "8:05 PM" && pill.shownSmallRanges.length === 0, "bar settings update live");
                    check(named(popup, "readout").text === "8:05 PM", "popup case updates live");
                    Settings.set("smallAmPm", true);
                    Timers.ringing = [{id: "ring", kind: "alarm", hour: 20, minute: 5, label: "", firedAt: Timers.now}];
                } else if (test.phase === 3) {
                    const title = named(popup, "title");
                    check(title.text === "8:05 PM", "ringing popup time keeps readable spacing");
                    check(title.font.pixelSize === Theme.popupTextSize && !named(popup, "titleAmPm"), "ringing popup time keeps full-size AM/PM");
                    check(pill.shownSmallRanges.length === 1, "ringing bar time uses smaller AM/PM");
                    Timers.ringing = [{id: "ring", kind: "alarm", hour: 20, minute: 5, label: "Dinner PM", firedAt: Timers.now}];
                } else {
                    check(pill.shownLabel === "Dinner PM" && pill.shownSmallRanges.length === 0, "named alarms remain normal text");
                    check(named(popup, "title").text === "Dinner PM", "alarm name is not mistaken for AM/PM");
                    Timers.ringing = [];
                    const base = Date.now();
                    Timers.now = base;
                    const alarm = {id: "track", kind: "alarm", hour: 20, minute: 5, label: "Dinner", running: true, days: [], endsAt: base + 3605000};
                    Timers._commit([alarm]);
                    check(pill.progress === -1 && pill.rate === 0 && !Timers.counting, "alarm has no track or second ticks before its final hour");
                    Timers.now = base + 5000;
                    check(pill.progress === 0 && pill.rate === 1 / 3600 && Timers.counting, "alarm track starts empty at one hour and advances smoothly");
                    Timers.now += 1800000;
                    check(pill.progress === 0.5, "alarm track is half full at thirty minutes");
                    Timers.now = alarm.endsAt - 1000;
                    check(Math.abs(pill.progress - (1 - 1 / 3600)) < 0.000001, "alarm track approaches full just before ringing");
                    Timers.now = alarm.endsAt;
                    check(pill.progress === 1, "alarm track is full at its deadline");
                    Timers.ringing = [{id: "track", kind: "alarm", hour: 20, minute: 5, label: "Dinner", firedAt: Timers.now}];
                    check(pill.progress === -1 && pill.rate === 0, "ringing hides and stops the track");
                    Timers.ringing = [];
                    Timers.now = base;
                    Timers._commit([Object.assign({}, alarm, {running: false})]);
                    check(pill.progress === -1 && pill.rate === 0 && !Timers.counting, "disabled alarms have no track");
                    const countdown = {id: "countdown", kind: "countdown", label: "Tea", total: 120000, running: true, endsAt: base + 60000};
                    Timers._commit([Object.assign({}, alarm, {endsAt: base + 1800000}), countdown]);
                    check(pill.progress === 0.5 && pill.rate === 1 / 120, "running countdown retains its own track duration ahead of an alarm");
                    Timers._commit([alarm, Object.assign({}, countdown, {running: false, left: 30000})]);
                    check(pill.progress === 0.75 && pill.rate === 0 && !Timers.counting, "paused countdown keeps its static track ahead of an alarm");
                    Timers._commit([]);
                    check(pill.progress === -1 && pill.rate === 0, "empty pill has no track");
                    console.log("PASS: bar and popup alarm casing, sizing, spacing, live settings and final-hour track");
                    Qt.quit();
                }
                test.phase++;
            } catch (error) {
                console.log("FAIL: " + error + "\\n" + error.stack);
                Qt.quit();
            }
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-alarm-display-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        for filename, names in (
            ("src/modules/Countdown.qml", ("words", "rolling")),
            ("src/components/TimerPopup.qml", ("readout", "title")),
        ):
            path = target / filename
            source = path.read_text()
            if filename == "src/components/TimerPopup.qml":
                source = source.replace("Popup {", "Column {\n    property bool morphs: false", 1)
            for name in names:
                source = source.replace(f"id: {name}\n", f'id: {name}\n                objectName: "{name}"\n')
            path.write_text(source)
        service = target / "src/services/Timers.qml"
        source = service.read_text().replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]')
        service.write_text(source)
        (target / "src/core/Notify.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var sent: []; function send(summary, body, options) { sent = [...sent, ["notify-send", ...(options ?? []), "--", summary, body]]; } }\n')
        (target / "src/services/PhoneAlarms.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string phoneWarning: ""; signal failed(string reason); signal acknowledged(string id, double firedAt); signal finished(); function hasLive(id, firedAt) { return false; } function notifyPhone(title, body, entry) {} function dismiss() {} }\n')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output)
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Failed to load configuration")
        assert result.returncode == 0 and "PASS: bar and popup alarm" in output
        assert not any(error in output for error in errors)


if __name__ == "__main__":
    main()
