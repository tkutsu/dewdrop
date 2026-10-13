#!/usr/bin/env python3
"""Exercise weather retry and request lifetimes without network access."""

from pathlib import Path
import json
import subprocess
import tempfile

from test_support import copy_shell, shell_env


HELPER = r'''import json, sys, time
from pathlib import Path
root = Path(__file__).resolve().parents[1]
mode = sys.argv[1]
response = json.loads((root / 'response.json').read_text())[mode]
with (root / 'requests.jsonl').open('a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\n')
time.sleep(response.get('delay', 0))
output = response['output']
print(output if isinstance(output, str) else json.dumps(output))
'''

SCENARIO = r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root
    property int replies: 0
    Connections { target: Weather.auditForecast; function onResult() { root.replies++; } }
    FileView { id: response; path: Quickshell.shellPath('response.json'); blockLoading: true }
    FileView { id: requests; path: Quickshell.shellPath('requests.jsonl'); blockLoading: true; printErrors: false }
    TestCase { id: test; when: false }
    function check(ok, why) {
        if (!ok) throw Error(why);
        console.log('PASS: ' + why);
    }
    function configure(forecast, search = {locations: [{name: 'Athens'}]}, delay = 0, searchDelay = 0) {
        response.setText(JSON.stringify({forecast: {output: forecast, delay}, search: {output: search, delay: searchDelay}}));
        response.waitForJob();
    }
    function forecast(name) {
        return {days: [{date: name, hours: []}], fetchedAt: AuditClock.now / 1000};
    }
    function count(mode) {
        requests.reload();
        requests.waitForJob();
        return requests.text().trim().split('\n').filter(line => line && JSON.parse(line)[0] === mode).length;
    }
    function lastForecast() {
        requests.reload();requests.waitForJob();
        const lines = requests.text().trim().split('\n').map(line => JSON.parse(line)).filter(args => args[0] === 'forecast');
        return lines[lines.length - 1];
    }
    function settled() { test.tryVerify(() => !Weather.loading, 2000); }
    function run() {
        test.tryVerify(() => Weather.restored && !Weather.loading, 2000);
        check(Weather.location.name === 'Saved' && Weather.feelsLike && Weather.days[0].date === 'startup',
            'saved city and preference restore before startup forecast');
        check(Weather.auditRetry.interval === 30000 && !Weather.auditRetry.running,
            'healthy startup leaves the 30-second retry stopped');
        let before = count('forecast');
        WallClock.wokeUp();test.wait(120);
        check(count('forecast') === before, 'wake preserves a fresh forecast without another request; before=' + before + ', after=' + count('forecast') + ', now=' + Weather.now + ', updated=' + Weather.updatedAt);

        configure({error: 'offline'});
        Weather.refresh(true);settled();
        check(Weather.trouble === 'offline' && Weather.auditRetry.running && Weather.days[0].date === 'startup',
            'failure retains forecast and arms the service retry');
        before = count('forecast');
        Weather.auditMinute.triggered();test.wait(120);
        check(count('forecast') === before, 'minute refresh cannot bypass the pending retry delay');
        configure(forecast('manual'));
        Weather.refresh(true);settled();
        check(Weather.days[0].date === 'manual' && !Weather.trouble && !Weather.auditRetry.running,
            'manual refresh can recover immediately and stops retry');

        configure({error: 'offline'});Weather.refresh(true);settled();
        before = count('forecast');
        Weather.auditRetry.interval = 150;
        Weather.auditRetry.restart();
        test.tryVerify(() => count('forecast') > before, 2000);settled();
        check(Weather.trouble === 'offline' && Weather.auditRetry.running,
            'another failure re-arms the same retry timer');
        configure(forecast('automatic'));
        test.tryVerify(() => Weather.days[0].date === 'automatic', 2000);settled();
        check(lastForecast().includes('--force'), 'retry reaches provider after a failed refresh with fresh cached data');
        before = count('forecast');test.wait(300);
        check(!Weather.auditRetry.running && count('forecast') === before,
            'automatic retry recovers once and stops after success');
        Weather.auditRetry.interval = 30000;

        configure({error: 'offline'});Weather.refresh(true);settled();
        configure(forecast('wake'));WallClock.wokeUp();settled();
        check(Weather.days[0].date === 'wake' && !Weather.auditRetry.running,
            'wake retries a failed forecast immediately');
        AuditClock.now += 3600000;
        configure(forecast('stale-wake'));WallClock.wokeUp();settled();
        check(Weather.days[0].date === 'stale-wake', 'wake refreshes an expired forecast');

        configure({error: 'offline'});Weather.refresh(true);settled();
        configure(forecast('network'));Network.online = true;settled();
        check(Weather.days[0].date === 'network' && !Weather.trouble,
            'network recovery retries failure without a cooldown gate');

        configure(Object.assign(forecast('ignored-old-city'), {error: 'old failure'}), undefined, 0.25);
        before = count('forecast');
        Weather.refresh(true);
        test.tryVerify(() => Weather.auditForecast.running && count('forecast') > before, 2000);
        test.wait(80);
        configure(forecast('new-city'), undefined, 0.25);
        const oldReplies = root.replies;
        Weather.choose({name: 'New', latitude: 40, longitude: 20, timezone: 'UTC'});
        test.tryVerify(() => root.replies > oldReplies, 2000);
        check(Weather.days.length === 0 && !Weather.trouble && !Weather.auditRetry.running,
            'late old-city reply cannot install forecast or retry state');
        settled();
        check(Weather.days[0].date === 'new-city', 'new city queues behind the old process and installs its own reply');

        configure('invalid JSON');Weather.refresh(true);settled();
        check(Weather.trouble.includes('Could not read') && Weather.auditRetry.running && Weather.days[0].date === 'new-city',
            'malformed reply retains forecast and schedules retry');
        configure({days: []});Weather.refresh(true);settled();
        check(Weather.trouble === 'The forecast is unavailable.' && Weather.auditRetry.running,
            'empty forecast also schedules retry');
        configure(forecast('final'));Weather.refresh(true);settled();

        configure(forecast('final'), {error: 'search offline'});
        Weather.query = 'Athens';
        test.tryVerify(() => !Weather.searching, 2000);
        check(Weather.searchTrouble === 'search offline' && !Weather.trouble && !Weather.auditRetry.running,
            'search failure stays local to search');
        configure(forecast('final'), {locations: [{name: 'Recovered'}]});
        Network.online = false;Network.online = true;
        test.tryVerify(() => Weather.locations[0]?.name === 'Recovered', 2000);
        check(!Weather.searchTrouble, 'network recovery reissues a failed location search');
        configure(forecast('final'), {error: 'search offline'});
        Weather.query = 'Wake';test.tryVerify(() => !Weather.searching, 2000);
        configure(forecast('final'), {locations: [{name: 'Wake recovery'}]});
        WallClock.wokeUp();
        test.tryVerify(() => Weather.locations[0]?.name === 'Wake recovery', 2000);
        check(!Weather.searchTrouble, 'wake also reissues a failed location search');

        configure(forecast('final'), {locations: [{name: 'Old search'}]}, 0, 0.25);
        Weather.query = 'Old';test.tryVerify(() => Weather.auditSearch.running, 2000);test.wait(80);
        configure(forecast('final'), {locations: [{name: 'New search'}]}, 0, 0.25);
        Weather.query = 'New';
        test.tryVerify(() => Weather.locations[0]?.name === 'New search', 2000);
        check(!Weather.searchTrouble, 'new query rejects the old search reply and accepts its own');
        Weather.query = '';
        requests.reload();
        requests.waitForJob();
        check(!requests.text().includes('--state') && requests.text().includes('--cache') && requests.text().includes('--force'),
            'actual helper commands preserve cache and force flags without request state');
        console.log('PASS: weather service lifecycle');
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { root.run(); } catch (error) { console.log('FAIL: ' + error + '\n' + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-weather-service-') as folder:
        target = Path(folder)
        copy_shell(target)
        (target / 'scripts/weather-fetch.py').write_text(HELPER)
        (target / 'services/AuditClock.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property double now: 10000000; function read() { return now; } }\n')
        (target / 'services/Network.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool online: false }\n')
        (target / 'services/WallClock.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { signal wokeUp }\n')
        (target / 'Paths.qml').write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function state(name) { return Quickshell.shellPath(name); } function cache(name) { return Quickshell.shellPath(name); } }\n')
        source = (target / 'services/Weather.qml').read_text().replace('Date.now()', 'AuditClock.read()')
        source = source.replace('id: root', 'id: root\n    property alias auditRetry: retryWake\n    property alias auditForecast: forecastJob\n    property alias auditSearch: searchJob\n    property alias auditMinute: minuteTick', 1)
        source = source.replace('    Timer {\n        // Align', '    Timer {\n        id: minuteTick\n        // Align', 1)
        (target / 'services/Weather.qml').write_text(source)
        (target / 'weather.json').write_text(json.dumps({'location': {'name': 'Saved', 'latitude': 0, 'longitude': 0, 'timezone': 'UTC'}, 'feelsLike': True}))
        (target / 'response.json').write_text(json.dumps({'forecast': {'output': {'days': [{'date': 'startup', 'hours': []}], 'fetchedAt': 10000}}, 'search': {'output': {'locations': []}}}))
        (target / 'requests.jsonl').write_text('')
        (target / 'shell.qml').write_text(SCENARIO)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=25)
        output = result.stdout + result.stderr
        print(output, end='')
        errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign', 'Failed to load configuration')
        return 0 if result.returncode == 0 and 'PASS: weather service lifecycle' in output and not any(error in output for error in errors) else 1


if __name__ == '__main__':
    raise SystemExit(main())
