#!/usr/bin/env python3
"""Exercise shared shell state and phone delivery with isolated files and HTTP."""

import json
import os
import re
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

FAKE_HTTP = """pragma Singleton
import QtQuick
import Quickshell
Singleton {
    id: root
    property var requests: []
    function make() {
        const request = {
            readyState: 0, status: 0, responseText: "", headers: {}, aborted: false,
            open: function(method, url) { this.method = method; this.url = url; },
            setRequestHeader: function(key, value) { this.headers[key] = value; },
            send: function(body) { this.body = body; },
            abort: function() { this.aborted = true; this.readyState = 4; this.onreadystatechange(); }
        };
        root.requests = root.requests.concat([request]);
        return request;
    }
    function reply(index, body, status) {
        const request = root.requests[index];
        request.status = status ?? 200;
        request.responseText = JSON.stringify(body);
        request.readyState = 4;
        request.onreadystatechange();
    }
}
"""

TEST = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int accepted: 0
    property int failed: 0
    property string acknowledged: ""
    function groupOf(notice) { return notice?.appName || "Notification"; }
    Column {
        id: group
        modelData: "App"
        GROUP_STATE
    }
    property var api: TestApi
    component WeatherSelection: Item {
        id: root
        WEATHER_SELECTION
    }
    WeatherSelection { id: weatherSelection }
    Connections {
        target: Pushover
        function onAcknowledged(id, firedAt) { root.acknowledged = id + ":" + firedAt; }
    }
    function check(ok, message) { if (!ok) throw Error(message); }
    function run() {
        try {
            const firstNote = {id: 1, appName: "App", closed: {connect: function(callback) {}}};
            const secondNote = {id: 2, appName: "App"};
            Notifications.list = [firstNote, secondNote];
            Notifications.centreFocus = firstNote;
            check(group.open, "focus opens its notification group");
            Notifications.list = [firstNote];
            Notifications.list = [firstNote, secondNote];
            Notifications.centreFocus = secondNote;
            check(group.open, "focus still opens a group after its items changed");
            const seenAt = Date.now();
            Notifications.ago(firstNote, seenAt);
            check(Notifications.ago(firstNote, seenAt + 120000) === "2m", "restored notification ages after first sight");
            Weather.now = 10000;
            Weather.days = [{date: "2026-10-03", hours: [
                {at: 7200, severity: 8, description: "Thunderstorm", icon: "storm"},
                {at: 10800, severity: 0, description: "Clear", icon: "clear"}
            ]}];
            check(Weather.upcoming.length === 2 && Weather.icon === "storm", "bar includes the current forecast hour");
            check(Weather.summary.includes("this hour"), "popup and bar agree on current storms");
            Weather.now = 10800;
            check(Weather.upcoming.length === 1 && Weather.icon === "clear", "elapsed forecast hour leaves the outlook");

            Weather.location = {name: "Fixture city"};
            Weather.now = 10000;
            const hours = Array.from({length: 7}, (_, index) => ({
                at: 7200 + index * 3600,
                time: ["23:00", "00:00", "01:00", "02:00", "03:00", "04:00", "05:00"][index],
                description: index < 3 ? "Overcast" : index < 5 ? "Rain" : "Clear",
                icon: index < 3 ? "cloud" : index < 5 ? "rain" : "clear",
                severity: index < 3 ? 2 : index < 5 ? 5 : 0,
                rain: index < 3 ? 10 : index < 5 ? 80 : 0,
                wind: index === 4 ? 45 : 12,
                temperature: 24 - index
            }));
            Weather.days = [{date: "2026-10-03", hours: hours.slice(0, 1)}, {date: "2026-10-04", hours: hours.slice(1)}];
            check(Weather.summary.startsWith("Rain likely from 02:00, clearing around 04:00."), "summary leads with rain onset and clearing across midnight");
            check(Weather.summary.includes("Strong winds around 03:00") && Weather.summary.includes("Cooling to 18°C"), "summary explains wind and temperature without repeating graph measurements");
            check(Weather.tooltip === `Next 6 hours: ${Weather.summary}` && !Weather.tooltip.includes("\\n"), "tooltip has only a single-line heading and summary");
            weatherSelection.picked = "2026-10-03";
            Weather.now = 10800;
            check(weatherSelection.picked === "" && weatherSelection.day.date === "2026-10-04", "midnight switches a manually selected old day to the new today");
            check(weatherSelection.hours[0].time === "00:00", "current-time graph starts at the next day's midnight");
            Weather.now = 10000;

            const ranges = Weather.hourRanges(hours, "icon");
            check(ranges.length === 3 && ranges[0].start === 7200 && ranges[0].end === 18000, "consecutive hourly icons form their full duration range");
            check(ranges[2].end === hours[6].at + 3600, "last icon includes its final hour");
            const repeated = hours.map(hour => Object.assign({}, hour, {icon: "clear", description: "Clear", severity: 0, rain: 5, wind: 10, temperature: 20}));
            check(Weather.hourRanges(repeated, "icon").length === 1, "unchanged icons appear once");
            check(Weather.hourRanges([repeated[0], repeated[2]], "icon").length === 2, "missing hour breaks an icon range");
            check(Weather.hourRanges([Object.assign({}, repeated[0], {time: "03:00"}), Object.assign({}, repeated[1], {time: "03:00"})], "icon")[0].end - repeated[0].at === 7200, "repeated DST clock labels keep epoch durations");
            check(Weather.hourRanges([], "icon").length === 0, "empty axis stays safe");

            Weather.days = [{date: "2026-10-03", hours: repeated}];
            check(Weather.summary === "Clear and dry. Around 20°C.", "steady weather reads at a glance");
            Weather.days = [{date: "2026-10-03", hours: repeated.filter((_, index) => index !== 2)}];
            check(Weather.summary.includes("Some hours are missing") && !Weather.summary.includes("dry"), "forecast gap does not promise six hours of dry weather");
            Weather.days = [{date: "2026-10-03", hours: repeated.map(hour => Object.assign({}, hour, {rain: null, temperature: null, wind: null}))}];
            check(!Weather.summary.includes("Rain chance") && !Weather.summary.includes("°C") && !Weather.summary.includes("km/h"), "missing measurements are not described as zero");
            Weather.updatedAt = 9000;
            Weather.trouble = "Fixture offline";
            check(Weather.tooltip.includes("Last forecast"), "cached tooltip identifies stale data");
            Weather.days = [];
            check(Weather.summary === "Forecast unavailable.", "empty summary is explicit");
            check(Weather.tooltip === "Next 6 hours: Forecast unavailable.", "empty tooltip keeps its requested heading");

            Weather.trouble = "";
            Weather.updatedAt = 0;
            const scenario = (descriptions, probabilities, temperatures, speeds) => repeated.map((hour, index) => Object.assign({}, hour, {
                description: descriptions[index], rain: probabilities[index], temperature: temperatures[index], wind: speeds[index]
            }));
            const clear = Array(7).fill("Clear");
            const cloudy = Array(7).fill("Overcast");
            const dry = Array(7).fill(0);
            const mild = Array(7).fill(20);
            const light = Array(7).fill(10);
            const cases = [
                ["clear night", scenario(clear, dry, [18, 18, 17, 17, 16, 16, 15], light), "Clear and dry. Cooling to 15°C."],
                ["changing clouds", scenario(["Clear", "Partly cloudy", "Clear", "Partly cloudy", "Overcast", "Partly cloudy", "Clear"], dry, mild, light), "Partly cloudy and dry. Around 20°C."],
                ["brief low rain chance", scenario(cloudy, [0, 0, 35, 0, 0, 0, 0], mild, light), "Rain possible around 01:00, easing around 02:00. Around 20°C."],
                ["steady rain", scenario(Array(7).fill("Rain"), Array(7).fill(85), mild, light), "Rain likely throughout. Around 20°C."],
                ["uncertain rain", scenario(cloudy, Array(7).fill(50), mild, light), "Rain possible throughout. Around 20°C."],
                ["intermittent rain", scenario(cloudy, [0, 80, 0, 80, 0, 0, 0], mild, light), "Rain likely on and off from 00:00. Around 20°C."],
                ["cloud clearing", scenario(["Overcast", "Overcast", "Overcast", "Clear", "Clear", "Clear", "Clear"], dry, mild, light), "Cloudy at first, clearing around 02:00. Around 20°C."],
                ["cloud increasing", scenario(["Clear", "Clear", "Clear", "Clear", "Overcast", "Overcast", "Overcast"], dry, mild, light), "Clear at first, cloudier from 03:00. Around 20°C."],
                ["persistent fog", scenario(Array(7).fill("Fog"), dry, mild, light), "Foggy throughout. Around 20°C."],
                ["fog followed by rain", scenario(["Fog", "Fog", "Overcast", "Rain", "Rain", "Overcast", "Overcast"], [0, 0, 0, 80, 80, 0, 0], mild, light), "Rain likely from 02:00, easing around 04:00. Around 20°C."],
                ["snow", scenario(Array(7).fill("Snow"), Array(7).fill(50), Array(7).fill(-2), light), "Snow throughout. Freezing, down to -2°C."],
                ["freezing rain", scenario(["Clear", "Clear", "Freezing rain", "Freezing rain", "Freezing rain", "Overcast", "Overcast"], [0, 0, 80, 80, 80, 0, 0], Array(7).fill(1), light), "Freezing rain from 01:00, easing around 04:00. Around 1°C."],
                ["hot peak", scenario(clear, dry, [26, 28, 33, 38, 37, 30, 27], light), "Clear and dry. Hot, up to 38°C."],
                ["warm without extreme heat", scenario(clear, dry, Array(7).fill(34.6), light), "Clear and dry. Around 35°C."],
                ["above freezing", scenario(clear, dry, Array(7).fill(0.4), light), "Clear and dry. Around 0°C."],
                ["cold and windy", scenario(clear, dry, [-2, -2, -3, -3, -4, -3, -2], Array(7).fill(35)), "Clear and dry. Breezy. Freezing, down to -4°C."],
                ["missing measurements", scenario(clear, Array(7).fill(null), Array(7).fill(null), Array(7).fill(null)), "Clear."],
                ["unknown conditions", scenario(["Clear", "Clear", "Unavailable", "Clear", "Clear", "Clear", "Clear"], dry, mild, light), "Clear. Around 20°C. Some conditions are unavailable."]
            ];
            for (const [name, forecast, expected] of cases) {
                Weather.days = [{date: "2026-10-03", hours: forecast}];
                check(Weather.summary === expected, `${name}: ${Weather.summary}`);
                check(Weather.summary.length < 220 && !Weather.summary.includes("\\n"), "summary stays concise and leaves formatting to its view");
            }
            const storms = scenario(["Overcast", "Overcast", "Overcast", "Rain", "Thunderstorm", "Rain", "Clear"], [10, 10, 10, 70, 90, 60, 0], [30, 29, 28, 27, 26, 25, 24], [12, 12, 12, 20, 60, 20, 10]);
            Weather.days = [{date: "2026-10-03", hours: storms}];
            check(Weather.summary.startsWith("Thunderstorms around 03:00") && Weather.summary.includes("Very strong winds around 03:00"), "storm risk leads the summary even when later hours clear");

            check(Weather.windLabel(0) === "Calm" && Weather.windLabel(8) === "Light" && Weather.windLabel(15) === "Gentle", "calm and light wind adjectives follow speed");
            check(Weather.windLabel(20) === "Moderate" && Weather.windLabel(30) === "Fresh" && Weather.windLabel(45) === "Strong", "wind strength crosses Beaufort bands");
            check(Weather.windLabel(null) === "Wind", "unknown speed has no invented adjective");
            check(Weather.windBearing(0) === "N ↑" && Weather.windBearing(360) === "N ↑", "north wind label and arrow use meteorological origin");
            check(Weather.windBearing(90) === "E →" && Weather.windBearing(180) === "S ↓" && Weather.windBearing(270) === "W ←", "arrows point toward the named compass direction");
            check(Weather.windBearing(45) === "NE ↗" && Weather.windBearing(359) === "N ↑", "diagonal direction and north wrap correctly");
            check(Weather.windBearing(null) === "" && Weather.windBearing(-1) === "" && Weather.windBearing(361) === "", "unknown or invalid direction has no arrow");

            Http.send("POST", "https://fixture.invalid", {answer: 42}, {Authorization: "fixture"}, 5000,
                () => root.accepted++, () => root.failed++);
            const request = FakeRequest.requests[0];
            check(request.headers["Content-Type"] === "application/json" && JSON.parse(request.body).answer === 42, "JSON and caller headers are sent");
            FakeRequest.reply(0, {});
            FakeRequest.reply(0, {});
            check(root.accepted === 1 && root.failed === 0, "HTTP completion occurs only once");

            Pushover.notifyPhone("Timer", "bread", {id: "timer", firedAt: 123000});
            FakeRequest.reply(1, {status: 1, receipt: "r".repeat(30)});
            Pushover.pollPhone();
            FakeRequest.reply(2, {status: 1, acknowledged: 1});
            check(root.acknowledged === "timer:123000" && Pushover.phoneAlerts.length === 0, "phone acknowledgement identifies the occurrence");

            Pushover.notifyPhone("Timer", "bread", {id: "dismissed", firedAt: 124000});
            Pushover.dismiss();
            FakeRequest.reply(3, {status: 1, receipt: "s".repeat(30)});
            check(FakeRequest.requests[4].url.endsWith("/cancel.json"), "dismissal before receipt cancels when it arrives");
            FakeRequest.reply(4, {status: 1});
            check(Pushover.phoneAlerts.length === 0, "cancelled delivery retires its receipt");

            Http.send("GET", "https://fixture.invalid/timeout", null, {}, 5,
                () => root.accepted++, () => root.failed++);
            Google.accessToken = "fixture";
            Google.tokenExpiry = Date.now() + 3600000;
            api.send("GET", "https://fixture.invalid/google", null, () => root.accepted++, () => root.failed++);
            check(api.loading, "Google service counts a request without a caller authorisation wrapper");
            FakeRequest.reply(6, {}, 401);
            check(FakeRequest.requests[7].url === Google.tokenEndpoint, "expired token refreshes once");
            FakeRequest.reply(7, {access_token: "renewed-fixture", expires_in: 3600});
            FakeRequest.reply(8, {});
            check(!api.loading && root.accepted === 2, "Google request retries with its refreshed token and settles the counter");
            finish.restart();
        } catch (error) { console.log("FAIL: " + error); Qt.quit(); }
    }
    Timer { interval: 100; running: true; onTriggered: root.run() }
    Timer {
        id: finish
        interval: 30
        onTriggered: {
            try {
                check(root.failed === 1 && FakeRequest.requests[5].aborted, "timeout aborts once");
                FakeRequest.reply(5, {});
                check(root.accepted === 2 && root.failed === 1, "late response cannot complete a timed-out request");
                console.log("PASS: weather outlook, HTTP deadlines and phone receipts");
            } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-state-test-") as folder:
        target = Path(folder)
        services = target / "services"
        services.mkdir()
        for name in ("Weather.qml", "Pushover.qml", "Http.qml", "Google.qml", "GoogleService.qml"):
            source = (ROOT / "services" / name).read_text()
            if name in ("Http.qml", "Google.qml"):
                source = source.replace("new XMLHttpRequest()", "FakeRequest.make()")
            (services / name).write_text(source)
        (services / "TestApi.qml").write_text("pragma Singleton\nimport QtQuick\nGoogleService { polling: false }\n")
        (services / "FakeRequest.qml").write_text(FAKE_HTTP)
        (services / "Retry.qml").write_text("import QtQuick\nQtObject { property bool active: false; property bool pending: false; signal triggered; function reset() {} function cancel() {} function schedule() {} }\n")
        (services / "Network.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool online: false }\n")
        (target / "components").mkdir()
        (target / "components/QueuedProcess.qml").write_text("import QtQuick\nQtObject { property string want: ''; property string arg: ''; property int interval: 0; property bool running: false; property var command: []; signal result(arg: string, text: string) }\n")
        (target / "Theme.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject {}\n")
        (target / "Settings.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { function moduleOn(name) { return false; } function inTerminal(command) { return command; } }\n")
        (target / "Paths.qml").write_text("pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function state(name) { return Quickshell.shellPath('state/' + name); } function data(name) { return Quickshell.shellPath('data/' + name); } function cache(name) { return Quickshell.shellPath('cache/' + name); } function script(name) { return name; } }\n")
        (target / "state").mkdir()
        (target / "data").mkdir()
        (target / "data/gtasks.json").write_text(json.dumps({"client_id": "fixture", "client_secret": "fixture", "refresh_token": "fixture"}))
        (target / "data/pushover.json").write_text(json.dumps({"token": "t" * 30, "user": "u" * 30}))
        notifications = (ROOT / "services/Notifications.qml").read_text()
        methods = "\n".join(re.findall(r'^    function (?:ago|remember)\([^\n]*\n.*?^    }', notifications, re.M | re.S))
        (services / "Notifications.qml").write_text("pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { id: root; property var list: []; property var centreFocus: null; property var arrived: ({}); property var passing: ({});\n" + methods + "\n}\n")
        popup = (ROOT / "components/NotificationsPopup.qml").read_text()
        start = popup.index("        required property string modelData", popup.index("component Group:"))
        end = popup.index("        width: ListView.view.width", start)
        weather_popup = (ROOT / "components/WeatherPopup.qml").read_text()
        selection_start = weather_popup.index('    property string picked:')
        selection_end = weather_popup.index('    acceptsKeyboard:', selection_start)
        (target / "shell.qml").write_text(TEST.replace("GROUP_STATE", popup[start:end]).replace("WEATHER_SELECTION", weather_popup[selection_start:selection_end]))
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        return 0 if result.returncode == 0 and "PASS: weather outlook" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
