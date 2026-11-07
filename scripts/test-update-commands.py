#!/usr/bin/env python3
"""Check the upgrade fallback and the updates module on machines with different tools."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import copy_shell, shell_env

SHELL = '''
import QtQuick
import Quickshell
import qs
import qs.services

ShellRoot {
    Component.onCompleted: Updates.refresh()
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            console.log("RESULT:" + JSON.stringify({ command: Settings.updateCommand, present: Updates.present,
                trouble: Updates.trouble, official: Updates.official }));
            Qt.quit();
        }
    }
}
'''
LOGGED = '#!/bin/sh\nprintf "%s\\n" "$(basename "$0") $*" >> "$TOOL_LOG"\n'
# What the bare fixtures still need from the system.
BASE = ('timeout', 'sh', 'basename', 'printf')


def toolbox(folder, tools):
    """A PATH holding only the base tools and logging stubs of those named."""
    folder.mkdir()
    for name in BASE:
        source = shutil.which(name)
        if source:
            (folder / name).symlink_to(source)
    for name, body in tools.items():
        (folder / name).write_text(body or LOGGED)
        (folder / name).chmod(0o700)
    return folder


def shell_result(target, tools, settings):
    copy_shell(target)
    (target / 'shell.qml').write_text(SHELL)
    (target / 'settings.json').write_text(json.dumps(settings))
    bin_dir = toolbox(target / 'tools', tools)
    done = subprocess.run([shutil.which('qs'), '-p', str(target), '--no-color'], capture_output=True, text=True, timeout=20,
                          env=shell_env(target, PATH=str(bin_dir)))
    output = done.stdout + done.stderr
    lines = [line.split('RESULT:', 1)[1] for line in output.splitlines() if 'RESULT:' in line]
    assert lines, output
    return json.loads(lines[-1])


def run_command(folder, tools, command):
    """Run an upgrade command with these tools and say what it called."""
    bin_dir = toolbox(folder, tools)
    log = folder / 'log'
    subprocess.run([str(bin_dir / 'sh'), '-c', command], env=dict(PATH=str(bin_dir), TOOL_LOG=str(log)), check=True)
    return log.read_text().splitlines()


def main():
    update = '#!/bin/sh\necho "linux 1 -> 2"\n'
    with tempfile.TemporaryDirectory(prefix='qs-update-commands-') as folder:
        base = Path(folder)

        result = shell_result(base / 'pacman', {'checkupdates': update}, {})
        assert result['present'] and result['trouble'] == '' and result['official'] == 1, result
        print('PASS: plain pacman counts updates with no AUR warning')
        fallback = result['command']

        assert run_command(base / 'with-yay', {'yay': '', 'sudo': ''}, fallback) == ['yay ']
        print('PASS: an empty updateCommand uses yay when it is installed')
        assert run_command(base / 'without-yay', {'sudo': ''}, fallback) == ['sudo pacman -Syu']
        print('PASS: an empty updateCommand falls back to pacman')

        result = shell_result(base / 'other-distro', {}, {})
        assert not result['present'] and result['trouble'] == '', result
        print('PASS: without checkupdates the module hides rather than warns')

        result = shell_result(base / 'chosen', {'checkupdates': update}, {'updateCommand': 'paru'})
        assert result['command'] == 'paru', result
        print('PASS: updateCommand wins over the fallback')


if __name__ == '__main__':
    main()
