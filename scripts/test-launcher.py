#!/usr/bin/env python3
"""Exercise launcher discovery and dispatch with desktop services isolated."""

import ast
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]

MOCKS = {
    "Hyprland": '''property var toplevels: ({values: []})
        function dispatch(command) { throw new Error("Unexpected window activation: " + command); }''',
    "AppIcons": 'function resolve(windowClass, entry) { return ""; }',
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
        readonly property string web: "https://mail.google.com/mail/u/0/"
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
        function parse(text) { return Parse.parse(text); }
        function brief(text) { return text; }''',
    "Google": 'property string setup: "test-sign-in"',
}

TEST = '''import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import QtTest
import qs
import qs.services

ShellRoot {
    id: test
    property string adopted: ""
    property var launcher: Launcher
    TestCase { id: fileKeys; when: false }

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
            const directPath = Quickshell.env("LAUNCHER_TEST_PATH");
            Launcher.pathCache = [];
            Launcher.query = directPath;
            fileKeys.wait(400);
            check(Launcher.results[0]?.kind === "path" && Launcher.results[0].path === directPath, "absolute file outside home is actionable without history");
            Launcher.activate(0);
            fileKeys.wait(200);
            check(!Launcher.shown, "opening an absolute file closes the launcher");
            Launcher.show();
            for (const [query, path, dir] of [
                [directPath + ".missing", "", false],
                [Quickshell.env("LAUNCHER_TEST_SPACED_PATH"), Quickshell.env("LAUNCHER_TEST_SPACED_PATH"), false],
                [Settings.home + "/", Settings.home, true],
                ["~/notes.txt", Settings.home + "/notes.txt", false],
                ["/ notes", Settings.home + "/notes.txt", false]
            ]) {
                Launcher.query = query;
                fileKeys.wait(400);
                if (path)
                    check(Launcher.results[0]?.path === path && Launcher.results[0].dir === dir, "direct path lookup " + query);
                else
                    check(!Launcher.results.some(row => row.path === directPath), "missing file cannot reuse a stale exact result");
            }
            check(Launcher.classifyQuery("/ notes").text === "notes", "explicit file search still strips its prefix");
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
            Hyprland.toplevels = {values: [{title: "Firefox test window", address: "123", workspace: {id: 1, name: "1"}, lastIpcObject: {class: "firefox"}}]};
            for (const query of ["_", "_firefox", "_ firefox", "  _firefox", "_\tFirefox"]) {
                check(Launcher.classifyQuery(query).mode === Launcher.windowPrefix, "explicit window mode " + query);
            }
            check(Launcher.classifyQuery("_ firefox").text === "firefox", "explicit window query strips its prefix");
            Launcher.query = "_firefox";
            check(Launcher.results[0]?.kind === "window" && Launcher.results[0].address === "123", "compact underscore query offers the matching window");
            Hyprland.toplevels = {values: [
                {address: "111", wayland: {appId: "chrome-test-Default"}},
                {address: "222", wayland: {appId: "chromium"}}
            ]};
            check(Launcher.browserFocus("/tmp/index.html").includes("address:0x222"), "HTML selects the browser and skips PWAs");
            check(Launcher.browserFocus("/tmp/index.XHTML").includes("address:0x222"), "XHTML selects the browser");
            check(Launcher.browserFocus("/tmp/notes.txt") === "", "text files do not change browser focus");
            Hyprland.toplevels = {values: []};
            check(Launcher.browserFocus("/tmp/index.html") === "", "HTML supports no existing browser");
            check(Launcher.classifyQuery("_projects").mode === "main", "unmatched underscore query falls back");
            Launcher.query = "_zzmissingwindow";
            check(Launcher.results[0]?.kind === "url" && Launcher.results[0].badge === "%", "unmatched window query reaches web fallback");
            const htmlPath = "_projects/_personal/liquidglass/launcher/prototypes/index.html";
            for (const query of [htmlPath, "  " + htmlPath, "~/" + htmlPath, "/home/test/" + htmlPath, "./" + htmlPath]) {
                const classified = Launcher.classifyQuery(query);
                check(classified.mode === Launcher.pathPrefix && classified.text.includes("_projects"), "filepath keeps underscore " + query);
            }
            Launcher.fdHits = {q: htmlPath, list: [{path: Settings.home + "/" + htmlPath, dir: false}]};
            Launcher.query = htmlPath;
            check(Launcher.pathMode && Launcher.results[0]?.path === Settings.home + "/" + htmlPath, "relative HTML path produces an actionable file row");
            Hyprland.toplevels = {values: []};
            check(Launcher.classifyQuery("_firefox").mode === "main", "closing the matching window enables fallback");
            check(Launcher.classifyQuery("_").mode === Launcher.windowPrefix, "bare underscore keeps empty window mode open");
            Launcher.query = "https://example.com";
            check(Launcher.results[0].kind === "url", "automatic URL precedence");
            check(Launcher.classifyQuery("example.com/docs").url?.host === "example.com", "URL paths keep URL precedence");
            for (const address of ["person@example.com", "First.Last+tag@sub.example.co.uk"]) {
                Launcher.query = address;
                check(!Launcher.pathMode && Launcher.classification.email === address, "address inference takes precedence over file suffix");
                check(Launcher.results[0]?.url === Email.web + "#search/" + encodeURIComponent(address), "address offers encoded Gmail search");
            }
            for (const invalid of ["name@", "@example.com", "a..b@example.com", "a b@example.com", "name@example..com"])
                check(!Launcher.parseEmail(invalid), "incomplete address stays ordinary input");
            check(Launcher.classifyQuery("2/3").math, "division keeps calculator precedence");
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
            const companion = Launcher.results.findIndex(r => r.kind === "app" && r.id === "launcher-continuity");
            check(companion > 0, "selection fixture starts below the frequent app");
            Launcher.index = companion;
            Launcher.query = "continuity";
            check(Launcher.index === 0, "narrowing selects the first match");
            Launcher.query = "zzlauncher";
            check(Launcher.index === 0 && Launcher.selected?.id === app.id, "broadening selects the first match instead of retaining the old app");
            Launcher.query = "regression";
            check(Launcher.index === 0 && Launcher.selected?.id !== "launcher-continuity", "missing selection falls back to first match");
            Launcher.query = "#";
            check(Launcher.index === 0, "mode changes reset selection");
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
            Settings.showDesktopActions = false;
            Launcher.db = ({"launcher-regression:private": {count: 100, last: Date.now()}});
            for (const query of ["", "regression priv"]) {
                Launcher.query = query;
                check(!Launcher.results.some(r => r.kind === "app" && r.action), "desktop-action switch hides history and search for " + query);
            }
            check(Launcher.appIndex.some(a => a.entry.id === "launcher-regression"), "desktop-action switch keeps the app");
            Settings.showDesktopActions = true;
            Settings.hiddenApps = ["launcher-hidden", "launcher-regression:private"];
            check(!Launcher.appIndex.some(a => a.id === "launcher-regression:private"), "enabled desktop actions still respect individual exclusions");
            Settings.hiddenApps = ["launcher-hidden"];
            Launcher.db = ({});
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

            Launcher.db = ({});
            Launcher.show();
            check(!Launcher.prefixHint.includes(":emoji"), "emoji selector is absent from mode hints");
            check(!Launcher.prefixHint.includes(">run") && !Launcher.actions.cmd, "run mode and dispatch removed");
            Launcher.query = ">echo test";
            check(Launcher.classification.mode === "main" && !Launcher.results.some(r => r.kind === "cmd"), "former run prefix is ordinary search");
            for (const query of [":", ":lol", ":greece"]) {
                Launcher.query = query;
                check(Launcher.classification.mode === "main", "former emoji prefix uses main search for " + query);
                check(!Launcher.results.some(r => r.kind === "emoji"), "main search has no emoji rows for " + query);
            }
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


def check_file_dispatch(target):
    """Run the launcher's file-opening command with a harmless default opener."""
    source = (ROOT / "services/Launcher.qml").read_text()
    match = re.search(r'Quickshell\.execDetached\(\["sh", "-c", (\x27[^\n]+?\x27), "sh", r\.path', source)
    script = ast.literal_eval(match.group(1))
    bin_dir = target / "bin"
    bin_dir.mkdir()
    opener = bin_dir / "xdg-open"
    opener.write_text('#!/bin/sh\nif [ -n "$LAUNCHER_TEST_OPEN_LOG" ]; then printf "%s\\n" "$1" > "$LAUNCHER_TEST_OPEN_LOG"; fi\nprintf "default\\n%s\\n" "$1"\n')
    opener.chmod(0o700)
    mime = bin_dir / "xdg-mime"
    mime.write_text('#!/bin/sh\nprintf "%s\\n" "$LAUNCHER_TEST_HANDLER"\n')
    mime.chmod(0o700)
    focus = bin_dir / "hyprctl"
    focus.write_text('#!/bin/sh\nprintf "%s\\n%s\\n" "$1" "$2" > "$LAUNCHER_TEST_FOCUS"\n')
    focus.chmod(0o700)
    focus_log = target / "focus.log"
    env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"], LAUNCHER_TEST_HANDLER="chromium.desktop", LAUNCHER_TEST_FOCUS=str(focus_log))
    browser = 'hl.dsp.focus({ window = "address:0x222" })'
    cases = [
        ("index.html", b"<!doctype html><title>Test</title>", "default"),
        ("index.htm", b"<html><title>Test</title></html>", "default"),
        ("index.HTML", b"<html><title>Test</title></html>", "default"),
        ("index.xhtml", b'<html xmlns="http://www.w3.org/1999/xhtml"/>', "default"),
        ("empty.html", b"", "default"),
        ("page with 'quotes'.html", b"<html/>", "default"),
        ("notes.txt", b"ordinary text", "editor"),
        ("empty.txt", b"", "editor"),
        ("image.bin", b"\x00\x01\x02\xff", "default"),
    ]
    for name, content, expected in cases:
        if focus_log.exists():
            focus_log.unlink()
        path = target / name
        path.write_bytes(content)
        result = subprocess.run(
            ["sh", "-c", script, "sh", str(path), browser, "/usr/bin/printf", "editor\\n%s\\n", str(path)],
            env=env, capture_output=True, text=True, timeout=5, check=True,
        )
        assert result.stdout == f"{expected}\n{path}\n", f"{name}: {result.stdout!r}"
        html = path.suffix.lower() in (".htm", ".html", ".xhtml")
        assert focus_log.exists() == html, f"{name}: browser focus is only used for HTML"
        if html:
            assert focus_log.read_text() == f"dispatch\n{browser}\n"
    path = target / "index.html"
    for handler, selected_browser in [("firefox.desktop", browser), ("chromium.desktop", "")]:
        result = subprocess.run(
            ["sh", "-c", script, "sh", str(path), selected_browser, "/usr/bin/true"],
            env=dict(env, LAUNCHER_TEST_HANDLER=handler), capture_output=True, text=True, timeout=5, check=True,
        )
        assert result.stdout == f"default\n{path}\n" and not focus_log.exists(), "other defaults and a closed browser open without changing focus"
    print("PASS: HTML/XHTML use default applications; text and binary dispatch preserved")


MENU_TEST = '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules
ShellRoot {
    LauncherMenu { id: menu }
    TestCase { id: keys; when: false }
    property bool trackEntrance: true
    property bool sawWide: false
    property bool sawNarrow: false
    property bool geometryChanged: false
    Timer { interval: 16; repeat: true; running: Launcher.shown && trackEntrance; onTriggered: {
        const box = keys.findChild(menu, "box"), input = keys.findChild(menu, "input");
        sawWide = sawWide || box.width > 680;
        sawNarrow = sawNarrow || box.width < 680;
        geometryChanged = geometryChanged || box.height !== 54 || box.radius !== Theme.popupRadius || Math.abs(box.x + box.width / 2 - menu.width / 2) > 1 || input.scale !== 1 || input.font.pixelSize !== Theme.queryTextSize;
    } }
    function check(ok, message) { if (!ok) throw new Error(message); }
    Timer { interval: 150; running: true; onTriggered: {
        try {
            Launcher.db = ({});
            Launcher.show();
            menu.requestActivate();
            keys.wait(400);
            const box = keys.findChild(menu, "box");
            const input = keys.findChild(menu, "input");
            const hint = keys.findChild(menu, "hint");
            const list = keys.findChild(menu, "list");
            const divider = keys.findChild(menu, "divider");
            const modes = keys.findChild(menu, "modeHints");
            const placeholder = keys.findChild(menu, "placeholder");
            const searchIcon = keys.findChild(menu, "searchIcon");
            trackEntrance = false;
            check(sawWide && sawNarrow && !geometryChanged && box.width === 680, "lateral spring settles without scaling text, height or corners");
            check(box.height === 54 && box.radius === Theme.popupRadius && !list.enabled, "starts with field only and existing radius");
            check(divider.opacity === 0 && hint.visible && placeholder.visible && searchIcon.visible, "compact field shows Search, magnifier and mode hints without divider");
            check(Launcher.modes.map(mode => mode.prefix).join("") === '=\"_/,#%@', "requested mode hint order");
            check(!keys.findChild(menu, "disclosure"), "chevron removed");
            const files = modes.children.find(child => child.modelData?.prefix === "/");
            check(files.children[0].font.bold && files.children[1].font.pixelSize < files.children[0].font.pixelSize, "mode symbols are bold and labels smaller");
            for (const [query, icon] of [
                ["", Theme.glyph.launcher], ["zzlauncher", Theme.glyph.launcher],
                ["=", Theme.glyph.launcherCalc], ["2+2", Theme.glyph.launcherCalc], ["2/3", Theme.glyph.launcherCalc],
                ['"', Theme.glyph.clipboard], ["_", Theme.glyph.launcherWindow],
                ["/", Theme.glyph.folder], ["~/docs", Theme.glyph.folder],
                [",", Theme.glyph.tasks], [",call mum", Theme.glyph.tasks], [",0m", Theme.glyph.tasks],
                [",25m tea", Theme.glyph.timer], [",7:30 wake up", Theme.glyph.alarm], [",8pm dinner", Theme.glyph.alarm],
                ["#", Theme.glyph.launcherMusic], ["%", Theme.glyph.launcherWeb], ["%y cats", Theme.glyph.launcherWeb],
                ["example.com/docs", Theme.glyph.launcherWeb], ["no-fixture-can-match-this", Theme.glyph.launcherWeb],
                ["_zzmissingwindow", Theme.glyph.launcherWeb],
                ["@", Theme.glyph.mailUnread], ["person@example.com", Theme.glyph.mailUnread],
                ["", Theme.glyph.launcher]
            ]) {
                input.adopt(query); keys.wait(30);
                check(searchIcon.text === icon && searchIcon.y === 1, "query icon and vertical offset for " + query);
            }
            keys.wait(Theme.rollMs * 1.45 + 180);
            const arrivingIcon = keys.findChild(searchIcon, "arrivingIcon");
            const departingIcon = keys.findChild(searchIcon, "departingIcon");
            input.adopt("%cats"); keys.wait(Theme.rollMs * 1.45 + 210);
            input.adopt(""); keys.wait(40);
            check(searchIcon.shown === Theme.glyph.launcherWeb && !searchIcon.rolling, "brief empty query does not flash or roll to the magnifier");
            input.adopt("=2+2"); keys.wait(80);
            check(searchIcon.shown === Theme.glyph.launcherWeb && !searchIcon.rolling, "new mode waits for the icon choice to settle");
            keys.wait(100);
            check(searchIcon.rolling && searchIcon.shown === Theme.glyph.launcherCalc && searchIcon.was === Theme.glyph.launcherWeb, "stable calculator rolls directly from web without the intermediate magnifier");
            keys.wait(Theme.rollMs * 1.45 + 30);
            input.adopt("%cats"); keys.wait(40);
            input.adopt("=2+3"); keys.wait(180);
            check(searchIcon.shown === Theme.glyph.launcherCalc && !searchIcon.rolling, "returning to the displayed mode cancels the pending icon change");
            input.adopt(""); keys.wait(Theme.rollMs * 1.45 + 210);
            input.adopt("=2+2"); keys.wait(195);
            check(searchIcon.rolling && searchIcon.was === Theme.glyph.launcher && searchIcon.shown === Theme.glyph.launcherCalc, "mode change rolls from SVG magnifier to calculator");
            check(departingIcon.visible && departingIcon.y < 0 && arrivingIcon.y > 0 && arrivingIcon.scale < 1 && departingIcon.scale < 1, "icons roll up, shrink and grow like the numbers");
            const rollTime = searchIcon.s;
            input.adopt("=2+3"); keys.wait(30);
            check(searchIcon.s > rollTime && searchIcon.was === Theme.glyph.launcher, "typing within one mode leaves the roll running");
            input.adopt("%cats"); keys.wait(190);
            check(searchIcon.rolling && searchIcon.shown === Theme.glyph.launcherWeb && searchIcon.was === Theme.glyph.launcherCalc, "interrupted mode roll follows the latest icon");
            keys.wait(Theme.rollMs * 1.45 + 30);
            check(!searchIcon.rolling && arrivingIcon.y === 0 && arrivingIcon.scale === 1 && arrivingIcon.opacity === 1 && !arrivingIcon.layer.enabled && !departingIcon.visible, "roll settles sharp at its original position");
            input.adopt("/"); keys.wait(190);
            Settings.reduceMotion = true; keys.wait(20);
            check(!searchIcon.rolling && searchIcon.shown === Theme.glyph.folder && !departingIcon.visible, "enabling reduced motion stops an active icon roll");
            input.adopt("#"); keys.wait(170);
            check(!searchIcon.rolling && searchIcon.shown === Theme.glyph.launcherMusic && arrivingIcon.y === 0, "reduced motion swaps mode icons immediately");
            Settings.reduceMotion = false;
            input.adopt("2+2"); keys.wait(30);
            Launcher.calcAnswer = {expr: "2+2", text: "4"}; keys.wait(30);
            check(searchIcon.text === Theme.glyph.launcherCalc, "calculator icon stays stable when the answer arrives");
            input.adopt("%cats"); keys.wait(30);
            Launcher.index = 1; keys.wait(30);
            check(searchIcon.text === Theme.glyph.launcherWeb, "result selection keeps the query-mode icon");
            input.adopt(""); keys.wait(250);
            input.adopt("W"); keys.wait(250);
            const queryLine = menu.contentItem;
            const iconPosition = searchIcon.mapToItem(queryLine, 0, 0);
            const iconLeft = Math.round(iconPosition.x);
            const iconTop = Math.round(iconPosition.y);
            const textLeft = Math.round(input.mapToItem(queryLine, 0, 0).x + input.leftPadding);
            const iconArea = keys.grabImage(queryLine);
            input.adopt("W".repeat(160)); keys.wait(250);
            check(input.contentWidth > input.width, "long query scrolls horizontally");
            check(input.leftFade > 0 && input.rightFade === 0, "long query softens the clipped beginning while keeping the caret clear: " + input.leftFade + "," + input.rightFade + " start=" + input.positionToRectangle(0).x + " end=" + input.positionToRectangle(input.length).x + " cursor=" + input.cursorRectangle.x);
            input.cursorPosition = 0; keys.wait(100);
            check(input.leftFade === 0 && input.rightFade > 0, "Home restores the beginning and softens the hidden ending");
            input.cursorPosition = Math.floor(input.text.length / 2); keys.wait(100);
            check((input.leftFade === 0 || input.cursorRectangle.x >= input.leftFade) && (input.rightFade === 0 || input.cursorRectangle.x + input.cursorRectangle.width <= input.width - input.rightFade), "editing in the middle leaves the caret outside the fades");
            input.cursorPosition = input.text.length; keys.wait(100);
            input.selectAll();
            check(input.selectedText === input.text, "overflow keeps the complete query selectable");
            input.deselect();
            const longQuery = keys.grabImage(queryLine);
            if (Quickshell.env("LAUNCHER_TEST_GPU")) {
                input.layer.enabled = false; keys.wait(30);
                const hardClip = keys.grabImage(queryLine);
                input.layer.enabled = Qt.binding(() => input.leftFade > 0 || input.rightFade > 0);
                const position = input.mapToItem(queryLine, 0, 0);
                let softened = 0;
                for (let y = Math.ceil(position.y); y < position.y + input.height; y++) {
                    for (let x = Math.ceil(position.x); x < position.x + input.leftFade; x++)
                        if (hardClip.pixel(x, y).r - longQuery.pixel(x, y).r > 0.03) softened++;
                }
                check(softened > 8, "rendered overflow fades instead of ending at a hard clip");
                const capture = Quickshell.env("LAUNCHER_QUERY_CAPTURE");
                if (capture) {
                    longQuery.save(capture + "/faded.png");
                    hardClip.save(capture + "/hard-clip.png");
                }
            }
            for (let y = iconTop; y < iconTop + menu.inputHeight; y++) {
                for (let x = iconLeft; x < textLeft; x++)
                    check(longQuery.pixel(x, y) === iconArea.pixel(x, y), "long query stays out of the left icon area");
            }
            input.adopt("short"); keys.wait(100);
            check(input.leftFade === 0 && input.rightFade === 0 && !input.layer.enabled, "shortening the query restores the unfaded field");
            input.adopt(""); keys.wait(250);
            check(input.leftFade === 0 && input.rightFade === 0 && !input.layer.enabled, "short query and empty hints have no fade");
            Launcher.hide();
            list.model = [{kind: "info", title: "Hidden result below the compact box"}];
            keys.wait(60);
            const compactExit = keys.grabImage(menu.contentItem);
            const stripY = Math.round(box.y + box.height + 10);
            let brightStrip = 0;
            for (let x = Math.round(box.x + 20); x < box.x + box.width - 20; x++) {
                const pixel = compactExit.pixel(x, stripY);
                if (Math.min(pixel.r, pixel.g, pixel.b) > 0.24)
                    brightStrip++;
            }
            check(brightStrip < box.width / 2, "compact exit does not expose the hidden result highlight below the glass");
            Launcher.show(); keys.wait(400);
            menu.requestActivate(); input.forceActiveFocus();
            if (Quickshell.env("LAUNCHER_TEST_GPU")) {
                console.log("PASS: launcher menu overflow shader, scrolling and fixed icon");
                Qt.quit();
                return;
            }
            const pinned = box.y;
            input.forceActiveFocus();
            keys.keyClick(Qt.Key_Up);
            check(Launcher.index === 0 && !menu.expanded, "Up does not navigate hidden results");
            keys.keyClick(Qt.Key_Return); keys.wait(240);
            check(menu.frecencyOpen && Launcher.shown && Launcher.chosen === -1 && box.height > 54, "empty Enter discloses without launching");
            check(box.y === pinned && list.enabled, "expansion pins the query and enables results");
            check(divider.opacity === 1 && hint.visible, "empty expanded list shows mode hints and divider");
            menu.toggleList(); keys.wait(250);
            keys.keyClick(Qt.Key_Down); keys.wait(240);
            check(menu.frecencyOpen && Launcher.index === 0, "first Down discloses without skipping the first result");
            keys.keyClick(Qt.Key_Down);
            check(Launcher.index === 1, "next Down navigates");
            keys.keyClick(Qt.Key_Escape); keys.wait(250);
            check(!menu.expanded && box.height === 54 && hint.visible, "Escape folds to the search field and keeps hints");
            input.adopt("zzlauncher"); keys.wait(240);
            const companion = Launcher.results.findIndex(r => r.id === "launcher-continuity");
            Launcher.index = companion;
            input.adopt("continuity"); keys.wait(240);
            check(Launcher.index === 0 && list.currentIndex === 0, "view selects the first match after typing");
            input.adopt("zzlauncher"); keys.wait(240);
            check(Launcher.index === 0 && list.currentIndex === 0, "view resets selection when search broadens");
            input.adopt("/"); keys.wait(240);
            check(Launcher.pathMode && box.width > 680 && !hint.visible && !placeholder.visible, "file mode keeps preview structure without hints");
            input.adopt("#"); keys.wait(240);
            check(Launcher.musicMode && box.width > 680, "music preview structure preserved");
            LauncherMusic.rows = Array.from({length: 12}, (_, i) => ({kind: "music", title: "row " + i}));
            keys.wait(240);
            const openedMode = Qt.createComponent(Qt.resolvedUrl("modules/LauncherMenu.qml")).createObject(null);
            keys.wait(110);
            const initialList = keys.findChild(openedMode, "list");
            check(initialList.itemAtIndex(0).opacity > initialList.itemAtIndex(6).opacity && initialList.itemAtIndex(6).opacity < 1, "a launcher created in a mode visibly cascades its rows");
            keys.wait(70);
            check(initialList.itemAtIndex(0).opacity === 1 && initialList.itemAtIndex(6).opacity <= 0.15, "cascade remains distinct after the first row has settled");
            const rowMotion = keys.findChild(openedMode, "rowEntrance");
            rowMotion.pause();
            const earlyRows = keys.grabImage(openedMode.contentItem);
            const rowPosition = initialList.mapToItem(openedMode.contentItem, 12, 6 * menu.rowHeight);
            const left = Math.round(rowPosition.x), top = Math.round(rowPosition.y);
            const background = earlyRows.pixel(left + 220, top + 14);
            let earlyInk = 0;
            for (let y = top; y < top + menu.rowHeight; y++) {
                for (let x = left; x < left + 200; x++)
                    if (earlyRows.pixel(x, y) !== background) earlyInk++;
            }
            check(earlyInk === 0, "later row is absent from the rendered frame during the cascade");
            rowMotion.resume();
            keys.wait(330);
            const settledRows = keys.grabImage(openedMode.contentItem);
            let changedPixels = 0;
            for (let y = top; y < top + menu.rowHeight; y++) {
                for (let x = left; x < left + 200; x++)
                    if (earlyRows.pixel(x, y) !== settledRows.pixel(x, y)) changedPixels++;
            }
            check(changedPixels > 20, "rendered later row visibly arrives after earlier rows");
            const capture = Quickshell.env("LAUNCHER_REVEAL_CAPTURE");
            if (capture) {
                earlyRows.save(capture + "/early.png");
                settledRows.save(capture + "/settled.png");
            }
            openedMode.destroy();
            menu.requestActivate(); input.forceActiveFocus();
            LauncherMusic.rows = Array.from({length: 20}, (_, i) => ({kind: "music", title: "row " + i}));
            input.adopt(""); keys.wait(250);
            input.adopt("#"); keys.wait(70);
            check(list.itemAtIndex(0).opacity > list.itemAtIndex(6).opacity && list.itemAtIndex(6).opacity < 1, "opening visibly reveals earlier rows before later rows");
            keys.wait(500);
            menu.rowsReveal = 0.6; keys.wait(240);
            check(list.itemAtIndex(8).opacity < list.itemAtIndex(7).opacity, "row reveal staggers rows below the eighth instead of showing them together");
            menu.animateRows(); keys.wait(520);
            check(list.itemAtIndex(11).opacity === 1, "all visible rows finish fully opaque");
            Launcher.index = 3; keys.wait(150);
            list.contentY = 3 * menu.rowHeight; keys.wait(30);
            check(list.topFadeReach === 0, "selected row at top edge stays solid");
            Launcher.index = 14; keys.wait(150);
            check(list.bottomFadeReach === 0, "selected row at bottom edge stays solid");
            input.adopt("no-fixture-can-match-this"); keys.wait(240);
            check(Launcher.results.every(r => r.kind !== "app"), "no-match path remains valid");
            input.adopt(""); keys.wait(250);
            check(box.height === 54, "clearing typed search returns to compact");
            check(divider.opacity === 0 && hint.visible, "collapse removes divider and restores hints");
            menu.toggleList(); keys.wait(45); menu.toggleList(); keys.wait(30); menu.toggleList(); keys.wait(250);
            check(menu.expanded && box.height === box.restHeight, "interrupted expansion settles at current intent");
            Launcher.hide(); keys.wait(120); Launcher.show(); keys.wait(400);
            check(!menu.frecencyOpen && box.height === 54 && box.width === 680 && menu.contentAlpha === 1 && menu.exitBlur === 0 && !box.layer.enabled, "reopening during exit restores compact geometry and sharp rendering");
            Settings.reduceMotion = true;
            menu.toggleList(); keys.wait(20);
            check(box.height === box.restHeight && menu.elevation === 1 && menu.rowsReveal === 1, "reduced motion applies geometry immediately");
            Launcher.hide(); keys.wait(20); Launcher.show(); keys.wait(20);
            check(menu.widthRatio === 1 && menu.contentAlpha === 1 && box.width === 680 && menu.exitBlur === 0, "reduced motion skips lateral spring and defocus");
            Settings.reduceMotion = false;
            const closingHeight = box.height;
            const closingCenter = box.y + box.height / 2;
            const closingGlass = box.color.a;
            Launcher.chosen = 0;
            Launcher.hide(); keys.wait(80);
            check(box.height === closingHeight && box.width > 680, "chosen exit gently expands sideways at fixed height");
            check(Math.abs(box.y + box.height / 2 - closingCenter) <= 1 && input.scale === 1, "exit keeps the baseline fixed without scaling text");
            check(menu.exitBlur > 0 && box.layer.enabled, "exit defocuses the glass");
            check(box.color.a === closingGlass && box.opacity === 1, "exit keeps the frost fill intact before the final fade");
            check(menu.contentAlpha > 0.5, "text remains readable in the first part of the exit");
            keys.wait(100);
            check(Launcher.active && menu.presenting && box.height > 0, "window survives past the old 160ms cutoff");
            keys.wait(100);
            check(!Launcher.active && !menu.presenting && menu.contentAlpha === 0 && menu.exitBlur === 1 && Math.abs(menu.widthRatio - 1.03) < .0001, "exit finishes before the window is released");
            console.log("PASS: launcher menu disclosure, modes, selection reset and interrupted motion");
        } catch (error) { console.log("FAIL: " + error); }
        Qt.quit();
    } }
}
'''


def check_menu(target, env):
    """Exercise real launcher UI and theme with only desktop surfaces isolated."""
    modules = target / "modules"
    modules.mkdir()
    source = (ROOT / "modules/LauncherMenu.qml").read_text()
    for name in ("box", "input", "hint", "list", "divider", "modeHints", "placeholder", "searchIcon", "listEdges", "rowEntrance"):
        source = source.replace(f"id: {name}\n", f'id: {name}\n                objectName: "{name}"\n')
    (modules / "LauncherMenu.qml").write_text(source)
    (target / "Theme.qml").write_text((ROOT / "Theme.qml").read_text())
    settings = target / "Settings.qml"
    settings.write_text(settings.read_text().replace("property var disabled:", 'property string font: "Inter"; property string monoFont: "monospace"; property bool reduceMotion: false; property bool reduceTransparency: false; property var disabled:'))
    components = target / "components"
    (components / "Rim.qml").write_text((ROOT / "components/Rim.qml").read_text())
    (components / "TextCaret.qml").write_text((ROOT / "components/TextCaret.qml").read_text())
    rolling = (ROOT / "components/RollingGlyph.qml").read_text()
    rolling = rolling.replace("id: now\n", 'id: now\n        objectName: "arrivingIcon"\n')
    rolling = rolling.replace("id: old\n", 'id: old\n        objectName: "departingIcon"\n')
    (components / "RollingGlyph.qml").write_text(rolling)
    stubs = {
        "OverlayWindow": 'import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true; color: "#333333" }',
        "BackdropProbe": 'import QtQuick\nItem { required property var screen; required property rect area; property bool active; property real luma: 0.5 }',
        "FilePreview": 'import QtQuick\nItem { property string path; function scroll(dir) {} }',
        "CoverArt": 'import QtQuick\nItem { property string dir; property string title; property string subtitle; property string glyph }',
        "Glyph": 'import QtQuick\nItem { property string text; property real fontSize: 16; property color color }',
    }
    for name, source in stubs.items():
        (components / f"{name}.qml").write_text(source)
    (components / "ScrollEdges.qml").write_text((ROOT / "components/ScrollEdges.qml").read_text())
    (target / "shaders").mkdir()
    (target / "shaders/edge.frag.qsb").write_bytes((ROOT / "shaders/edge.frag.qsb").read_bytes())
    (target / "shaders/query-edge.frag.qsb").write_bytes((ROOT / "shaders/query-edge.frag.qsb").read_bytes())
    music = target / "services/LauncherMusic.qml"
    music.write_text(music.read_text().replace('property var rows:', 'property string coverDir: ""; property var rows:'))
    (target / "shell.qml").write_text(MENU_TEST)
    if os.environ.get("LAUNCHER_TEST_GPU"):
        env = dict(env, QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", QT_OPENGL="software", LIBGL_ALWAYS_SOFTWARE="1")
    result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    print(output, end="")
    return result.returncode == 0 and "PASS: launcher menu" in output and all(message not in output for message in ("FAIL:", "Binding loop", "Unable to assign", "Failed to load"))


def main():
    """Run the real launcher with mocked services and temporary state."""
    with tempfile.TemporaryDirectory(prefix="quickshell-launcher-test-") as folder:
        target = Path(folder)
        check_file_dispatch(target)
        services = target / "services"
        components = target / "components"
        services.mkdir()
        components.mkdir()
        source = (ROOT / "services/Launcher.qml").read_text()
        file_command = re.search(r'^        command: .*fd\.arg.*$', source, re.MULTILINE).group(0)
        # Reads of clipboard/history and query helpers stay inside the fixture.
        source = re.sub(r"^(\s*)command:.*?(,?)$", r'\1command: ["/usr/bin/true"]\2', source, flags=re.MULTILINE)
        source = source.replace('QueuedProcess {\n        id: fd', 'FileQuery {\n        id: fd')
        source = re.sub(r'(id: fd.*?)(        command: [^\n]+)', lambda match: match.group(1) + file_command, source, count=1, flags=re.DOTALL)
        source = source.replace("import Quickshell.Hyprland", "import qs.services as TestDesktop")
        source = source.replace("Hyprland.", "TestDesktop.Hyprland.")
        (services / "Launcher.qml").write_text(source)
        for name, body in MOCKS.items():
            imports = 'import "TimersParse.js" as Parse\n' if name == "Timers" else ""
            (services / (name + ".qml")).write_text("pragma Singleton\nimport QtQuick\n" + imports + "QtObject {\n" + body + "\n}\n")
        (services / "TimersParse.js").write_text((ROOT / "services/TimersParse.js").read_text())
        for name in ("Fuzzy.js", "Linger.qml"):
            (target / name).parent.mkdir(exist_ok=True)
            (target / name).write_text((ROOT / name).read_text())
        (target / "OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var disabled: ({}); property var hiddenApps: ["launcher-hidden"]; property bool showDesktopActions: true; property string home: "/tmp"; property string editor: "/usr/bin/true"; function inTerminal(command) { return command; } function screenOn(name) { return true; } function moduleOn(key) { return !disabled[key]; } function expand(path) { return path.replace(/^~(?=\\/|$)/, home); } }\n')
        (target / "Paths.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function state(name) { return Quickshell.shellPath("state/" + name); } function script(name) { return "/tmp/unused/" + name; } }\n')
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property int revealMs: 10; property var glyph: ({lock: "", alarm: "alarm", timer: "timer", tasks: "tasks", launcher: "apps", launcherCalc: "calc", clipboard: "clip", launcherWindow: "windows", folder: "files", launcherMusic: "music", launcherWeb: "web", mailUnread: "mail", vol: ["sound"], wifiStrength: ["network"]}) }\n')
        (components / "QueuedProcess.qml").write_text('import QtQuick\nQtObject { property string want: ""; property string arg: ""; property int interval: 60; property var command: []; signal result(arg: string, text: string); function cancel() { want = ""; } }\n')
        (components / "FileQuery.qml").write_text((ROOT / "components/QueuedProcess.qml").read_text())
        (target / "shell.qml").write_text(TEST)
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        applications = target / "data/applications"
        applications.mkdir(parents=True)
        (applications / "launcher-regression.desktop").write_text("[Desktop Entry]\nType=Application\nName=Launcher regression app\nKeywords=zzlauncher;\nExec=/usr/bin/true\nActions=private;\n\n[Desktop Action private]\nName=Private window\nExec=/usr/bin/true\n")
        (applications / "launcher-continuity.desktop").write_text("[Desktop Entry]\nType=Application\nName=Launcher continuity companion\nKeywords=zzlauncher;\nExec=/usr/bin/true\n")
        (applications / "launcher-hidden.desktop").write_text("[Desktop Entry]\nType=Application\nName=Launcher hidden app\nExec=/usr/bin/true\n")
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"), XDG_DATA_HOME=str(target / "data"))
        fixture_home = target / "home"
        fixture_home.mkdir()
        (fixture_home / "notes.txt").write_text("fixture")
        spaced_path = target / "image with 'quotes' $(touch should-not-exist).bin"
        spaced_path.write_bytes(b"\x00\x01\xff")
        (target / "bin/fasd").write_text("#!/bin/sh\nexit 0\n")
        (target / "bin/fasd").chmod(0o700)
        (target / "ignore").write_text("")
        paths = target / "Paths.qml"
        paths.write_text(paths.read_text().replace('return "/tmp/unused/" + name;', f'return "{target / "ignore"}";'))
        settings = target / "Settings.qml"
        settings.write_text(settings.read_text().replace('home: "/tmp"', f'home: "{fixture_home}"'))
        env["PATH"] = str(target / "bin") + os.pathsep + env["PATH"]
        env["LAUNCHER_TEST_PATH"] = os.environ.get("LAUNCHER_TEST_PATH", str(target / "image.bin"))
        env["LAUNCHER_TEST_SPACED_PATH"] = str(spaced_path)
        opened = target / "opened.log"
        env["LAUNCHER_TEST_OPEN_LOG"] = str(opened)
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        passed = result.returncode == 0 and "PASS: launcher discovery" in output and "FAIL:" not in output
        if passed:
            assert opened.read_text() == env["LAUNCHER_TEST_PATH"] + "\n", "absolute binary file reaches the default opener"
        return 0 if passed and check_menu(target, env) else 1


if __name__ == "__main__":
    raise SystemExit(main())
