#!/usr/bin/env python3
"""Check accessibility actions against real pointer paths with isolated state."""

import os
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def main():
    target = ROOT / ".a11y-test/controls"
    target.mkdir(parents=True, exist_ok=True)
    files = subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True)
    for name in files.splitlines():
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    (target / "settings.json").write_text("{}\n")
    (target / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    Window {
        id: win
        visible: true; width: 600; height: 300
        property int clicks: 0
        property int rights: 0
        property int barClicks: 0
        property int taps: 0
        property int rows: 0
        property int moves: 0
        property int wheelSteps: 0
        property int changes: 0
        property bool settingValue: false
        property int choiceValue: 0
        Column {
            ClickArea {
                id: click; name: "Click"; width: 100; height: 30
                actions: ({[Qt.LeftButton]: () => win.clicks++, [Qt.RightButton]: () => win.rights++})
            }
            ClickArea { id: hoverOnly; name: "Hover only"; width: 100; height: 20; hovers: true }
            ClickArea { id: silent; name: "Nothing to do"; width: 100; height: 20 }
            ClickArea {
                id: wheel; name: "Wheel"; width: 100; height: 20; scrolls: true
                Accessible.onScrollUpAction: win.wheelSteps++
                Accessible.onScrollDownAction: win.wheelSteps--
            }
            ClickArea {
                id: sideButtons; name: "Side buttons"; width: 100; height: 20
                actions: ({[Qt.RightButton]: () => win.rights++, [Qt.MiddleButton]: () => win.rights++})
            }
            ClickArea {
                id: idle; name: "Nothing right now"; width: 100; height: 20
                actions: ({[Qt.LeftButton]: null, [Qt.RightButton]: null})
            }
            BarItem {
                id: layered; tooltip: "Layered"; pinKey: "test-layered"; popupButton: Qt.RightButton
                width: 100; height: 38
                popup: Component { Item { property var anchorItem } }
            }
            BarItem {
                id: bar; name: "Bar action"; width: 100; height: 38
                actions: ({[Qt.LeftButton]: () => win.barClicks++})
                Text { text: "Bar action" }
            }
            BarItem {
                id: popup; name: "Popup"; width: 100; height: 38
                actions: ({[Qt.LeftButton]: () => win.barClicks++})
                popup: Component {
                    Item {
                        property var anchorItem
                        property var anchor: ({rect: Qt.rect(0, 0, 0, 0)})
                        property real shadowTop: 0
                        property bool requestedVisible
                    }
                }
                Text { text: "Popup" }
            }
            PopupButton { id: button; label: "Button"; onTapped: win.taps++ }
            PopupRow { id: row; name: "Row"; width: 100; height: 24; onTapped: win.rows++ }
            Slider {
                id: slider; name: "Level"; value: 0.5; width: 100
                onMoved: function(v) { win.moves++; value = v; }
            }
            SettingRow {
                id: toggle; width: 500
                setting: ({type: "toggle", title: "Test toggle", get: () => win.settingValue,
                           set: v => {win.changes++; win.settingValue = v;}})
            }
            SettingChoice {
                id: choice
                setting: ({title: "Test choice", options: [{value: 0, label: "First"}, {value: 1, label: "Second"}],
                           get: () => win.choiceValue, set: v => {win.changes++; win.choiceValue = v;}})
            }
        }
        TestCase {
            id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function run() {
                mouseClick(click, 50, 15); click.Accessible.pressAction();
                check(win.clicks === 2 && win.rights === 0, "ClickArea press matches one left click");
                mouseClick(click, 50, 15, Qt.RightButton);
                check(win.clicks === 2 && win.rights === 1, "right action stays separate");
                check(click.Accessible.role === Accessible.Button && !click.Accessible.ignored, "a press is a button");
                check(!hoverOnly.Accessible.ignored && hoverOnly.Accessible.role === Accessible.StaticText, "a hover-only area stays in the tree as text");
                check(silent.Accessible.ignored, "an area with nothing to press, hover or scroll stays out");
                check(!wheel.Accessible.ignored, "a wheel area stays in the tree");
                wheel.Accessible.scrollUpAction(); wheel.Accessible.scrollUpAction(); wheel.Accessible.scrollDownAction();
                check(win.wheelSteps === 1, "scroll actions reach the wheel area's handlers");
                check(click.Accessible.description === "Pointer: right click", "a right action is named on the pointer line");
                check(hoverOnly.Accessible.description === "Pointer: hover" && wheel.Accessible.description === "Pointer: scroll", "hover and wheel are named");
                check(!sideButtons.Accessible.ignored && sideButtons.Accessible.role === Accessible.StaticText
                      && sideButtons.Accessible.description === "Pointer: right click, middle click", "right and middle alone keep an area in the tree");
                check(idle.Accessible.ignored && idle.Accessible.description === "", "buttons mapped to null are not named");
                check(layered.Accessible.description === "Pointer: right click, middle click, hover", "BarItem names its pin and popup layers' buttons");
                mouseClick(bar, 50, 15); bar.Accessible.pressAction();
                check(win.barClicks === 2, "BarItem press activates once, not twice through inheritance");
                mouseClick(popup, 50, 15);
                check(OpenPopup.owner === popup && win.barClicks === 2, "popup intercepts physical left click");
                popup.Accessible.pressAction();
                check(OpenPopup.owner === null && win.barClicks === 2, "accessibility closes popup without module action");
                popup.stowed = true; popup.Accessible.pressAction();
                check(OpenPopup.owner === null && win.barClicks === 2, "stowed bar item has no press action");
                mouseClick(button, button.width / 2, button.height / 2); button.Accessible.pressAction();
                check(win.taps === 2, "PopupButton press matches one tap");
                button.live = false; button.Accessible.pressAction();
                check(win.taps === 2, "inactive popup button does nothing");
                mouseClick(row, 50, 12); row.Accessible.pressAction();
                check(win.rows === 2, "PopupRow press matches one tap");
                const sliderValue = slider.children.find(child => child.objectName === "accessibleValue");
                sliderValue.Accessible.increaseAction();
                check(win.moves === 1 && Math.abs(slider.value - 0.55) < 0.001, "slider increase emits moved once");
                sliderValue.Accessible.decreaseAction();
                check(win.moves === 2 && Math.abs(slider.value - 0.5) < 0.001, "slider decrease emits moved once");
                slider.value = 1; sliderValue.Accessible.increaseAction();
                check(slider.value === 1, "slider clamps at upper bound");
                const beforeValueWrite = win.moves;
                sliderValue.value = 0.7;
                check(win.moves === beforeValueWrite + 1 && slider.value === 0.7, "Value interface write emits moved once");
                slider.value = 0.4;
                check(win.moves === beforeValueWrite + 1 && sliderValue.value === 0.4, "model updates refresh proxy without writes");
                toggle.Accessible.pressAction();
                check(win.changes === 1 && win.settingValue, "settings press toggles once");
                toggle.Accessible.toggleAction();
                check(win.changes === 2 && !win.settingValue, "settings toggle toggles once");
                const second = choice.children[0].children.find(child => child.Accessible.name === "Test choice: Second");
                second.Accessible.pressAction();
                check(win.changes === 3 && win.choiceValue === 1, "choice press selects once");
                second.Accessible.toggleAction();
                check(win.changes === 3 && win.choiceValue === 1, "choice toggle keeps selected radio checked");
                console.log("PASS: accessibility matches pointer actions, popup routing, guards and slider steps");
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}
''')
    runtime = ROOT / ".a11y-test/r"
    runtime.mkdir(mode=0o700, exist_ok=True)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"),
               XDG_DATA_HOME=str(target / "data"), XDG_CACHE_HOME=str(target / "cache"))
    for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
        env.pop(key, None)
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output, end="")
    return 0 if result.returncode == 0 and "PASS: accessibility matches" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
