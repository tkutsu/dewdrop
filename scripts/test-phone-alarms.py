#!/usr/bin/env python3
"""Exercise phone identity checks, delivery races and outage handling in real QML."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from test_support import copy_shell, shell_env
import importlib.util

spec = importlib.util.spec_from_file_location('shell_state', Path(__file__).with_name('test-shell-state.py'))
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
QML = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
import "services/PhoneCrypto.js" as Crypto
ShellRoot {
    id: root
    property int failures: 0
    property int acknowledgements: 0
    property string occurrence: ""
    TestCase { id: test; when: false }
    Connections {
        target: PhoneAlarms
        function onFailed(reason) { root.failures++; }
        function onAcknowledged(id, firedAt) { root.acknowledgements++; root.occurrence = id + ':' + firedAt; }
    }
    function check(ok, message) { if (!ok) throw Error(message); console.log('PASS: ' + message); }
    function reply(index, state) {
        const request = JSON.parse(FakeRequest.requests[index].body);
        FakeRequest.reply(index, {v:1,pairId:'a'.repeat(32),key:request.key,firedAt:request.firedAt,state:state});
    }
    function prove(index) {
        const request = JSON.parse(FakeRequest.requests[index].body);
        check(request.op === 'probe' && !request.secret, 'identity challenge carries no shared secret');
        FakeRequest.reply(index, {v:1,pairId:'a'.repeat(32),nonce:request.nonce,proof:Crypto.sha256('b'.repeat(64)+':'+request.nonce)});
        test.tryVerify(() => FakeRequest.requests.length > index + 1, 500);
    }
    function pump() { PhoneAlarms.address='192.168.1.121'; PhoneAlarms.pump(); }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            check(Crypto.sha256('') === 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'SHA-256 empty vector');
            check(Crypto.sha256('abc') === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'SHA-256 standard vector');
            check(Crypto.sha256('Αθήνα 🔔') === 'UNICODE_HASH', 'SHA-256 UTF-8 vector');
            check(PhoneAlarms.atHome, 'saved home Wi-Fi enables delivery');
            PhoneAlarms.address='192.168.1.121';
            const fired = Date.now();
            PhoneAlarms.notifyPhone('Timer','test',{id:'same',firedAt:fired});
            FakeRequest.reply(0,{v:1,pairId:'a'.repeat(32),nonce:'wrong',proof:'wrong'});
            check(FakeRequest.requests.length===1 && failures===1, 'unrelated listener receives no alarm or secret');
            PhoneAlarms.phoneAlerts[0].due=0; pump();
            FakeRequest.reply(1,{v:1,pairId:'a'.repeat(32),nonce:'wrong',proof:'wrong'});
            check(failures===1, 'one failure report per outage');
            PhoneAlarms.phoneAlerts[0].due=0; pump(); prove(2);
            check(JSON.parse(FakeRequest.requests[3].body).op==='ring', 'verified peer receives ring');
            PhoneAlarms.dismiss();
            reply(3,'ringing');
            check(PhoneAlarms.phoneAlerts.length===1 && PhoneAlarms.phoneAlerts[0].dismissed, 'dismissal retains an in-flight start until stop');
            pump(); prove(4);
            check(JSON.parse(FakeRequest.requests[5].body).op==='stop', 'late start is followed by stop');
            FakeRequest.reply(5,{},0);
            check(PhoneAlarms.phoneAlerts.length===1 && failures===2, 'failed stop remains pending and a recovered outage can report once');
            PhoneAlarms.phoneAlerts[0].due=0; pump(); prove(6); reply(7,'stopped');
            check(PhoneAlarms.phoneAlerts.length===0 && acknowledgements===0, 'remote stop retires without a phone acknowledgement');
            PhoneAlarms.address='192.168.1.121';
            PhoneAlarms.notifyPhone('Timer','new',{id:'same',firedAt:fired+1});prove(8);reply(9,'ringing');
            PhoneAlarms.phoneAlerts[0].due=0;pump();prove(10);reply(11,'dismissed');
            check(acknowledgements===1 && occurrence==='same:'+(fired+1), 'phone dismissal identifies the exact occurrence');
            PhoneAlarms.notifyPhone('Timer','timeout',{id:'timeout',firedAt:fired+2});prove(12);reply(13,'timed_out');
            check(acknowledgements===1 && PhoneAlarms.phoneAlerts.length===0, 'natural timeout is not an explicit acknowledgement');
            PhoneAlarms.notifyPhone('Timer','deadline',{id:'deadline',firedAt:Date.now()-PhoneAlarms.lifetimeMs-1000});
            const ending = PhoneAlarms.phoneAlerts[0];
            check(PhoneAlarms.hasLive(ending.id,ending.firedAt), 'deadline retains a dismissible entry until phone stop settles');
            prove(14);
            check(JSON.parse(FakeRequest.requests[15].body).op==='stop', 'elapsed phone deadline reconciles with stop instead of replaying ring');
            reply(15,'stopped');
            check(PhoneAlarms.phoneAlerts.length===0 && acknowledgements===1, 'deadline reconciliation retires without acknowledgement');
            const beforeExpiry=FakeRequest.requests.length;
            PhoneAlarms.notifyPhone('Timer','expired',{id:'expired',firedAt:Date.now()-PhoneAlarms.lifetimeMs-PhoneAlarms.reconciliationMs-1});
            check(PhoneAlarms.phoneAlerts.length===0 && FakeRequest.requests.length===beforeExpiry, 'unreachable reconciliation expires without a late start');
            Network.current={name:'Other saved Wi-Fi',known:true};
            const count=FakeRequest.requests.length;
            PhoneAlarms.notifyPhone('Timer','away',{id:'away',firedAt:Date.now()});PhoneAlarms.pump();
            check(!PhoneAlarms.atHome && FakeRequest.requests.length===count && PhoneAlarms.phoneAlerts.length===0, 'other saved Wi-Fi produces no delivery or discovery');
            console.log('PASS: local phone protocol');
        } catch(error) { console.log('FAIL: '+error+'\n'+error.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-phone-test-') as folder:
        target=Path(folder);copy_shell(target)
        source=(target/'services/PhoneAlarms.qml').read_text()
        source=source.replace('Timer { interval: 150 }','Timer { interval: 1 }')
        source=source.replace('onTriggered: root.pump()','onTriggered: {}')
        (target/'services/PhoneAlarms.qml').write_text(source)
        source=(target/'services/Http.qml').read_text().replace('new XMLHttpRequest()','FakeRequest.make()')
        (target/'services/Http.qml').write_text(source)
        (target/'services/FakeRequest.qml').write_text(shared.FAKE_HTTP)
        (target/'services/Network.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var current: ({name:"Home",known:true}) }\n')
        env=shell_env(target)
        data=Path(env['XDG_DATA_HOME'])/'quickshell';data.mkdir(parents=True)
        (data/'phone.json').write_text(json.dumps(dict(secret='b'*64,pairId='a'*32,port=8080,homeNetworks=[dict(ssid='Home',uuid='fixture',cidr='192.168.1.0/24')])))
        (target/'shell.qml').write_text(QML.replace('UNICODE_HASH',hashlib.sha256('Αθήνα 🔔'.encode()).hexdigest()))
        result=subprocess.run(['qs','-p',str(target),'--no-color'],env=env,capture_output=True,text=True,timeout=12)
        output=result.stdout+result.stderr;print(output,end='')
        errors=('FAIL:','ReferenceError:','TypeError:','Binding loop','Unable to assign','Failed to load configuration')
        return 0 if result.returncode==0 and 'PASS: local phone protocol' in output and not any(e in output for e in errors) else 1


if __name__=='__main__': raise SystemExit(main())
