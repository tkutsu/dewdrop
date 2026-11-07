#!/usr/bin/env python3
"""Run the services with optional programs missing: nothing sticks, and nothing is promised."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

SHELL = '''
import QtQuick
import Quickshell
import qs
import qs.services

ShellRoot {
    readonly property var programsFound: Tools.found
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (Tools.found === null)
                return;
            running = false;
            console.log("RESULT:" + JSON.stringify({
                fades: ["--poweroff", "--reboot", "--logout", "--suspend", "--lock"].filter(arg => Power.fades(arg)),
                terminal: Tools.hasTerminal,
                calc: Launcher.calcResults("1+1", false).map(row => row.kind),
                calcAsked: Launcher.calcResults("1+1", true).length,
                files: LauncherFiles.results("x").map(row => row.kind),
            }));
            MpdEqualizer.load();
            console.log("EQ:" + JSON.stringify({ busy: MpdEqualizer.busy, error: MpdEqualizer.error }));
            Qt.quit();
        }
    }
}
'''


def run(target, programs):
    """The fixture with only sh and these programs on PATH."""
    copy_shell(target)
    (target / 'shell.qml').write_text(SHELL)
    tools = target / 'tools'
    tools.mkdir()
    (tools / 'sh').symlink_to(shutil.which('sh'))
    for name in programs:
        (tools / name).write_text('#!/bin/sh\nexit 0\n')
        (tools / name).chmod(0o700)
    done = subprocess.run([shutil.which('qs'), '-p', str(target), '--no-color'], capture_output=True, text=True, timeout=20,
                          env=shell_env(target, PATH=str(tools)))
    output = done.stdout + done.stderr
    errors = [line for line in output.splitlines() if re.search(r'ReferenceError|TypeError', line)]
    assert not errors, errors
    found = {key: json.loads(re.search(key + r':(\{.*\})', output).group(1)) for key in ('RESULT', 'EQ')}
    return found['RESULT'], found['EQ']


def check_list_is_complete():
    """A program asked about but not probed for would always count as missing."""
    listed = re.search(r'programs: \[(.*?)\]', (ROOT / 'Tools.qml').read_text(), re.S).group(1)
    for path in ROOT.rglob('*.qml'):
        if path.relative_to(ROOT).parts[0] not in ('.claude', 'lab'):
            for name in re.findall(r'Tools\.has\("([^"]+)"\)', path.read_text()):
                assert f'"{name}"' in listed, f'{path.name} asks for {name}, which Tools.qml does not probe'
    used = re.findall(r'"([\w-]+)"', listed)
    text = ''.join(path.read_text() for path in ROOT.rglob('*.qml') if path.relative_to(ROOT).parts[0] not in ('.claude', 'lab', 'Tools.qml'))
    for name in used:
        assert f'"{name}"' in text.replace(listed, ''), f'nothing uses {name}'
    print('PASS: Tools probes every program the shell asks about')
    assert 'Tools.found' in (ROOT / 'shell.qml').read_text(), 'a singleton waits to be asked, so shell.qml has to ask'
    print('PASS: the shell looks for the programs at startup')


def main():
    check_list_is_complete()
    with tempfile.TemporaryDirectory(prefix='qs-missing-tools-') as folder:
        base = Path(folder)

        result, eq = run(base / 'none', [])
        assert result['fades'] == [], result
        print('PASS: with nothing installed no power action goes black')
        assert not result['terminal'], result
        print('PASS: a missing terminal is known')
        assert result['calc'] == ['note'] and result['calcAsked'] == 0, result
        print('PASS: the calculator says what it needs, but only when asked for')
        assert result['files'] == ['note'], result
        print('PASS: file search says what it needs')
        assert not eq['busy'] and 'Python' in eq['error'], eq
        print('PASS: the equalizer says what it needs instead of waiting for ever')

        result, _ = run(base / 'jq', ['jq'])
        assert result['fades'] == ['--poweroff', '--reboot', '--logout'], result
        print('PASS: jq brings back the animation for leaving, not for sleep')

        result, _ = run(base / 'wake', ['setpriv', 'stdbuf', 'gdbus'])
        assert result['fades'] == ['--suspend'], result
        print('PASS: the wake signal brings back the animation for sleep')

        result, _ = run(base / 'all', ['jq', 'setpriv', 'stdbuf', 'gdbus', 'kitty', 'qalc', 'fd'])
        assert len(result['fades']) == 4 and result['terminal'], result
        assert result['calc'] == [] and result['files'] != ['note'], result
        print('PASS: with everything installed nothing changes')


if __name__ == '__main__':
    main()
