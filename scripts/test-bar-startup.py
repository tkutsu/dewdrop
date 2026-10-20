#!/usr/bin/env python3
"""Check startup centring before enabling normal pill position changes."""

from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


QML = """import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    FloatingWindow {
        id: bar
        implicitWidth: 1800; implicitHeight: 100
        STARTUP_FADE
        Item {
            id: host
            width: 0; height: 80
            Pill {
                id: pill
                drawsSlab: false
                animatePosition: true
                BarItem { Rectangle { implicitWidth: 120; implicitHeight: 20 } }
            }
        }
        TestCase {
            id: test
            when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function centred(why) {
                check(Math.abs(pill.x + pill.centreAt - host.width / 2) <= 1,
                    why + ': x=' + pill.x + ', target=' + Math.round(host.width / 2 - pill.centreAt));
            }
            function run() {
                if (Theme.reduceMotion)
                    check(bar.contentItem.opacity === 1, 'Reduce Motion skips the startup fade');
                else
                    check(bar.contentItem.opacity > 0 && bar.contentItem.opacity < 1,
                        'the complete bar fades in at startup');
                host.width = 1800;
                wait(20);
                centred('initial window sizing must not slide the centre pill from the left');
                pill.centreAt = 100;
                wait(20);
                centred('startup layout changes must settle immediately');
                check(pill.scale === 1 && bar.contentItem.scale === 1, 'startup does not scale the bar');
                wait(Theme.startMs + 50);
                check(bar.contentItem.opacity === 1, 'startup fade finishes fully visible');
                Settings.user = {reduceMotion: false};
                pill.centreAt = 150;
                wait(30);
                check(pill.animating, 'later content changes keep their normal position animation');
                wait(Theme.foldMs + 50);
                centred('normal animation lands on the centre');
                Settings.user = {reduceMotion: true};
                pill.centreAt = 80;
                wait(20);
                centred('Reduce Motion centres immediately');
                console.log('PASS: startup stays centred; later motion and Reduce Motion work');
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (e) { console.log('FAIL: ' + e); }
            Qt.quit();
        }
    }
}
"""


def main():
    source = (ROOT / "Bar.qml").read_text()
    fade = source[source.index('    // Fade the complete bar'):source.index('    readonly property var drops:')]
    for reduced in (False, True):
        run(fade, reduced)


def run(fade, reduced):
    with tempfile.TemporaryDirectory(prefix="qs-bar-startup-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "settings.json").write_text('{"reduceMotion": ' + str(reduced).lower() + '}\n')
        (target / "shell.qml").write_text(QML.replace('STARTUP_FADE', fade))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
                                env=shell_env(target), capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS:" in output and "FAIL:" not in output, output
        for error in ("ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign"):
            assert error not in output, output


if __name__ == "__main__":
    main()
