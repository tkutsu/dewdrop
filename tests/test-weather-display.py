#!/usr/bin/env python3
"""Exercise weather formats and duration-weighted outlooks with real QML."""

from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile

from test_support import copy_shell, shell_env


SCENARIO = r'''import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.src.core
import qs.src.modules as Modules
import qs.src.services
ShellRoot {
    Window {
        visible: true; width: 600; height: 100
        RowLayout {
            Modules.Weather { id: readout; stowed: false }
        }
        TestCase {
            id: test; when: false
            function check(ok, why) { if (!ok) throw Error(why); console.log('PASS: ' + why); }
            function hour(index, severity = 0, extra = {}) {
                return Object.assign({at: index * 3600, time: index + ':00', temperature: index * 10, feelsLike: index * 10 - 5,
                    severity, isDay: true, wind: 0, rain: 0,
                    icon: severity === 0 ? '\u{f0599}' : severity === 2 ? '\u{f0590}' : '\u{f0597}',
                    description: severity === 0 ? 'Clear' : severity === 2 ? 'Overcast' : 'Rain'}, extra);
            }
            function parts() { return readout.keyBox.children.filter(item => item.modelData !== undefined); }
            function run() {
                Settings.user = {weatherDisplay: 'temperature', reduceMotion: true};
                wait(150);
                check(Settings.weatherDisplay === 'hour' && Settings.weatherFormat === '{icon} {temp}', 'legacy temperature mode gains icon and retains current weather');
                const hours = Array.from({length: 7}, (_, index) => hour(index, index === 6 ? 2 : 0));
                Weather.days = [{date: 'test', hours}];
                Weather.now = 1800;
                Weather.updatedAt = Weather.now;
                Weather.feelsLike = false;
                check(Weather.barForecast === hours[0], 'current mode uses current-hour conditions and temperature');
                Settings.set('weatherDisplay', 'average'); wait(100);
                check(Math.abs(Weather.average.temperature - 30) < 0.001, 'six-hour average clips the first and last hours');
                check(Weather.average.description === 'Clear' && Weather.average.icon === '\u{f0599}', 'the longest-lasting sky wins the average');
                check(Weather.barForecast === Weather.average && readout.temperature === 30, 'bar reads the average temperature');
                Weather.feelsLike = true;
                check(readout.temperature === 25, 'average temperature follows Feels Like');
                Settings.set('weatherUnit', 'fahrenheit');
                check(Weather.formatTemperature(readout.temperature, false) === '77°', 'averaged temperature uses selected units');
                Settings.set('weatherUnit', 'kelvin');
                check(Weather.formatTemperature(readout.temperature, false) === '298 K', 'Kelvin works for averaged temperature');
                Settings.set('weatherUnit', 'celsius');
                Settings.set('weatherDisplay', 'worst');
                check(Weather.barForecast === hours[6] && readout.temperature === 55, 'worst mode pairs the worst conditions with that hour temperature');
                Settings.set('weatherDisplay', 'day');
                Weather.days = [{date: 'test', icon: '\u{f0595}', description: 'Partly cloudy', hours}];
                check(Weather.barForecast.icon === '\u{f0595}' && readout.temperature === 25, 'today keeps its daylight icon and averages the full day temperature');
                for (const format of ['{icon}', '{temp}', '{icon} {temp}', '{temp} {icon}', 'Now {temp} | {icon}']) {
                    Settings.set('weatherFormat', format); wait(80);
                    const delegates = parts();
                    check(delegates.map(item => item.modelData).join('') === format && delegates.every(item => item.item && item.width > 0), 'format renders all parts: ' + format);
                    check(delegates.every((item, index) => index === 0 || item.x >= delegates[index - 1].x + delegates[index - 1].width - 1), 'rendered order follows format: ' + format);
                    for (const item of delegates) {
                        if (item.modelData === '{icon}') check(item.item.text === Weather.barForecast.icon, 'icon token shows selected forecast');
                        if (item.modelData === '{temp}') check(item.item.text === Weather.formatTemperature(readout.temperature, false), 'temperature token shows selected forecast');
                    }
                    check(readout.showTemperature === format.includes('{temp}'), 'format determines text interaction');
                }
                const average = list => Weather.averageForecast(list, 0, list.length * 3600);
                check(average([hour(0, 2), hour(1, 0)]).description === 'Overcast' && average([hour(0, 0), hour(1, 2)]).description === 'Overcast', 'an even split goes to the worse sky in either order');
                check(average([hour(0, 4), hour(1), hour(2)]).description === 'Clear', 'brief rain gives way to the longer sky');
                check(average([hour(0, 5), hour(1, 5), hour(2)]).description === 'Rain', 'sustained precipitation keeps rain');
                check(average([hour(0, 3, {description: 'Fog'}), hour(1), hour(2)]).description === 'Clear', 'brief fog does not label the whole period foggy');
                check(average([hour(0, 3, {description: 'Fog'}), hour(1, 3, {description: 'Fog'}), hour(2)]).description === 'Fog', 'sustained fog keeps fog');
                check(average([hour(0, 0, {isDay: false, icon: '\u{f0594}'}), hour(1, 0, {isDay: false, icon: '\u{f0594}'})]).icon === '\u{f0594}', 'night hours keep their moon icon');
                const missing = average([hour(0, -1, {temperature: null, feelsLike: null})]);
                check(missing.temperature === null && missing.feelsLike === null && missing.description === 'Unavailable', 'missing measurements remain unavailable');
                check(Weather.averageForecast([], 0, 21600) === null, 'empty forecast stays unavailable');
                Weather.days = [];
                check(Weather.barForecast === null && readout.temperature == null, 'missing forecast renders without an invented temperature');
                console.log('PASS: weather display and outlooks');
                Qt.quit();
            }
        }
    }
    Timer { interval: 250; running: true; onTriggered: {
        try { test.run(); } catch (error) { console.log('FAIL: ' + error.stack); Qt.exit(1); }
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='quickshell-weather-display-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(SCENARIO)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end='')
        errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Binding loop', 'Unable to assign', 'Failed to load configuration')
        return 0 if result.returncode == 0 and 'PASS: weather display and outlooks' in output and not any(error in output for error in errors) else 1


if __name__ == '__main__':
    raise SystemExit(main())
