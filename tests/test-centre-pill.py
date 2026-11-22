#!/usr/bin/env python3
"""Exercise live module moves, fixed and fused centre modules, pinned-span centring, drawer modes and saved layout."""

import json
from pathlib import Path
from test_support import fixture_root
import re
import runpy
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

RIGHT_TESTS = runpy.run_path(str(Path(__file__).with_name("test-right-pill.py")))


def block(source, marker, start):
    at = source.rindex(start, 0, source.index(marker))
    opening = source.index("{", at)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[at:end]


def run_shell(target, qml):
    (target / "shell.qml").write_text(qml)
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    print(output, end="")
    assert result.returncode == 0 and "PASS:" in output, output
    for error in ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration"):
        assert error not in output, output


QML = r"""
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.src.core
import qs.src.bar
import qs.src.components
import qs.src.modules
import qs.src.services as Services
ShellRoot {
    id: bar
    QtObject { id: countdown; property real reveal: 0; property string shownGlyph: ""; property bool stowed: true; property bool settled: false; property bool iconInCentre: false; property bool dismissed: false; property Item mergedIcon: null; property var iconHandoff: ({progress: 1, targetX: 0}); function expand() {} }
    function check(ok, why) { if (!ok) throw Error(why); }
    function openFromClock(item) {}
    QtObject { id: recording; property bool iconInCentre: true; property bool stowed: true; property var iconHandoff: ({progress: 1, targetX: 0}) }
    QtObject { id: nowPlaying; property bool paused: true; property bool expanded: false; property bool iconInCentre: true; property bool stowed: true; property var iconHandoff: ({progress: 1, targetX: 0}); property var player: null; property real reveal: 0; property string label: ''; property string appName: ''; property string shownApp: '' }
    QtObject { id: music; property bool paused: true; property bool expanded: false; property bool iconInCentre: true; property bool stowed: true; property var iconHandoff: ({progress: 1, targetX: 0}); property real reveal: 0 }
    QtObject { id: notice; property bool stowed: true; property real reveal: 0; property Item mergedIcon: null; property var iconHandoff: ({progress: 1, targetX: 0}) }
    QtObject { id: noticePill; property real dropReveal: 0; property vector4d foldBox: Qt.vector4d(0, 0, 0, 0) }
    readonly property var drops: ({lip: function() { return 0; }})
    QtObject { id: barHover; property bool hovered: true }
    Item { id: wallpaperImage }
    REGISTRY
    SETTINGS_METADATA
    readonly property var drawerRows: DRAWER_ROWS
    Window {
        visible: true; width: 1800; height: 180
        Item {
            id: host
            width: 1800; height: 80
            CENTRAL
            RIGHT
            DISMISSAL
        }
        TestCase {
            id: test
            when: false
            function settle() { wait(Theme.foldMs + 150); }
            function waitVisibility(item, visible) {
                for (let frame = 0; frame < 200 && (item.visible !== visible || (visible && item.reveal < 1)); frame++) wait(10);
                bar.check(item.visible === visible && (!visible || item.reveal === 1), 'drawer fold settles for ' + (item.settingsKey || item.pinKey));
                wait(Theme.foldMs + 50);
            }
            function centralItems() { return clockPill.shown.filter(item => clockPill.order.includes(item.settingsKey)); }
            // The screen's middle goes through the middle of the pinned
            // modules' span, or the pill's own middle when none is pinned.
            function checkCentre(why) {
                const pinned = centralItems().filter(item => DrawerPins.pinned(item.visibilityKey));
                if (pinned.length === 0) {
                    bar.check(Math.abs(clockPill.x + clockPill.width / 2 - host.width / 2) <= 1, why + ': pill is centred with nothing pinned');
                    return;
                }
                const left = Math.min(...pinned.map(item => item.keyBox.mapToItem(host, 0, 0).x));
                const right = Math.max(...pinned.map(item => item.keyBox.mapToItem(host, item.keyBox.width, 0).x));
                bar.check(Math.abs((left + right) / 2 - host.width / 2) <= 1, why + ': pinned span ' + left + '..' + right + ' is not centred');
            }
            function transfer(item, destination, before) {
                const source = item.pill;
                const key = item.settingsKey;
                // Into the right pill's middle: late in a long run of
                // synthetic drags, the offscreen pointer lands about 20 px
                // right of where it was sent, past the screen's last pixel.
                const x = before ? before.x : destination === rightPill ? destination.width / 2 : destination.width - 1;
                const prior = JSON.stringify(Settings.user);
                mousePress(item, item.width / 2, 20);
                mouseMove(destination, x, 20, 20); mouseMove(destination, x, 20, 20);
                bar.check(source.dragging && source.dropMoves, key + ': drag reaches peer');
                bar.check(JSON.stringify(Settings.user) === prior, 'hover does not save placement');
                bar.check(destination.children.some(child => child._at !== undefined && !isNaN(child.target)), 'destination shows insertion line');
                mouseRelease(destination, x, 20); settle();
                bar.check(item.pill === destination && !source.dragging, key + ': same live module arrives');
                bar.check(bar.movableModules.length === 19 && clockPill.modules.length + rightPill.modules.length === 20, 'every module has exactly one instance');
                bar.check(item.pinKey === key, 'pin controls remain available in either pill');
                if (destination === rightPill) bar.check(DrawerPins.pinned(key), key + ': transfer automatically pins');
                else bar.check(!item.stowed && item.visible, key + ': open drawer reveals central modules');
                bar.check(bar.drawerRows.some(row => row.id === 'pin:' + key), 'mode settings remain available in both pills');
                checkCentre('after moving ' + key);
                mouseClick(item, item.width / 2, 20);
                bar.check(OpenPopup.owner === item, key + ': popup still opens');
                OpenPopup.dismiss();
            }
            // Date & Time and Weather can be reordered but never leave.
            function checkFixed(item) {
                const key = item.settingsKey;
                const prior = JSON.stringify(Settings.user);
                const rightOrder = JSON.stringify(RightPillOrder.keys);
                const pins = JSON.stringify(DrawerPins.pins);
                mousePress(item, item.width / 2, 20);
                mouseMove(rightPill, rightPill.width / 2, 20, 20); mouseMove(rightPill, rightPill.width / 2, 20, 20);
                bar.check(!rightPill.children.some(child => child._at !== undefined && !isNaN(child.target) && child.opacity > 0),
                    key + ': the right pill offers no place for it');
                mouseRelease(rightPill, rightPill.width / 2, 20); settle();
                bar.check(item.pill === clockPill && Settings.modulePosition(key) === 'centre', key + ': stays in the centre pill');
                bar.check(JSON.stringify(Settings.user) === prior && JSON.stringify(RightPillOrder.keys) === rightOrder && JSON.stringify(DrawerPins.pins) === pins,
                    key + ': a refused move saves no placement or pin');
                OpenPopup.dismiss();
                Settings.set(key + 'Position', 'right'); settle();
                bar.check(item.pill === clockPill && Settings.centralComponents.includes(key), key + ': a hand-written right position is ignored');
                bar.check(!clockPill.transferableKeys.includes(key) && !rightPill.transferableKeys.includes(key), key + ': not transferable');
            }
            function run() {
                // Fixed and fused modules.
                bar.check(clock.pill === clockPill && weather.pill === clockPill, 'Date & Time and Weather start in the centre pill');
                bar.check(bell.pill === clockPill && timerModule.pill === clockPill && bell.trailingControl && timerModule.trailingControl
                    && bell.settingsKey === '' && timerModule.settingsKey === '', 'the bell and timers are fused to the centre pill');
                bar.check(!Settings.moduleKeys.includes('bell') && !Settings.moduleKeys.includes('countdown'), 'fused modules are not ordered');
                bar.check(recordingNote.pill === clockPill && recordingNote.settingsKey === 'privacy' && !recordingNote.leadingControl,
                    'Privacy is one of the centre pill\'s own modules');
                bar.check(centralItems().map(item => item.settingsKey).join(',') === 'datetime', 'Auto hides quiet central weather and idle privacy by default');
                bar.check(weather.stowed && recordingNote.stowed && drawer.holding, 'quiet central modules are available through the drawer');
                checkCentre('nothing pinned');
                drawer.open = true; settle();
                bar.check(centralItems()[0] === recordingNote, 'Privacy starts left of Date & Time');
                for (const item of [clock, weather, recordingNote, timerModule, bell]) {
                    const key = item.pinKey;
                    mouseClick(item, item.width / 2, 20, Qt.MiddleButton);
                    bar.check(DrawerPins.pinned(key), 'middle click pins central ' + key);
                    bar.check(item.marksPin, 'central pin mark appears while drawer is open');
                    drawer.open = false; settle();
                    bar.check(!item.stowed && item.visible, 'pinned central module stays visible: ' + key);
                    drawer.open = true; settle();
                    mouseClick(item, item.width / 2, 20, Qt.MiddleButton);
                    bar.check(DrawerPins.mode(key) === 'auto', 'middle click unpins central ' + key);
                }
                for (const item of [clock, weather, recordingNote]) checkFixed(item);
                // Privacy moves freely inside the centre pill.
                CentrePillOrder.move('privacy', null, centralItems().map(item => item.settingsKey)); settle();
                bar.check(centralItems()[centralItems().length - 1] === recordingNote, 'Privacy can move to the right of the other central modules');
                CentrePillOrder.move('privacy', 'datetime', centralItems().map(item => item.settingsKey)); settle();
                bar.check(centralItems().indexOf(recordingNote) === centralItems().indexOf(clock) - 1, 'and back just before Date & Time');
                drawer.open = false; settle(); waitVisibility(weather, false); waitVisibility(recordingNote, false);

                // Centring on the pinned span.
                DrawerPins.setMode('datetime', 'pinned'); settle();
                checkCentre('Date & Time pinned alone');
                weather.quiet = false; settle(); waitVisibility(weather, true);
                checkCentre('an Auto module coming out leaves the pinned centre alone');
                DrawerPins.setMode('weather', 'pinned'); settle();
                checkCentre('Date & Time and Weather pinned');
                CentrePillOrder.move('weather', 'datetime', ['datetime', 'weather']); settle();
                checkCentre('Weather before Date & Time');
                CentrePillOrder.move('weather', null, ['weather', 'datetime']); settle();
                checkCentre('Weather after Date & Time');
                DrawerPins.setMode('bell', 'pinned'); DrawerPins.setMode('countdown', 'pinned'); settle();
                checkCentre('the fused notes grow the pill round the pinned span');

                // The fused notes sit after the ordered modules, the last to
                // merge on the outer edge.
                const lastOrdered = Math.max(...centralItems().map(item => item.Layout.column));
                bar.check(bell.Layout.column > lastOrdered && timerModule.Layout.column > lastOrdered, 'fused notes follow the ordered modules');
                bar.check(bell.Layout.column > timerModule.Layout.column, 'the bell starts outermost');
                timerModule.landing = true; wait(10);
                bar.check(timerModule.Layout.column > bell.Layout.column && clockPill.trailingOrder[0] === timerModule, 'the timer landing last takes the outer edge');
                timerModule.landing = false;
                clockPill.putOutside(bell); settle();
                bar.check(bell.Layout.column > timerModule.Layout.column, 'the bell taking its notice back takes the outer edge');
                checkCentre('trading the fused notes keeps the centre');
                // The media notes keep the order they merged in, newest outside.
                clockPill.putOutside(musicNote);
                clockPill.putOutside(nowPlayingNote);
                bar.check(clockPill.leadingOrder[0] === nowPlayingNote && clockPill.leadingOrder[1] === musicNote,
                    'media notes stack newest first');
                bar.check(nowPlayingNote.Layout.column < musicNote.Layout.column
                    && musicNote.Layout.column < recordingNote.Layout.column, 'media notes come before the ordered modules, Privacy included, newest outermost');
                clockPill.putOutside(musicNote);
                bar.check(clockPill.leadingOrder[0] === musicNote && clockPill.leadingOrder[1] === nowPlayingNote,
                    'a note merging again moves out');
                DrawerPins.setMode('bell', 'auto'); DrawerPins.setMode('countdown', 'auto');

                // Other modules move both ways, and none is locked in.
                drawer.open = true; settle();
                transfer(audio, clockPill, clock);
                checkCentre('an Auto module moved between the pinned ones');
                transfer(network, clockPill, null);
                bar.check(centralItems().length === 5, 'central modules gather round Date & Time, Weather and Privacy');
                transfer(audio, rightPill, null);
                transfer(network, rightPill, null);
                bar.check(Settings.centralComponents.slice().sort().join(',') === 'datetime,privacy,weather', 'the last movable module can leave the centre');
                DrawerPins.setMode('email', 'drawer');
                transfer(email, clockPill, null);
                bar.check(email.quiet && !email.stowed && email.pinKey === 'email', 'open drawer reveals pinnable quiet central module');
                const emailMode = bar.drawerRows.find(row => row.id === 'pin:email');
                emailMode.set('auto'); wait(10);
                drawer.open = false; settle(); waitVisibility(email, false);
                bar.check(email.stowed && email.pill === clockPill && Settings.modulePosition('email') === 'centre', 'central Auto hides quiet module without moving it');
                emailMode.set('pinned'); wait(10); settle(); waitVisibility(email, true);
                checkCentre('a pinned module beside Date & Time and Weather widens the span');
                emailMode.set('drawer'); wait(10); settle(); waitVisibility(email, false);
                drawer.open = true; settle(); waitVisibility(email, true);
                transfer(email, rightPill, null);
                // Every other movable module supports both transfer directions.
                for (const item of bar.movableModules.filter(item => !['datetime', 'weather', 'email', 'audio', 'network'].includes(item.settingsKey))) {
                    transfer(item, clockPill, null);
                    transfer(item, rightPill, null);
                }
                transfer(tray, clockPill, null);
                DrawerPins.setMode('tray:fixture', 'drawer'); wait(10);
                drawer.open = false; settle();
                bar.check(!tray.entryTucked && tray.visible, 'Pinned central tray reveals hidden entries');
                DrawerPins.setMode('tray', 'auto'); wait(10); settle(); waitVisibility(tray, false);
                bar.check(tray.entryTucked, 'Auto central tray hides tucked entries');
                drawer.open = true; settle(); waitVisibility(tray, true);
                bar.check(!tray.entryTucked, 'drawer reveals central tray entries');
                DrawerPins.setMode('tray:fixture', 'auto'); wait(10);
                transfer(tray, rightPill, null);

                // Date & Time, Weather, the fused modules and a right module share the drawer modes.
                for (const item of [clock, weather, recordingNote, timerModule, bell, audio]) {
                    const key = item.pinKey;
                    if (DrawerPins.pinned(key)) mouseClick(item, item.width / 2, 20, Qt.MiddleButton);
                    bar.check(!DrawerPins.pinned(key), 'middle click unpins ' + key);
                    const row = bar.drawerRows.find(row => row.id === 'pin:' + key);
                    bar.check(row !== undefined, 'drawer settings include ' + key);
                    row.set('drawer');
                    wait(10);
                    bar.check(row.get() === 'drawer', 'drawer selector changes ' + key);
                    drawer.open = false; settle();
                    waitVisibility(item, false);
                    bar.check(item.stowed && !item.visible, 'Drawer hides ' + key);
                    drawer.open = true; settle();
                    waitVisibility(item, true);
                    bar.check(item.visible && !item.stowed, 'drawer reveals ' + key);
                    mouseClick(item, item.width / 2, 20, Qt.MiddleButton);
                    bar.check(DrawerPins.pinned(key), 'middle click pins ' + key);
                    drawer.open = false; settle();
                    bar.check(item.visible && !item.stowed, 'pinned module remains visible');
                    drawer.open = true;
                }
                checkCentre('Date & Time and Weather pinned again');

                // A cancelled transfer leaves layout and pin mode untouched.
                settle();
                transfer(audio, clockPill, null);
                const prior = JSON.stringify(Settings.user);
                const pins = JSON.stringify(DrawerPins.pins);
                mousePress(audio, audio.width / 2, 20);
                mouseMove(clockPill, 1, 20, 20); mouseMove(clockPill, 1, 20, 20);
                const gap = (clockPill.mapToItem(host, clockPill.width, 0).x + rightPill.mapToItem(host, 0, 0).x) / 2;
                mouseMove(host, gap, 20, 20); mouseRelease(host, gap, 20); wait(30);
                bar.check(JSON.stringify(Settings.user) === prior && JSON.stringify(DrawerPins.pins) === pins, 'release between pills cancels without pinning');
                // A real relocation animates the central pill and respects Reduce Motion.
                Settings.set('audioPosition', 'right'); wait(20);
                bar.check(clockPill.animating && Tooltips.blocked, 'centre position animates and suppresses tooltips');
                settle(); checkCentre('animated layout');
                Theme.reduceMotion = true;
                Settings.set('audioPosition', 'centre'); wait(30);
                checkCentre('reduced motion');
                DrawerPins.setMode('datetime', 'drawer');
                drawer.open = false; settle();
                waitVisibility(clock, false);
                bar.check(!clock.visible && clock.stowed, 'date can remain hidden in drawer');
                checkCentre('hidden Date & Time leaves Weather as the pinned span');
                DrawerPins.setMode('weather', 'auto'); settle();
                checkCentre('nothing pinned centres the pill');
                bar.check(Settings.centralComponents.includes('audio'), 'central layout saved');
                console.log('PASS: fixed and fused centre modules, pinned-span centring, drawer modes and live transfers');
            }
        }
    }
    PLACEMENT_CONNECTION
    Timer { interval: 200; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\n' + e.stack); } Qt.quit(); } }
}
"""


