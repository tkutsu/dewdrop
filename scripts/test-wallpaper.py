#!/usr/bin/env python3
"""Exercise wallpaper motion, glass sampling, flat colours and saved options in Qt."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import copy_shell, shell_env

ROOT = Path(__file__).resolve().parents[1]

FOLDER_SWITCH = r"""
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
ShellRoot {
    TestCase { id: test; when: false
        function run() {
            tryVerify(() => Wallpaper.files.length === 2, 3000);
            Settings.wallpaperDir = Quickshell.shellPath('other wallpapers');
            tryVerify(() => Wallpaper.files.length === 1 && Wallpaper.files[0] === Quickshell.shellPath('other wallpapers/only.png'), 3000);
            Settings.wallpaperDir = Quickshell.shellPath('wallpapers');
            tryVerify(() => Wallpaper.files.length === 2 && Wallpaper.files.every(f => f.startsWith(Settings.wallpaperDir + '/')), 3000);
            console.log('PASS: changing the wallpaper folder refreshes the file list');
        }
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch (e) { console.log('FAIL: ' + e); }
        Qt.quit();
    } }
}
"""

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
    property var one: ({ id: 1, name: '1', monitor: Hyprland.monitor })
    property var two: ({ id: 2, name: '2', monitor: Hyprland.monitor })
    property var three: ({ id: 3, name: '3', monitor: Hyprland.monitor })
    Window {
        visible: true; width: 400; height: 220
        Backdrop { id: desktop; modelData: ({ name: 'fixture', width: 400, height: 200 }); width: 400; height: 200 }
        WallpaperStrip { id: strip; screen: desktop.screen; width: 400; height: 24 }
        TestCase {
            id: test
            when: false
            function check(ok, message) { if (!ok) throw new Error(message); }
            function near(a, b) { return Math.abs(a - b) < 0.002; }
            function faded() { return desktop.back.path === '' && desktop.back.swatch === ''; }
            function visit(workspace) {
                Hyprland.monitor.activeWorkspace = workspace;
                wait(20);
                tryVerify(() => !desktop.pan.running, 1500);
            }
            function checkWorkspaceMotion() {
                const pan = desktop.pan;
                // Samples from the installed hyprutils 0.14.2 advanceSpring,
                // using Hyprland's glide (mass 1, stiffness 246.7, damping 31.42).
                for (const [seconds, expected] of [[0.008, 0.007263184], [0.2, 0.820896506], [0.4, 0.986360431], [0.6, 0.999153376]]) {
                    pan.moveTo(0, true);
                    pan.moveTo(1, false);
                    pan.motion.pause();
                    pan.advance(seconds);
                    check(Math.abs(pan.fraction - expected) < 0.000002, 'pan matches the compositor curve at ' + seconds + ' seconds: ' + pan.fraction);
                    check(pan.running, 'pan continues while the compositor spring is moving');
                }
                pan.advance(0.175);
                check(!pan.running && pan.fraction === 1, 'pan stops on the compositor spring completion frame');
                pan.moveTo(0, true);
                pan.moveTo(1, false);
                pan.motion.pause();
                pan.advance(0.08);
                const turningCrop = pan.fraction;
                pan.moveTo(0, false);
                pan.motion.pause();
                check(pan.fraction === turningCrop, 'reversal starts at the visible crop');
                pan.advance(0.2);
                check(Math.abs(pan.fraction - turningCrop * (1 - 0.820896506)) < 0.000002, 'reversal restarts the incoming workspace curve without old momentum');
                pan.moveTo(0, true);
            }
            function run() {
                tryVerify(() => Wallpaper.restored && desktop.ready, 5000);
                check(!Wallpaper.parallax && Wallpaper.parallaxY === 0.5, 'older state files default to stationary wallpaper');
                Hyprland.workspaces.values = [root.one, root.two, root.three];
                Hyprland.toplevels.values = [root.one, root.two, root.three].map(w => ({workspace: w}));
                Hyprland.monitor.activeWorkspace = root.one;
                Wallpaper.setParallax(true);
                wait(20);
                tryVerify(() => !desktop.pan.running, 1500);
                check(near(desktop.pan.fraction, 0), 'first workspace uses the start of the occupied-plus-empty ring');
                tryVerify(() => desktop.front.zoom > 1 && faded(), 2000);
                checkWorkspaceMotion();
                const firstImage = strip.stripFor(desktop.front).children[0];
                tryVerify(() => strip.readyFor(desktop.front), 5000);
                const request = firstImage.sampleRequest;
                const sourceClip = JSON.stringify(firstImage.sourceClipRect);
                const left = strip.averageRegion(Qt.rect(0, 0, 16, 24));
                const panStart = desktop.pan.fraction;
                Hyprland.monitor.activeWorkspace = root.three;
                wait(200);
                const progress = (desktop.pan.fraction - panStart) / (2 / 3 - panStart);
                check(progress > 0.76 && progress < 0.89, 'wallpaper follows the workspace glide spring at 200 ms');
                tryVerify(() => !desktop.pan.running, 1500);
                check(near(desktop.pan.fraction, 2 / 3), 'direct jump leaves travel for the next workspace');
                const right = strip.averageRegion(Qt.rect(0, 0, 16, 24));
                check(right.b > left.b && right.r < left.r, 'glass colour sampling follows horizontal pan');
                check(firstImage.sampleRequest === request && JSON.stringify(firstImage.sourceClipRect) === sourceClip, 'pan does not reload or resample the wallpaper strip');
                check(near(firstImage.x, -32 * 2 / 3), 'strip uses the same travel as the desktop');
                Wallpaper.setParallaxY(0.2);
                wait(20);
                check(near(desktop.front.offsetY, 0.3 * 200 * 0.08), 'height moves the desktop crop');
                check(near(firstImage.y, 0.3 * 200 * 0.08 - 8), 'strip uses the same height as the desktop');
                check(firstImage.sampleRequest === request && JSON.stringify(firstImage.sourceClipRect) === sourceClip, 'height does not reload or resample the wallpaper strip');
                check(strip.averageRegion(Qt.rect(0, 0, 16, 24)).g < right.g && strip.average(0, 16).g < right.g, 'glass colour sampling follows the height');
                desktop.grabToImage(result => { result.saveToFile(Quickshell.shellPath('desktop.png')); root.grabs++; });
                strip.sourceItem.grabToImage(result => { result.saveToFile(Quickshell.shellPath('strip.png')); root.grabs++; });
                tryVerify(() => root.grabs === 2, 1000);
                const beforeNewRight = desktop.front.offsetX;
                const newRight = {id: 4, name: '4', monitor: Hyprland.monitor};
                Hyprland.workspaces.values = [root.one, root.two, root.three, newRight];
                visit(newRight);
                check(near(desktop.front.offsetX - beforeNewRight, -32 / 3), 'entering the edge empty slot moves by a full workspace step');
                visit(root.one);
                check(near(desktop.pan.fraction, 0), 'empty-to-first wraps to the first crop');
                visit(newRight);
                check(near(desktop.pan.fraction, 1), 'first-to-empty wraps to the last crop');
                Hyprland.workspaces.values = [root.one, root.two, root.three];
                visit(root.three);
                check(near(desktop.front.offsetX, beforeNewRight), 'removing the empty workspace restores the same occupied crop');
                const current = desktop.pan.fraction;
                root.three.id = 2; root.three.name = '2';
                Hyprland.toplevels.values = [root.one, root.three].map(w => ({workspace: w}));
                Hyprland.workspaces.values = [root.one, root.three];
                wait(100);
                check(near(desktop.pan.fraction, current), 'compaction leaves the active crop in place');
                Hyprland.workspaces.values = [root.one, root.three, {id: 3, name: '3', monitor: Hyprland.monitor}];
                wait(100);
                check(near(desktop.pan.fraction, current), 'creation leaves the active crop in place');
                visit({ id: -99, name: 'special:fixture' });
                check(near(desktop.pan.fraction, current), 'special workspace retains underlying crop');
                visit({ id: 90, name: 'named-fixture' });
                check(near(desktop.pan.fraction, current), 'named workspace retains underlying crop');
                visit(root.one);
                check(near(desktop.pan.fraction, 0), 'last-to-first wraps across finite travel');
                Hyprland.monitor.activeWorkspace = root.three;
                wait(20);
                Hyprland.monitor.activeWorkspace = root.one;
                wait(20);
                tryVerify(() => !desktop.pan.running, 1500);
                check(near(desktop.pan.fraction, 0), 'rapid reversal settles at latest workspace');
                strip.atTop = false;
                tryVerify(() => strip.readyFor(desktop.front), 5000);
                check(firstImage.sourceClipRect.y > 150, 'bottom bar crops the bottom of the image');
                Wallpaper.show(1);
                Hyprland.monitor.activeWorkspace = root.three;
                tryVerify(() => desktop.front.path === Wallpaper.current && strip.readyFor(desktop.front), 5000);
                check(desktop.front.opacity === 1 && desktop.back.path === '', 'wallpaper change mid-pan finishes its crossfade');
                tryVerify(() => !desktop.pan.running, 1500);
                const zoomedCrop = desktop.front.offsetX;
                Wallpaper.setParallax(false);
                tryVerify(() => desktop.progress > 0, 1000);
                check(desktop.front.zoom > 1 && near(desktop.front.offsetX, zoomedCrop), 'disabling parallax crossfades from the zoomed crop');
                tryVerify(() => desktop.front.zoom === 1 && faded(), 2000);
                check(near(desktop.front.offsetX, 0), 'disabled parallax restores ordinary crop');
                Hyprland.toplevels.values = [{workspace: root.one}];
                Hyprland.workspaces.values = [root.one];
                Hyprland.monitor.activeWorkspace = root.one;
                Wallpaper.setParallax(true);
                wait(20);
                tryVerify(() => !desktop.pan.running, 1500);
                check(near(desktop.pan.fraction, 0), 'one occupied workspace retains its virtual empty slot');
                tryVerify(() => desktop.front.zoom > 1 && faded(), 2000);
                const loneCrop = desktop.front.offsetX;
                Hyprland.workspaces.values = [root.one, root.two];
                visit(root.two);
                check(desktop.front.offsetX < loneCrop - 0.5, 'first newly created workspace moves away from the occupied crop');
                const elsewhere = {id: 7, name: '7', monitor: {}};
                Hyprland.workspaces.values = [root.one, root.two, elsewhere];
                Hyprland.toplevels.values = [{workspace: root.one}, {workspace: elsewhere}];
                visit(root.one);
                visit(root.two);
                check(near(desktop.pan.fraction, 1), "another monitor's workspaces do not join the pan");


                Wallpaper.setColor('#8090a0');
                tryVerify(() => desktop.front.swatch !== '' && desktop.front.path === '', 5000);
                Hyprland.monitor.activeWorkspace = root.one;
                wait(20);
                check(!desktop.pan.running && near(desktop.pan.fraction, 0), 'a flat colour jumps rather than animating an unseen pan');
                tryVerify(() => near(desktop.front.color.r, Qt.color('#8090a0').r) && near(desktop.front.color.b, Qt.color('#8090a0').b), 1000);
                Wallpaper.setColor('#000000');
                check(desktop.wantedColor === '#000000' && desktop.wantedPath === '', 'black remains a valid flat colour');
                Wallpaper.show(0);
                check(desktop.wantedColor === '' && desktop.wantedPath !== '', 'an image replaces the flat colour');
                Wallpaper.setColor('#8090a0');
                Wallpaper.setParallax(true);
                Settings.reduceMotion = true;
                check(!desktop.parallax && desktop.wantedZoom === 1, 'reduce motion turns parallax off');
                Settings.reduceMotion = false;
                check(desktop.parallax && desktop.wantedZoom > 1, 'parallax returns with motion');
                wait(150);
                console.log('PASS: workspace pan, compaction, wrapping, glass sampling, crossfades and flat colours');
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
        id: fixtureWindow
        visible: true; width: popup.width + 24; height: popup.height + 24; color: '#171717'
        WallpaperPopup { id: popup; x: 12; y: 12 }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw new Error(message); }
            function bounds(item) {
                const a = item.mapToItem(popup, 0, 0), b = item.mapToItem(popup, item.width, item.height);
                return Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
            }
            function buttons(item, found) {
                if (item.label !== undefined && item.tapped !== undefined) found[item.label.toLowerCase()] = item;
                if (item.checked !== undefined && item.toggled !== undefined) found[item.name.toLowerCase()] = item;
                if (item.fullHeight !== undefined) found.framing = item;
                if (item.cursorShape === Qt.OpenHandCursor) found.frameArea = item;
                if (item.snapMode !== undefined && item.cellWidth !== undefined) found.grid = item;
                if (item.name === 'Parallax zoom' && item.moved !== undefined) found.zoom = item;
                if (item.text?.endsWith('%')) found.readout = item;
                if (item.text === 'Parallax zoom') found.zoomLabel = item;
                for (const child of item.children) buttons(child, found);
            }
            function run() {
                tryVerify(() => Wallpaper.restored, 5000);
                // The framing shows a picture, so put one up.
                Wallpaper.show(0);
                wait(100);
                const controls = {};
                buttons(popup, controls);
                check(popup.width === popup.bodyWidth + Theme.popupPadding * 2, 'trailing thumbnail gap does not widen the popup');
                const gridBounds = bounds(controls.grid);
                check(Math.abs(gridBounds.x + popup.gridWidth / 2 - popup.width / 2) < 0.5, 'visible thumbnails have equal frame insets');
                check(controls.parallax && controls.monochrome && !controls.drift, 'parallax and monochrome sections have switches, and drift is gone');
                mouseClick(controls.parallax, controls.parallax.width / 2, controls.parallax.height / 2);
                check(!Wallpaper.parallax && !controls.parallax.on, 'parallax switch turns off');
                mouseClick(controls.parallax, controls.parallax.width / 2, controls.parallax.height / 2);
                check(Wallpaper.parallax && controls.parallax.on, 'parallax switch turns on');
                const framing = controls.framing, area = controls.frameArea;
                tryVerify(() => framing.height === framing.fullHeight && framing.opacity === 1, 1000);
                check(waitForPolish(fixtureWindow), 'framing layout settles before measuring the reserved height');
                const zoom = controls.zoom, readout = controls.readout;
                check(zoom && readout && !controls.zoomLabel, 'zoom shows only its percentage');
                const track = bounds(zoom), picture = bounds(area);
                check(Math.abs(picture.x + picture.width / 2 - popup.width / 2) < 0.5, 'wallpaper preview itself is centered');
                check(track.height > track.width && track.x + track.width < picture.x, 'zoom track is vertical to the left of the preview');
                check(track.x >= 6, 'zoom track fits the wallpaper popup');
                const hint = bounds(readout);
                const knob = zoom.mapToItem(popup, zoom.knobX, zoom.height / 2);
                check(hint.x + hint.width < track.x && Math.abs(hint.y + hint.height / 2 - knob.y) < 0.5 && readout.text === '108%', 'zoom percentage sits beside the knob');
                check(readout.font.pixelSize === Theme.footnoteSize && ['r', 'g', 'b', 'a'].every(k => Math.abs(readout.color[k] - Theme.label2[k]) < 1 / 255), 'zoom percentage uses the gray hint style');
                check(hint.x >= 6, 'zoom hint fits the wallpaper popup');
                const originalZoom = Settings.wallpaperParallaxZoom;
                mouseClick(zoom, zoom.width - 1, zoom.height / 2);
                check(readout.text === '130%' && framing.zoom === 1.3, 'top of vertical track previews maximum zoom');
                check(bounds(readout).y < hint.y && bounds(readout).y >= picture.y, 'zoom percentage follows the knob upward and stays inside the preview');
                tryCompare(Settings, 'wallpaperParallaxZoom', 1.3, 1000);
                mouseClick(zoom, 1, zoom.height / 2);
                tryCompare(Settings, 'wallpaperParallaxZoom', 1, 1000);
                check(readout.text === '100%', 'bottom of vertical track selects minimum zoom');
                check(bounds(readout).y > hint.y && bounds(readout).y + readout.height <= picture.y + picture.height, 'zoom percentage follows the knob downward and stays inside the preview');
                Settings.set('wallpaperParallaxZoom', originalZoom);
                const reserved = popup.reserveHeight;
                check(bounds(area).y > bounds(controls.parallax).y + controls.parallax.height, 'framing picture sits under the parallax switch');
                mouseClick(area, area.width / 2, area.height * 0.25);
                check(Math.abs(Wallpaper.parallaxY - 0.25) < 0.02, 'pressing a quarter down the picture frames a quarter down');
                mouseWheel(area, area.width / 2, area.height / 2, 0, -120);
                wait(50);
                check(Math.abs(Wallpaper.parallaxY - 0.25) < 0.02, 'the framing leaves the wheel alone');
                mouseClick(controls.parallax, controls.parallax.width / 2, controls.parallax.height / 2);
                tryVerify(() => framing.height === 0, 1000);
                check(!zoom.visible, 'zoom control hides with the parallax preview');
                check(waitForPolish(fixtureWindow), 'closed framing layout settles');
                check(popup.reserveHeight === reserved, 'closing the framing keeps the window its size');
                mouseClick(controls.parallax, controls.parallax.width / 2, controls.parallax.height / 2);
                tryVerify(() => framing.height === framing.fullHeight, 1000);
                const grid = controls.grid, files = Wallpaper.files.slice();
                check(!grid.interactive, 'a short library does not scroll');
                Wallpaper.files = Array.from({length: 20}, () => files[0]);
                wait(50);
                check(grid.interactive && grid.height === 3 * grid.cellHeight - 4, 'a long library scrolls inside three rows');
                mouseWheel(grid, grid.width / 2, grid.height / 2, 0, -120);
                tryVerify(() => grid.contentY > 0, 1000);
                Wallpaper.files = files;
                wait(50);
                const mono = controls.monochrome, wasColour = Wallpaper.color !== '';
                mouseClick(mono, mono.width / 2, mono.height / 2);
                check((Wallpaper.color !== '') !== wasColour && mono.on !== wasColour, 'the monochrome switch swaps the colour and a picture');
                mouseClick(mono, mono.width / 2, mono.height / 2);
                check((Wallpaper.color !== '') === wasColour && mono.on === wasColour, 'and swaps back');
                const preview = Quickshell.env('QUICKSHELL_WALLPAPER_PREVIEW');
                if (preview) {
                    let saved = false;
                    popup.grabToImage(result => { saved = result.saveToFile(preview); });
                    tryVerify(() => saved, 1000);
                }
                // Exercise layout when there is no image grid to set its width.
                Wallpaper.files = [];
                wait(30);
                check(popup.bodyWidth >= 320 && controls.parallax.width < popup.bodyWidth / 2, 'empty library retains readable section headers');
                popup.screen = { width: 3440, height: 1440 };
                wait(30);
                check(bounds(zoom).x + bounds(zoom).width <= popup.width - 6 && bounds(area).x >= 6, 'ultrawide preview and zoom fit the narrow popup');
                check(Math.abs(bounds(area).x + area.width / 2 - popup.width / 2) < 0.5, 'ultrawide preview stays centered');
                console.log('PASS: wallpaper popup layout, pointer toggles and checkmarks');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\n' + e.stack); } Qt.quit(); } }
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
            if (Wallpaper.color !== '#8090a0' || !Wallpaper.parallax || Math.abs(Wallpaper.parallaxY - 0.2) > 0.001)
                throw new Error('saved colour, parallax and its height did not restore');
            console.log('PASS: wallpaper options survive restart');
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e); } Qt.quit(); } }
}
"""


