#!/usr/bin/env python3
"""Exercise wake recovery and changed QML state paths without desktop actions."""

import os
from pathlib import Path
import re
import selectors
import time
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

TEST = '''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking as NM
import qs.services
import qs.components
ShellRoot {
    id: test
    property int wakes: 0
    property int runs: 0
    property var api: TestApi
    property var night: NightMode
    property var sys: Sys
    property var keyboard: Keyboard
    property var notifications: Notifications
    property var network: Network
    property var library: Library
    property var agenda: Agenda
    property var wallpaper: Wallpaper
    property var updates: Updates
    property int checksBeforeLog: 0
    Connections { target: WallClock; function onWokeUp() { test.wakes++; } }
    QtObject { id: radio; property bool scannerEnabled: false; property int type: NM.DeviceType.Wifi; property var networks: ({values: []}) }
    QtObject { id: radio2; property bool scannerEnabled: false; property int type: NM.DeviceType.Wifi; property var networks: ({values: []}) }
    QtObject { id: notice; property int id: 42; signal closed }
    QueuedProcess {
        id: job
        interval: 1
        command: ["sh", "-c", "sleep 0.03; printf '%s' \\\"$1\\\"", "fixture", arg]
        onResult: (arg, text) => {
            test.runs++;
            check(arg === "same" && text === "same", "cancel preserves in-flight result identity");
        }
    }
    FilePreview { id: preview }
    FileView { id: packageLog; path: LOG_PATH; printErrors: false }
    function check(ok, why) { if (!ok) throw Error(why); }
    function run() {
        try {
            const initial = WallClock.now;
            WallClock.sample(initial + 60000);
            check(wakes === 0, "ordinary minute is not a wake");
            Google.configured = true;
            WallClock.sample(initial + 3600000);
            check(wakes === 1 && TestApi.fetches === 1, "clock jump refreshes Google services");
            Google.needsConsent = true;
            TestApi.loaded = true;
            check(TestApi.stale, "expired consent dims cached counts");
            WallClock.sample(initial + 7200000);
            check(TestApi.fetches === 1, "wake respects expired consent");
            Google.needsConsent = false;
            Sys.gpuPresent = false;
            Sys.watchers = 1;
            check(Sys.gpuPresent, "reopening popup permits another GPU probe");
            Sys.watchers = 0;
            Library.loaded = true;
            Library.loading = true;
            Mpd.connected = true;
            check(!Library.loaded && Library.stale, "MPD reconnect invalidates cached and in-flight library");
            Library.loading = false;
            Library.stale = false;
            Network.watchers = 1;
            Network.devices = [radio];
            check(radio.scannerEnabled, "a replacement Wi-Fi device starts scanning");
            Network.devices = [radio2];
            check(radio2.scannerEnabled, "scanning follows a recreated device");
            Network.watchers = 0;
            check(!radio2.scannerEnabled, "closing popup stops scanning");
            Keyboard.mainKeyboard = "old-keyboard";
            const queries = Keyboard.testRefreshes;
            FakeHyprland.rawEvent({name: "activelayout", parse: count => ["new-keyboard", "English (US)"]});
            check(Keyboard.testRefreshes > queries, "layout event from a different keyboard rechecks main device");
            Google.today = "2026-09-30";
            Agenda.months = ({"2026-09": {"2026-10-01": [{title: "October event"}]}});
            Google.today = "2026-10-01";
            check(Agenda.todays[0]?.title === "October event", "month rollover uses already fetched adjacent events");
            Notifications.arrived[42] = Date.now() - 3600000;
            Notifications.remember(notice);
            check(Notifications.ago(notice, Date.now()) === "1h", "restored notification retains its age");
            notice.closed();
            check(Notifications.arrived[42] === undefined, "restored notification still prunes its timestamp");
            check(NightMode.brightness === 30, "startup reads real brightness");
            NightMode.setBrightness(50);
            preview.front = shot;
            preview.next = broken;
            preview.landed(broken);
            check(!preview.front && !preview.next, "failed image removes previous preview");
            job.want = "same";
            next.restart();
        } catch (error) { fail(error); }
    }
    QtObject { id: shot }
    QtObject { id: broken; property int status: Image.Error }
    Timer { interval: 150; running: true; onTriggered: test.run() }
    Timer {
        id: next
        interval: 10
        onTriggered: {
            try {
                check(job.running, "query is in flight");
                job.cancel();
                job.want = "same";
                finish.restart();
            } catch (error) { test.fail(error); }
        }
    }
    Timer {
        id: finish
        interval: 200
        onTriggered: {
            try {
                check(runs === 2, "cancelled identical query runs again after old process exits");
                check(NightMode.committed === 50 && NightMode.brightness === 50, "slider calculates step from startup level");
                job.cancel();
                job.want = "same";
                finalCheck.restart();
            } catch (error) { test.fail(error); }
        }
    }
    Timer {
        id: finalCheck
        interval: 100
        onTriggered: {
            try {
                check(runs === 3, "completed query also runs again after cancellation");
                Wallpaper.current = "fixture-wallpaper";
                Wallpaper.files = ["fixture-wallpaper"];
                Wallpaper.restored = true;
                Wallpaper.hour = -1;
                WallClock.wokeUp();
                check(Math.abs(Wallpaper.hour - Wallpaper.hourNow()) < 0.02 && Wallpaper.current === "fixture-wallpaper", "wake updates wallpaper time while preserving the image");
                measureCheck.restart();
            } catch (error) { test.fail(error); }
        }
    }
    Timer {
        id: measureCheck
        interval: 300
        onTriggered: {
            try {
                // The stubbed identify prints nothing, like one that cannot read the file.
                check(Wallpaper.measuredPath === "fixture-wallpaper" && Wallpaper.currentSize.width === 0, "a size magick cannot read still counts as measured");
                Wallpaper.setColor("#112233");
                Wallpaper.setDrift(true);
                Wallpaper.hour = -1;
                WallClock.wokeUp();
                wallpaperCheck.restart();
            } catch (error) { test.fail(error); }
        }
    }
    Timer {
        id: wallpaperCheck
        interval: 300
        onTriggered: {
            try {
                check(Wallpaper.color === "#112233" && Wallpaper.lastColor === "#112233" && Wallpaper.current === "", "colour selection remains consistent after wake");
                check(Wallpaper.onScreen === String(Wallpaper.drifted(Wallpaper.color, Wallpaper.hour)), "wake refreshes the drifting wallpaper colour");
                checksBeforeLog = Updates.testRefreshes;
                packageLog.setText("fixture package transaction finished\\n");
                packageCheck.restart();
            } catch (error) { test.fail(error); }
        }
    }
    Timer {
        id: packageCheck
        interval: 2300
        onTriggered: {
            try {
                check(Updates.testRefreshes > checksBeforeLog, "package log changes refresh update count");
                console.log("PASS: wake, brightness, GPU, Wi-Fi, keyboard, MPD, agenda, notification ages, queries, previews, wallpaper and packages");
                Qt.quit();
            } catch (error) { test.fail(error); }
        }
    }
    function fail(error) { console.log("FAIL: " + error + "\\n" + error.stack); Qt.quit(); }
}
'''



