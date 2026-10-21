#!/usr/bin/env python3
"""Exercise live module moves, central anchoring, drawer modes and saved layout."""

import json
from pathlib import Path
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
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=45)
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
import qs
import qs.components
import qs.modules
import qs.services as Services
ShellRoot {
    id: bar
    function check(ok, why) { if (!ok) throw Error(why); }
    QtObject { id: recording; property bool iconInCentre: true; property bool stowed: true; property var iconHandoff: ({progress: 1, targetX: 0}) }
    QtObject { id: nowPlaying; property bool paused: true; property bool expanded: false; property bool iconInCentre: true; property var iconHandoff: ({progress: 1, targetX: 0}); property var player: null; property real reveal: 0; property string label: ''; property string appName: ''; property string shownApp: '' }
    QtObject { id: music; property bool paused: true; property bool expanded: false; property bool iconInCentre: true; property var iconHandoff: ({progress: 1, targetX: 0}); property real reveal: 0 }
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
                bar.check(item.visible === visible && (!visible || item.reveal === 1), 'drawer fold settles for ' + item.settingsKey);
                wait(Theme.foldMs + 50);
            }
            function centralItems() { return clockPill.shown.filter(item => clockPill.order.includes(item.settingsKey)); }
            function checkCentre(why) {
                const anchor = Settings.centrePillAnchor;
                const keys = ({ between: ['date', 'time'], middle: [] })[anchor] ?? [anchor];
                const content = centralItems().filter(item => keys.includes(item.settingsKey)).map(item => item.keyBox);
                if (content.length === 0) {
                    bar.check(Math.abs(clockPill.x + clockPill.width / 2 - host.width / 2) <= 1, why + ': pill is centred without time or date');
                    return;
                }
                const x = content.reduce((sum, item) => sum + item.mapToItem(host, item.width / 2, 0).x, 0) / content.length;
                bar.check(Math.abs(x - host.width / 2) <= 1, why + ': time/date content is centred at ' + x);
            }
            function transfer(item, destination, before) {
                const source = item.pill;
                const key = item.settingsKey;
                const x = before ? before.x : destination.width - 1;
                const prior = JSON.stringify(Settings.user);
                mousePress(item, item.width / 2, 20);
                mouseMove(destination, x, 20, 20); mouseMove(destination, x, 20, 20);
                bar.check(source.dragging && source.dropMoves, key + ': drag reaches peer');
                bar.check(JSON.stringify(Settings.user) === prior, 'hover does not save placement');
                bar.check(destination.children.some(child => child._at !== undefined && !isNaN(child.target)), 'destination shows insertion line');
                mouseRelease(destination, x, 20); settle();
                bar.check(item.pill === destination && !source.dragging, key + ': same live module arrives');
                bar.check(bar.movableModules.length === 20 && clockPill.modules.length + rightPill.modules.length === 20, 'every module has exactly one instance');
                bar.check(item.pinKey === (destination === rightPill ? key : ''), 'pin controls follow placement');
                if (destination === rightPill) bar.check(DrawerPins.pinned(key), key + ': transfer automatically pins');
                else bar.check(!item.stowed && item.visible, key + ': open drawer reveals central modules');
                bar.check(bar.drawerRows.some(row => row.id === 'pin:' + key), 'mode settings remain available in both pills');
                checkCentre('after moving ' + key);
                mouseClick(item, item.width / 2, 20);
                bar.check(OpenPopup.owner === item, key + ': popup still opens');
                OpenPopup.dismiss();
            }
            function checkLocked(item) {
                bar.check(centralItems().length === 1 && clockPill.lockedKeys.includes(item.settingsKey), 'last central module is locked');
                const prior = JSON.stringify(Settings.user);
                const centreOrder = JSON.stringify(CentrePillOrder.keys);
                const rightOrder = JSON.stringify(RightPillOrder.keys);
                mousePress(item, item.width / 2, 20);
                mouseMove(rightPill, rightPill.width / 2, 20, 20); mouseMove(rightPill, rightPill.width / 2, 20, 20);
                bar.check(!clockPill.dragging, 'locked module cannot start dragging');
                mouseRelease(rightPill, rightPill.width / 2, 20); wait(30);
                bar.check(JSON.stringify(Settings.user) === prior && JSON.stringify(CentrePillOrder.keys) === centreOrder && JSON.stringify(RightPillOrder.keys) === rightOrder, 'locked drag saves nothing');
                bar.check(OpenPopup.owner === item, 'the press opened the popup and the refused drag left it');
                OpenPopup.dismiss();
                mousePress(item, item.width / 2, 20);
                bar.check(OpenPopup.owner === item, 'popup opens on the press, before the release');
                mouseRelease(item, item.width / 2, 20);
                bar.check(OpenPopup.owner === item, 'locked module still opens popup');
                OpenPopup.dismiss();
                checkCentre('locked ' + item.settingsKey);
            }
            function run() {
                bar.check(centralItems().map(item => item.settingsKey).join(',') === 'date,time', 'Auto hides quiet central weather by default');
                bar.check(weather.stowed && drawer.holding, 'quiet central module is available through the drawer');
                DrawerPins.setMode('date', 'pinned');
                DrawerPins.setMode('time', 'pinned');
                CentrePillOrder.move('weather', null, ['date', 'weather', 'time']);
                settle(); checkCentre('quiet Auto beside two pinned modules');
                weather.quiet = false; settle(); waitVisibility(weather, true);
                checkCentre('weather does not change the time/date anchors');
                CentrePillOrder.move('date', null, ['date', 'time', 'weather']);
                settle(); checkCentre('reversed time/date with weather between them');
                CentrePillOrder.move('date', 'time', ['time', 'weather', 'date']);
                DrawerPins.setMode('date', 'drawer'); settle(); waitVisibility(clock, false);
                checkCentre('time alone beside weather');
                DrawerPins.setMode('date', 'pinned');
                DrawerPins.setMode('time', 'drawer'); settle(); waitVisibility(timeClock, false);
                checkCentre('date alone beside weather');
                Settings.set('centrePillAnchor', 'time'); settle();
                checkCentre('Centre On time without time falls back to the middle');
                Settings.set('centrePillAnchor', 'between'); settle();
                DrawerPins.setMode('date', 'drawer'); settle(); waitVisibility(clock, false);
                checkCentre('weather alone uses screen centre');
                DrawerPins.setMode('date', 'pinned');
                DrawerPins.setMode('time', 'pinned'); settle();
                DrawerPins.setMode('time', 'auto'); settle();
                checkCentre('Auto time still anchors with date');
                for (const anchor of ['time', 'date', 'middle', 'between']) {
                    Settings.set('centrePillAnchor', anchor); settle();
                    checkCentre('Centre On ' + anchor);
                }
                weather.quiet = true; settle(); waitVisibility(weather, false);
                checkCentre('weather folding away keeps the time/date anchors');
                DrawerPins.setMode('weather', 'drawer');
                drawer.open = true; settle(); waitVisibility(weather, true);
                checkCentre('drawer reveal does not change the time/date anchors');
                mousePress(weather, weather.width / 2, 20);
                mouseMove(clockPill, 1, 20, 20); mouseMove(clockPill, 1, 20, 20);
                settle();
                bar.check(drawer.open && weather.visible && clockPill.dragging && clockPill.dragSource === weather,
                    'revealed central module stays visible and draggable after press');
                mouseRelease(clockPill, 1, 20); settle();
                bar.check(clockPill.clockItems[0] === weather && !clockPill.dragging,
                    'revealed central module can be reordered');
                transfer(weather, rightPill, null);
                transfer(weather, clockPill, null);
                DrawerPins.setMode('weather', 'drawer');
                mouseClick(host, 1, 20); settle();
                bar.check(!drawer.open && !weather.visible, 'click outside the ordered pills still closes the drawer');
                CentrePillOrder.move('weather', null, ['date', 'weather', 'time']);
                drawer.open = false; settle(); waitVisibility(weather, false);
                DrawerPins.setMode('weather', 'auto');
                DrawerPins.setMode('date', 'auto');
                CentrePillOrder.move('weather', 'time', ['date', 'time', 'weather']);
                settle();
                const middleClicks = clock.middleClicks;
                mouseClick(clock, clock.width / 2, 20, Qt.MiddleButton);
                bar.check(clock.middleClicks === middleClicks + 1 && !DrawerPins.pinned('date'), 'central date keeps its own middle-click action');
                checkCentre('default with music notes');
                drawer.open = true; settle();
                transfer(audio, clockPill, clock);
                transfer(network, clockPill, null);
                bar.check(centralItems().length === 5, 'five central modules retain time/date centring');
                for (const item of [clock, weather, timeClock]) transfer(item, rightPill, null);
                transfer(audio, rightPill, null);
                checkLocked(network);
                Settings.set('networkPosition', 'right');
                bar.check(Settings.modulePosition('network') === 'centre', 'last non-clock module is guarded in settings');
                DrawerPins.setMode('email', 'drawer');
                transfer(email, clockPill, null);
                bar.check(email.quiet && !email.stowed && email.pinKey === '', 'open drawer reveals quiet central module');
                const emailMode = bar.drawerRows.find(row => row.id === 'pin:email');
                emailMode.set('auto'); wait(10);
                drawer.open = false; settle(); waitVisibility(email, false);
                bar.check(email.stowed && email.pill === clockPill && Settings.modulePosition('email') === 'centre', 'central Auto hides quiet module without moving it');
                email.quiet = false; settle(); waitVisibility(email, true);
                bar.check(!email.stowed, 'central Auto shows an active module');
                email.quiet = true; settle(); waitVisibility(email, false);
                emailMode.set('pinned'); wait(10); settle(); waitVisibility(email, true);
                bar.check(!email.stowed, 'central Pinned shows a quiet module');
                emailMode.set('drawer'); wait(10); settle(); waitVisibility(email, false);
                email.quiet = false; wait(10);
                bar.check(email.stowed, 'central Drawer keeps active module hidden');
                email.quiet = true;
                drawer.open = true; settle(); waitVisibility(email, true);
                bar.check(email.pill === clockPill, 'opening drawer reveals module in its central slot');
                transfer(network, rightPill, null);
                checkLocked(email);
                // Every original right module supports both transfer directions.
                for (const item of bar.movableModules.filter(item => !['date', 'weather', 'time', 'email'].includes(item.settingsKey))) {
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
                drawer.open = false; settle(); waitVisibility(email, false);
                bar.check(drawer.holding && drawer.visible && email.pill === clockPill, 'chevron remains available for the hidden last central module');
                drawer.open = true; settle(); waitVisibility(email, true);
                checkLocked(email);
                // Date, time and weather have the same right-pill modes as other modules.
                for (const item of [clock, weather, timeClock, audio]) {
                    mouseClick(item, item.width / 2, 20, Qt.MiddleButton);
                    bar.check(!DrawerPins.pinned(item.settingsKey), 'middle click unpins ' + item.settingsKey);
                    const row = bar.drawerRows.find(row => row.id === 'pin:' + item.settingsKey);
                    bar.check(row !== undefined, 'drawer settings include ' + item.settingsKey);
                    row.set('drawer');
                    wait(10);
                    bar.check(row.get() === 'drawer', 'drawer selector changes ' + item.settingsKey + ': id=' + row.id + ', get=' + row.get() + ', actual=' + DrawerPins.mode(item.settingsKey) + ', pins=' + JSON.stringify(DrawerPins.pins));
                    drawer.open = false; settle();
                    waitVisibility(item, false);
                    bar.check(item.stowed && !item.visible, 'Drawer hides ' + item.settingsKey + ': stowed=' + item.stowed + ', visible=' + item.visible + ', pin=' + DrawerPins.mode(item.settingsKey) + ', out=' + drawer.out + ', popup=' + item.popupOpen + ', reveal=' + item.reveal);
                    drawer.open = true; settle();
                    waitVisibility(item, true);
                    bar.check(item.visible && !item.stowed, 'drawer reveals ' + item.settingsKey);
                    mouseClick(item, item.width / 2, 20, Qt.MiddleButton);
                    bar.check(DrawerPins.pinned(item.settingsKey), 'middle click pins ' + item.settingsKey);
                    drawer.open = false; settle();
                    bar.check(item.visible && !item.stowed, 'pinned module remains visible');
                    drawer.open = true;
                }
                // A configured central module can become unavailable without emptying the bar.
                Settings.set('trayPosition', 'centre');
                for (const item of bar.movableModules.filter(item => item !== tray)) Settings.set(item.settingsKey + 'Position', 'right');
                settle(); checkLocked(tray);
                tray.present = false; settle();
                bar.check(timeClock.pill === clockPill && timeClock.visible, 'time fills in for an unavailable last module');
                checkLocked(timeClock);
                tray.present = true; settle();
                bar.check(tray.pill === clockPill && timeClock.pill === rightPill, 'returning module restores configured layout');
                Settings.set('audioPosition', 'centre');
                Settings.set('trayPosition', 'right'); settle();
                checkLocked(audio);
                // A cancelled transfer leaves layout and pin mode untouched.
                const prior = JSON.stringify(Settings.user);
                const pins = JSON.stringify(DrawerPins.pins);
                mousePress(weather, weather.width / 2, 20);
                mouseMove(clockPill, 1, 20, 20); mouseMove(clockPill, 1, 20, 20);
                const gap = (clockPill.mapToItem(host, clockPill.width, 0).x + rightPill.mapToItem(host, 0, 0).x) / 2;
                mouseMove(host, gap, 20, 20); mouseRelease(host, gap, 20); wait(30);
                bar.check(JSON.stringify(Settings.user) === prior && JSON.stringify(DrawerPins.pins) === pins, 'release between pills cancels without pinning');
                // A real relocation animates the central pill and respects Reduce Motion.
                Settings.set('weatherPosition', 'centre'); wait(20);
                bar.check(clockPill.animating && Tooltips.blocked, 'centre position animates and suppresses tooltips');
                settle(); checkCentre('animated layout');
                Theme.reduceMotion = true;
                Settings.set('weatherPosition', 'right'); wait(30);
                checkCentre('reduced motion');
                DrawerPins.setMode('date', 'drawer');
                drawer.open = false; settle();
                waitVisibility(clock, false);
                bar.check(!clock.visible && clock.stowed, 'date can remain hidden in drawer');
                bar.check(Settings.centralComponents.join(',') === 'audio', 'non-clock central layout saved');
                console.log('PASS: shared Auto/Pinned/Drawer modes, central drawer access, live transfers, locks and centring');
            }
        }
    }
    PLACEMENT_CONNECTION
    Timer { interval: 200; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e + '\n' + e.stack); } Qt.quit(); } }
}
"""


def main():
    source = (ROOT / "Bar.qml").read_text()
    registry = source[source.index('    readonly property var movableModules:'):source.index('    // Split inside')]
    qml = QML.replace('REGISTRY', registry)
    qml = qml.replace('CENTRAL', block(source, 'id: clockPill', 'Pill {'))
    qml = qml.replace('RIGHT', block(source, 'id: rightPill', 'Pill {'))
    qml = qml.replace('DISMISSAL', block(source, 'enabled: drawer.open || OpenPopup.owner', 'MouseArea {'))
    qml = qml.replace('PLACEMENT_CONNECTION', block(source, 'function onCentreKeysChanged', 'Connections {'))
    menu = (ROOT / 'modules/SettingsMenu.qml').read_text()
    metadata = menu[menu.index('    readonly property var modules:'):menu.index('    // Running now,')]
    metadata = metadata.replace('readonly property var modules:', 'readonly property var settingsModules:').replace('root.modules', 'bar.settingsModules').replace('root.pinOptions', 'bar.pinOptions')
    qml = qml.replace('SETTINGS_METADATA', metadata)
    rows = re.search(r'rows: (RightPillOrder.keys.filter[^\n]+)', menu).group(1)
    qml = qml.replace('DRAWER_ROWS', rows.replace('root.modules', 'bar.settingsModules').replace('root.placement', 'bar.placement'))
    with tempfile.TemporaryDirectory(prefix='qs-centre-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'services/Privacy.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property string summary: ""; property bool active: false }\n')
        (target / 'services/Mpd.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool loaded: false; property string label: "" }\n')
        for name, contents in RIGHT_TESTS['STUBS'].items():
            if name not in ('Settings.qml', 'DrawerPins.qml'):
                if name == 'OpenPopup.qml':
                    contents = contents.replace('function dismiss()', 'function deselect() { selected = null; } function dismiss()')
                (target / name).write_text(contents)
        (target / 'state').mkdir(exist_ok=True)
        (target / 'Settings.qml').write_text((ROOT / 'Settings.qml').read_text())
        for name in ('WeatherPopup', 'TimerPopup'):
            (target / f'components/{name}.qml').write_text('import QtQuick\nItem {}\n')
        (target / 'components/Glyph.qml').write_text('import QtQuick\nItem { implicitWidth: 16; implicitHeight: 20; property string text; property int fontSize; property color color; property real nudge: 0 }\n')
        (target / 'components/AppIcon.qml').write_text('import QtQuick\nItem { implicitWidth: 16; implicitHeight: 20; property string windowClass; property bool tightWidth: false }\n')
        (target / 'components/RollingText.qml').write_text('import QtQuick\nItem { implicitWidth: 48; implicitHeight: 20; property string text; property var smallRanges; property bool tightWidth: false }\n')
        (target / 'modules/Clock.qml').write_text('import QtQuick\nimport qs.components\nBarItem { id: root; property date date: new Date(); property int middleClicks: 0; actions: ({ [Qt.MiddleButton]: () => root.middleClicks++ }); popup: Component { Item {} } Rectangle { implicitWidth: 90; implicitHeight: 20 } }\n')
        (target / 'modules/Drawer.qml').write_text('import QtQuick\nimport qs.components\nBarItem { property bool open: false; property bool out: open; property real windup: 0; property bool moving: false; property bool holding: false; property bool pointerNear: false; present: holding; Rectangle { implicitWidth: 8; implicitHeight: 20 } }\n')
        (target / 'modules/LauncherButton.qml').write_text('import QtQuick\nimport qs.components\nBarItem { Rectangle { implicitWidth: 16; implicitHeight: 20 } }\n')
        names = ['Audio', 'Email', 'Tasks', 'Updater', 'Feeds', 'NotificationBell', 'Satty', 'IdleInhibit', 'Wallpaper', 'NightMode', 'Sys', 'SettingsButton', 'Drives', 'Bluetooth', 'Network', 'Tray', 'Language']
        for name in names:
            tucked = re.search(r'            readonly property bool tucked: [^\n]+', (ROOT / 'modules/Tray.qml').read_text()).group(0)
            extra = 'id: root; property bool drawerOut: false; readonly property bool tucks: DrawerPins.kept("tray:fixture"); readonly property bool entryTucked: entry.tucked; Item { id: entry; property var modelData: ({id: "fixture"}); ' + tucked + ' }' if name == 'Tray' else ''
            if name == 'NotificationBell': extra = 'property bool noticeMerging: false; property bool handingOff: false; property real handoffProgress: 1; property real handoffX: 0;'
            quiet = 'true' if name in ('Email', 'Updater', 'Feeds', 'SettingsButton') else 'false'
            if name == 'Tray': quiet = 'DrawerPins.kept("tray:fixture")'
            (target / f'modules/{name}.qml').write_text(f'import QtQuick\nimport qs\nimport qs.components\nBarItem {{ {extra} quiet: {quiet}; popup: Component {{ Item {{}} }} Rectangle {{ implicitWidth: 22; implicitHeight: 20 }} }}\n')
        (target / 'services/Weather.qml').write_text("pragma Singleton\nimport QtQuick\nQtObject { property string tooltip: 'Weather'; property string icon: 'sun'; property bool outlook: true; property bool stale: false; function refresh(force) {} }\n")
        theme = (target / 'Theme.qml').read_text().replace('property int glyphSize:', 'property int trayGlyphSize: 16; property real dimOpacity: 0.5; property int glyphSize:')
        glyphs = {key: 'icon' for key in re.findall(r'Theme.glyph\.(\w+)', metadata)}
        glyphs.update(pin='pin', track='music', micMuted='mic', vol=['volume'], wifiStrength=['wifi'])
        theme = re.sub(r'property var glyph: [^\n]+', 'property var glyph: (' + json.dumps(glyphs) + ')', theme)
        (target / 'Theme.qml').write_text(theme)
        run_shell(target, qml)
        centre_order = json.loads((target / 'state/centre-pill.json').read_text())['order']
        right_order = json.loads((target / 'state/right-pill.json').read_text())['order']
        restart = '''import QtQuick
import Quickshell
import qs
ShellRoot {
property var centre: Settings.centralComponents
property var centreOrder: CentrePillOrder.keys
property var rightOrder: RightPillOrder.keys
property var pins: DrawerPins.pins
Timer { interval: 150; running: true; onTriggered: {
    if (centre.join(',') !== 'audio' || !Settings.positionLocked('audio') || !DrawerPins.kept('date') || !DrawerPins.pinned('network') || JSON.stringify(centreOrder) !== 'CENTRE_ORDER' || JSON.stringify(rightOrder) !== 'RIGHT_ORDER') console.log('FAIL: saved layout or drawer mode');
    else console.log('PASS: module positions, both orders, central lock and drawer modes survive restart');
    Qt.quit();
} } }'''
        run_shell(target, restart.replace('CENTRE_ORDER', json.dumps(centre_order, separators=(',', ':'))).replace('RIGHT_ORDER', json.dumps(right_order, separators=(',', ':'))))


if __name__ == '__main__':
    main()
