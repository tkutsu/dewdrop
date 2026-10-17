#!/usr/bin/env python3
"""Check badge sampling through module layout, pill transfer and wallpaper motion."""

from pathlib import Path
import re
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


SCENARIO = r"""
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    id: root
    property int failures: 0
    QtObject {
        id: picture
        property string path: 'fixture.png'
        property bool glass: true
        property real zoom: 1.2
        property real offsetX: 0
        property real offsetY: 0
        property size natural: Qt.size(0, 0)
        property color average: '#808080'
        property real opacity: 1
    }
    QtObject {
        id: renderer
        property var wallpaperLayers: [picture, picture]
        property var front: picture
        property var back: picture
        property real progress: 0
        function startFade() {}
    }
    Window {
        visible: true; width: 400; height: 200
        WallpaperStrip {
            id: strip
            screen: ({name: 'badge-fixture', width: 400, height: 200})
            width: 400; height: 40
        }
        Pill {
            id: first
            side: Pill.Side.Left; edges: false; backdrop: strip
            order: ['count', 'spacer']
            BarItem {
                id: module
                settingsKey: 'count'
                BadgedGlyph { id: glyph; glyph: 'M'; badge: '2' }
            }
            BarItem {
                settingsKey: 'spacer'
                Item { implicitWidth: 120; implicitHeight: Theme.barHeight }
            }
        }
        Pill {
            id: second
            side: Pill.Side.Right; edges: false; backdrop: strip
            order: ['count', 'other']
            BarItem {
                settingsKey: 'other'
                Item { implicitWidth: 100; implicitHeight: Theme.barHeight }
            }
        }
        TestCase {
            id: test
            when: false
            function check(ok, message) {
                console.log((ok ? 'PASS: ' : 'FAIL: ') + message);
                if (!ok) root.failures++;
            }
            function same(a, b) {
                return Math.abs(a.r - b.r) < 0.002 && Math.abs(a.g - b.g) < 0.002 && Math.abs(a.b - b.b) < 0.002;
            }
            function badge() { return glyph.children.find(child => child instanceof Badge); }
            function snapshot() {
                const c = badge().fill;
                return Qt.rgba(c.r, c.g, c.b, c.a);
            }
            function expected() {
                const icon = glyph.children[0];
                const top = Math.floor((icon.height - glyph.glyphSize) / 2) + glyph.nudge;
                const pos = icon.mapToItem(strip, 0, top);
                return Theme.mix(Theme.glassOver(strip.averageRegion(Qt.rect(pos.x, pos.y, icon.width, glyph.glyphSize))), Qt.rgba(1, 1, 1, 1), Theme.selectionStrong.a);
            }
            function run() {
                Wallpaper.registerBackdrop('badge-fixture', renderer);
                wait(30);
                // Deterministic cached samples; no image decoding or subprocesses.
                const cells = [];
                for (let y = 0; y < 20; y++)
                    for (let x = 0; x < 60; x++)
                        cells.push(Qt.rgba(x / 59, y / 19, 1 - x / 59, 1));
                strip.stripFor(picture).children[0].grid = {nx: 60, cells};
                wait(30);
                check(strip.sampled, 'wallpaper colour grid is ready');
                check(same(badge().fill, expected()), 'badge uses the wallpaper under its own icon');
                const iconWidth = glyph.implicitWidth;
                glyph.dot = true; wait(20);
                const disc = badge().children[0];
                check(same(disc.color, Qt.rgba(1, 1, 1, 1)) && Math.abs(disc.color.a - 0.7) < 0.002,
                    'dots use white at 70 percent opacity');
                let before = snapshot();
                first.order = ['spacer', 'count']; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge refreshes when reordered within its pill');
                check(same(disc.color, Qt.rgba(1, 1, 1, 1)) && Math.abs(disc.color.a - 0.7) < 0.002,
                    'dots stay translucent white after reordering');
                before = snapshot();
                picture.offsetX = -20; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge follows horizontal parallax before transferring');
                before = snapshot();
                picture.offsetY = 8; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge follows vertical parallax before transferring');
                before = snapshot();
                module.parent = second.moduleHost; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge refreshes when transferred between pills');
                before = snapshot();
                module.shift = -15; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge follows the module spring translation');
                before = snapshot();
                second.edgeOffset = 25; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge follows its moving pill');
                before = snapshot();
                picture.offsetX = -50; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge refreshes during horizontal wallpaper parallax');
                before = snapshot();
                picture.offsetY = 15; wait(40);
                check(!same(badge().fill, before) && same(badge().fill, expected()), 'badge refreshes during vertical wallpaper parallax');
                glyph.dot = false; glyph.underdot = true; wait(20);
                check(badge().width === Theme.focusDotSize && badge().height === Theme.focusDotSize, 'underdot uses the left pill dot size');
                check(Math.abs(badge().x + badge().width / 2 - glyph.implicitWidth / 2) < 0.01, 'underdot is centred below the icon');
                check(badge().y === Math.round(Theme.pillTop(glyph.height) + Theme.focusDotLine - badge().height / 2), 'underdot shares the left pill baseline');
                check(glyph.children[0].layer.enabled, 'underdot cuts a clear gap out of the icon');
                check(glyph.implicitWidth === iconWidth, 'changing indicator style preserves icon spacing');
                const label = glyph.badge;
                glyph.badge = ''; wait(20);
                check(!badge().visible && !glyph.children[0].layer.enabled, 'empty count removes the underdot and its cutout');
                glyph.badge = label; glyph.underdot = false; wait(20);
                check(badge().visible && !badge().dot && badge().height === Theme.badgeSize, 'switching back restores the count badge');
                strip.stripFor(picture).children[0].grid = {nx: 0, cells: []}; wait(30);
                const fallback = Theme.mix(second.surface, Qt.rgba(1, 1, 1, 1), Theme.selectionStrong.a);
                check(same(badge().fill, fallback), 'badge falls back to its pill before wallpaper samples are ready');
            }
        }
        Timer {
            interval: 100; running: true
            onTriggered: {
                try { test.run(); } catch (e) { root.failures++; console.log('FAIL: ' + e); }
                console.log('RESULT: ' + root.failures + ' failures');
                Qt.quit();
            }
        }
    }
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-badge-colors-') as folder:
        target = Path(folder)
        copy_shell(target)
        def run(scenario):
            (target / 'shell.qml').write_text(scenario)
            result = subprocess.run(['qs', '-p', str(target), '--no-color'],
                                    env=shell_env(target), capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            print(output, end='')
            return result.returncode == 0 and 'RESULT: 0 failures' in output and 'FAIL:' not in output

        generic_ok = run(SCENARIO)
        # Use the real bell with a retained count, without taking over desktop notifications.
        (target / 'services/Notifications.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property int waiting: 2
    property int count: 2
    property string label: '2'
    property string tooltip: '2 notifications'
    property string icon: 'M'
    signal centreRequested(bool toggle)
    function clearAll() {}
}
''')
        bell = SCENARIO.replace('import qs.components', 'import qs.components\nimport qs.modules')
        bell = bell.replace('    property int failures: 0', '''    property int failures: 0
    readonly property var glyph: module.keyBox.children.find(child => child instanceof BadgedGlyph)''')
        bell = bell.replace('''            BarItem {
                id: module
                settingsKey: 'count'
                BadgedGlyph { id: glyph; glyph: 'M'; badge: '2' }
            }''', '''            NotificationBell { id: module; settingsKey: 'count' }''')
        # Carry over the centre pill's actual wallpaper wiring from the bar.
        central_header = (ROOT / 'Bar.qml').read_text().split('        id: clockPill', 1)[1].split('        // Paused', 1)[0]
        backdrop = re.search(r'^        backdrop: (.+)$', central_header, re.M)
        central_backdrop = 'backdrop: strip' if backdrop and backdrop[1] == 'wallpaperImage' else ''
        bell = bell.replace('side: Pill.Side.Left; edges: false; backdrop: strip',
                            'side: Pill.Side.Centre; drawsSlab: false; edges: false; ' + central_backdrop)
        print('Checking the real notification bell in the centre pill:')
        bell_ok = run(bell)
        return 0 if generic_ok and bell_ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
