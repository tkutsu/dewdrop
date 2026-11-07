#!/usr/bin/env python3
"""Check the Hyprland config the bar publishes, and that it still matches this machine's."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HYPR = ROOT / 'hypr'
PUBLISHED = (HYPR / 'dewdrop.lua').read_text()
# A meter that is never seen, so nothing blurs or animates it.
UNSTYLED = {'ink'}


def namespaces_in_shell():
    """Every layer namespace a QML file asks for, including OverlayWindow's names."""
    found = set()
    for path in ROOT.rglob('*.qml'):
        if path.relative_to(ROOT).parts[0] in ('lab', '.claude'):
            continue
        text = path.read_text()
        found.update(re.findall(r'namespace: "quickshell:(\w+)"', text))
        if re.search(r'^OverlayWindow \{', text, re.M):
            found.update(re.findall(r'^    name: "(\w+)"', text, re.M))
    return found


def check_rules():
    rules = set(re.findall(r'namespace = "quickshell:(\w+)"', PUBLISHED))
    shell = namespaces_in_shell() - UNSTYLED
    assert rules == shell, f'rules {sorted(rules)} but surfaces {sorted(shell)}'
    print('PASS: a layer rule for every surface, and none left over')


def check_workspaces():
    lua = shutil.which('lua')
    if not lua:
        return print('SKIP: no lua to run the workspace checks')
    subprocess.run([lua, str(HYPR / 'tests/workspaces.lua')], check=True, capture_output=True, text=True)
    print('PASS: workspace checks')


def check_hyprland():
    """Hyprland's own parser: it knows the option and dispatcher names, a stub would not."""
    if not shutil.which('Hyprland'):
        return print('SKIP: no Hyprland to verify the config')
    with tempfile.TemporaryDirectory(prefix='dewdrop-verify-') as folder:
        config = Path(folder) / 'hyprland.lua'
        config.write_text(f'local workspaces = dofile("{HYPR}/dewdrop.lua")\n'
                          'assert(type(workspaces.cycle) == "function")\n')
        done = subprocess.run(['Hyprland', '--verify-config', '-c', str(config)],
                              capture_output=True, text=True, timeout=30)
        assert done.returncode == 0 and 'config ok' in done.stdout + done.stderr, done.stdout + done.stderr
    print('PASS: Hyprland accepts the config, and it returns the workspace module')


def check_this_machine():
    """A copy goes stale quietly, so compare it with the config it was taken from."""
    configs = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'hypr/configs'
    if not (configs / 'workspaces.lua').exists():
        return print('SKIP: no personal Hyprland config to compare with')
    assert (configs / 'workspaces.lua').read_text() == (HYPR / 'workspaces.lua').read_text(), \
        'hypr/workspaces.lua has drifted from ~/.config/hypr/configs/workspaces.lua'
    rules = (configs / 'wrules.lua').read_text()
    binds = (configs / 'keybinds.lua').read_text()
    for line in PUBLISHED.splitlines():
        if 'namespace = "quickshell:' in line:
            assert line in rules, f'not in wrules.lua: {line.strip()}'
        if line.startswith('hl.bind("mouse:'):
            assert line in binds, f'not in keybinds.lua: {line}'
    print('PASS: the published copy matches the personal config')


if __name__ == '__main__':
    check_rules()
    check_workspaces()
    check_hyprland()
    check_this_machine()
