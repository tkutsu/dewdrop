#!/usr/bin/env python3
"""Check shared clock/alarm notation and 12h input with isolated QML state."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

QML = '''import QtQuick
import Quickshell
import qs
import qs.services
ShellRoot {
    id: test
    property int phase: 0
    readonly property string label: Timers.label
    readonly property string tooltip: Timers.tooltip()
    readonly property string preview: Timers.brief("8:05pm", Timers.parse("8:05pm"))
    property real alarmAt: 0
    function check(ok, why) { if (!ok) throw Error(why); }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            try {
                if (test.phase === 0) {
                    check(Settings.timeFormat === "HH:mm" && !Settings.twelveHour, "24h default");
                    for (const [input, hour, minute, label] of [
                        ["8pm dinner", 20, 0, "dinner"],
                        ["7:30AM wake up", 7, 30, "wake up"],
                        ["12am midnight", 0, 0, "midnight"],
                        ["12:15PM lunch", 12, 15, "lunch"]
                    ]) {
                        Timers.run(input);
                        const entry = Timers.entries[Timers.entries.length - 1];
                        check(entry.kind === "alarm" && entry.hour === hour && entry.minute === minute && entry.label === label, "12h creation: " + input);
                    }
                    for (const input of ["0pm", "13am", "23:30pm", "7:60am", "24:00"])
                        check(!Timers.parse(input).ok, "reject invalid time: " + input);
                    Timers._commit([]);
                    check(Timers.run("8:05pm") === "Alarm set for 20:05", "24h confirmation");
                    test.alarmAt = Timers.entries[0].endsAt;
                    check(test.label === "20:05" && test.tooltip.includes("20:05") && test.preview.includes("20:05"), "24h alarm bindings");
                    Settings.setTwelveHour(true);
                } else if (test.phase === 1) {
                    check(Settings.timeFormat === "h:mm AP" && Settings.twelveHour, "12h setting");
                    check(Qt.formatDateTime(new Date(2026, 0, 1, 20, 5), Settings.timeFormat) === "8:05 PM", "12h bar clock");
                    check(test.label === "8:05 PM" && test.tooltip.includes("8:05 PM") && test.preview.includes("8:05 PM"), "existing alarm and launcher bindings update");
                    check(Timers.ringTitle({kind: "alarm", hour: 20, minute: 5, label: ""}) === "8:05 PM", "ringing title");
                    check(Timers.hhmm(0, 0) === "12:00 AM" && Timers.hhmm(12, 0) === "12:00 PM", "midnight and noon display");
                    check(Timers.entries[0].endsAt === test.alarmAt, "notation does not reschedule alarms");
                    check(Timers.clock(90000) === "1:30" && Timers.parse("25m tea").ms === 1500000, "countdown behavior stays unchanged");
                    Settings.set("timeCase", "lowercase");
                    Settings.set("smallAmPm", true);
                } else if (test.phase === 2) {
                    check(test.label === "8:05pm" && test.tooltip.includes("8:05pm") && test.preview.includes("8:05pm"), "alarm bindings share case and spacing");
                    check(Timers.hhmm(0, 0) === "12:00am" && Timers.hhmm(12, 0) === "12:00pm", "case and spacing at midnight and noon");
                    check(JSON.stringify(Timers.alarmDisplay(20, 5).smallRanges) === '[{"start":4,"end":6}]', "alarm AM/PM sizing ranges");
                    check(Timers.ringTitle({kind: "alarm", hour: 20, minute: 5, label: ""}) === "8:05pm", "ringing title shares clock settings");
                    check(Timers.ringTitle({kind: "alarm", hour: 20, minute: 5, label: "Dinner"}) === "Dinner", "alarm names retain their case");
                    check(Timers.entries[0].endsAt === test.alarmAt, "display changes do not reschedule alarms");
                    Settings.set("timeCase", "uppercase");
                    Settings.set("smallAmPm", false);
                    Settings.set("timeFormat", "h:mm:ss ap");
                    Settings.setTwelveHour(false);
                } else if (test.phase === 3) {
                    check(Settings.timeFormat === "HH:mm:ss" && !Settings.twelveHour, "seconds retained switching to 24h");
                    check(test.label === "20:05" && test.preview.includes("20:05"), "switch back updates alarms");
                    Settings.set("timeFormat", "HH:mm 'AP'");
                    check(!Settings.twelveHour, "quoted AM/PM text is not a 12h format");
                    Settings.set("timeFormat", "HH:mm:ss");
                    Settings.setTwelveHour(true);
                } else {
                    check(Settings.timeFormat === "h:mm:ss AP", "seconds retained switching to 12h");
                    for (const [custom, twelve, back] of [
                        ["HH.mm:ss.zzz 's AP' t", "hh.mm:ss.zzz 's AP' t AP", "HH.mm:ss.zzz 's AP' t"],
                        ["H:mm 'o''clock' t", "h:mm 'o''clock' t AP", "H:mm 'o''clock' t"],
                        ["'AP' HH:mm", "'AP' hh:mm AP", "'AP' HH:mm"]
                    ]) {
                        Settings.set("timeFormat", custom);Settings.setTwelveHour(true);
                        check(Settings.timeFormat === twelve, "custom 12h format: " + custom);
                        Settings.setTwelveHour(false);
                        check(Settings.timeFormat === back, "custom 24h format: " + custom);
                    }
                    Settings.set("timeFormat", "AP hh.mm:ss");Settings.setTwelveHour(false);
                    check(Settings.timeFormat === "HH.mm:ss", "leading AM/PM removal preserves other tokens");
                    Settings.set("timeFormat", "h:mm:ss AP");
                    console.log("PASS: clock/alarm notation, live bindings and 12h alarm creation");
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

RESTART_QML = '''import QtQuick
import Quickshell
import qs
import qs.services
ShellRoot {
    readonly property string label: Timers.label
    Timer {
        interval: 100; running: true
        onTriggered: {
            if (Settings.timeFormat === "h:mm:ss AP" && Settings.twelveHour && Timers.entries.length === 1 && Timers.label === "8:05 PM")
                console.log("PASS: notation and alarm survive restart");
            else console.log("FAIL: persisted settings or alarm");
            Qt.quit();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-timer-time-") as folder:
        target = Path(folder)
        for name in ("Settings.qml", "Paths.qml", "settings.default.json", "services/Timers.qml", "services/TimersParse.js", "services/WallClock.qml"):
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        (target / "settings.json").write_text("{}\n")
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property var glyph: ({timerRing: "ring", alarm: "alarm", timer: "timer", timerPaused: "paused"}) }\n')
        (target / "services/Pushover.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property string phoneWarning: ""; signal failed(string reason); signal acknowledged(string id, double firedAt); function notifyPhone(title, body, entry) {} function dismiss() {} }\n')
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        (target / "state/quickshell").mkdir(parents=True)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        for source, expected in ((QML, "PASS: clock/alarm"), (RESTART_QML, "PASS: notation and alarm")):
            (target / "shell.qml").write_text(source)
            result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            print(output)
            assert result.returncode == 0 and expected in output
            assert not any(error in output for error in ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign"))


if __name__ == "__main__":
    main()
