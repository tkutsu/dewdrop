#!/usr/bin/env python3
"""Drive a real popup from the keyboard: arrows, Return, sliders and Escape."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

SHELL = '''import QtQuick
import Quickshell
import qs
import qs.components
ShellRoot {
    id: test
    property int rows: 0
    property int buttons: 0
    property int adds: 0
    property int rings: 0
    property real level: 0.5

    FloatingWindow {
        implicitWidth: 300; implicitHeight: 60
        Item { id: anchor; width: 40; height: 20 }
    }

    Popup {
        id: popup
        anchorItem: anchor
        visible: true

        PopupHeader { width: 220; title: "Things"; addable: true; onAdd: test.adds++ }
        PopupRow {
            id: first; name: "First"; width: 220; height: 22
            onTapped: test.rows++
            PopupButton { id: inline; anchors.right: parent.right; glyph: "x"; name: "Remove"; onTapped: test.buttons++ }
        }
        PopupRow { id: second; name: "Second"; width: 220; height: 22; onTapped: test.rows += 10 }
        PopupRow { id: label; width: 220; height: 22 }
        Slider { id: slider; name: "Level"; width: 220; value: test.level; onMoved: v => test.level = v }
        Item {
            id: ringed; width: 40; height: 20
            readonly property var keyPress: () => test.rings++
        }
        Item { id: folded; width: 40; height: 0; readonly property var keyPress: () => {} }
    }

    function check(ok, message) {
        if (!ok) throw new Error(message);
    }
    function press(key) {
        return OpenPopup.key({ key: key });
    }

    function run() {
        check(popup.opened, "popup opened offscreen");
        check(OpenPopup.keyed.includes(popup), "an open popup takes keys");
        check(popup.keyItem === null, "nothing is selected on opening");
        const targets = popup.keyTargets();
        check(!targets.includes(label), "a row with nothing to press is skipped");
        check(!targets.includes(folded), "a control folded to nothing is skipped");

        press(Qt.Key_Down);
        const plus = targets[0];
        check(popup.keyItem === plus && plus.keyed && plus.lit, "Down picks the header's plus first");
        press(Qt.Key_Return);
        check(test.adds === 1, "Return presses the header's plus");

        // A header with only the plus is all press, as wide as the rows, so
        // Down lands on the row rather than on the button at its end.
        press(Qt.Key_Down);
        check(popup.keyItem === first && first.hovered, "Down from a full-width target goes to the full-width row");
        press(Qt.Key_Space);
        check(test.rows === 1, "Space presses the row");
        press(Qt.Key_Right);
        check(popup.keyItem === inline && inline.hovered && !first.hovered, "Right moves along the row to its button, lit alone");
        press(Qt.Key_Return);
        check(test.buttons === 1 && test.rows === 1, "Return on the button presses only the button");
        press(Qt.Key_Left);
        check(popup.keyItem === first, "Left comes back to the row");
        press(Qt.Key_Right);

        press(Qt.Key_Down);
        check(popup.keyItem === second, "Down from the button reaches the next row");
        press(Qt.Key_Up);
        check(popup.keyItem === first, "Up from a full-width row goes to the full-width row above");
        press(Qt.Key_Down);
        press(Qt.Key_Return);
        check(test.rows === 11, "Return presses the second row");
        press(Qt.Key_Down);
        check(popup.keyItem === slider, "Down passes a row with no press and reaches the slider");
        press(Qt.Key_Right);
        check(Math.abs(test.level - 0.55) < 0.001, "Right steps the slider up");
        press(Qt.Key_Left);
        press(Qt.Key_Left);
        check(Math.abs(test.level - 0.45) < 0.001, "Left steps the slider down");
        press(Qt.Key_Down);
        check(popup.keyItem === ringed && ringed.keyed === undefined, "a control with no highlight of its own is reached");
        press(Qt.Key_Return);
        check(test.rings === 1, "Return presses it");
        press(Qt.Key_Down);
        check(popup.keyItem === ringed, "Down at the end stays put");
        press(Qt.Key_Up);
        check(popup.keyItem === slider, "Up goes back");
        press(Qt.Key_Tab);
        check(popup.keyItem === ringed, "Tab is reading order");

        check(!press(Qt.Key_A), "keys the popup has no use for are passed on");

        OpenPopup.owner = anchor;
        press(Qt.Key_Escape);
        check(OpenPopup.owner === null, "Escape puts the popup away");

        popup.setKey(first);
        popup.requestedVisible = false;
        check(!OpenPopup.keyed.includes(popup) && popup.keyItem === null && !first.keyed, "a closed popup gives the keys back");
        console.log("PASS: popup keyboard selection, presses, sliders and escape");
    }

    Timer {
        interval: 300; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
            Qt.quit();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-popup-keys-") as folder:
        target = Path(folder)
        files = subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True)
        for name in files.splitlines():
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        (target / "settings.json").write_text("{}\n")
        (target / "shell.qml").write_text(SHELL)
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"),
                   XDG_DATA_HOME=str(target / "data"), XDG_CACHE_HOME=str(target / "cache"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        ok = result.returncode == 0 and "PASS: popup keyboard" in output and "FAIL:" not in output
        for error in ("ReferenceError:", "TypeError:", "Binding loop", "Unable to assign"):
            ok = ok and error not in output
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
