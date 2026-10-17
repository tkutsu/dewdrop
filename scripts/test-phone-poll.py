#!/usr/bin/env python3
"""Check phone polling with the actual QML scheduler rather than manual pumping."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from test_support import copy_shell, shell_env

spec = importlib.util.spec_from_file_location('shell_state', Path(__file__).with_name('test-shell-state.py'))
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)

QML = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
import "services/PhoneCrypto.js" as Crypto
ShellRoot {
    TestCase { id: test; when: false }
    function prove(index) {
        const nonce = JSON.parse(FakeRequest.requests[index].body).nonce;
        FakeRequest.reply(index, {v:1,pairId:'a'.repeat(32),nonce:nonce,
            proof:Crypto.sha256('b'.repeat(64)+':'+nonce)});
        test.tryVerify(() => FakeRequest.requests.length > index + 1, 1000);
    }
    function ringing(index) {
        const data = JSON.parse(FakeRequest.requests[index].body);
        FakeRequest.reply(index, {v:1,pairId:'a'.repeat(32),key:data.key,
            firedAt:data.firedAt,state:'ringing'});
    }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            PhoneAlarms.address = '192.168.1.121';
            PhoneAlarms.notifyPhone('Timer','poll test',{id:'poll',firedAt:Date.now()});
            prove(0);
            ringing(1);
            for (let index = 2; index <= 4; index += 2) {
                const started = Date.now();
                test.tryVerify(() => FakeRequest.requests.length > index, 3100);
                const elapsed = Date.now() - started;
                if (elapsed > 3000) throw Error('State poll took '+elapsed+'ms');
                prove(index);
                if (JSON.parse(FakeRequest.requests[index+1].body).op !== 'state')
                    throw Error('Expected state poll');
                ringing(index+1);
                console.log('PASS: native phone state poll within three seconds; elapsed='+elapsed+'ms');
            }
        } catch(error) { console.log('FAIL: '+error); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='qs-phone-poll-') as folder:
        target = Path(folder)
        copy_shell(target)
        phone = target / 'services/PhoneAlarms.qml'
        phone.write_text(phone.read_text().replace('Timer { interval: 150 }', 'Timer { interval: 1 }'))
        http = target / 'services/Http.qml'
        http.write_text(http.read_text().replace('new XMLHttpRequest()', 'FakeRequest.make()'))
        (target / 'services/FakeRequest.qml').write_text(shared.FAKE_HTTP)
        (target / 'services/Network.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property var current: ({name:"Home",known:true}) }')
        env = shell_env(target)
        data = Path(env['XDG_DATA_HOME']) / 'quickshell'
        data.mkdir(parents=True)
        (data / 'phone.json').write_text(json.dumps(dict(secret='b'*64, pairId='a'*32,
            port=8080, homeNetworks=[dict(ssid='Home', uuid='fixture', cidr='192.168.1.0/24')])))
        (target / 'shell.qml').write_text(QML)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env,
                                text=True, capture_output=True, timeout=9)
        output = result.stdout + result.stderr
        print(output, end='')
        return 0 if result.returncode == 0 and output.count('PASS: native phone state poll') == 2 and 'FAIL:' not in output else 1


if __name__ == '__main__':
    raise SystemExit(main())
