#!/usr/bin/env python3
"""Check settings text, controls and wrapped options fit and remain selectable."""

import os
from pathlib import Path
import subprocess
import shutil
import tempfile

from test_support import offscreen_ink

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'modules/SettingsMenu.qml').read_text()


def section_rows(title):
    start = source.index('rows: [', source.index(f'title: "{title}",\n                    rows:')) + len('rows: ')
    end = source.index('\n                    ]', start) + len('\n                    ]')
    return source[start:end][1:-1]


rows = '[' + ','.join(section_rows(title) for title in ('Time', 'Date', 'Wallpaper', 'Desktop actions')) + ']'
qml = '''import QtQuick
import Quickshell
import QtTest
import qs
import qs.components
ShellRoot {
    FloatingWindow {
        id: win
        property int failures: 0
        property int phase: 0
        readonly property int settingsWidth: 700 - 168 - Theme.pillBorder - 24 + 2 * Theme.selectionInset
        readonly property var widths: [win.settingsWidth, 360, 1200, win.settingsWidth]
        implicitWidth: 1240; implicitHeight: 900
        TestCase { id: pointer; when: false }
        color: "#202020"
        Column {
            id: page
            x: 12; y: 12; width: win.settingsWidth
            Repeater {
                id: rows
                model: SETTINGS_ROWS
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
                expect(control.x >= row.lead && control.x + control.width <= row.width - 7, "selector stays within row");
                expect(words.x + words.width <= control.x || words.y + words.height <= control.y, "text does not overlap selector");
                expect(words.y >= 0 && words.y + words.height <= row.height, "row contains description height");
                expect(control.y >= 0 && control.y + control.height <= row.height, "row contains selector height");
                if (row.setting.type === "toggle") {
                    const before = row.setting.get();
                    pointer.mouseClick(row, row.width / 2, row.height / 2);
                    expect(row.setting.get() === !before, "toggle can be changed");
                }
                if (row.setting.type === "choice") {
                    const options = control.item.children[0];
                    for (const option of options.children.filter(c => c.modelData !== undefined)) {
                        const p = option.mapToItem(row, 0, 0);
                        expect(p.x >= row.lead && p.x + option.width <= row.width - 7, "option " + option.modelData.label + " stays within row");
                        expect(option.y + option.height <= control.height - 2, "wrapped option fits selector height");
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
            interval: 250; running: true; repeat: true
            onTriggered: {
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
'''.replace('SETTINGS_ROWS', rows)
with tempfile.TemporaryDirectory(prefix='qs-settings-layout-') as folder:
    target = Path(folder)
    files = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '--cached', '--others', '--exclude-standard'], text=True)
    for name in files.splitlines():
        path = ROOT / name
        if not path.is_file():
            continue
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
    (target / 'settings.json').write_text('{}\n')
    offscreen_ink(target)
    (target / 'shell.qml').write_text(qml)
    runtime = target / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / 'state'), XDG_DATA_HOME=str(target / 'data'), XDG_CACHE_HOME=str(target / 'cache'))
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    try:
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired as error:
        print(error.stdout.decode() if error.stdout else '', error.stderr.decode() if error.stderr else '')
        raise SystemExit(1)
    output = result.stdout + result.stderr
    print(output)
    errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign')
    raise SystemExit(0 if result.returncode == 0 and 'PASS: settings layout' in output and not any(error in output for error in errors) else 1)
