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
import qs.src.core
import qs.src.services

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
                launcherNotes: [...Launcher.calcResults("1+1", false), ...LauncherFiles.results("x")].map(row => [row.subtitle, row.install]),                terminalName: Tools.terminal,
                install: Tools.installCommand,
                weather: Tools.needs("Weather", ["python3"], "grey"),
                upgrade: Tools.needs("Upgrade", [Tools.terminal], "grey"),
                themis: Tools.needs("", ["themis"], "grey"),
                network: Settings.helper(Settings.networkCommand, false),
                monitor: Settings.helper(Settings.monitorCommand, true),
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
    tools = (ROOT / 'src/core/Tools.qml').read_text()
    listed = re.search(r'programs: \[(.*?)\]\.filter', tools, re.S).group(1)
    terminals = re.search(r'terminals: \[(.*?)\]', tools).group(1)
    probed = set(re.findall(r'"([\w-]+)"', listed + terminals)) | {'themis'}  # the icon theme, by its folder
    sources = set(re.findall(r'"([\w-]+)": "', re.search(r'sources: \(\{(.*?)\}\)', tools, re.S).group(1)))
    for path in ROOT.rglob('*.qml'):
        if path.relative_to(ROOT).parts[0] not in ('.claude', 'lab', '.plans', '.git') and path.name != 'src/core/Tools.qml':
            text = path.read_text()
            asked = re.findall(r'Tools\.has\("([^"]+)"\)', text)
            for names in re.findall(r'programs: \[([^\]]*)\]', text):
                asked += re.findall(r'"([\w-]+)"', names)
            for name in asked:
                assert name in probed, f'{path.name} asks for {name}, which src/core/Tools.qml does not probe'
    for name in probed - {'pacman'}:
        assert name in sources, f'{name} has no package for Install'
    print('PASS: Tools probes every program the shell asks about, and knows its package')
    assert 'Tools.found' in (ROOT / 'shell.qml').read_text(), 'a singleton waits to be asked, so shell.qml has to ask'
    print('PASS: the shell looks for the programs at startup')


def main():
    check_list_is_complete()
    with tempfile.TemporaryDirectory(prefix='qs-missing-tools-') as folder:
        base = Path(folder)

        result, eq = run(base / 'none', [])
        assert result['fades'] == ['--poweroff', '--reboot', '--logout'], result
        print('PASS: with nothing installed only sleep skips the black')
        assert not result['terminal'], result
        print('PASS: a missing terminal is known')
        assert result['calc'] == ['note'] and result['calcAsked'] == 0, result
        print('PASS: the calculator says what it needs, but only when asked for')
        assert result['files'] == ['note'], result
        print('PASS: file search says what it needs')
        assert result['launcherNotes'] == [['needs libqalculate', None], ['needs fd', None]], result
        print('PASS: with nothing to install with, the launcher only names the packages')
        assert not eq['busy'] and 'Python' in eq['error'], eq
        print('PASS: the equalizer says what it needs instead of waiting for ever')
        assert result['terminalName'] == '' and result['upgrade'] == 'Upgrade needs a terminal.', result
        print('PASS: with no terminal, Upgrade says it needs one')
        assert result['install'] == '' and result['weather'] == 'Weather needs python.', result
        print('PASS: without pacman a missing package is named, with nothing to press')
        assert 'Needs Themis Icons.' in result['themis'] and 'href="https://github.com/tkutsu/themis-icons"' in result['themis'], result
        print('PASS: missing Themis links to where it comes from')
        assert result['network'] == [] and result['monitor'] == [], result
        print('PASS: a right click with its app missing has nothing to run')

        result, _ = run(base / 'arch', ['pacman', 'foot'])
        assert result['terminalName'] == 'foot' and result['upgrade'] == '', result
        print('PASS: an empty terminal setting finds the one installed')
        assert result['install'] == 'sudo pacman -S --needed', result
        assert result['weather'] == 'Weather needs python. <a href="install" style="color: grey">Install</a>', result
        print('PASS: with pacman and a terminal, Install is offered, as a grey link')
        assert result['launcherNotes'] == [['needs libqalculate. Install', ['qalc']], ['needs fd. Install', ['fd']]], result
        print('PASS: the calculator and file search offer Install too')

        result, _ = run(base / 'helpers', ['nm-connection-editor', 'btop'])
        assert result['network'] == ['sh', '-c', 'nm-connection-editor'] and result['monitor'] == [], result
        print('PASS: the monitor waits for a terminal as well as its program')

        result, _ = run(base / 'wake', ['gdbus'])
        assert result['fades'] == ['--poweroff', '--reboot', '--logout', '--suspend'], result
        print('PASS: the wake signal brings back the animation for sleep')

        result, _ = run(base / 'all', ['gdbus', 'kitty', 'qalc', 'fd'])
        assert len(result['fades']) == 4 and result['terminal'], result
        assert result['calc'] == [] and result['files'] != ['note'], result
        print('PASS: with everything installed nothing changes')


if __name__ == '__main__':
    main()
