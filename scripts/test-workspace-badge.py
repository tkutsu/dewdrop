#!/usr/bin/env python3
"""Render the workspace's actual count badge across the selection glass."""

from pathlib import Path
import re
import subprocess
import tempfile

from PIL import Image, ImageChops

from test_support import ROOT, copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    id: suite
    property int phase: 0
    FloatingWindow {
        implicitWidth: 70; implicitHeight: 40
        Item {
            id: scene; width: 70; height: 40
            Rectangle { id: ground; anchors.fill: parent; color: "#006080" }
            ShaderEffectSource {
                id: wallpaper; property real glassWeight: 1
                sourceItem: ground; visible: false
            }
            Item {
                id: leftPill; anchors.fill: parent
                property color surface: "#146285"
                Rectangle { id: slab; x: 8; y: 5; width: 54; height: 28; radius: 14; color: leftPill.surface }
                Item {
                    id: root; anchors.fill: parent
                    property Item badgeLayer: BADGE_LAYER
                    property real shift: 0
                    Item {
                        id: strip; anchors.fill: parent
                        Item {
                            id: button; anchors.fill: parent
                            property real drawnX: suite.phase >= 2 ? 4 : 0
                            transform: Translate { id: workspaceShift; x: button.drawnX }
                            Item {
                                id: app; x: 14; width: 20; height: 38
                                property var icon: ({addresses: ['a', 'b']})
                                BADGE
                            }
                        }
                    }
                }
            }
            Item {
                id: mark
                property point windowPos: Qt.point(0, 0)
                property real frontLeft: 8; property real frontRight: 46
                property real slabTop: 7; property real thickness: 25
                property bool held: false
                property real headLeft: 8; property real headRight: 46
                property real wantLeft: 8; property real wantRight: 46
            }
            GlassMark {
                id: glassMark; anchors.fill: parent
                visible: suite.phase === 0
                mark: mark; slabItem: slab; inkItem: root; wallpaperItem: wallpaper
            }
            BADGE_OVERLAY
        }
    }
    Timer {
        interval: 900; running: true; repeat: true
        onTriggered: scene.grabToImage(result => {
            result.saveToFile(Quickshell.shellPath('frame-' + suite.phase + '.png'));
            if (suite.phase++ === 2) Qt.quit();
        })
    }
}
'''


def main():
    source = (ROOT / 'modules/Workspaces.qml').read_text()
    badge = 'Badge {' + source.split('                                Badge {', 1)[1].split(
        '\n                                Component.onDestruction', 1)[0]
    bar = (ROOT / 'Bar.qml').read_text()
    layer = re.search(r'^            badgeLayer: (.+)$', bar, re.M)
    overlay = re.search(r'    Item \{\n        id: workspaceBadges\n.*?^    \}', bar, re.M | re.S)
    qml = QML.replace('BADGE_LAYER', layer[1] if layer else 'null')
    qml = qml.replace('BADGE_OVERLAY', overlay[0] if overlay else '').replace('BADGE', badge)
    with tempfile.TemporaryDirectory(prefix='qs-workspace-badge-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'settings.json').write_text('{"groupWindowBadges": true}\n')
        (target / 'shell.qml').write_text(qml)
        result = subprocess.run(
            ['qs', '-p', str(target), '--no-color'], capture_output=True, text=True, timeout=15,
            env=shell_env(target, QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl',
                          QT_OPENGL='software', LIBGL_ALWAYS_SOFTWARE='1'))
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert not any(error in output for error in (
            'ReferenceError:', 'TypeError:', 'Unable to assign', 'non-bindable properties')), output
        frames = [Image.open(target / f'frame-{i}.png').convert('RGB') for i in range(3)]
        badge_box = (27, 2, 40, 15)
        assert ImageChops.difference(frames[0], frames[1]).crop((31, 5, 37, 11)).getbbox() is None, \
            'workspace glass smears the badge'
        assert frames[1].crop(badge_box).tobytes() == frames[2].crop((31, 2, 44, 15)).tobytes(), \
            'badge does not follow the workspace translation'
        assert frames[1].crop((31, 4, 37, 12)).getextrema()[0][1] > 180, 'badge digit is missing'
        print('PASS: count stays crisp above workspace glass and follows workspace translation')


if __name__ == '__main__':
    main()
