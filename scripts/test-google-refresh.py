#!/usr/bin/env python3
"""Check shared OAuth completion, encoding and queued callers without network access."""

import json
from pathlib import Path
import runpy
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int successes: 0
    property int failures: 0
    property string reason: ""
    TestCase { id: test; when: false }
    function check(ok, why) { if (!ok) throw Error(why);console.log('PASS: ' + why); }
    function go() { successes++; }
    function fail(why) { failures++;reason = why; }
    function clear() { Google.accessToken = '';Google.tokenExpiry = 0; }
    function run() {
        test.tryVerify(() => Google.configured, 1000);
        Google.authorised(go, fail);Google.authorised(go, fail);
        check(FakeRequest.requests.length === 1 && Google.waiting.length === 2, 'two callers share one token refresh');
        const request = FakeRequest.requests[0];
        check(request.headers['Content-Type'] === 'application/x-www-form-urlencoded'
            && request.body.includes('client_secret=a%26%3D%20b') && request.body.includes('grant_type=refresh_token'),
            'token refresh preserves form encoding and literal credentials');
        FakeRequest.reply(0, {access_token: 'fresh', expires_in: 3600});FakeRequest.reply(0, {});
        check(successes === 2 && failures === 0 && !Google.refreshing && Google.waiting.length === 0,
            'successful refresh settles all waiting callers exactly once');
        clear();Google.authorised(go, fail);Google.authorised(go, fail);
        test.tryVerify(() => failures === 2, 1000);
        check(FakeRequest.requests[1].aborted && reason === 'Sign-in timed out' && !Google.refreshing && Google.waiting.length === 0,
            'shared deadline aborts the request and fails every waiting caller');
        FakeRequest.reply(1, {access_token: 'too late'});
        check(successes === 2 && Google.accessToken === '', 'late refresh response cannot install a token or settle again');
        Google.authorised(go, fail);FakeRequest.reply(2, {}, 503);
        check(failures === 3 && reason === 'Sign-in failed (503)' && !Google.tokenDead,
            'temporary HTTP failure keeps consent usable');
        Google.authorised(go, fail);
        FakeRequest.requests[3].responseText = 'broken';FakeRequest.requests[3].status = 200;
        FakeRequest.requests[3].readyState = 4;FakeRequest.requests[3].onreadystatechange();
        check(failures === 4 && reason.includes('unreadable'), 'malformed refresh fails and clears its queue');
        Google.authorised(go, fail);FakeRequest.reply(4, {}, 400);
        check(failures === 5 && Google.tokenDead && reason === Google.reconnect,
            'revoked refresh token still requests renewed consent');
        Google.tokenDead = false;
        Google.authorised(go, () => { failures++;Google.authorised(go, fail); });
        FakeRequest.reply(5, {}, 503);
        check(FakeRequest.requests.length === 7 && Google.refreshing && Google.waiting.length === 1,
            'failure callback may re-enter without losing the new caller');
        FakeRequest.reply(6, {access_token: 'recovered', expires_in: 3600});
        check(successes === 3 && !Google.refreshing && Google.waiting.length === 0,
            'reentrant refresh settles independently');
        Http.send("POST", "https://fixture/tasks/move", null, {}, 1000, () => {}, fail);
        check(FakeRequest.requests[7].body === undefined,
            'empty move request sends no body rather than a null string');
        FakeRequest.reply(7, {});

        clear();
        let reached = false;
        let next = FakeRequest.requests.length;
        Google.authorised(() => { throw Error('fixture success callback'); }, fail);
        Google.authorised(() => { reached = true; }, fail);
        try { FakeRequest.reply(next, {access_token: 'fresh', expires_in: 3600}); } catch (_) {}
        check(reached && !Google.refreshing && Google.waiting.length === 0,
            'throwing success callback cannot strand later token callers');

        clear();reached = false;next = FakeRequest.requests.length;
        Google.authorised(go, () => { throw Error('fixture failure callback'); });
        Google.authorised(go, () => { reached = true; });
        try { FakeRequest.reply(next, {}, 503); } catch (_) {}
        check(reached && !Google.refreshing && Google.waiting.length === 0,
            'throwing failure callback cannot strand later token callers');

        for (const scope of ['calendar.readonly calendar.app.created', 'calendar.readonly']) {
            clear();Google.scopeMissing = false;next = FakeRequest.requests.length;
            const beforeSuccesses = successes;
            const beforeFailures = failures;
            Google.authorised(go, fail);Google.authorised(go, fail);
            FakeRequest.reply(next, {access_token: 'limited', expires_in: 3600,
                scope: scope.split(' ').map(s => 'https://www.googleapis.com/auth/' + s).join(' ')});
            check(successes === beforeSuccesses && failures === beforeFailures + 2
                && Google.scopeMissing && Google.needsConsent && reason === Google.reconnect
                && !Google.refreshing && Google.waiting.length === 0,
                'restricted Calendar grant requests reconnect and settles all callers: ' + scope);
        }
        for (const scope of ['calendar.events', 'calendar.events.owned', 'calendar']) {
            clear();Google.scopeMissing = false;next = FakeRequest.requests.length;
            const beforeSuccesses = successes;
            Google.authorised(go, fail);
            FakeRequest.reply(next, {access_token: 'writable', expires_in: 3600,
                scope: 'https://www.googleapis.com/auth/' + scope});
            check(successes === beforeSuccesses + 1 && !Google.needsConsent,
                'primary Calendar event write grant is accepted: ' + scope);
        }
        console.log('PASS: Google refresh lifecycle');
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { root.run(); } catch (error) { console.log('FAIL: ' + error + '\n' + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    fake = runpy.run_path(str(Path(__file__).with_name('test-shell-state.py')))['FAKE_HTTP']
    with tempfile.TemporaryDirectory(prefix='quickshell-google-refresh-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'services/FakeRequest.qml').write_text(fake)
        path = target / 'services/Http.qml'
        path.write_text(path.read_text().replace('new XMLHttpRequest()', 'FakeRequest.make()'))
        path = target / 'services/GoogleAccount.qml'
        path.write_text(path.read_text().replace('refreshTimeoutMs: 15000', 'refreshTimeoutMs: 30'))
        (target / 'services/WallClock.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { signal wokeUp }')
        (target / 'Paths.qml').write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function data(name) { return Quickshell.shellPath(name); } function script(name) { return name; } }')
        (target / 'gtasks.json').write_text(json.dumps({'client_id': 'fixture', 'client_secret': 'a&= b', 'refresh_token': 'fixture'}))
        (target / 'shell.qml').write_text(QML)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end='')
        errors = ('FAIL:', 'TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop', 'Failed to load configuration')
        return 0 if result.returncode == 0 and 'PASS: Google refresh lifecycle' in output and not any(error in output for error in errors) else 1


if __name__ == '__main__':
    raise SystemExit(main())
