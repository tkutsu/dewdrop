#!/usr/bin/env python3
"""Check on a live Hyprland session that the launcher keeps the keyboard through its power veil."""

from pathlib import Path
from test_support import fixture_root
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix='qs-native-focus-') as folder:
        target = fixture_root(folder)
        for name in ['src/components/OverlayWindow.qml', 'src/components/OutsideClick.qml', 'src/modules/PowerVeil.qml']:
            dest = target / name
            dest.parent.mkdir(exist_ok=True)
            dest.write_text((ROOT / name).read_text().replace('import qs.src.core\n', ''))
        (target / 'src/services').mkdir(parents=True, exist_ok=True)
        (target / 'src/services/qmldir').write_text('singleton Launcher 1.0 Launcher.qml\n')
        (target / 'src/services/Launcher.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function hide() {} }\n')
        (target / 'shell.qml').write_text(QML)
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
import Quickshell.Io
import Quickshell.Wayland
import qs.src.components
import qs.src.modules
ShellRoot {
    OverlayWindow {
        id: root
        name: "launcher-focus-test"
        shown: true
        inputItem: box
        readonly property bool veiled: root.opened && input.text.startsWith("!")
        property int losses: 0
        Connections {
            target: input.Window.window
            function onActiveChanged() { if (!input.Window.window.active) root.losses++; }
        }
        Process {
            id: shortcut
            command: ["hyprctl", "repl", "hl.dispatch(hl.dsp.focus({ window = hl.get_active_window() }))"]
        }
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
                    check(input.text === "", "Backspace leaves power mode (pass " + i + ", text '" + input.text + "', active " + input.Window.window.active + ", focus " + root.WlrLayershell.keyboardFocus + ")");
                    check(input.activeFocus, "Backspace out of power mode keeps the launcher focused");
                    keyClick(Qt.Key_S); wait(30);
                    check(input.text === "s", "typing continues after leaving power mode");
                    check(root.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive,
                        "the open launcher holds the keyboard");
                    keyClick(Qt.Key_Backspace);
                    keyClick(Qt.Key_Exclam); wait(150);
                    check(input.text === "!" && input.activeFocus, "power mode can be entered again");
                }
                // A shortcut that focuses the window behind does not take the keyboard.
                const before = root.losses;
                shortcut.running = true; wait(400);
                check(root.losses === before && input.activeFocus, "a shortcut leaves the launcher the keyboard");
                // A password panel wants the keyboard to itself: no taking it back.
                claimant.visible = true; wait(400);
                check(claimantFocus.Window.window.active && !input.Window.window.active,
                    "another exclusive layer keeps the keyboard it took");
                claimant.visible = false; wait(400);
                check(input.activeFocus, "the launcher has the keyboard again once it closes");
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
    PanelWindow {
        id: claimant
        visible: false
        anchors.bottom: true
        implicitWidth: 200; implicitHeight: 40
        exclusionMode: ExclusionMode.Ignore
        color: "#666666"
        WlrLayershell.namespace: "quickshell:launcher-focus-claimant"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        Item { id: claimantFocus; focus: true }
    }
}
'''


if __name__ == '__main__':
    raise SystemExit(main())
