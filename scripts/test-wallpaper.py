#!/usr/bin/env python3
"""Exercise wallpaper motion, glass sampling, colour drift and saved options in Qt."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

SCENARIO = r"""
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
import qs.testing
ShellRoot {
    id: root
    property int grabs: 0
    property var one: ({ id: 1, name: '1' })
    property var two: ({ id: 2, name: '2' })
    property var three: ({ id: 3, name: '3' })
    Window {
        visible: true; width: 400; height: 220
        Backdrop { id: desktop; modelData: ({ name: 'fixture', width: 400, height: 200 }); width: 400; height: 200 }
        WallpaperStrip { id: strip; screen: desktop.screen; width: 400; height: 24 }
        TestCase {
            id: test
            when: false
            function check(ok, message) { if (!ok) throw new Error(message); }
            function near(a, b) { return Math.abs(a - b) < 0.002; }
            function visit(workspace) {
                Hyprland.monitor.activeWorkspace = workspace;
                wait(20);
                tryVerify(() => !desktop.panAnimating, 1500);
            }
            function run() {
                tryVerify(() => Wallpaper.restored && desktop.ready, 5000);
                check(!Wallpaper.parallax && !Wallpaper.drift, 'older state files default to stationary wallpaper');
                Hyprland.workspaces.values = [root.one, root.two, root.three];
                Hyprland.toplevels.values = [root.one, root.two, root.three].map(w => ({workspace: w}));
                Hyprland.monitor.activeWorkspace = root.one;
                Wallpaper.setParallax(true);
                wait(20);
                tryVerify(() => !desktop.panAnimating, 1500);
                check(near(desktop.panFraction, 0), 'first workspace uses the start of the occupied-plus-empty ring');
                const firstImage = strip.stripFor(desktop.front).children[0];
                tryVerify(() => strip.readyFor(desktop.front), 5000);
                const request = firstImage.sampleRequest;
                const sourceClip = JSON.stringify(firstImage.sourceClipRect);
                const left = strip.averageRegion(Qt.rect(0, 0, 16, 24));
                const panStart = desktop.panFraction;
                Hyprland.monitor.activeWorkspace = root.three;
                wait(200);
                const progress = (desktop.panFraction - panStart) / (2 / 3 - panStart);
                check(progress > 0.76 && progress < 0.89, 'wallpaper follows the workspace glide spring at 200 ms');
                tryVerify(() => !desktop.panAnimating, 1500);
                check(near(desktop.panFraction, 2 / 3), 'direct jump leaves travel for the next workspace');
                const right = strip.averageRegion(Qt.rect(0, 0, 16, 24));
                check(right.b > left.b && right.r < left.r, 'glass colour sampling follows horizontal pan');
                check(firstImage.sampleRequest === request && JSON.stringify(firstImage.sourceClipRect) === sourceClip, 'pan does not reload or resample the wallpaper strip');
                check(near(firstImage.x, -32 * 2 / 3), 'strip uses the same travel as the desktop');
                desktop.grabToImage(result => { result.saveToFile(Quickshell.shellPath('desktop.png')); root.grabs++; });
                strip.sourceItem.grabToImage(result => { result.saveToFile(Quickshell.shellPath('strip.png')); root.grabs++; });
                tryVerify(() => root.grabs === 2, 1000);
                const beforeNewRight = desktop.offsetX;
                const newRight = {id: 4, name: '4'};
                Hyprland.workspaces.values = [root.one, root.two, root.three, newRight];
                visit(newRight);
                check(near(desktop.offsetX - beforeNewRight, -32 / 3), 'entering the edge empty slot moves by a full workspace step');
                visit(root.one);
                check(near(desktop.panFraction, 0), 'empty-to-first wraps to the first crop');
                visit(newRight);
                check(near(desktop.panFraction, 1), 'first-to-empty wraps to the last crop');
                Hyprland.workspaces.values = [root.one, root.two, root.three];
                visit(root.three);
                check(near(desktop.offsetX, beforeNewRight), 'removing the empty workspace restores the same occupied crop');
                const current = desktop.panFraction;
                root.three.id = 2; root.three.name = '2';
                Hyprland.toplevels.values = [root.one, root.three].map(w => ({workspace: w}));
                Hyprland.workspaces.values = [root.one, root.three];
                wait(100);
                check(near(desktop.panFraction, current), 'compaction leaves the active crop in place');
                Hyprland.workspaces.values = [root.one, root.three, {id: 3, name: '3'}];
                wait(100);
                check(near(desktop.panFraction, current), 'creation leaves the active crop in place');
                visit({ id: -99, name: 'special:fixture' });
                check(near(desktop.panFraction, current), 'special workspace retains underlying crop');
                visit({ id: 90, name: 'named-fixture' });
                check(near(desktop.panFraction, current), 'named workspace retains underlying crop');
                visit(root.one);
                check(near(desktop.panFraction, 0), 'last-to-first wraps across finite travel');
                Hyprland.monitor.activeWorkspace = root.three;
                wait(20);
                Hyprland.monitor.activeWorkspace = root.one;
                wait(20);
                tryVerify(() => !desktop.panAnimating, 1500);
                check(near(desktop.panFraction, 0), 'rapid reversal settles at latest workspace');
                strip.atTop = false;
                tryVerify(() => strip.readyFor(desktop.front), 5000);
                check(firstImage.sourceClipRect.y > 150, 'bottom bar crops the bottom of the image');
                Wallpaper.show(1);
                Hyprland.monitor.activeWorkspace = root.three;
                tryVerify(() => desktop.front.path === Wallpaper.current && strip.readyFor(desktop.front), 5000);
                check(desktop.front.opacity === 1 && desktop.back.path === '', 'wallpaper change mid-pan finishes its crossfade');
                Wallpaper.setParallax(false);
                wait(100);
                check(desktop.zoom === 1 && near(desktop.offsetX, 0), 'disabled parallax restores ordinary crop');
                Hyprland.toplevels.values = [{workspace: root.one}];
                Hyprland.workspaces.values = [root.one];
                Hyprland.monitor.activeWorkspace = root.one;
                Wallpaper.setParallax(true);
                wait(20);
                tryVerify(() => !desktop.panAnimating, 1500);
                check(near(desktop.panFraction, 0), 'one occupied workspace retains its virtual empty slot');
                const loneCrop = desktop.offsetX;
                Hyprland.workspaces.values = [root.one, root.two];
                visit(root.two);
                check(desktop.offsetX < loneCrop - 0.5, 'first newly created workspace moves away from the occupied crop');


                Wallpaper.setColor('#8090a0');
                tryVerify(() => desktop.front.swatch !== '' && desktop.front.path === '', 5000);
                Wallpaper.hour = (Wallpaper.hourNow() + 12) % 24;
                Wallpaper.setDrift(true);
                wait(30);
                check(Math.abs(Wallpaper.hour - Wallpaper.hourNow()) < 0.02, 'enabling drift refreshes the clock');
                Wallpaper.hour = 12;
                wait(100);
                const day = Qt.color(Wallpaper.onScreen);
                check(near(day.r, Qt.color('#8090a0').r), 'midday preserves the selected colour');
                Wallpaper.hour = 19;
                wait(100);
                const dusk = Qt.color(Wallpaper.onScreen);
                check(dusk.r / dusk.b > day.r / day.b, 'dusk makes the colour warmer');
                Wallpaper.hour = 0;
                wait(100);
                const night = Qt.color(Wallpaper.onScreen);
                check(night.r + night.g + night.b < day.r + day.g + day.b, 'night makes the colour darker');
                tryVerify(() => near(desktop.front.color.r, night.r) && near(desktop.front.color.b, night.b), 1000);
                const end = Wallpaper.drifted('#8090a0', 24);
                check(near(night.r, end.r) && near(night.b, end.b), 'drift is continuous across midnight');
                Wallpaper.setDrift(false);
                wait(100);
                check(Wallpaper.onScreen === '#8090a0', 'disabling drift restores the base colour');
                Wallpaper.setDrift(true);
                Wallpaper.hour = 0;
                WallClock.wokeUp();
                check(Math.abs(Wallpaper.hour - Wallpaper.hourNow()) < 0.02, 'wake refreshes the drift clock');
                Wallpaper.setColor('#000000');
                Wallpaper.hour = 0;
                check(Wallpaper.onScreen !== '', 'black remains a valid drifting colour');
                Wallpaper.show(0);
                check(Wallpaper.onScreen === '' && Wallpaper.drift, 'image selection suspends drift without losing its preference');
                Wallpaper.setColor('#8090a0');
                Wallpaper.setParallax(true);
                Wallpaper.setDrift(true);
                wait(150);
                console.log('PASS: workspace pan, compaction, wrapping, glass sampling, crossfades and colour drift');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e); } Qt.quit(); } }
    }
}
"""

UI = r"""
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    Window {
        visible: true; width: popup.width + 24; height: popup.height + 24; color: '#171717'
        WallpaperPopup { id: popup; x: 12; y: 12 }
        TestCase { id: test; when: false
            function buttons(item, found) {
                if (item.label !== undefined && item.tapped !== undefined) found[item.label] = item;
                for (const child of item.children) buttons(child, found);
            }
            function run() {
                tryVerify(() => Wallpaper.restored, 5000);
                wait(100);
                const controls = {};
                buttons(popup, controls);
                verify(controls.parallax && controls.drift, 'both section headers have a toggle');
                verify(controls.parallax.framed && controls.drift.framed, 'toggles use standard framed buttons');
                mouseClick(controls.parallax, controls.parallax.width / 2, controls.parallax.height / 2);
                verify(!Wallpaper.parallax && !controls.parallax.lit && controls.parallax.glyph === '', 'parallax button switches off');
                mouseClick(controls.parallax, controls.parallax.width / 2, controls.parallax.height / 2);
                verify(Wallpaper.parallax && controls.parallax.glyph === Theme.glyph.check, 'parallax button switches on with standard check');
                mouseClick(controls.drift, controls.drift.width / 2, controls.drift.height / 2);
                verify(!Wallpaper.drift && !controls.drift.lit, 'drift button switches off');
                mouseClick(controls.drift, controls.drift.width / 2, controls.drift.height / 2);
                verify(Wallpaper.drift && controls.drift.glyph === Theme.glyph.check, 'drift button switches on with standard check');
                verify(controls.drift.y + controls.drift.parent.parent.y < popup.height - 60, 'drift sits above the colour controls');
                const preview = Quickshell.env('QUICKSHELL_WALLPAPER_PREVIEW');
                if (preview) {
                    let saved = false;
                    popup.grabToImage(result => { saved = result.saveToFile(preview); });
                    tryVerify(() => saved, 1000);
                }
                // Exercise layout when there is no image grid to set its width.
                Wallpaper.files = [];
                wait(30);
                verify(popup.bodyWidth >= 320 && controls.parallax.width < popup.bodyWidth / 2, 'empty library retains readable section headers');
                console.log('PASS: wallpaper popup layout, pointer toggles and checkmarks');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e); } Qt.quit(); } }
    }
}
"""

RELOAD = r"""
import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    TestCase { id: test; when: false
        function run() {
            tryVerify(() => Wallpaper.restored, 5000);
            if (Wallpaper.color !== '#8090a0' || !Wallpaper.drift || !Wallpaper.parallax)
                throw new Error('saved colour, drift and parallax did not restore');
            console.log('PASS: wallpaper options survive restart');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e); } Qt.quit(); } }
}
"""


def run_shell(target, scenario):
    (target / 'shell.qml').write_text(scenario)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(target / 'runtime'))
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    print(output, end='')
    assert result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output, output
    for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Failed to load configuration', 'Cannot assign', 'Unable to assign'):
        assert error not in output, output


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-wallpaper-test-') as folder:
        target = Path(folder)
        for name in ('services', 'components', 'modules', 'testing', 'wallpapers', 'cache', 'runtime'):
            (target / name).mkdir(mode=0o700)
        for name in ('Theme.qml', 'services/Wallpaper.qml', 'services/WallClock.qml', 'components/QueuedProcess.qml', 'components/WallpaperStrip.qml', 'modules/Backdrop.qml', 'components/WallpaperPopup.qml', 'components/PopupHeader.qml', 'components/PopupButton.qml', 'components/PopupText.qml', 'components/Glyph.qml', 'components/BarText.qml', 'components/FittedIcon.qml', 'components/InkProbe.qml', 'components/Slider.qml', 'services/GlyphInk.qml', 'services/IconInk.qml'):
            source = (ROOT / name).read_text().replace('import Quickshell.Hyprland', 'import qs.testing')
            if name == 'services/Wallpaper.qml':
                # Keep border IPC off the host; exercise all wallpaper state and timers.
                source = source.replace('Quickshell.execDetached(["hyprctl", "eval",', 'Hyprland.recordBorder(["hyprctl", "eval",')
            if name == 'modules/Backdrop.qml':
                # Render the real image layers in a test window without a Wayland surface.
                source = source.replace('PanelWindow {', 'Item {', 1).replace('    screen: modelData', '    property var screen: modelData\n    readonly property real devicePixelRatio: 1')
                source = source.replace('    WlrLayershell.namespace: "quickshell:backdrop"\n    WlrLayershell.layer: WlrLayer.Background\n', '')
                start = source.index('    anchors {')
                end = source.index('    visible: root.ready', start)
                source = source[:start] + source[end:]
            (target / name).write_text(source)
        (target / 'components/Popup.qml').write_text("""import QtQuick
