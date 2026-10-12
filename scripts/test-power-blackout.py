#!/usr/bin/env python3
"""Exercise power menu dismissal and the CRT handoff with harmless commands."""

from pathlib import Path
import os
import runpy
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
support = runpy.run_path(str(ROOT / 'scripts/test-right-pill.py'))

STUBS = {
    'Theme.qml': '''pragma Singleton
import QtQuick
QtObject {
    property bool reduceMotion: false
    property int revealMs: 160
    property int fadeMs: 200
    property int markInset: 4
    property int pillBorder: 1
    property color tint: "#222222"
    property color barBg: "#88222222"
    property color label: "white"
    property string bodyFont: "sans-serif"
    property int labelSize: 14
    property int bodyWeight: Font.Normal
    property var glyph: ({powerSuspend: "", powerReboot: "", powerShutdown: "", powerLogout: "", powerKill: ""})
}''',
    'Paths.qml': '''pragma Singleton
import QtQuick
QtObject {
    id: root
    property bool fail: false
    function script(name: string): string { return root.fail ? "/bin/false" : "/bin/true"; }
}''',
    'services/Wallpaper.qml': '''pragma Singleton
import QtQuick
QtObject { property var backdrops: ({}) }''',
    'components/OverlayWindow.qml': '''import QtQuick
import QtQuick.Window
Window {
    required property bool shown
    required property string name
    required property Item inputItem
    property bool dismissOnOutsidePress: true
    signal dismissed
    property bool completed: false
    readonly property bool opened: completed && shown
    property real devicePixelRatio: 1
    width: 800; height: 600; visible: true
    Component.onCompleted: completed = true
}''',
    'components/Glyph.qml': 'import QtQuick\nText { property int fontSize: 18 }',
    'components/Liquid.qml': '''import QtQuick
Item { property vector4d box0; property real rimFrom; property real rimTo; property vector4d fill }''',
    'components/FlowMark.qml': '''import QtQuick
Item {
    property bool resetWhenHidden; property bool held; property real slabHeight
    property real wantLeft; property real wantRight; property bool atFirst; property bool atLast
    property real wallLeft; property real wallRight
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
    LazyLoader { id: menu; active: Power.active; PowerMenu {} }
    Window {
        visible: true; width: 1; height: 1
        TestCase {
            id: test
            when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function open() {
                Power.blackout = false;
                Power.shown = true;
                wait(600);
                check(menu.item !== null && menu.item.reveal === 1, "menu finishes appearing");
                check(menu.item.shade === 0, "wallpaper stays visible before an action");
                check(menu.item.widthRatio === 1 && menu.item.contentAlpha === 1, "launcher-style entrance settles");
            }
            function checkPointer() {
                open();
                const window = menu.item;
                const desktop = Qt.createQmlObject('import QtQuick; MouseArea { anchors.fill: parent; z: -1; property int clicks: 0; onClicked: clicks++ }', window.contentItem);
                mousePress(window.contentItem, 20, 20, Qt.LeftButton);
                check(Power.shown, "wallpaper press keeps the surface until release");
                mouseRelease(window.contentItem, 20, 20, Qt.LeftButton);
                check(!Power.shown && desktop.clicks === 0, "wallpaper click dismisses without reaching the desktop");
                wait(250);
                open();
                check(menu.item.inputItem.width === menu.item.width && menu.item.inputItem.height === menu.item.height, "power menu input covers the wallpaper");
                menu.item.choose(1);
                check(menu.item.pending !== null, "restart requests confirmation");
                mouseClick(menu.item.contentItem, 20, 20, Qt.RightButton);
                check(!Power.shown && !Power.blackout, "wallpaper click also dismisses confirmation without executing it");
                wait(250);
                console.log("PASS: wallpaper clicks are consumed and dismiss the entire power menu");
            }
            function run() {
                open();
                menu.item.execute("--suspend");
                wait(950);
                check(!Power.shown && Power.blackout && menu.item !== null, "Sleep keeps the desktop covered after the CRT and queued request");
                check(menu.item.reveal === 1 && menu.item.shade === 1, "Sleep keeps the final frame black");
                wait(1300);
                check(!Power.blackout && !Power.active && menu.item === null, "wake signal restores the desktop");
                console.log("PASS: Sleep holds black until the wake signal");
                for (const reduced of [false, true]) {
                    Theme.reduceMotion = reduced;
                    for (const action of reduced ? ["--logout"] : ["--logout", "--reboot", "--poweroff"]) {
                        open();
                        const window = menu.item;
                        window.execute(action);
                        wait(1000);
                        check(!Power.shown && Power.blackout && Power.active, "service holds the overlay after " + action);
                        check(menu.item === window, "menu survives beyond dismissal linger");
                        check(window.reveal === 1 && window.shade === 1, "CRT black stays opaque after " + action);
                        check(window.afterglow === 0, "CRT finishes before black hold");
                        Power.blackout = false;
                        wait(250);
                        check(menu.item === null, "explicit cancellation releases blackout");
                    }
                }
                Theme.reduceMotion = false;
                open();
                menu.item.execute("--logout");
                wait(100);
                menu.item.cancelCrt();
                wait(800);
                check(Power.shown && !Power.blackout && menu.item.shade === 0, "Escape before handoff restores the undimmed menu");
                Paths.fail = true;
                menu.item.execute("--logout");
                wait(1000);
                check(!Power.blackout && !Power.active && menu.item === null, "failed command releases black hold");
                Paths.fail = false;
                open();
                Power.shown = false;
                wait(300);
                check(!Power.active && menu.item === null, "ordinary dismissal still unloads the menu");
                console.log("PASS: CRT black persists after successful commands, with and without reduced motion");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        } }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-power-test-') as folder:
        target = Path(folder)
        for name in ('components', 'modules', 'services'):
            (target / name).mkdir()
        (target / 'runtime').mkdir(mode=0o700)
        (target / 'bin').mkdir()
        monitor = target / 'bin/gdbus'
        monitor.write_text('#!/bin/sh\nsleep 1.2\nprintf "%s\\n" "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)"\nsleep 1\n')
        monitor.chmod(0o700)
        for name in ('Linger.qml', 'services/Power.qml'):
            shutil.copyfile(ROOT / name, target / name)
        # Offscreen Qt has no layer shell; only replace the platform window/focus.
        source = (ROOT / 'modules/PowerMenu.qml').read_text()
        source = '\n'.join(line for line in source.splitlines() if 'WlrLayershell.keyboardFocus:' not in line)
        (target / 'modules/PowerMenu.qml').write_text(source)
        for name, source in STUBS.items():
            (target / name).write_text(source)
        original_path = os.environ['PATH']
        try:
            os.environ['PATH'] = str(target / 'bin') + ':' + original_path
            support['run_shell'](target, SCENARIO.replace('test.run();', 'test.checkPointer();'))
            support['run_shell'](target, SCENARIO)
        finally:
            os.environ['PATH'] = original_path


if __name__ == '__main__':
    main()
