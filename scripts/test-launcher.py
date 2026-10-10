#!/usr/bin/env python3
"""Exercise launcher discovery and dispatch with desktop services isolated."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

MOCKS = {
    "Audio": '''property bool muted: false
        property var sink: ({audio: {}})
        property string icon: "sound"
        function toggleMute() { muted = !muted; }''',
    "NightMode": '''property bool on: false
        property string icon: "display"
        function toggle() { on = !on; }''',
    "Network": '''property bool wifiOn: true
        property var wifi: ({})
        property string icon: "network"
        function toggleWifi() { wifiOn = !wifiOn; }''',
    "Bluetooth": '''property bool present: true
        property bool on: true
        property string icon: "bluetooth"
        property var devices: []
        property int activations: 0
        function toggle() { on = !on; }
        function activate(device) {
            activations++;
            if (device.connected) device.disconnect();
            else device.connect();
        }''',
    "Notifications": '''property bool dnd: false
        property string icon: "notifications"
        function setDnd(value) { dnd = value; }''',
    "Power": '''property var armed: null
        property var actions: [{key: "shutdown", label: "shut down", glyph: "power", arg: "--poweroff", confirm: true}]
        function arm(action) { armed = action; }
        function run(arg) { throw new Error("Unexpected power action: " + arg); }''',
    "LauncherMusic": '''property var rows: []
        property string activated: ""
        function cancel() {}
        function route(inMode, rest) {}
        function results(query) { return rows; }
        function activate(row, mode) { activated = mode; return false; }''',
    "Email": '''property var threads: []
        property bool configured: true
        property bool loaded: true
        property bool loading: false
        property string trouble: ""
        property var bodies: ({})
        property var found: null
        function sayWhen(at) { return "10:00"; }
        property int searches: 0
        function search(query, all) { searches++; }''',
    "Tasks": '''property bool configured: false
        property string syntax: "task text"
        property var ordered: []''',
    "Timers": '''property var entries: []
        property string syntax: "25m or 7:30"
        function parse(text) { return {ok: !!text, kind: text.includes(":") ? "alarm" : "countdown"}; }
        function brief(text) { return text; }''',
    "Google": 'property string setup: "test-sign-in"',
}

TEST = '''import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import qs
import qs.services

ShellRoot {
    id: test
    property string adopted: ""
    property var launcher: Launcher

    QtObject {
        id: headphones
        property string address: "AA:BB:CC:DD:EE:01"
        property string name: "Sony WH-1000XM5"
        property string icon: "audio-headset"
        property bool paired: true
        property bool connected: false
        property bool pairing: false
        property int state: BlueZ.BluetoothDeviceState.Disconnected
        function connect() { state = BlueZ.BluetoothDeviceState.Connecting; }
        function disconnect() { state = BlueZ.BluetoothDeviceState.Disconnecting; }
    }
    QtObject {
        id: keyboard
        property string address: "AA:BB:CC:DD:EE:02"
        property string name: "Desk keyboard"
        property string icon: "input-keyboard"
        property bool paired: true
        property bool connected: true
        property bool pairing: false
        property int state: BlueZ.BluetoothDeviceState.Connected
    }

    Connections {
        target: Launcher
        function onQueryReplaced(text) { test.adopted = text; }
    }

    function check(ok, message) {
        if (!ok) throw new Error(message);
    }
    function desktop(key) {
        return Launcher.desktopMatches([]).find(x => x.row.action.key === key)?.row;
    }
    function activateDesktop(key) {
        Launcher.query = desktop(key).title;
        const at = Launcher.results.findIndex(r => r.kind === "desktop" && r.action.key === key);
        check(at >= 0, "searchable desktop action " + key);
        Launcher.activate(at);
    }

    function bluetoothRow() {
        return Launcher.results.find(r => r.kind === "bluetooth" && r.address === headphones.address);
    }
    function activateHeadphones() {
        const at = Launcher.results.findIndex(r => r.kind === "bluetooth" && r.address === headphones.address);
        check(at >= 0, "headphones are searchable");
        Launcher.activate(at);
    }

    function checkBluetooth() {
        Bluetooth.devices = [headphones, keyboard];
        Bluetooth.on = true;
        Launcher.show();
        for (const query of ["Sony", "WH-1000", "headphones", "connect headphones", "disconnect headphones", "bluetooth"]) {
            Launcher.query = query;
            check(bluetoothRow()?.title === "Connect Sony WH-1000XM5", "device alias " + query);
        }
        Launcher.query = "headphones";
        check(!Launcher.results.some(r => r.kind === "bluetooth" && r.address === keyboard.address), "headphone alias excludes keyboards");
        Settings.disabled = ({bluetooth: true});
        check(!!bluetoothRow(), "device action works independently of bar module");
        Settings.disabled = ({});
        Launcher.query = "bluetooth";
        const deviceOrder = Launcher.results.filter(r => r.kind === "bluetooth").map(r => r.address).join(",");
        Launcher.index = Launcher.results.findIndex(r => r.kind === "bluetooth" && r.address === headphones.address);
        const staleConnect = bluetoothRow();
        Launcher.activate(Launcher.index);
        check(Bluetooth.activations === 1 && headphones.state === BlueZ.BluetoothDeviceState.Connecting && Launcher.shown, "connect delegates and keeps launcher open");
        check(bluetoothRow().subtitle.includes("Connecting…"), "connecting state shown without typing");
        check(Launcher.selected?.address === headphones.address, "busy device stays selected");
        Launcher.activate(Launcher.index);
        check(Bluetooth.activations === 1, "connecting ignores repeated activation");
        headphones.connected = true;
        headphones.state = BlueZ.BluetoothDeviceState.Connected;
        check(bluetoothRow().title === "Disconnect Sony WH-1000XM5", "connected device updates action without typing");
        check(Launcher.selected?.address === headphones.address && Launcher.results.filter(r => r.kind === "bluetooth").map(r => r.address).join(",") === deviceOrder, "connection keeps device order and selection");
        Launcher.actions.bluetooth(staleConnect, 0);
        check(Bluetooth.activations === 1, "stale connect cannot disconnect device");
        const staleDisconnect = bluetoothRow();
        Launcher.query = "disconnect headphones";
        activateHeadphones();
        check(Bluetooth.activations === 2 && headphones.state === BlueZ.BluetoothDeviceState.Disconnecting && Launcher.shown, "disconnect delegates and keeps launcher open");
        check(bluetoothRow().subtitle.includes("Disconnecting…"), "disconnect query retains busy row");
        activateHeadphones();
        check(Bluetooth.activations === 2, "disconnecting ignores repeated activation");
        headphones.connected = false;
        headphones.state = BlueZ.BluetoothDeviceState.Disconnected;
        check(bluetoothRow().title === "Connect Sony WH-1000XM5", "disconnected device updates action");
        Launcher.actions.bluetooth(staleDisconnect, 0);
        check(Bluetooth.activations === 2, "stale disconnect cannot reconnect device");
        headphones.pairing = true;
        activateHeadphones();
        check(Bluetooth.activations === 2, "pairing device ignores activation");
        headphones.pairing = false;
        headphones.paired = false;
        check(!bluetoothRow(), "unpaired device excluded");
        Launcher.actions.bluetooth(staleConnect, 0);
        check(Bluetooth.activations === 2, "stale row cannot pair a device");
        headphones.paired = true;
        Bluetooth.devices = [keyboard];
        check(!bluetoothRow(), "removed device disappears");
        Launcher.actions.bluetooth(staleConnect, 0);
        check(Bluetooth.activations === 2, "removed device ignored");
        Bluetooth.devices = [headphones, keyboard];
        Bluetooth.present = false;
        check(!bluetoothRow(), "missing adapter excludes devices");
        Launcher.actions.bluetooth(staleConnect, 0);
        check(Bluetooth.activations === 2, "missing adapter ignores stale action");
        Bluetooth.present = true;
        Bluetooth.on = false;
        for (const query of ["headphones", "Sony"]) {
            Launcher.query = query;
            check(!bluetoothRow(), "powered-off device excluded");
            check(Launcher.results.some(r => r.kind === "desktop" && r.action.key === "bluetooth-power"), "power-on offered for " + query);
        }
        Launcher.actions.bluetooth(staleConnect, 0);
        check(Bluetooth.activations === 2, "powered-off adapter ignores stale action");
        activateDesktop("bluetooth-power");
        check(Bluetooth.on && Launcher.shown, "power-on keeps launcher open");
        Launcher.query = "Sony";
        check(!!bluetoothRow(), "device appears after power-on");
        activateHeadphones();
        headphones.state = BlueZ.BluetoothDeviceState.Disconnected;
        check(bluetoothRow().title === "Connect Sony WH-1000XM5" && bluetoothRow().subtitle.includes("Disconnected"), "failed connection returns to disconnected");
        activateHeadphones();
        check(Bluetooth.activations === 4, "failed connection can be retried");
        headphones.state = BlueZ.BluetoothDeviceState.Disconnected;
        Bluetooth.devices = [];
        check(!bluetoothRow(), "empty device list has no action");
    }

    function run() {
        try {
            check(Launcher.results.length === 0, "a closed launcher computes nothing");
            Launcher.show();
            LauncherMusic.rows = [{kind: "music", title: "first"}, {kind: "music", title: "last"}];
            Launcher.query = "#";
            Launcher.index = 1;
            LauncherMusic.rows = LauncherMusic.rows.slice(0, 1);
            check(Launcher.index === 0 && Launcher.selected.title === "first", "selection clamps when rows disappear");
            Launcher.mailOpen = {message: "new", messages: [{id: "old", from: "Ann", at: 1}, {id: "new", from: "Bob", at: 2}]};
            Email.bodies = ({old: "earlier reply", new: "latest reply"});
            check(Launcher.mailText.includes("earlier reply") && Launcher.mailText.includes("latest reply"), "reader shows unread conversation");
            Launcher.mailOpen = null;
            Launcher.db = ({});
            Email.found = null;
            check(Launcher.mailResults("")[0].title === "reading inbox...", "bare mail query reports pending inbox");
            Email.found = {q: Launcher.recentMail, rows: [], trouble: "mail fetch failed"};
            check(Launcher.mailResults("")[0].title === "mail fetch failed", "bare mail query reports failed inbox");
            Email.found = {q: Launcher.recentMail, rows: [], trouble: ""};
            Email.loading = true;
            check(Launcher.mailResults("")[0].title === "reading inbox...", "cached empty inbox stays marked while reloading");
            Email.loading = false;
            Email.trouble = "Google needs reconnecting";
            check(Launcher.mailResults("")[0].title === Email.trouble, "cached empty inbox shows expired sign-in");
            Email.trouble = "";
            Launcher.rankingNow = Date.now();
            Launcher.db = ({aged: {count: 2, last: Launcher.rankingNow}});
            check(Launcher.frecency("aged") === 8, "recent launch weight");
            Launcher.rankingNow += 25 * 3600000;
            check(Launcher.frecency("aged") === 2, "ranking decays when clock advances");
            Launcher.db = ({});
            Launcher.show();
            check(!Launcher.results.some(r => r.kind === "desktop"), "no unused desktop actions on home");
            check(!Launcher.results.some(r => r.kind === "mode"), "modes stay in the hint line, not the list");
            check(Launcher.results.some(r => r.kind === "app"), "home opens full of apps without history");
            check(!Launcher.results.some(r => r.kind === "power"), "no power actions on home");
            check(Launcher.noteRow("g", "title").subtitle === "", "note rows default to no subtitle");
            const stableResults = Launcher.results;
            Audio.icon = "different-volume";
            Network.icon = "different-signal";
            check(Launcher.results === stableResults, "volume and network icons do not rebuild launcher results");
            Email.found = {q: Launcher.recentMail, at: Date.now(), rows: [], trouble: ""};
            Launcher.query = "@";
            Launcher.query = "@ ";
            check(Email.searches === 0, "fresh recent-mail search is reused");
            Launcher.query = "%y cats";
            check(Launcher.results[0].badge === "%y", "explicit engine key selects YouTube");
            Launcher.query = "";
            check(!Launcher.results.some(r => r.kind === "desktop"), "no unused toggles on home");

            const popupKeys = ["sound", "display", "network", "bluetooth", "notifications"];
            for (const query of ["", " ", "brightness", "volume", "wifi", "bluetooth", "notifications"]) {
                Launcher.query = query;
                check(!Launcher.results.some(r => r.kind === "desktop" && popupKeys.includes(r.action.key)), "no popover-only actions for " + query);
            }
            for (const [query, key] of [["volume", "mute"], ["wifi", "wifi"], ["bluetooth", "bluetooth-power"], ["dnd", "dnd"], ["night mode", "night"]]) {
                Launcher.query = query;
                check(Launcher.results.some(r => r.kind === "desktop" && r.action.key === key), "alias " + query);
            }
            check(Launcher.classifyQuery(" ").mode === "main", "space retains full app listing");
            for (const mode of Launcher.modes) {
                check(Launcher.classifyQuery(mode.prefix).mode === mode.prefix, "prefix " + mode.prefix);
            }
            Launcher.query = "https://example.com";
            check(Launcher.results[0].kind === "url", "automatic URL precedence");
            Launcher.calcAnswer = {expr: "2+2", text: "4"};
            Launcher.query = "2+2";
            check(Launcher.results[0].kind === "calc", "automatic calculator precedence");

            Launcher.db = ({"desktop:display": {count: 100, last: Date.now()}, "desktop:mute": {count: 10, last: Date.now()}, "desktop:dnd": {count: 2, last: Date.now()}});
            Launcher.query = "";
            check(Launcher.results[0].action.key === "mute", "history ranking");
            check(!Launcher.results.some(r => r.kind === "desktop" && popupKeys.includes(r.action.key)), "old popover history cannot restore removed actions");
            const ids = Launcher.results.filter(r => r.kind === "desktop").map(r => r.action.key);
            check(new Set(ids).size === ids.length, "home actions do not duplicate history");
            const app = Launcher.appIndex.find(a => a.entry.name === "Launcher regression app");
            check(!!app, "fixture desktop app indexed");
            const history = {};
            history[app.entry.id] = {count: 20, last: Date.now()};
            Launcher.db = history;
            check(Launcher.results[0].kind === "app" && Launcher.results[0].entry.id === app.entry.id, "frequent apps included on home");
            Launcher.query = "zzlauncher";
            check(Launcher.results[0].kind === "app", "application matching remains first for exact app keywords");
            Launcher.query = "";
            Settings.disabled = ({night: true});
            check(!!desktop("night"), "direct action works independently of bar module");
            Settings.disabled = ({});
            Bluetooth.present = false;
            check(!desktop("bluetooth") && !desktop("bluetooth-power"), "absent Bluetooth excluded");
            Bluetooth.present = true;
            Network.wifi = null;
            check(!desktop("wifi"), "Wi-Fi action unavailable without Wi-Fi device");
            Network.wifi = ({});
            Audio.sink = null;
            check(!desktop("mute"), "mute unavailable without audio");
            Audio.sink = ({audio: {}});

            Launcher.show();
            activateDesktop("mute");
            check(Audio.muted && !Launcher.shown && desktop("mute").title === "Unmute sound", "mute changes state and label");
            check(Launcher.db["desktop:mute"].count === 1, "action usage recorded");
            Launcher.show();
            activateDesktop("dnd");
            check(Notifications.dnd && desktop("dnd").title.endsWith("off"), "DND changes state and label");
            Launcher.show();
            activateDesktop("night");
            check(NightMode.on, "night action delegates to service");
            Launcher.show();
            activateDesktop("wifi");
            check(!Network.wifiOn, "Wi-Fi action delegates to service");
            Launcher.show();
            activateDesktop("bluetooth-power");
            check(!Bluetooth.on && !Launcher.shown, "Bluetooth power-off delegates and closes");
            checkBluetooth();

            Launcher.db = ({});
            Launcher.show();
            check(!Launcher.results.some(r => r.action), "unused desktop actions stay off home");
            check(!Launcher.appIndex.some(a => a.entry.id === "launcher-hidden"), "hidden apps are not indexed");
            Launcher.query = "regression priv";
            const priv = Launcher.results.findIndex(r => r.kind === "app" && r.action?.name === "Private window");
            check(priv === 0 && Launcher.results[0].subtitle === "Launcher regression app", "desktop action found by app and action name");
            Launcher.activate(priv);
            check(Launcher.db["launcher-regression:private"]?.count === 1 && !Launcher.shown, "desktop action launches and is ranked");
            Launcher.show();
            check(Launcher.results.some(r => r.action?.name === "Private window"), "used desktop action joins home");
            Launcher.db = ({});

            LauncherMusic.rows = [{kind: "music-track", title: "Track", subtitle: ""}];
            Launcher.query = "#track";
            Launcher.activate(0, "queue");
            check(LauncherMusic.activated === "queue" && Launcher.shown, "Enter queues without closing");
            Launcher.activate(0, "play");
            check(LauncherMusic.activated === "play", "Ctrl+Enter play dispatch preserved");

            Launcher.query = "shutdown";
            const off = Launcher.results.findIndex(r => r.kind === "power" && r.action.key === "shutdown");
            check(off >= 0, "existing power search preserved");
            Launcher.index = off;
            Launcher.activate(off);
            check(Power.armed?.key === "shutdown", "power confirmation preserved");

            // The emoji list loads on first use; checkEmoji runs once it has.
            Launcher.db = ({});
            Launcher.show();
            Launcher.query = ":";
        } catch (error) {
            fail(error);
        }
    }

    Connections {
        target: Launcher
        // Later, so the results binding has heard of the list first.
        function onEmojisChanged() { Qt.callLater(test.checkEmoji); }
    }

    function checkEmoji() {
        try {
            check(Launcher.emojis.length > 1000, "emoji list loaded");
            Launcher.query = ":";
            check(Launcher.results.length === Launcher.maxResults && Launcher.results[0].emoji === "😀", "bare emoji mode lists in Unicode order");
            check(Launcher.hint.includes("enter"), "emoji mode has a hint");
            Launcher.query = ":lol";
            check(Launcher.results.slice(0, 5).some(r => r.emoji === "😂"), "keywords find emoji");
            Launcher.query = ":greece";
            check(Launcher.results[0]?.emoji === "🇬🇷", "flags found by country");
            Launcher.query = ":heart";
            check(Launcher.results[0]?.title.includes("heart"), "names outrank keywords");
            Launcher.query = ":lol";
            const joy = Launcher.results.findIndex(r => r.emoji === "😂");
            Launcher.activate(joy);
            check(!Launcher.shown && Launcher.db["emoji:😂"]?.count === 1, "enter picks an emoji and ranks it");
            Launcher.show();
            Launcher.query = ":";
            check(Launcher.results[0].emoji === "😂", "used emoji lead the bare list");
            check(!Launcher.results.slice(1).some(r => r.emoji === "😂"), "used emoji are not listed twice");
            Launcher.query = "/";
            check(Launcher.hint.includes("show in folder"), "file mode hints its keys");

            console.log("PASS: launcher discovery, ranking, prefixes and direct actions");
            Qt.quit();
        } catch (error) {
            fail(error);
        }
    }
    function fail(error) {
        console.log("FAIL: " + error + "\\n" + error.stack);
        Qt.quit();
    }
    Timer { interval: 100; running: true; onTriggered: test.run() }
}
'''


def main():
    """Run the real launcher with mocked services and temporary state."""
    with tempfile.TemporaryDirectory(prefix="quickshell-launcher-test-") as folder:
        target = Path(folder)
        services = target / "services"
        components = target / "components"
        services.mkdir()
        components.mkdir()
        source = (ROOT / "services/Launcher.qml").read_text()
        # Reads of clipboard/history and query helpers stay inside the fixture.
        source = re.sub(r"^(\s*)command:.*?(,?)$", r'\1command: ["/usr/bin/true"]\2', source, flags=re.MULTILINE)
        (services / "Launcher.qml").write_text(source)
        for name, body in MOCKS.items():
            (services / (name + ".qml")).write_text("pragma Singleton\nimport QtQuick\nQtObject {\n" + body + "\n}\n")
        for name in ("Fuzzy.js", "Linger.qml", "data/emoji.tsv"):
            (target / name).parent.mkdir(exist_ok=True)
            (target / name).write_text((ROOT / name).read_text())
        (target / "OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var disabled: ({}); property var hiddenApps: ["launcher-hidden"]; property string home: "/tmp"; function screenOn(name) { return true; } function moduleOn(key) { return !disabled[key]; } function expand(path) { return path; } }\n')
        (target / "Paths.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function state(name) { return Quickshell.shellPath("state/" + name); } function script(name) { return "/tmp/unused/" + name; } }\n')
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property int zipTotalMs: 50; property int revealMs: 10; property var glyph: ({lock: "", alarm: "", timer: "", tasks: "", vol: ["sound"], wifiStrength: ["network"]}) }\n')
        (components / "QueuedProcess.qml").write_text('import QtQuick\nQtObject { property string want: ""; property string arg: ""; property int interval: 60; property var command: []; signal result(arg: string, text: string); function cancel() { want = ""; } }\n')
        (target / "shell.qml").write_text(TEST)
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        applications = target / "data/applications"
        applications.mkdir(parents=True)
        (applications / "launcher-regression.desktop").write_text("[Desktop Entry]\nType=Application\nName=Launcher regression app\nKeywords=zzlauncher;\nExec=/usr/bin/true\nActions=private;\n\n[Desktop Action private]\nName=Private window\nExec=/usr/bin/true\n")
        (applications / "launcher-hidden.desktop").write_text("[Desktop Entry]\nType=Application\nName=Launcher hidden app\nExec=/usr/bin/true\n")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"), XDG_DATA_HOME=str(target / "data"))
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        return 0 if result.returncode == 0 and "PASS: launcher discovery" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
