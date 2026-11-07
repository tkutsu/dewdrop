#!/usr/bin/env python3
"""Check the real power script with compositor and system actions stubbed."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).with_name('power.sh')
SHADER = str(SCRIPT.with_name('power-blackout.frag'))
PREVIOUS = '/tmp/previous "shader".frag'
EXIT = ['hyprctl', 'dispatch', 'hl.dsp.exit(1)']

with tempfile.TemporaryDirectory(prefix='power-blackout-test-') as folder:
    target = Path(folder)
    log = target / 'calls.jsonl'
    saved = target / 'saved'
    stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['POWER_TEST_LOG'], 'a') as stream:
    stream.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
if name == 'hyprctl':
    if sys.argv[1:3] == ['-j', 'getoption']:
        print(json.dumps({'str': os.environ['POWER_TEST_SHADER']}))
    else:
        print('ok')
elif name == 'systemctl':
    sys.exit(int(os.environ['POWER_TEST_EXIT']))
'''
    for name in ('hyprctl', 'systemctl'):
        path = target / name
        path.write_text(stub)
        path.chmod(0o700)
    env = dict(os.environ, PATH=f'{target}:{os.environ["PATH"]}',
               POWER_TEST_LOG=str(log), POWER_TEST_SHADER=PREVIOUS)
    for action, failure in (('--reboot', 0), ('--poweroff', 0),
                            ('--reboot', 1), ('--suspend', 0)):
        log.write_text('')
        env['POWER_TEST_EXIT'] = str(failure)
        result = subprocess.run(['bash', str(SCRIPT), action], env=env,
                                capture_output=True, text=True)
        assert result.returncode == failure, result.stderr
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        command = ['systemctl', action.removeprefix('--')]
        if action == '--suspend':
            assert calls == [command], calls
        else:
            assert calls[0] == ['hyprctl', '-j', 'getoption', 'decoration:screen_shader'], calls
            assert calls[1] == ['hyprctl', 'eval',
                'hl.config({ decoration = { screen_shader = ' + json.dumps(SHADER) + ' } })'], calls
            assert calls[2] == command, calls
            if failure:
                assert calls[3] == ['hyprctl', 'eval',
                    'hl.config({ decoration = { screen_shader = ' + json.dumps(PREVIOUS) + ' } })'], calls
            assert len(calls) == (4 if failure else 3), calls
        print(f'PASS: {action}, exit {failure}: blackout ordering and restoration')

    # Logging out runs the session save first, survives it failing, and needs none.
    for save, wrote in ((f'printf ok > "{saved}"', True), ('exit 3', False), ('', False)):
        log.write_text('')
        saved.unlink(missing_ok=True)
        result = subprocess.run(['bash', str(SCRIPT), '--logout', save], env=env,
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert saved.exists() == wrote, save
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert calls[-1] == EXIT, calls
        print(f'PASS: logout with session save {save!r}')