import qs
Item {
    id: root
    default property alias content: body.data
    property alias spacing: body.spacing
    implicitWidth: body.implicitWidth + 12
    implicitHeight: body.implicitHeight + 12
    Rectangle { anchors.fill: parent; color: '#242424'; radius: Theme.popupRadius; border.width: 1; border.color: Theme.stroke }
    Column { id: body; x: 6; y: 6 }
}
""")
        (target / 'testing/Hyprland.qml').write_text("""pragma Singleton
import QtQuick
QtObject {
    property QtObject monitor: QtObject { property var activeWorkspace: null }
    property QtObject workspaces: QtObject { property var values: [] }
    property QtObject toplevels: QtObject { property var values: [] }
    signal rawEvent(var event)
    function monitorFor(screen) { return monitor; }
    function recordBorder(command) {}
}
""")
        (target / 'Settings.qml').write_text("""pragma Singleton
import QtQuick
import Quickshell
QtObject {
    readonly property string wallpaperDir: Quickshell.shellPath('wallpapers')
    readonly property real wallpaperParallaxZoom: 1.08
    readonly property string font: 'Sans'
    readonly property string monoFont: 'Monospace'
    function inTerminal(command) { return command; }
}
""")
        (target / 'Paths.qml').write_text("pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function cache(name) { return Quickshell.shellPath('cache/' + name); } }\n")
        # Real decoded images and ImageMagick colour grids, confined to fixtures.
        for name, gradient in (('a.png', 'red-blue'), ('b.png', 'green-yellow')):
            subprocess.run(['magick', '-size', '200x432', 'gradient:' + gradient, '-rotate', '-90', str(target / 'wallpapers' / name)], check=True)
        (target / 'scripts').mkdir()
        shutil.copy(ROOT / 'scripts/wallpaper-thumbs', target / 'scripts/wallpaper-thumbs')
        (target / 'wallpapers/.current_wallpaper').write_text(str(target / 'wallpapers/a.png') + '\n\n\n')
        run_shell(target, SCENARIO)
        saved = (target / 'wallpapers/.current_wallpaper').read_text().splitlines()
        assert saved == ['#8090a0', '#8090a0', 'drift', 'parallax'], saved
        run_shell(target, RELOAD)
        # Compare actual Qt-rendered desktop and bar pixels, not only crop formulas.
        from PIL import Image
        desktop = Image.open(target / 'desktop.png').convert('RGB')
        strip = Image.open(target / 'strip.png').convert('RGB')
        for x in range(8, 392, 16):
            for y in range(2, 22, 4):
                assert max(abs(a - b) for a, b in zip(desktop.getpixel((x, y)), strip.getpixel((x, y)))) <= 3, (x, y, desktop.getpixel((x, y)), strip.getpixel((x, y)))
        print('PASS: glass strip pixels match the rendered desktop')
        run_shell(target, UI)


if __name__ == '__main__':
    main()
