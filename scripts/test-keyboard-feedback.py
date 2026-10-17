#!/usr/bin/env python3
"""Exercise layout events, independent feedback options and visibility recovery."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 600; implicitHeight: 600
        Language {
            id: module
            pinKey: "language"
            quiet: true
            stowed: !showsClosed
        }
        Column {
            id: settingsPage
            x: 20; y: 80; width: 507
            Repeater {
                id: settingsRows
                model: SETTINGS_ROWS
                SettingRow { required property var modelData; width: settingsPage.width; setting: modelData }
            }
        }
    }
    property int switches: 0
    Connections { target: Keyboard; function onSwitched() { switches++; } }
    TestCase {
        id: test
        when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function layout(name, keyboard = "main") {
            FakeHyprland.rawEvent({name: "activelayout", parse: n => [keyboard, name]});
        }
        function options(notification, bounce) {
            Settings.user = {layoutChangeNotification: notification, layoutChangeBounce: bounce};
        }
        function reset() {
            module.auditShow.stop(); module.auditDelay.stop(); module.auditBounce.stop();
            Keyboard.sent = [];
        }
        function run() {
            for (const width of [507, 360]) {
                settingsPage.width = width;
                wait(50);
                for (let i = 0; i < settingsRows.count; i++) {
                    const row = settingsRows.itemAt(i);
                    const words = row.children.find(c => c.toString().startsWith("QQuickColumn"));
                    const control = row.children.find(c => c.toString().startsWith("QQuickLoader"));
                    check(words.x + words.width <= control.x && control.x + control.width <= row.width
                        && words.y >= 0 && words.y + words.height <= row.height,
                        row.setting.title + " fits at width " + width);
                    const before = row.setting.get();
                    mouseClick(row, row.width / 2, row.height / 2);
                    check(row.setting.get() === !before, row.setting.title + " toggles at width " + width);
                    wait(100);
                }
            }
            options(true, true);
            Keyboard.mainKeyboard = "main";
            Keyboard.layouts = [{name: "English (US)"}, {name: "Greek"}];
            layout("English (US)");
            check(switches === 0 && Keyboard.sent.length === 0 && !module.forceShown,
                "initial layout discovery is silent");
            layout("English (US)");
            layout("Greek", "secondary");
            check(switches === 0 && Keyboard.layout === "English (US)",
                "duplicates and secondary keyboard events do not announce a switch");

            DrawerPins.pins = {language: false};
            for (let mask = 0; mask < 4; mask++) {
                reset();
                options(!!(mask & 1), !!(mask & 2));
                layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
                check(Keyboard.sent.length === (mask & 1 ? 1 : 0)
                    && module.auditShow.running === !!(mask & 2)
                    && (module.auditDelay.running || module.auditBounce.running) === !!(mask & 2)
                    && module.showsClosed === !!(mask & 2), "independent feedback combination " + mask);
                if (mask & 1) {
                    const command = Keyboard.sent[0];
                    check(command.includes("-e") && command[command.indexOf("-t") + 1] === "3000"
                        && command.includes("string:x-canonical-private-synchronous:keyboard-layout")
                        && command[command.length - 1] === Keyboard.layout,
                        "notification is transient, timed and replaces the preceding layout notice");
                }
                check(DrawerPins.kept("language"), "temporary feedback preserves drawer preference " + mask);
            }

            reset(); options(false, true);
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            check(module.auditDelay.running && !module.auditBounce.running,
                "hidden module unfolds before bouncing");
            tryVerify(() => module.auditBounce.running, 1000);
            tryVerify(() => module.auditBounce.offset < -1, 1000);
            check(module.contentAnimating && module.forceShown, "bounce moves and holds the module visible");
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            tryVerify(() => !module.auditBounce.running, 2000);
            check(module.forceShown, "module stays visible after its bounce finishes");
            tryVerify(() => !module.forceShown, 2500);
            check(module.auditBounce.offset === 0 && module.auditBounce.fade === 1 && module.stowed,
                "repeated changes finish one bounce and restore hidden visibility");

            Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            tryVerify(() => module.auditBounce.fade < 0.9, 2000);
            check(module.auditBounce.offset === 0, "Reduce Motion dims without moving the label");
            tryVerify(() => !module.forceShown, 3500);

            options(false, true);
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            wait(1700);
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            wait(1500);
            check(module.forceShown && !module.stowed, "another switch restarts the three-second reveal");
            tryVerify(() => !module.forceShown, 2000);
            check(module.stowed && DrawerPins.kept("language"), "reveal expires without changing saved visibility");

            DrawerPins.pins = {language: true};
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            reset();
            check(module.showsClosed && !module.stowed, "pinned module stays visible after feedback ends");
            DrawerPins.pins = {};
            OpenPopup.owner = module;
            layout(Keyboard.layout === "Greek" ? "English (US)" : "Greek");
            reset();
            check(module.showsClosed, "an open keyboard popup keeps the module visible");
            OpenPopup.owner = null;
            check(module.stowed, "quiet Auto mode returns to the drawer after the popup closes");
            console.log("PASS: keyboard feedback complete");
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-keyboard-feedback-") as folder:
        target = Path(folder)
        copy_shell(target)
        keyboard = target / "services/Keyboard.qml"
        source = keyboard.read_text().replace("target: Hyprland", "target: FakeHyprland")
        source = source.replace('command: ["hyprctl", "devices", "-j"]', 'command: ["/usr/bin/true"]')
        source = source.replace('    id: root', '    id: root\n    property var sent: []\n    function notify(command) { sent = [...sent, command]; }', 1)
        source = source.replace('Quickshell.execDetached(["notify-send",', 'root.notify(["notify-send",')
        keyboard.write_text(source)
        (target / "services/FakeHyprland.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { signal rawEvent(var event) }\n')
        language = target / "modules/Language.qml"
        language.write_text(language.read_text().replace('    id: root',
            '    id: root\n    property alias auditShow: showTimer\n    property alias auditDelay: bounceDelay\n    property alias auditBounce: bounce', 1))
        (target / "components/HoverPopup.qml").write_text('''import QtQuick
Item {
    property Item anchorItem; property bool hovered; property bool pressed
    property real anchorHeight
    property bool open; property string text; property Component popup
    property var item: null
}''')
        (target / "components/LanguagePopup.qml").write_text('import QtQuick\nItem {}\n')
        settings = (target / "modules/SettingsMenu.qml").read_text()
        pages = settings.index('readonly property var pages: [')
        start = settings.index('rows: [', settings.index('title: "Keyboard Layout",', pages)) + len('rows: ')
        end = settings.index('\n                    ]', start) + len('\n                    ]')
        (target / "shell.qml").write_text(QML.replace("SETTINGS_ROWS", settings[start:end]))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
            env=shell_env(target), capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: keyboard feedback complete" in output and not any(
            error in output for error in ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop")), output


if __name__ == "__main__":
    main()
