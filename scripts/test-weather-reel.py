#!/usr/bin/env python3
"""Exercise weather day slides and midnight rollover in an isolated Qt window."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-weather-reel-") as folder:
        target = Path(folder)
        components = target / "components"
        services = target / "services"
        components.mkdir()
        services.mkdir()
        source = (ROOT / "components/WeatherPopup.qml").read_text()
        for name in ("reel", "outgoing", "incoming", "slide", "daily"):
            source = source.replace(f"id: {name}\n", f'id: {name}\n        objectName: "{name}"\n')
        (components / "WeatherPopup.qml").write_text(source)
        for name in ("WeatherGraph.qml", "PopupText.qml", "PopupRow.qml"):
            source = (ROOT / "components" / name).read_text()
            if name == "WeatherGraph.qml":
                for item in ("seriesTitle", "plot"):
                    source = source.replace(f"id: {item}\n", f'id: {item}\n                        objectName: "{item}"\n')
                source = source.replace('text: Math.round(modelData)', 'objectName: "axisTick"\n                            text: Math.round(modelData)')
            (components / name).write_text(source)
        (components / "Popup.qml").write_text('''import QtQuick
Item {
    property bool acceptsKeyboard: false
    property bool requestedVisible: true
    property alias spacing: body.spacing
    default property alias content: body.data
    width: body.implicitWidth; height: body.implicitHeight
    Column { id: body }
}
''')
        (components / "PopupHeader.qml").write_text('import QtQuick\nRow { property string title: ""; height: 24 }\n')
        (components / "PopupButton.qml").write_text('''import QtQuick
Item { property bool framed: false; property bool lit: false; property bool live: true
    property string label: ""; signal tapped; width: 70; height: 24 }
''')
        (components / "Glyph.qml").write_text('import QtQuick\nText { property int fontSize: 16; font.pixelSize: fontSize }\n')
        (components / "QueuedProcess.qml").write_text('''import QtQuick
QtObject { property string want: ""; property string arg: ""; property int interval: 0
    property bool running: false; property var command: []; signal result(arg: string, text: string) }
''')
        (services / "Weather.qml").write_text((ROOT / "services/Weather.qml").read_text())
        (services / "WallClock.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { signal wokeUp }\n')
        (services / "Network.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool online: false }\n')
        (target / "Paths.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
QtObject { function state(name) { return Quickshell.shellPath(name); }
    function cache(name) { return Quickshell.shellPath(name); } }
''')
        (target / "OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
        (target / "Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property int foldMs: 360; property int selectionRadius: 4; property int pillBorder: 1
    property int captionSize: 12; property int footnoteSize: 10; property int popupTextSize: 14
    property int popupGlyphSize: 16; property string bodyFont: "sans-serif"
    property var figures: ({}); property color fg: "white"; property color label2: "grey"
    property color selection: "#333333"; property color selectionStrong: "#444444"
    property color stroke: "#666666"; property color warn: "orange"
}
''')
        (target / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    Window {
        visible: true; width: 600; height: 700
        WeatherPopup { id: popup }
        TestCase {
            id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function named(item, name, index) {
                if (item.objectName === name && (index === undefined || item.index === index)) return item;
                for (const child of item.children || []) {
                    const found = named(child, name, index);
                    if (found) return found;
                }
                return null;
            }
            function clickDay(index) {
                const row = named(popup, "daily", index);
                mouseClick(row, row.width / 2, row.height / 2);
                wait(70);
            }
            function namedAll(item, name) {
                let found = item.objectName === name ? [item] : [];
                for (const child of item.children || [])
                    found = found.concat(namedAll(child, name));
                return found;
            }
            function coloredAt(image, x, y) {
                for (let row = Math.max(0, y - 3); row <= Math.min(image.height - 1, y + 3); row++) {
                    const color = image.pixel(x, row);
                    if (Math.max(color.r, color.g, color.b) - Math.min(color.r, color.g, color.b) > 0.03)
                        return true;
                }
                return false;
            }
            function midnightLines(graph) {
                const midnight = Weather.allHours.find(hour => hour.at === graph.end);
                check(!!midnight, "fixture includes the next midnight forecast");
                for (const plot of namedAll(graph, "plot")) {
                    const key = plot.parent.parent.modelData.key;
                    const position = plot.mapToItem(popup, 0, 0);
                    const x = Math.round(position.x + plot.width) - 1;
                    const y = Math.round(position.y + 2 + (plot.high - midnight[key]) / (plot.high - plot.low) * (plot.height - 4));
                    const image = grabImage(popup);
                    check(coloredAt(image, x, y), key + " curve reaches the next day's midnight point at the plot edge");
                }
            }
            function joinedLines(reel, outgoing, incoming) {
                const earlier = outgoing.start < incoming.start ? outgoing : incoming;
                const later = earlier === outgoing ? incoming : outgoing;
                if (earlier.end !== later.start)
                    return;
                const slide = findChild(popup, "slide");
                slide.pause();
                wait(30);
                const image = grabImage(popup);
                for (const plot of namedAll(earlier, "plot")) {
                    const key = plot.parent.parent.modelData.key;
                    const position = plot.mapToItem(popup, 0, 0);
                    const seam = Math.round(position.x + plot.width);
                    const y = Math.round(position.y + 2 + (plot.high - later.hours[0][key]) / (plot.high - plot.low) * (plot.height - 4));
                    for (const offset of [-1, 0, 1])
                        check(coloredAt(image, seam + offset, y), key + " curve stays unbroken across the moving day seam");
                }
                slide.resume();
            }
            function missingMidnight(graph) {
                const image = grabImage(popup);
                for (const plot of namedAll(graph, "plot")) {
                    const key = plot.parent.parent.modelData.key;
                    const last = graph.hours[graph.hours.length - 1];
                    const position = plot.mapToItem(popup, 0, 0);
                    const x = Math.round(position.x + plot.width) - 1;
                    const y = Math.round(position.y + 2 + (plot.high - last[key]) / (plot.high - plot.low) * (plot.height - 4));
                    check(!coloredAt(image, x, y), key + " curve does not invent a midnight sample");
                }
            }
            function day(date, at, temperature) {
                return {date: date, high: temperature, low: temperature - 5, rain: 0, icon: "",
                    hours: Array.from({length: 24}, (_, i) => ({at: at + i * 3600,
                        time: i + ":00", temperature: temperature, feelsLike: temperature - 2,
                        wind: 10, windDirection: 0, rain: 0, icon: "", severity: 0, description: "Clear"}))};
            }
            function moving(reel, direction, oldDate, newDate) {
                const outgoing = named(reel, "outgoing"), incoming = named(reel, "incoming");
                check(reel.progress > 0 && reel.progress < 1, "day change animates between endpoints");
                check(reel.direction === direction, "slide follows date order");
                check(reel.displayedDay.date === oldDate && reel.incomingDay.date === newDate, "both day forecasts survive during the slide");
                check(direction * outgoing.contentOffset < 0 && direction * incoming.contentOffset > 0, "old day exits as new day enters from the opposite edge");
                check(Math.abs(Math.abs(incoming.contentOffset - outgoing.contentOffset) - outgoing.plotWidth) < 0.01, "plots form a continuous reel with no gap");
                check(outgoing.x === 0 && incoming.x === 0, "graph frames stay in place");
                const title = named(outgoing, "seriesTitle"), tick = named(outgoing, "axisTick");
                const titlePosition = title.mapToItem(reel, 0, 0), tickPosition = tick.mapToItem(reel, 0, 0);
                check(title.visible && tick.visible && !named(incoming, "seriesTitle").visible && !named(incoming, "axisTick").visible, "one stationary set of Y-axis labels is visible");
                const outgoingPlot = named(outgoing, "plot"), incomingPlot = named(incoming, "plot");
                check(outgoingPlot.parent.clip && outgoingPlot.parent.x === outgoing.plotLeft, "plot viewport clips moving data away from the axes");
                check(outgoingPlot.low === incomingPlot.low && outgoingPlot.high === incomingPlot.high, "both forecasts share the stationary axis scale");
                check(outgoing.implicitHeight === incoming.implicitHeight, "forecast rows remain aligned across different day ranges");
                wait(70);
                check(title.mapToItem(reel, 0, 0).x === titlePosition.x && title.mapToItem(reel, 0, 0).y === titlePosition.y, "Y-axis legend does not move during the slide");
                check(tick.mapToItem(reel, 0, 0).x === tickPosition.x && tick.mapToItem(reel, 0, 0).y === tickPosition.y, "Y-axis tick labels do not move during the slide");
                check(reel.clip && !outgoing.enabled && !incoming.enabled, "moving graphs stay clipped and ignore hover");
                check(reel.height > 0 && Number.isFinite(reel.height), "transition retains a valid popup height");
                joinedLines(reel, outgoing, incoming);
            }
            function settled(reel, date) {
                wait(420);
                check(reel.displayedDay.date === date && reel.incomingDay === null && reel.progress === 0, "slide settles on the selected date");
                check(named(reel, "outgoing").contentOffset === 0 && named(reel, "outgoing").enabled, "settled graph restores position and hover");
            }
            function run() {
                Weather.location = {label: "Fixture", latitude: 0, longitude: 0, timezone: "UTC"};
                Weather.now = 10000;
                Weather.updatedAt = 10000;
                Weather.days = [day("2026-10-08", 0, 20), day("2026-10-09", 86400, 40), day("2026-10-10", 172800, 15)];
                popup.choosing = false;
                wait(60);
                const reel = named(popup, "reel");
                check(reel.displayedDay.date === "2026-10-08" && reel.progress === 0, "initial day appears without sliding");
                midnightLines(named(reel, "outgoing"));
                Weather.feelsLike = true;
                wait(40);
                midnightLines(named(reel, "outgoing"));
                Weather.feelsLike = false;
                wait(40);
                clickDay(1);
                moving(reel, 1, "2026-10-08", "2026-10-09");
                settled(reel, "2026-10-09");
                clickDay(0);
                moving(reel, -1, "2026-10-09", "2026-10-08");
                settled(reel, "2026-10-08");
                clickDay(1);
                clickDay(2);
                wait(760);
                check(reel.displayedDay.date === "2026-10-10" && reel.incomingDay === null, "rapid clicks settle on the latest selection");
                clickDay(0);
                settled(reel, "2026-10-08");
                const refreshed = day("2026-10-08", 0, 22);
                Weather.days = [refreshed].concat(Weather.days.slice(1));
                wait(60);
                check(reel.displayedDay === refreshed && reel.incomingDay === null, "same-date refresh updates without sliding");
                clickDay(0);
                check(reel.incomingDay === null, "clicking the selected day does not slide");
                Weather.now = 86400;
                // Midnight clock and forecast replacement may land in the same event loop.
                Weather.days = Weather.days.slice(1);
                wait(70);
                moving(reel, 1, "2026-10-08", "2026-10-09");
                settled(reel, "2026-10-09");
                popup.picked = "2026-10-10";
                wait(70);
                popup.choosing = true;
                wait(60);
                check(reel.incomingDay === null && reel.progress === 0, "location picker cancels hidden transitions");
                popup.choosing = false;
                wait(60);
                check(reel.displayedDay.date === "2026-10-10" && reel.progress === 0, "returning from the picker shows the selected day immediately");
                popup.choosing = true;
                Weather.now = 10000;
                const missing = day("2026-10-09", 86400, 20);
                for (const key of ["temperature", "feelsLike", "rain", "wind"])
                    missing.hours[0][key] = null;
                Weather.days = [day("2026-10-08", 0, 20), missing];
                popup.picked = "";
                wait(40);
                popup.choosing = false;
                wait(60);
                missingMidnight(named(reel, "outgoing"));
                missing.hours = missing.hours.slice(1);
                Weather.days = [Weather.days[0], missing];
                wait(60);
                missingMidnight(named(reel, "outgoing"));
                console.log("PASS: weather reel, continuous curves, fixed axes, rapid clicks, refresh and midnight rollover");
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}
''')
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        return 0 if result.returncode == 0 and "PASS: weather reel" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
