#!/usr/bin/env python3
"""An icon that goes while held (a tray app quitting mid-press) lets go of the
bar's glass: no glow left where it was until the next press. A quick click
still plays the whole press before it lets go."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import qs.src.components
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 200; implicitHeight: 100
        Component {
            id: entryComp
            Item {
                id: entry
                width: 40; height: 30
                QtObject { id: area; property bool pressed: false; property real mouseX: 10; property real mouseY: 10
                    function mapToItem(a, x, y) { return entry.mapToItem(a, x, y) } }
                property alias areaPressed: area.pressed
                PressGlass { icon: entry; area: area }
            }
        }
        Timer {
            interval: 50; running: true
            onTriggered: {
                const e = entryComp.createObject(win.contentItem);
                e.areaPressed = true;
                console.log("HELD " + GlassPress.down);
                e.destroy();
                later.start();
            }
        }
        Timer { id: later; interval: 700; onTriggered: {
            console.log((!GlassPress.down && GlassPress.lit < 0.01 ? "PASS" : "FAIL")
                + ": gone while held, down=" + GlassPress.down + " lit=" + GlassPress.lit.toFixed(2));
            quick.areaPressed = true;
            letGo.start();
        } }

        // A quick click lets go before the spring has run: the glass still
        // plays the whole press, then lets go.
        Item {
            id: quick
            width: 40; height: 30
            QtObject { id: quickArea; property bool pressed: false; property real mouseX: 10; property real mouseY: 10
                function mapToItem(a, x, y) { return quick.mapToItem(a, x, y) } }
            property alias areaPressed: quickArea.pressed
            PressGlass { icon: quick; area: quickArea }
        }
        property real peak: 0
        Timer { interval: 8; repeat: true; running: quick.areaPressed || GlassPress.down
            onTriggered: win.peak = Math.max(win.peak, GlassPress.popOf(quick)) }
        Timer { id: letGo; interval: 40; onTriggered: { quick.areaPressed = false; settled.start(); } }
        Timer { id: settled; interval: 1500; onTriggered: {
            console.log((win.peak > 1 && !GlassPress.down && GlassPress.lit < 0.01 ? "PASS" : "FAIL")
                + ": quick click, peak=" + win.peak.toFixed(2) + " down=" + GlassPress.down + " lit=" + GlassPress.lit.toFixed(2));
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-press-release-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line or "rror" in line))
        assert "HELD true" in output, "the press never landed"
        assert "PASS: gone while held" in output, output
        assert "PASS: quick click" in output, output


if __name__ == "__main__":
    main()