def run_shell(target, scenario):
    (target / 'shell.qml').write_text(scenario)
    env = shell_env(target)
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    print(output, end='')
    assert result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output, output
    for error in ('ReferenceError:', 'TypeError:', 'Binding loop', 'Failed to load configuration', 'Cannot assign', 'Unable to assign'):
        assert error not in output, output


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-wallpaper-test-#?%-') as folder:
        target = Path(folder)
        copy_shell(target)
        for name in ('services', 'components', 'modules', 'testing', 'wallpapers', 'cache', 'runtime'):
            (target / name).mkdir(mode=0o700, exist_ok=True)
        for name in ('Theme.qml', 'services/Wallpaper.qml', 'services/WallClock.qml', 'components/QueuedProcess.qml', 'components/WallpaperStrip.qml', 'modules/Backdrop.qml', 'components/WallpaperPopup.qml', 'components/PopupHeader.qml', 'components/PopupButton.qml', 'components/PopupText.qml', 'components/Glyph.qml', 'components/BarText.qml', 'components/FittedIcon.qml', 'components/Slider.qml'):
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
    property real reserveHeight: 0
    readonly property bool animateContents: !Theme.reduceMotion
    readonly property real chromeHeight: implicitHeight
    readonly property real radius: Theme.popupRadius
    readonly property Item chromeItem: root
    readonly property real devicePixelRatio: 1
    property var screen: null
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
    property string wallpaperDir: Quickshell.shellPath('wallpapers')
    property real wallpaperParallaxZoom: 1.08
    readonly property string font: 'Sans'
    readonly property string monoFont: 'Monospace'
    property bool reduceMotion: false
    property bool reduceTransparency: false
    function set(key, value) { this[key] = value; }
    function inTerminal(command) { return command; }
}
""")
        (target / 'Paths.qml').write_text("pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function cache(name) { return Quickshell.shellPath('cache/' + name); } }\n")
        # Real decoded images and ImageMagick colour grids, confined to fixtures.
        # Green rises down the picture, so a vertical misplacement shows too.
        for name, gradient in (('a.png', 'red-blue'), ('b.png', 'green-yellow')):
            subprocess.run(['magick', '-size', '200x432', 'gradient:' + gradient, '-rotate', '-90', '(', '-size', '432x200', 'gradient:black-lime', ')', '-compose', 'plus', '-composite', str(target / 'wallpapers' / name)], check=True)
        (target / 'scripts').mkdir(exist_ok=True)
        shutil.copy(ROOT / 'scripts/wallpaper-thumbs', target / 'scripts/wallpaper-thumbs')
        (target / 'wallpapers/.current_wallpaper').write_text(str(target / 'wallpapers/a.png') + '\n\n\n')
        run_shell(target, SCENARIO)
        saved = (target / 'wallpapers/.current_wallpaper').read_text().splitlines()
        assert saved == ['#8090a0', '#8090a0', '', 'parallax', '0.2'], saved
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
        (target / 'other wallpapers').mkdir()
        shutil.copy(target / 'wallpapers/a.png', target / 'other wallpapers/only.png')
        run_shell(target, FOLDER_SWITCH)


if __name__ == '__main__':
    main()
