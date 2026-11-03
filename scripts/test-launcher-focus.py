#!/usr/bin/env python3
"""Exercise the launcher's power-veil focus recovery on a live Hyprland session."""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / 'modules/LauncherMenu.qml').read_text()
    focus = source[source.index('    // Hyprland can deactivate'):source.index('    PowerVeil {')]
    with tempfile.TemporaryDirectory(prefix='qs-native-focus-') as folder:
        target = Path(folder)
        for name in ['components/OverlayWindow.qml', 'components/OutsideClick.qml', 'modules/PowerVeil.qml']:
            dest = target / name
            dest.parent.mkdir(exist_ok=True)
            dest.write_text((ROOT / name).read_text().replace('import qs\n', ''))
        (target / 'services').mkdir()
        (target / 'services/qmldir').write_text('singleton Launcher 1.0 Launcher.qml\n')
        (target / 'services/Launcher.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function hide() {} }\n')
        (target / 'shell.qml').write_text(QML.replace('FOCUS_BLOCK', focus))
        env = dict(os.environ, XDG_CONFIG_HOME=str(target / 'config'), XDG_STATE_HOME=str(target / 'state'),
                   XDG_DATA_HOME=str(target / 'data'), XDG_CACHE_HOME=str(target / 'cache'), QT_QPA_PLATFORM='wayland')
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env,
                                capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        print(output, end='')
        return 0 if result.returncode == 0 and 'PASS: native launcher focus' in output and 'FAIL:' not in output else 1


QML = '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.modules
ShellRoot {
    OverlayWindow {
        id: root
        name: "launcher-focus-test"
        shown: true
        inputItem: box
        readonly property bool veiled: root.opened && input.text.startsWith("!")
FOCUS_BLOCK
        PowerVeil { screen: root.screen; visible: root.veiled }
        Rectangle {
            id: box
            anchors.centerIn: parent
            width: 400; height: 80; color: "#444444"
            TextInput {
                id: input
                anchors.fill: parent
                color: "white"; focus: true; text: "!"
                Component.onCompleted: forceActiveFocus()
            }
        }
        TestCase {
            id: keys; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function run() {
                check(input.activeFocus, "launcher starts focused");
                for (let i = 0; i < 3; i++) {
                    keyClick(Qt.Key_Backspace); wait(150);
                    check(input.text === "", "Backspace leaves power mode");
                    check(input.activeFocus, "Backspace out of power mode keeps the launcher focused");
                    keyClick(Qt.Key_S); wait(30);
                    check(input.text === "s", "typing continues after leaving power mode");
                    check(root.WlrLayershell.keyboardFocus === WlrKeyboardFocus.OnDemand,
                        "focus recovery releases its temporary exclusive request");
                    keyClick(Qt.Key_Backspace);
                    keyClick(Qt.Key_Exclam); wait(150);
                    check(input.text === "!" && input.activeFocus, "power mode can be entered again");
                }
                root.shown = false; wait(50);
                check(root.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None,
                    "closing releases the keyboard");
                console.log("PASS: native launcher focus");
            }
        }
        Timer { interval: 500; running: true; onTriggered: {
            try { keys.run(); } catch (e) { console.log("FAIL: " + e); }
            Qt.quit();
        } }
    }
}
'''


if __name__ == '__main__':
    raise SystemExit(main())
