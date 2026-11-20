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
    """Every layer namespace a QML file asks for, including OverlayWindow's names.

    The shell's own files only, as copy_shell picks them: tracked or new, never
    ignored, so a scratch folder of old copies (.a11y-test/) names no surface.
    """
    found = set()
    names = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z', '--cached', '--others',
                                      '--exclude-standard', '--', '*.qml']).decode().split('\0')
    for name in filter(None, names):
        path = ROOT / name
        if path.parts[len(ROOT.parts)] == 'lab' or not path.is_file():
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
    subprocess.run([lua, str(ROOT / 'tests/hypr/workspaces.lua')], check=True, capture_output=True, text=True)
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
    """This machine loads the published file rather than keeping copies, which go stale quietly."""
    hypr = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'hypr'
    if not (hypr / 'hyprland.lua').exists():
        return print('SKIP: no personal Hyprland config to compare with')
    assert 'quickshell/hypr/dewdrop.lua' in (hypr / 'hyprland.lua').read_text(), 'hyprland.lua does not load dewdrop.lua'
    assert not (hypr / 'configs/workspaces.lua').exists(), 'configs/workspaces.lua copies hypr/workspaces.lua'
    starts_bar = re.compile(r'exec_cmd\("(?:qs|quickshell)(?: -\w)*"\)')
    for path in [hypr / 'hyprland.lua', *sorted((hypr / 'configs').glob('*.lua'))]:
        text = path.read_text()
        assert not starts_bar.search(text), f'{path.name} starts a second bar; dewdrop.lua starts it'
        for line in PUBLISHED.splitlines():
            if 'namespace = "quickshell:' in line or line.startswith('hl.bind("mouse:'):
                assert line.strip() not in text, f'{path.name} copies dewdrop.lua: {line.strip()}'
    print('PASS: the personal config loads dewdrop.lua and copies none of it')


if __name__ == '__main__':
    check_rules()
    check_workspaces()
    check_hyprland()
    check_this_machine()
