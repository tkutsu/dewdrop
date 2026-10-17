#!/usr/bin/env python3
"""Exercise bar web-app actions, direct links, app overrides and folder settings."""
import importlib.util
import json
import os
import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env

ROOT = Path(__file__).resolve().parents[1]
APP_IDS = {
    "tasks": "okhfeehhillipaleckndoboggdkcebmo",
    "gmail": "fmgjjmmmlfnkbppncabfkddbjimcfncm",
    "calendar": "kjbdgfilnfhdoflbpgamdcdgpehopbep",
}
spec = importlib.util.spec_from_file_location("task_harness", ROOT / "scripts/test-tasks.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules as Modules
import qs.services
ShellRoot {
    FloatingWindow { visible: true; implicitWidth: 500; implicitHeight: 400
        Item { id: anchor; width: 40; height: 20 }
        Modules.Tasks { id: barTasks }
        Modules.Clock { id: barClock }
        TestCase { id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function launch(action) { action(); wait(150); }
            function find(item, predicate) {
                if (predicate(item)) return item;
                for (const child of item.children ?? []) {
                    const found = find(child, predicate);
                    if (found) return found;
                }
                return null;
            }
            function run() {
                tryVerify(() => DesktopEntries.applications.values.some(e => e.id === "custom-pwa"));
                tryVerify(() => Settings.defaults.downloadsDir !== undefined);
                if (Quickshell.env("WEB_APPS_INSTALLED") === "1") {
                    tryVerify(() => Settings.desktopApps.length === 4);
                }
                const button = popup.keyTargets().find(t => t.name === "Open Google Tasks");
                if (!button) throw Error("Open Google Tasks button missing");
                launch(() => button.tapped());
                launch(() => barTasks.actions[Qt.RightButton]());
                launch(() => Email.openInbox());
                launch(() => Email.open({ id: "thread-id", unread: false }));
                launch(() => Email.compose("A & B"));
                launch(() => calendar.openDay(new Date(2026, 9, 23)));
                launch(() => barClock.actions[Qt.RightButton]());

                const apps = menu.pages.find(p => p.title === "Apps & Services").sections.reduce((rows, s) => rows.concat(s.rows), []);
                const tasks = apps.find(r => r.id === "webApp:tasks");
                const gmail = apps.find(r => r.id === "webApp:gmail");
                gmail.set("browser");
                menu.page = menu.pages.findIndex(p => p.title === "Apps & Services");
                menu.query = "tasks open with";
                wait(80);
                const selector = find(menu.contentItem, i => i.setting?.id === "webApp:tasks" && i.currentIndex !== undefined);
                check(selector !== null && selector.currentIndex >= 0, "web app selector renders its automatic choice");
                selector.activated(selector.model.findIndex(o => o.value === "custom-pwa"));
                check(Settings.webApps.gmail === "browser" && tasks.get() === "custom-pwa", "app choices preserve other web apps");
                launch(() => Tasks.openApp());
                tasks.set("browser");
                launch(() => Tasks.openApp());
                tasks.set("missing-pwa");
                check(Settings.webAppOptions("tasks").some(o => o.value === "missing-pwa" && o.label.endsWith("(Unavailable)")), "unavailable choice stays visible in settings");
                launch(() => Tasks.openApp());
                tasks.set("custom-pwa");
                launch(() => Quickshell.execDetached(Settings.webApp("tasks", "https://tasks.google.com/deep", "https://tasks.google.com/")));

                const folders = menu.pages.reduce((rows, p) => rows.concat(...p.sections.map(s => s.rows)), []).filter(r => ["downloadsDir", "wallpaperDir", "scriptsDir"].includes(r.id));
                for (const row of folders) {
                    menu.query = row.title;
                    wait(80);
                    const folder = Quickshell.env("WEB_APPS_TEST_DIR") + "/" + row.id + " with spaces";
                    const field = find(menu.contentItem, i => i.stored !== undefined && i.parent?.setting?.id === row.id);
                    check(field !== null, row.id + " field renders in settings");
                    field.text = folder;
                    field.editingFinished();
                    check(row.get() === folder && Settings[row.id].replace(/\\/$/, "") === folder, row.id + " setting updates its consumer path");
                }
                console.log("DONE: Web app actions and settings");
            }
        }
    }
    TasksPopup { id: popup; visible: true; anchorItem: anchor }
    Calendar { id: calendar; anchorItem: anchor }
    Modules.SettingsMenu { id: menu }
    Timer { interval: 200; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e); }
        Qt.quit();
    } }
}'''


def check_launch(installed):
    """Record actual detached launches without opening a browser or PWA."""
    with tempfile.TemporaryDirectory(prefix="qs-web-apps-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/GoogleService.qml").write_text(harness.BASE)
        (target / "components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
        (target / "shell.qml").write_text(SHELL)
        commands = target / "bin"
        commands.mkdir()
        record = target / "launches"
        for name in ("pwa", "xdg-open", "custom"):
            command = commands / name
            command.write_text('#!/bin/sh\nprintf "%s\\n" "' + name + ' $*" >> "$WEB_APPS_LAUNCH_RECORD"\n')
            command.chmod(0o755)
        applications = target / "data/applications"
        applications.mkdir(parents=True)
        (applications / "custom-pwa.desktop").write_text(f"[Desktop Entry]\nType=Application\nName=Custom app\nExec={commands / 'custom'} %U\n")
        if installed:
            for key, app_id in APP_IDS.items():
                (applications / f"chrome-{app_id}-Profile_2.desktop").write_text(
                    f"[Desktop Entry]\nType=Application\nName={key}\nExec={commands / 'pwa'} {key} --app-id={app_id} --profile-directory=Profile_2\n"
                )
        env = shell_env(target, PATH=f"{commands}:{os.environ['PATH']}",
                        WEB_APPS_LAUNCH_RECORD=str(record), WEB_APPS_INSTALLED="1" if installed else "0",
                        WEB_APPS_TEST_DIR=str(target),
                        XDG_DATA_DIRS=str(target / "system-data"))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign", "Binding loop", "Failed to load configuration")
        if result.returncode or "DONE: Web app actions and settings" not in output or any(e in output for e in errors):
            print(output)
            return False
        launches = record.read_text().splitlines() if record.exists() else []
        homes = {"tasks": "https://tasks.google.com/", "gmail": "https://mail.google.com/mail/u/0/", "calendar": "https://calendar.google.com/"}
        cases = [("tasks", ""), ("tasks", ""), ("gmail", ""), ("gmail", homes["gmail"] + "#inbox/thread-id"),
                 ("gmail", homes["gmail"] + "?view=cm&fs=1&su=A%20%26%20B"),
                 ("calendar", "https://calendar.google.com/calendar/r/day/2026/10/23"), ("calendar", "")]
        expected = []
        for key, url in cases:
            if installed:
                expected.append(f"pwa {key} --app-id={APP_IDS[key]} --profile-directory=Profile_2"
                                + (f" --app-launch-url-for-shortcuts-menu-item={url}" if url else ""))
            else:
                expected.append("xdg-open " + (url or homes[key]))
        expected += ["custom ", "xdg-open " + homes["tasks"], "xdg-open " + homes["tasks"], "custom https://tasks.google.com/deep"]
        ok = launches == expected
        saved = json.loads((target / "settings.json").read_text().split("\n", 2)[2])
        ok = ok and saved["webApps"] == {"gmail": "browser", "tasks": "custom-pwa"} and saved["downloadsDir"] == str(target / "downloadsDir with spaces")
        state = "installed PWA" if installed else "browser fallback"
        print(f"{'PASS' if ok else 'FAIL'}: {state}, direct links, app overrides and persisted folders")
        if not ok:
            print(f"Expected: {expected}\nActual: {launches}")
        return ok


if __name__ == "__main__":
    results = [check_launch(True), check_launch(False)]
    raise SystemExit(0 if all(results) else 1)
