#!/usr/bin/env python3
"""Keep Settings open through dropdown selection and dismiss on outside clicks."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules
import qs.services
ShellRoot {
    SettingsMenu { id: menu }
    TestCase {
        id: test
        when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children ?? []) {
                const hit = find(child, predicate);
                if (hit) return hit;
            }
            return null;
        }
        function event(data) { FakeHyprland.rawEvent({name: "custom", data}); }
        function run() {
            Preferences.shown = true;
            menu.query = "mail badge";
            wait(400);
            const row = find(menu.contentItem, i => i.setting?.id === "emailBadgeStyle" && i.controls !== undefined);
            check(row !== null, "badge setting is rendered");
            const box = row.children.find(c => c.toString().startsWith("QQuickLoader")).item;
            for (const value of ["underdot", "dot", "badge", "hide"]) {
                mouseMove(box, box.width / 2, box.height / 2);
                mouseClick(box, box.width / 2, box.height / 2);
                tryVerify(() => box.popup.visible);
                wait(100);
                const index = box.model.findIndex(o => o.value === value);
                const option = box.popup.contentItem.itemAtIndex(index);
                check(option !== null, "dropdown option is rendered: " + value);
                mouseMove(option, option.width / 2, option.height / 2);
                wait(30);
                event("click");
                mouseClick(option, option.width / 2, option.height / 2);
                event("click-release");
                wait(150);
                check(Settings.badgeStyle("email") === value, "selection applies: " + value);
                check(Preferences.shown, "Settings stays open after selecting " + value);
                check(!box.popup.visible, "only dropdown closes after selecting " + value);
            }
            // Closing the menu without a selection must not leave dismissal disabled.
            mouseClick(box, box.width / 2, box.height / 2);
            tryVerify(() => box.popup.visible);
            box.popup.close();
            wait(100);
            check(!box.popup.visible && Preferences.shown, "closing the dropdown keeps Settings open");

            for (const [query, id] of [["group windows", "groupWindows"], ["module visibility mail", "pin:email"]]) {
                menu.query = query;
                wait(100);
                const setting = find(menu.contentItem, i => i.setting?.id === id && i.controls !== undefined);
                check(setting !== null, "setting is rendered: " + id);
                const control = setting.children.find(c => c.toString().startsWith("QQuickLoader")).item;
                const before = setting.setting.get();
                mouseMove(control, control.width - 4, control.height / 2);
                wait(30);
                event("click");
                mouseClick(control, control.width - 4, control.height / 2);
                event("click-release");
                wait(100);
                check(setting.setting.get() !== before && Preferences.shown, "setting changes without closing Settings: " + id);
            }
            mouseMove(menu.contentItem, 5, 5);
            wait(30);
            event("click"); event("click-release");
            wait(100);
            check(!Preferences.shown, "an outside click still dismisses Settings");
            console.log("PASS: settings selection complete");
        }
    }
    Timer {
        interval: 150; running: true
        onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-settings-selection-") as folder:
        target = Path(folder)
        copy_shell(target)
        # Keep the real overlay hover/dismissal logic, replacing only Wayland plumbing.
        overlay = target / "components/OverlayWindow.qml"
        source = overlay.read_text().replace("import QtQuick\n", "import QtQuick\nimport QtQuick.Window\n")
        source = source.replace("PanelWindow {", "Window {", 1)
        start = source.index("    function pickScreen(): void {")
        end = source.index("    HoverHandler {", start)
        source = source[:start] + "    function pickScreen(): void {}\n    width: 1100; height: 800; visible: true\n\n" + source[end:]
        overlay.write_text(source)
        outside = target / "components/OutsideClick.qml"
        outside.write_text(outside.read_text().replace("import Quickshell.Hyprland", "import qs.services")
                           .replace("target: Hyprland", "target: FakeHyprland").replace("event: HyprlandEvent", "event: var"))
        (target / "services/FakeHyprland.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { signal rawEvent(var event) }\n")
        menu = target / "modules/SettingsMenu.qml"
        menu.write_text(menu.read_text().replace("layer.enabled: contentHeight + topMargin + bottomMargin > height", "layer.enabled: false"))
        (target / "components/BackdropProbe.qml").write_text("import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }")
        (target / "services/Keyboard.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [] }")
        (target / "services/Launcher.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property var powerCommands: [] }")
        (target / "services/Tasks.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: []; property var defaultList: ({id: ""}) }')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: settings selection complete" in output and not any(
            error in output for error in ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop")), output


if __name__ == "__main__":
    main()
