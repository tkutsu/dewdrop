#!/usr/bin/env python3
"""Render alarm times in the real bar module and popup with isolated state."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
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
                    check(readout.font.pixelSize === Theme.captionSize && !named(popup, "readoutAmPm"), "popup keeps the entire time at full size");
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
                    check(title.font.pixelSize === Theme.captionSize && !named(popup, "titleAmPm"), "ringing popup time keeps full-size AM/PM");
                    check(pill.shownSmallRanges.length === 1, "ringing bar time uses smaller AM/PM");
                    Timers.ringing = [{id: "ring", kind: "alarm", hour: 20, minute: 5, label: "Dinner PM", firedAt: Timers.now}];
                } else {
                    check(pill.shownLabel === "Dinner PM" && pill.shownSmallRanges.length === 0, "named alarms remain normal text");
                    check(named(popup, "title").text === "Dinner PM", "alarm name is not mistaken for AM/PM");
                    Timers.ringing = [];
                    Timers._commit([]);
                    console.log("PASS: bar and popup alarm casing, sizing, spacing and live settings");
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
        target = Path(folder)
        copy_shell(target)
        for filename, names in (
            ("modules/Countdown.qml", ("words", "rolling")),
            ("components/TimerPopup.qml", ("readout", "title")),
        ):
            path = target / filename
            source = path.read_text()
            if filename == "components/TimerPopup.qml":
                source = source.replace("Popup {", "Column {\n    property bool morphs: false", 1)
            for name in names:
                source = source.replace(f"id: {name}\n", f'id: {name}\n                objectName: "{name}"\n')
            path.write_text(source)
        service = target / "services/Timers.qml"
        source = service.read_text().replace('["pw-play", root.alarmSound]', '["/usr/bin/true"]')
        source = source.replace('Quickshell.execDetached(["notify-send",', 'return; Quickshell.execDetached(["notify-send",')
        service.write_text(source)
        (target / "services/Pushover.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string phoneWarning: ""; signal failed(string reason); signal acknowledged(string id, double firedAt); function notifyPhone(title, body, entry) {} function dismiss() {} }\n')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output)
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Failed to load configuration")
        assert result.returncode == 0 and "PASS: bar and popup alarm" in output
        assert not any(error in output for error in errors)


if __name__ == "__main__":
    main()