HOT_RELOAD = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    property var service: Notifications
    PersistentProperties { id: stage; reloadableId: "age-test"; property bool saved: false }
    QtObject { id: notice; property int id: 123; signal closed }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            if (!stage.saved) {
                Notifications.arrived[123] = Date.now() - 3600000;
                Notifications.remember(notice);
                stage.saved = true;
                console.log("READY: reload notification ages");
            } else {
                if (Notifications.ago(notice, Date.now()) === "1h")
                    console.log("PASS: notification age survives actual hot reload");
                else
                    console.log("FAIL: notification age reset on hot reload");
                Qt.quit();
            }
        }
    }
}
"""


def hot_reload(target, env):
    """Force Quickshell to reload and check the restored arrival metadata."""
    shell = target / "shell.qml"
    shell.write_text(HOT_RELOAD)
    process = subprocess.Popen(["qs", "-p", str(target), "--no-color"], env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    output = []
    reloaded = False
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if not selector.select(timeout=0.5):
                continue
            chunk = os.read(process.stdout.fileno(), 65536).decode()
            if not chunk:
                break
            output.append(chunk)
            print(chunk, end="", flush=True)
            text = "".join(output)
            if "READY:" in text and not reloaded:
                shell.write_text(HOT_RELOAD + "\n// Force the reload.\n")
                reloaded = True
            if "PASS:" in text or "FAIL:" in text:
                break
        try:
            tail, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.terminate()
            tail, _ = process.communicate(timeout=2)
        output.append(tail.decode())
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
    text = "".join(output)
    print(tail.decode(), end="")
    return 0 if "PASS: notification age survives" in text and "Reloading configuration" in text and "FAIL:" not in text and "TypeError:" not in text else 1


def main():
    with tempfile.TemporaryDirectory(prefix="qs-recovery-") as folder:
        target = Path(folder)
        services = target / "services"
        components = target / "components"
        services.mkdir()
        components.mkdir()
        log_path = target / "pacman.log"
        log_path.write_text("fixture initial log\n")
        display = target / "display.sh"
        level = target / "brightness"
        display.write_text(f'''#!/bin/sh
case "$1" in
get) echo 30;;
up) echo "$((30 + $2))" > '{level}';;
down) echo "$((30 - $2))" > '{level}';;
esac
''')
        display.chmod(0o700)
        for name in ("WallClock", "Retry", "GoogleService", "Agenda", "NightMode", "Sys", "Library", "Network", "Keyboard", "Notifications", "Wallpaper", "Updates"):
            source = (ROOT / f"services/{name}.qml").read_text()
            if name == "Agenda":
                source = source.replace('    service: "Calendar"', '    polling: false\n    service: "Calendar"')
            elif name == "NightMode":
                source = source.replace('"/tmp/flag-brightness"', repr(str(level)).replace("'", '"'))
                source = source.replace('"/tmp/flag-night-mode"', repr(str(target / "night")).replace("'", '"'))
            elif name in ("Sys", "Library", "Keyboard", "Wallpaper"):
                source = re.sub(r"^(\s*)command:.*$", r'\1command: ["/usr/bin/true"]', source, flags=re.M)
                if name == "Keyboard":
                    source = source.replace('target: Hyprland', 'target: FakeHyprland')
                    source = source.replace('    function refresh() {', '    property int testRefreshes: 0\n    function refresh() {\n        root.testRefreshes++;')
                elif name == "Wallpaper":
                    source = source.replace('Quickshell.execDetached(["hyprctl",', 'Quickshell.execDetached(["/usr/bin/true",')
            elif name == "Updates":
                source = re.sub(r"^(\s*)command:.*$", r'\1command: ["/usr/bin/true"]', source, flags=re.M)
                source = source.replace('"/var/log/pacman.log"', '"' + str(log_path) + '"')
                source = source.replace('    property int official: 0', '    property int testRefreshes: 0\n    property int official: 0')
                source = source.replace('root.checksRemaining = 2;', 'root.checksRemaining = 2;\n        root.testRefreshes++;')
            elif name == "Network":
                source = source.replace('readonly property var devices: NM.Networking.devices.values', 'property var devices: []')
            (services / f"{name}.qml").write_text(source)
        (services / "TestApi.qml").write_text('pragma Singleton\nimport QtQuick\nGoogleService { property int fetches: 0; onFetch: fetches++ }\n')
        (services / "FakeHyprland.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { signal rawEvent(var event) }\n')
        (services / "Google.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool configured: false
    property bool needsConsent: false
    property string today: "2026-09-30"
    property date now: new Date(2026, 8, 30)
    property string reconnect: "Google needs reconnecting"
    signal ready
    function authorised(then, fail) { then(); }
    function send(method, url, body, then, fail) { then({items: []}); }
    function dayString(date) { return Qt.formatDate(date, "yyyy-MM-dd"); }
}
''')
        (services / "Mpd.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: false; signal databaseChanged }\n')
        (target / "Fuzzy.js").write_text((ROOT / "Fuzzy.js").read_text())
        (target / "Settings.qml").write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ property var layoutNames: ({{}}); property string wallpaperDir: "{target}"; function moduleOn(name) {{ return name === "updater"; }} }}\n')
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property color tint: "black"; property color backdrop: "black"; property var glyph: ({notif: "", notifDnd: "", nightOn: "", nightOff: "", wifiOff: "", wired: "", wifiStrength: [""], folder: "", file: "", update: ""}); property int fadeMs: 1; property int previewFontSize: 12; property string monoFont: "monospace"; property color menuText: "white"; property int previewTextSize: 12; property color label2: "grey"; property color label: "white"; property int iconSize: 16; property real glyphInk: 1 }\n')
        (target / "Paths.qml").write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ function state(name) {{ return "{target}/" + name; }} function cache(name) {{ return "{target}/" + name; }} function script(name) {{ return "{display}"; }} }}\n')
        (target / "OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
        for name in ("QueuedProcess", "FilePreview"):
            (components / f"{name}.qml").write_text((ROOT / f"components/{name}.qml").read_text())
        (components / "Glyph.qml").write_text('import QtQuick\nItem { property string text: ""; property int fontSize: 16; property color color: "white" }\n')
        (target / "scripts").mkdir()
        thumbs = target / "scripts/wallpaper-thumbs"
        thumbs.write_text("#!/bin/sh\nexit 0\n")
        thumbs.chmod(0o700)
        # Keep the real failed-image handler while substituting status fixtures.
        preview = (components / "FilePreview.qml").read_text().replace('property Image front:', 'property var front:').replace('property Image next:', 'property var next:')
        (components / "FilePreview.qml").write_text(preview)
        (target / "shell.qml").write_text(TEST.replace('LOG_PATH', '"' + str(log_path) + '"'))
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output, end="")
        if result.returncode != 0 or 'PASS: wake' not in output or any(error in output for error in ('FAIL:', 'ReferenceError:', 'TypeError:')):
            return 1
        return hot_reload(target, env)


if __name__ == "__main__":
    raise SystemExit(main())