def main():
    source = (ROOT / "src/bar/Bar.qml").read_text()
    registry = source[source.index('    readonly property var movableModules:'):source.index('    // Split inside')]
    qml = QML.replace('REGISTRY', registry)
    qml = qml.replace('CENTRAL', block(source, 'id: clockPill', 'Pill {'))
    qml = qml.replace('RIGHT', block(source, 'id: rightPill', 'Pill {'))
    qml = qml.replace('DISMISSAL', block(source, 'enabled: drawer.open || OpenPopup.owner', 'MouseArea {'))
    qml = qml.replace('PLACEMENT_CONNECTION', block(source, 'function onCentreKeysChanged', 'Connections {'))
    menu = (ROOT / 'src/modules/SettingsMenu.qml').read_text()
    metadata = menu[menu.index('    readonly property var modules:'):menu.index('    // Running now,')]
    metadata = metadata.replace('readonly property var modules:', 'readonly property var settingsModules:').replace('root.modules', 'bar.settingsModules').replace('root.', 'bar.')
    qml = qml.replace('SETTINGS_METADATA', metadata)
    rows = re.search(r'rows: (\[\.\.\.RightPillOrder\.keys[^\n]+)', menu).group(1)
    qml = qml.replace('DRAWER_ROWS', rows.replace('root.modules', 'bar.settingsModules').replace('root.placement', 'bar.placement'))
    with tempfile.TemporaryDirectory(prefix='qs-centre-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'src/services/Privacy.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string summary: ""; property bool active: false }\n')
        (target / 'src/services/Mpd.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool loaded: false; property string label: "" }\n')
        for name, contents in RIGHT_TESTS['STUBS'].items():
            if name not in ('src/core/Settings.qml', 'src/core/DrawerPins.qml'):
                if name == 'src/core/OpenPopup.qml':
                    contents = contents.replace('function dismiss()', 'function deselect() { selected = null; } function dismiss()')
                (target / name).write_text(contents)
        paths = target / 'src/core/Paths.qml'
        paths.write_text(paths.read_text().replace('function state(name)', 'function cache(name) { return Quickshell.shellPath("cache/" + name); } function state(name)'))
        (target / 'state').mkdir(exist_ok=True)
        (target / 'src/core/Settings.qml').write_text((ROOT / 'src/core/Settings.qml').read_text())
        for name in ('WeatherPopup', 'TimerPopup'):
            (target / f'src/components/{name}.qml').write_text('import QtQuick\nItem {}\n')
        (target / 'src/components/Glyph.qml').write_text('import QtQuick\nItem { property real inkBase; implicitWidth: 16; implicitHeight: 20; property string text; property var alternates: []; property int fontSize; property color color; property real nudge: 0 }\n')
        (target / 'src/components/AppIcon.qml').write_text('import QtQuick\nItem { implicitWidth: 16; implicitHeight: 20; property string windowClass; property bool tightWidth: false }\n')
        (target / 'src/components/RollingText.qml').write_text('import QtQuick\nItem { implicitWidth: 48; implicitHeight: 20; property string text; property var smallRanges; property bool tightWidth: false }\n')
        (target / 'src/modules/Clock.qml').write_text('import QtQuick\nimport qs.src.components\nBarItem { id: root; settingsKey: "datetime"; property date date: new Date(); property int middleClicks: 0; actions: ({ [Qt.MiddleButton]: () => root.middleClicks++ }); popup: Component { Item {} } Rectangle { implicitWidth: 90; implicitHeight: 20 } }\n')
        (target / 'src/modules/Timers.qml').write_text('import QtQuick\nimport qs.src.components\nBarItem { settingsKey: "countdown"; property bool drawerOut: false; property bool expanded: false; property bool wantsExpansion: false; property bool collapsed: false; property real handoffProgress: 1; property real handoffOffset: 0; property bool landing: false; property string landingGlyph: ""; readonly property Item icon: null; signal expandRequested(); popup: Component { Item {} } Rectangle { implicitWidth: 16; implicitHeight: 20 } }\n')
        (target / 'src/modules/Drawer.qml').write_text('import QtQuick\nimport qs.src.components\nBarItem { property bool open: false; property bool out: open; property real windup: 0; property bool moving: false; property bool holding: false; property bool pointerNear: false; present: holding; Rectangle { implicitWidth: 8; implicitHeight: 20 } }\n')
        (target / 'src/modules/LauncherButton.qml').write_text('import QtQuick\nimport qs.src.components\nBarItem { Rectangle { implicitWidth: 16; implicitHeight: 20 } }\n')
        names = ['Audio', 'Email', 'Tasks', 'Updater', 'Feeds', 'Downloads', 'NotificationBell', 'Satty', 'IdleInhibit', 'Wallpaper', 'NightMode', 'Sys', 'SettingsButton', 'Drives', 'Bluetooth', 'Network', 'Tray', 'Language']
        for name in names:
            tucked = re.search(r'            readonly property bool tucked: [^\n]+', (ROOT / 'src/modules/Tray.qml').read_text()).group(0)
            extra = 'id: root; property bool drawerOut: false; readonly property bool tucks: DrawerPins.kept("tray:fixture"); readonly property bool entryTucked: entry.tucked; Item { id: entry; property var modelData: ({id: "fixture"}); ' + tucked + ' }' if name == 'Tray' else ''
            if name == 'NotificationBell': extra = 'property bool noticeMerging: false; property bool handingOff: false; property real handoffProgress: 1; property real handoffX: 0;'
            quiet = 'true' if name in ('Email', 'Updater', 'Feeds', 'SettingsButton') else 'false'
            if name == 'Tray': quiet = 'DrawerPins.kept("tray:fixture")'
            (target / f'src/modules/{name}.qml').write_text(f'import QtQuick\nimport qs.src.core\nimport qs.src.bar\nimport qs.src.components\nBarItem {{ {extra} quiet: {quiet}; popup: Component {{ Item {{}} }} Rectangle {{ implicitWidth: 22; implicitHeight: 20 }} }}\n')
        (target / 'src/services/Weather.qml').write_text("pragma Singleton\nimport QtQuick\nQtObject { property string tooltip: 'Weather'; property string icon: 'sun'; property var tints: ({}); property bool outlook: true; property bool stale: false; function refresh(force) {} function formatTemperature(value, unit) { return ''; } function temperatureFigure(value) { return ''; } }\n")
        theme = (target / 'src/core/Theme.qml').read_text().replace('property int glyphSize:', 'property int textSize: 14; property string bodyFont: "sans-serif"; property int bodyWeight: 400; property var figures: ({}); function barInk(item, color) { return color; } property int trayGlyphSize: 16; property real dimOpacity: 0.5; property int glyphSize:')
        glyphs = {key: 'icon' for key in re.findall(r'Theme.glyph\.(\w+)', metadata)}
        glyphs.update(pin='pin', track='music', micMuted='mic', vol=['volume'], wifiStrength=['wifi'])
        theme = re.sub(r'property var glyph: [^\n]+', 'property var glyph: (' + json.dumps(glyphs) + ')', theme)
        (target / 'src/core/Theme.qml').write_text(theme)
        run_shell(target, qml)
        centre_order = json.loads((target / 'state/centre-pill.json').read_text())['order']
        right_order = json.loads((target / 'state/right-pill.json').read_text())['order']
        restart = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.bar
ShellRoot {
property var centre: Settings.centralComponents
property var centreOrder: CentrePillOrder.keys
property var rightOrder: RightPillOrder.keys
property var pins: DrawerPins.pins
Timer { interval: 150; running: true; onTriggered: {
    if (centre.slice().sort().join(',') !== 'audio,datetime,privacy,weather' || !DrawerPins.kept('datetime') || !DrawerPins.pinned('bell') || JSON.stringify(centreOrder) !== 'CENTRE_ORDER' || JSON.stringify(rightOrder) !== 'RIGHT_ORDER') console.log('FAIL: saved layout or drawer mode: ' + centre.join(','));
    else console.log('PASS: module positions, both orders and drawer modes survive restart');
    Qt.quit();
} } }'''
        run_shell(target, restart.replace('CENTRE_ORDER', json.dumps(centre_order, separators=(',', ':'))).replace('RIGHT_ORDER', json.dumps(right_order, separators=(',', ':'))))


if __name__ == '__main__':
    main()
