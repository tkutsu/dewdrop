#!/usr/bin/env python3
"""Keep system detail delegates while samples change, and update their readings."""

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
        implicitWidth: 400; implicitHeight: 800
        SysPopup { id: popup }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function run() {
                const core = popup.auditCores.itemAt(0), disk = popup.auditDisks.itemAt(0);
                check(core && disk, "core and drive delegates exist");
                Sys.coreUse = [0.8, 0.1];
                Sys.drives = [Object.assign({}, Sys.drives[0], {model: "updated disk", free: 250})];
                wait(20);
                check(popup.auditCores.itemAt(0) === core && popup.auditDisks.itemAt(0) === disk, "new samples retain existing delegates");
                check(core.children[0].height === 9, "retained core meter updates its reading");
                check(disk.children[0].title === "updated disk" && disk.children[1].value === 0.75, "retained drive details update their readings");
                Sys.coreUse = [0.3]; Sys.drives = [];
                wait(20);
                check(popup.auditCores.count === 1 && popup.auditDisks.count === 0, "removed hardware removes its delegates");
                Sys.coreUse = [0.3, 0.4, 0.5];
                Sys.drives = [{model: "new disk", temp: 30, util: 0, total: 100, free: 20, read: 0, write: 0}];
                wait(20);
                check(popup.auditCores.count === 3 && popup.auditDisks.itemAt(0).children[0].title === "new disk", "added hardware creates current delegates");
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-sys-popup-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string font: "Sans"; property string monoFont: "Monospace"; property bool reduceMotion: false; property bool reduceTransparency: false }')
        (target / "components/Popup.qml").write_text('import QtQuick\nColumn { property real hPadding: 6; property real vPadding: 6 }')
        (target / "components/Glyph.qml").write_text('import QtQuick\nItem { property string text: ""; property int fontSize: 16; property color color: "white"; implicitWidth: 16 }')
        (target / "services/Sys.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property int watchers: 0
    property string cpuModel: "fixture CPU"
    property var cpuTemps: []
    property real cpuUse: 0
    property int cpuMhz: 1000
    property var fans: []
    property var topCpu: []
    property var topMem: []
    property real memUsed: 100
    property real memTotal: 1000
    property real memCache: 0
    property real swapUsed: 0
    property real swapTotal: 0
    property var gpu: null
    property var coreUse: [0.2, 0.6]
    property var drives: [{model: "fixture disk", temp: 30, util: 0, total: 1000, free: 500, read: 0, write: 0}]
}''')
        source = (target / "components/SysPopup.qml").read_text()
        source = source.replace('id: root', 'id: root\n    property alias auditCores: auditCores\n    property alias auditDisks: auditDisks', 1)
        source = source.replace('model: Sys.coreUse', 'id: auditCores\n                model: Sys.coreUse', 1)
        source = source.replace('model: Sys.drives', 'id: auditDisks\n        model: Sys.drives', 1)
        (target / "components/SysPopup.qml").write_text(source)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and output.count('PASS:') == 6 and not any(error in output for error in ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop')), output


if __name__ == '__main__':
    main()
