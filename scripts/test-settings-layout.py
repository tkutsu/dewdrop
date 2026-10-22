#!/usr/bin/env python3
"""Check settings text, controls and options fit and remain selectable."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env

qml = '''import QtQuick
import Quickshell
import QtTest
import qs
import qs.components
import qs.modules
ShellRoot {
    SettingsMenu { id: menu }
    FloatingWindow {
        id: win
        property int failures: 0
        property int phase: 0
        readonly property int settingsWidth: 700 - 168 - Theme.pillBorder - 2 * Theme.panelPadding
        readonly property var widths: [win.settingsWidth, 360, 1200, win.settingsWidth]
        implicitWidth: 1240; implicitHeight: 2600
        TestCase { id: pointer; when: false }
        color: "#202020"
        Column {
            id: page
            x: 12; y: 12; width: win.settingsWidth
            Repeater {
                id: rows
                model: []
                SettingRow { required property var modelData; width: page.width; setting: modelData }
            }
        }
        function check() {
            for (let i = 0; i < rows.count; i++) {
                const row = rows.itemAt(i);
                const words = row.children.find(c => c.toString().startsWith("QQuickColumn"));
                const control = row.children.find(c => c.toString().startsWith("QQuickLoader"));

                function expect(ok, message) {
                    if (!ok) { console.log("FAIL: " + row.setting.id + " " + message); win.failures++; }
                }
                expect(words.width >= Math.min(200, (row.width - row.lead - 24) / 2), "title and description have readable width");
                expect(control.x >= row.lead && control.x + control.width <= row.width - Theme.popupInset, "selector stays within row");
                expect(words.x + words.width <= control.x || words.y + words.height <= control.y, "text does not overlap selector");
                expect(words.y >= 0 && words.y + words.height <= row.height, "row contains description height");
                expect(control.y >= 0 && control.y + control.height <= row.height, "row contains selector height");
                if (row.setting.type === "toggle" && row.enabled) {
                    const before = row.setting.get();
                    // Narrow controls wrap onto more lines; keep the click inside the window.
                    page.y = Math.min(12, win.height - row.y - row.height - 12);
                    pointer.mouseClick(row, row.width / 2, row.height / 2);
                    page.y = 12;
                    expect(row.setting.get() === !before, "toggle can be changed");
                }
                if (row.setting.type === "choice" && row.kind === "dropdown") {
                    const box = control.item;
                    expect(row.setting.options.length > 3 || row.setting.options.some(o => o.label.length > 8), "short choice stays a capsule");
                    const next = (box.currentIndex + 1) % box.count;
                    box.activated(next);
                    expect(row.setting.get() === row.setting.options[next].value, "long choice can be selected from its pop-up button");
                }
                if (row.kind === "choice") {
                    const options = control.item.children.find(c => c.children.some(o => o.modelData !== undefined));
                    for (const option of options.children.filter(c => c.modelData !== undefined)) {
                        const p = option.mapToItem(row, 0, 0);
                        expect(p.x >= row.lead && p.x + option.width <= row.width - Theme.popupInset, "option " + option.modelData.label + " stays within row");
                        expect(option.y + option.height <= control.height, "option fits selector height");
                    }
                    const choices = options.children.filter(c => c.modelData !== undefined);
                    const next = choices[(win.phase + 1) % choices.length];
                    pointer.mouseClick(next, next.width / 2, next.height / 2);
                    expect(row.setting.get() === next.modelData.value, "choice can be selected");
                }
            }
            console.log("Checked settings rows at width " + page.width);
        }
        Timer {
            property bool prepared: false
            interval: 250; running: true; repeat: true
            onTriggered: {
                if (!prepared) {
                    rows.model = menu.pages.reduce((out, p) => out.concat(...p.sections.map(s => s.rows)), []).filter(r => !/^(launcher:|pin:|screen:|mail:|layout:)/.test(r.id));
                    prepared = true;
                    return;
                }
                try { win.check(); } catch (error) {
                    console.log("FAIL: " + error + "\\n" + error.stack); win.failures++;
                }
                win.phase++;
                if (win.phase === win.widths.length) {
                    if (!win.failures) console.log("PASS: settings layout and selection");
                    Qt.quit();
                } else {
                    page.width = win.widths[win.phase];
                }
            }
        }
    }
}
'''
with tempfile.TemporaryDirectory(prefix='qs-settings-layout-') as folder:
    target = Path(folder)
    copy_shell(target)
    (target / 'components/OverlayWindow.qml').write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: false }')
    (target / 'components/BackdropProbe.qml').write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
    (target / 'services/Keyboard.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [] }')
    (target / 'services/Power.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var actions: [] }')
    (target / 'services/Tasks.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: []; property var defaultList: ({id: ""}) }')
    (target / 'shell.qml').write_text(qml)
    env = shell_env(target)
    try:
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired as error:
        print(error.stdout.decode() if error.stdout else '', error.stderr.decode() if error.stderr else '')
        raise SystemExit(1)
    output = result.stdout + result.stderr
    print(output)
    errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign')
    raise SystemExit(0 if result.returncode == 0 and 'PASS: settings layout' in output and not any(error in output for error in errors) else 1)
