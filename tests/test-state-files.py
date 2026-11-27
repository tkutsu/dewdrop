#!/usr/bin/env python3
"""A state file that does not parse is set aside as .broken, never overwritten."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
from test_support import copy_shell, shell_env

FILES = ['timers.json', 'modules.json', 'drawer.json', 'weather.json', 'downloads.json', 'feeds.json', 'tasks.json']

SHELL = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.bar
import qs.src.services
ShellRoot {
    // Touching each store loads it, and its file with it.
    readonly property var stores: [Timers.entries, ModulePlaces.centre, DrawerPins.pins, Weather.location,
        Downloads.files, Feeds.videos, Tasks.lists]
    Timer { interval: 2500; running: true; onTriggered: {
        console.log("TIMERS " + Timers.entries.length);
        Qt.quit();
    } }
}'''


def run(contents):
    with tempfile.TemporaryDirectory(prefix='state-files-test-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(SHELL)
        (target / 'notify-send').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$(dirname "$0")/notices.txt"\n')
        (target / 'notify-send').chmod(0o700)
        state = target / 'state/quickshell'
        state.mkdir(parents=True)
        for name in FILES:
            (state / name).write_text(contents)
        env = shell_env(target, PATH=f"{target}:{os.environ['PATH']}")
        result = subprocess.run(['quickshell', '-p', str(target), '--no-color'], env=env,
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        broken = {name: (state / f'{name}.broken').read_text() for name in FILES if (state / f'{name}.broken').exists()}
        notices = (target / 'notices.txt').read_text().splitlines() if (target / 'notices.txt').exists() else []
        downloads = (state / 'downloads.json').read_text()
        return output, broken, notices, downloads


failures = []


def check(ok, message):
    print(('PASS: ' if ok else 'FAIL: ') + message)
    if not ok:
        failures.append(message)


def errors(output):
    return [line for line in output.splitlines() if 'ReferenceError' in line or 'TypeError' in line or 'StateFile' in line]


malformed = '{"entries": [{"kind": "alarm",\n'
output, broken, notices, downloads = run(malformed)
missing = [name for name in FILES if broken.get(name) != malformed]
check(not missing, f'a malformed file survives as .broken in every store (missing: {missing})')
unannounced = [name for name in FILES if not any(n.startswith(f'-a Dewdrop -- {name} did not parse') for n in notices)]
check(not unannounced and len(notices) == len(FILES), f'one notice per malformed file (missing: {unannounced})')
check('TIMERS 0' in output, 'the timers start empty after a malformed file')
check(json.loads(downloads or '{}').get('seen', 0) > 0, f'Downloads starts as on a first run, so old files are not new: {downloads!r}')
check(not errors(output), f'no errors with a malformed file: {errors(output)[:3]}')

# An empty file has nothing to keep: the store starts afresh, quietly.
output, broken, notices, _ = run('')
check(not broken and not notices, f'an empty file is not copied or announced (set aside: {list(broken)}, notices: {notices})')
check('TIMERS 0' in output and not errors(output), 'the timers start empty after an empty file')

output, broken, notices, _ = run('{}\n')
check(not broken and not notices, f'a file that parses is left alone (set aside: {list(broken)}, notices: {notices})')

raise SystemExit(1 if failures else 0)
