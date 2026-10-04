#!/usr/bin/env python3
"""Exercise tooltip lifetime while real pill folds overlap and reverse."""

from pathlib import Path
import runpy
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
support = runpy.run_path(str(ROOT / 'scripts/test-right-pill.py'))

SCENARIO = r"""
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    Window {
        visible: true; width: 700; height: 200
        Item {
            width: 600; height: 100
            Pill {
                id: first
                drawsSlab: false
                BarItem { id: folding; Rectangle { implicitWidth: 100; implicitHeight: 20 } }
            }
            Pill {
                id: second
                drawsSlab: false
                side: Pill.Side.Right
                BarItem { id: other; Rectangle { implicitWidth: 80; implicitHeight: 20 } }
            }
            HoverPopup { id: tag; anchorItem: folding; text: 'Test tooltip' }
            HoverPopup { id: clicked; anchorItem: folding; popup: Component { Item { property Item anchorItem; property var anchor: ({rect: null}); property int shadowTop: 0; property bool requestedVisible } } open: true }
        }
        TestCase {
            id: test
            when: false
            function check(ok, message) { if (!ok) throw new Error(message); }
            function run() {
                folding._started = true;
                other._started = true;
                tag.hovered = true;
                wait(1050);
                check(tag.tipping && tag.item !== null, 'stationary hover shows a tooltip');
                folding.stowed = true;
                wait(20);
                check(!tag.tipping && tag.item === null, 'fold immediately removes tooltip surface');
                check(Tooltips.blocked, 'spring blocks tooltips through settling');
                check(clicked.item !== null, 'motion preserves a clicked popup');
                other.stowed = true;
                folding.stowed = false;
                wait(20);
                check(Tooltips.blocked && !tag.tipping, 'overlapping and reversed folds stay blocked');
                tryVerify(() => !Tooltips.blocked, 4000);
                check(!tag.tipping, 'motion ending requires a fresh hover delay');
                wait(1050);
                check(tag.tipping, 'stationary hover resumes after settling');
                other.stowed = false;
                wait(20);
                tag.hovered = false;
                tryVerify(() => !Tooltips.blocked, 4000);
                wait(1050);
                check(!tag.tipping && Tooltips.showing === 0, 'leaving during motion never revives the tooltip');
                folding.folds = false;
                folding.stowed = true;
                wait(20);
                check(Tooltips.blocked, 'eased centre-pill departure also blocks');
                tryVerify(() => !Tooltips.blocked, 1000);
                const transient = Qt.createQmlObject('import qs.components; Pill { drawsSlab: false }', first.parent);
                transient.dragging = true;
                check(Tooltips.blocked, 'pill drag blocks globally');
                transient.destroy();
                wait(20);
                check(!Tooltips.blocked, 'destroyed moving pill releases suppression');
                console.log('PASS: tooltip suppression, overlap, reversal, delay, popups and cleanup');
            }
        }
        Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log('FAIL: ' + e); } Qt.quit(); } }
    }
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-tooltips-test-') as folder:
        target = Path(folder)
        (target / 'components').mkdir()
        (target / 'runtime').mkdir(mode=0o700)
        for name, source in support['STUBS'].items():
            (target / name).write_text(source)
        for name in ('Tooltips.qml', 'Linger.qml', 'components/Pill.qml', 'components/BarItem.qml',
                     'components/ClickArea.qml', 'components/DropLine.qml', 'components/HoverPopup.qml'):
            shutil.copyfile(ROOT / name, target / name)
        (target / 'components/Tooltip.qml').write_text("import QtQuick\nItem { property string text; property Item anchorItem; property var anchor: ({rect: null}); property int shadowTop: 0; property bool requestedVisible }")
        support['run_shell'](target, SCENARIO)


if __name__ == '__main__':
    main()
