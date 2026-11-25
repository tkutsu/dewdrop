#!/usr/bin/env python3
"""The energy popup on a desktop and on a laptop, and the real service's waits."""

from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env

POPUP_SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 600
        EnergyPopup { id: popup }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function all(item, test, out) {
                out = out ?? [];
                if (test(item)) out.push(item);
                for (const child of item.children) all(child, test, out);
                return out;
            }
            function shown(item) {
                for (let i = item; i; i = i.parent) if (!i.visible) return false;
                return true;
            }
            function text(value) { return all(popup, i => i.text === value && i.font !== undefined).filter(shown)[0] ?? null; }
            function button(name) { return all(popup, i => i.name === name && i.glyph !== undefined).filter(shown)[0] ?? null; }
            function menus() { return all(popup, i => i.currentText !== undefined && i.popup !== undefined).filter(shown); }
            function run() {
                // A desktop: no battery, the mode and the waits.
                check(text("Energy") && !text("Battery"), "a desktop titles it Energy");
                check(!text("Charge") && !button("Power Statistics"), "a desktop shows no battery and no Power Statistics");
                let picks = menus().map(m => m.currentText);
                check(JSON.stringify(picks) === JSON.stringify(["Automatic", "10 Minutes", "45 Minutes"]), "mode and waits read Automatic, 10 and 45 minutes: " + picks);
                check(text("Turn Display Off") && text("Sleep"), "the waits are named");
                check(!text("Paused while Caffeine is on"), "no Caffeine note while it is off");
                Caffeine.active = true;
                check(text("Paused while Caffeine is on"), "Caffeine on says the timers wait");
                // Choosing a wait writes the setting.
                const display = menus()[1];
                display.setting.set(0);
                check(Settings.saved.displayOffMinutes === 0 && display.currentText === "Never", "Never is saved and shown");

                // A laptop on battery.
                Energy.battery = ({});
                check(text("Battery") && !text("Energy"), "a laptop titles it Battery");
                check(text("82%") && text("Battery") && text("3:41") && text("9.4 W") && text("91%"), "charge, source, time left, draw and health read out");
                check(text("Time Left") && text("Using"), "discharging reads Time Left and Using");
                check(button("Power Statistics")?.glyph === Theme.glyph.openApp, "the way out to Power Statistics is there");
                Energy.plugged = true; Energy.charging = true;
                check(text("Power Adapter") && text("Until Full") && text("Charging At"), "charging reads Power Adapter and Until Full");
                Energy.charging = false;
                check(text("Not charging"), "on the adapter and not charging says so");
                Energy.low = true; Energy.plugged = false;
                check(text("82%").color === Theme.warn, "a low charge reads in warn");
                Energy.heldBack = "High Power is held back while the machine is hot";
                check(text(Energy.heldBack), "a held-back High Power says why");
            }
        }
        Timer { interval: 200; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
    }
}'''

SERVICE_SHELL = '''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    Timer {
        interval: 200; running: true
        onTriggered: {
            const check = (ok, message) => console.log((ok ? "PASS: " : "FAIL: ") + message);
            const labels = Energy.waits([1, 60, 120, 0, 45], 20).map(o => o.label);
            check(JSON.stringify(labels) === JSON.stringify(["1 Minute", "20 Minutes", "45 Minutes", "1 Hour", "2 Hours", "Never"]),
                "waits sort shortest first, Never last, and keep a typed-in length: " + labels);
            check(Energy.waits([10, 0], 10).length === 2, "a chosen stop is not listed twice");
            check(Energy.battery === null && Energy.summary === "", "no laptop battery here reads as none");
            Qt.quit();
        }
    }
}'''

SETTINGS = '''pragma Singleton
import QtQuick
QtObject {
    id: root
    property string font: "Sans"; property string monoFont: "Monospace"
    property bool reduceMotion: false; property bool reduceTransparency: false
    property var values: ({}); property var saved: ({})
    property string batteryCommand: "gnome-power-statistics"
    property int displayOffMinutes: 10; property int sleepMinutes: 45
    function set(key, value) { root.saved[key] = value; root[key] = value; }
    function helper(command, terminal) { return command ? [command] : []; }
    function program(command) { return command ?? ""; }
}'''

ENERGY = '''pragma Singleton
import QtQuick
QtObject {
    property var battery: null
    property int percent: 82
    property bool plugged: false; property bool charging: false; property bool full: false; property bool low: false
    property string timeLeft: "3:41"; property string draw: "9.4 W"; property int health: 91
    property bool hasModes: true
    property var modes: [{ value: 0, label: "Low Power" }, { value: 1, label: "Automatic" }]
    property int mode: 1
    property string heldBack: ""
    property var displayOffStops: [1, 10, 0]; property var sleepStops: [45, 0]
    function waits(stops, current) { return [...new Set([...stops, current])].map(m => ({ value: m, label: m === 0 ? "Never" : m + " Minutes" })); }
    function setMode(profile) { mode = profile; }
}'''


def run(target, expected):
    result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    print(output, end='')
    # Up to the last check only: on quit UPower empties its devices while
    # the service's context is already gone, and every binding on them
    # reads undefined once.
    running = output[:output.rfind('PASS:')]
    assert output.count('PASS:') == expected and 'FAIL:' not in output and not any(error in running for error in (
        'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-energy-popup-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "src/core/Settings.qml").write_text(SETTINGS)
        (target / "src/services/Energy.qml").write_text(ENERGY)
        (target / "src/services/Caffeine.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool active: false }')
        (target / "src/components/Popup.qml").write_text('import QtQuick\nColumn { property real hPadding: 6; property real vPadding: 6; property bool animateContents: false }')
        (target / "shell.qml").write_text(POPUP_SHELL)
        run(target, 15)
    with tempfile.TemporaryDirectory(prefix="quickshell-energy-service-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(SERVICE_SHELL)
        run(target, 3)


if __name__ == '__main__':
    main()
