#!/usr/bin/env python3
"""Exercise the black hold behind the launcher's CRT exit with harmless commands."""

from pathlib import Path
import os
import re
import runpy
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
support = runpy.run_path(str(ROOT / 'scripts/test-right-pill.py'))

STUBS = {
    'Theme.qml': '''pragma Singleton
import QtQuick
QtObject {
    property int fadeMs: 200
    property var glyph: ({powerSuspend: "", powerReboot: "", powerShutdown: "", powerLogout: "", powerKill: "", lock: ""})
}''',
    'Paths.qml': '''pragma Singleton
import QtQuick
QtObject {
    id: root
    property bool fail: false
    function script(name: string): string { return root.fail ? "/bin/false" : "/bin/true"; }
}''',
}

SCENARIO = '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.modules
import qs.services
ShellRoot {
    LazyLoader { id: black; active: Power.dark; Blackout {} }
    Window {
        visible: true; width: 1; height: 1
        TestCase {
            id: test
            when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function fill() { return black.item.contentItem.children[0]; }
            // What the launcher does: the exit plays, then the command runs.
            function leave(arg) {
                Power.leaving = {key: arg, arg: arg};
                wait(250);
                check(black.item !== null && fill().opacity === 1, "black fades in under the exit for " + arg);
                Power.run(arg, true);
                Power.leaving = null;
            }
            function checkSleep() {
                leave("--suspend");
                wait(300);
                check(Power.blackout && black.item !== null, "Sleep keeps the screen black after the request");
                wait(1200);
                check(!Power.blackout && !Power.dark && black.item === null, "wake signal restores the desktop");
                console.log("PASS: Sleep holds black until the wake signal");
            }
            function run() {
                for (const arg of ["--logout", "--reboot", "--poweroff"]) {
                    leave(arg);
                    wait(800);
                    check(Power.blackout && black.item !== null, "black holds after " + arg);
                    Power.blackout = false;
                    check(black.item === null, "explicit release unloads the black");
                }
                Power.leaving = {key: "logout", arg: "--logout"};
                wait(50);
                Power.leaving = null;
                check(!Power.dark && black.item === null, "an exit taken back leaves no black");
                Power.run("--lock", true);
                check(!Power.blackout && !Power.dark, "lock never holds black");
                Paths.fail = true;
                leave("--logout");
                wait(800);
                check(!Power.blackout && black.item === null, "failed command releases the black");
                Paths.fail = false;
                console.log("PASS: black persists after successful commands and lets go on failure");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        } }
    }
}'''


def offscreen(source):
    """Offscreen Qt has no layer shell: keep the window, drop its placement."""
    source = re.sub(r'\n    anchors \{.*?\n    \}\n', '\n', source, flags=re.DOTALL)
    keep = [line for line in source.splitlines()
            if not re.match(r'\s*(WlrLayershell\.|exclusionMode:|mask:|screen:|import Quickshell\.(Wayland|Hyprland))', line)]
    source = '\n'.join(keep).replace('PanelWindow {', 'Window {\n    width: 100; height: 100; visible: true', 1)
    return 'import QtQuick.Window\n' + source


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-power-test-') as folder:
        target = Path(folder)
        for name in ('modules', 'services'):
            (target / name).mkdir()
        (target / 'runtime').mkdir(mode=0o700)
        (target / 'bin').mkdir()
        monitor = target / 'bin/gdbus'
        monitor.write_text('#!/bin/sh\nsleep 1.2\nprintf "%s\\n" "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)"\nsleep 1\n')
        monitor.chmod(0o700)
        shutil.copyfile(ROOT / 'services/Power.qml', target / 'services/Power.qml')
        (target / 'modules/Blackout.qml').write_text(offscreen((ROOT / 'modules/Blackout.qml').read_text()))
        for name, source in STUBS.items():
            (target / name).write_text(source)
        original_path = os.environ['PATH']
        try:
            os.environ['PATH'] = str(target / 'bin') + ':' + original_path
            # One run each, so every scenario stays inside run_shell's timeout.
            for check in ('checkSleep', 'run'):
                support['run_shell'](target, SCENARIO.replace('test.run();', f'test.{check}();'))
        finally:
            os.environ['PATH'] = original_path


if __name__ == '__main__':
    main()
