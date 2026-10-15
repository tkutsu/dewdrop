#!/usr/bin/env python3
"""Elide a long drive name before it reaches the size beside it."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.components
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 400
        DrivesPopup { id: popup }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function run() {
                const row = popup.auditRows.itemAt(0);
                check(row, "drive row exists");
                const name = row.auditName, usage = row.auditUsage;
                check(name.truncated, "long name elides");
                check(name.x + name.width <= usage.x, "name ends before the size");
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-drives-popup-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string font: "Sans"; property string monoFont: "Monospace"; property bool reduceMotion: false; property bool reduceTransparency: false }')
        (target / "components/Popup.qml").write_text('import QtQuick\nColumn { property real hPadding: 6; property real vPadding: 6 }')
        (target / "services/Drives.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property var drives: [{disk: "/dev/sda", name: "nixos-graphical-25.11-x86_64", size: 14.4e9, used: 3.4e9, total: 3.4e9, volumes: []}]
    property var batteries: []
    property var ejecting: ({})
    function open(drive) {}
    function eject(drive) {}
}''')
        source = (target / "components/DrivesPopup.qml").read_text()
        source = source.replace('id: root', 'id: root\n    property alias auditRows: auditRows', 1)
        source = source.replace('model: ScriptModel {\n            values: Drives.drives', 'id: auditRows\n        model: ScriptModel {\n            values: Drives.drives', 1)
        source = source.replace('required property var modelData', 'required property var modelData\n            property alias auditName: name\n            property alias auditUsage: usage', 1)
        (target / "components/DrivesPopup.qml").write_text(source)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 3 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
