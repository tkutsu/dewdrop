#!/usr/bin/env python3
"""Check the real display script's choice of tool with fake ones on a bare PATH."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

SOURCE = (Path(__file__).resolve().parents[1] / "scripts/display.sh").read_text()
STUB = '''#!/bin/sh
printf '%s\\n' "$(basename "$0") $*" >> "$TOOL_LOG"
case "$(basename "$0") $*" in
    "brightnessctl -m") echo 'panel,backlight,300,42%,700' ;;
    ddcutil*getvcp*) echo 'current value =    30, max value =   100' ;;
esac
'''


def fixture(root, tools, backlight=False, settings=None):
    """A script in scripts/ beside settings.json, seeing only the tools named."""
    root.mkdir()
    (root / 'scripts').mkdir()
    (root / 'bin').mkdir()
    (root / 'sys').mkdir()
    if backlight:
        (root / 'sys/panel').mkdir()
    script = SOURCE.replace('/sys/class/backlight', str(root / 'sys'))
    script = script.replace('"${XDG_RUNTIME_DIR:-$HOME/.cache}/quickshell"', f'"{root}"')
    (root / 'scripts/display.sh').write_text(script)
    if settings is not None:
        (root / 'settings.json').write_text(settings)
    for name in ('sed', 'cat', 'flock', 'dirname', 'realpath', 'rm', 'mkdir', 'cut', 'tr', 'basename', 'sh'):
        (root / 'bin' / name).symlink_to(subprocess.check_output(['which', name], text=True).strip())
    for name in tools:
        (root / 'bin' / name).write_text(STUB)
        (root / 'bin' / name).chmod(0o700)
    return root


def run(root, *args):
    """Run the script, then wait for the tint it sends off in the background."""
    done = subprocess.run(['/usr/bin/bash', str(root / 'scripts/display.sh'), *args], capture_output=True, text=True,
                          env=dict(PATH=str(root / 'bin'), TOOL_LOG=str(root / 'log')))
    return done.returncode, done.stdout.strip(), done.stderr


def calls(root):
    log = root / 'log'
    return log.read_text().splitlines() if log.exists() else []


def main():
    with tempfile.TemporaryDirectory(prefix='qs-display-script-') as folder:
        base = Path(folder)

        root = fixture(base / 'default', ['ddcutil', 'hyprctl'])
        assert run(root, 'get') == (0, '30', ''), run(root, 'get')
        assert calls(root)[0] == 'ddcutil --display 1 getvcp 10', calls(root)
        print('PASS: with no bus set, a monitor is the first display')

        comment = '// This machine\'s settings\n'
        for name, value in (('text', '"7"'), ('number', '7')):
            root = fixture(base / name, ['ddcutil', 'hyprctl'],
                           settings=comment + '{\n    "displayBus": ' + value + ',\n    "font": "Inter"\n}\n')
            run(root, 'set', '55')
            assert 'ddcutil --bus 7 setvcp 10 55' in calls(root), calls(root)
            assert (root / 'brightness').read_text().strip() == '55'
        print('PASS: displayBus from settings.json names the monitor, as text or a number')

        root = fixture(base / 'empty', ['ddcutil', 'hyprctl'], settings=json.dumps({'displayBus': ''}, indent=4))
        run(root, 'set', '55')
        assert 'ddcutil --display 1 setvcp 10 55' in calls(root), calls(root)
        print('PASS: an empty displayBus is no bus')

        root = fixture(base / 'laptop', ['brightnessctl', 'ddcutil', 'hyprctl'], backlight=True)
        assert run(root, 'get')[:2] == (0, '42')
        run(root, 'set', '55')
        assert 'brightnessctl -q --min-value=1 set 55%' in calls(root), calls(root)
        assert not any(call.startswith('ddcutil') for call in calls(root)), calls(root)
        print('PASS: a kernel backlight goes through brightnessctl, never to a true 0')

        root = fixture(base / 'night', ['brightnessctl', 'hyprctl'], backlight=True)
        assert run(root, 'toggle')[0] == 0
        assert (root / 'night-mode').exists()
        assert 'brightnessctl -q --min-value=1 set 0%' in calls(root), calls(root)
        print('PASS: night mode dims a laptop panel without turning it off')

        root = fixture(base / 'no-sunset', ['ddcutil'])
        assert run(root, 'toggle')[0] == 0 and (root / 'night-mode').exists()
        print('PASS: night mode still dims without hyprctl answering for a tint')

        root = fixture(base / 'nothing', ['hyprctl'])
        code, out, err = run(root, 'get')
        assert code == 1 and out == '' and 'ddcutil' in err, (code, out, err)
        assert run(root, 'toggle')[0] == 1 and not (root / 'night-mode').exists()
        assert calls(root) == [], calls(root)
        print('PASS: with no tool, get fails and nothing tints')

        root = fixture(base / 'no-brightnessctl', ['ddcutil', 'hyprctl'], backlight=True)
        code, _, err = run(root, 'get')
        assert code == 1 and 'brightnessctl' in err, (code, err)
        print('PASS: a laptop without brightnessctl names what it needs')


if __name__ == '__main__':
    main()
