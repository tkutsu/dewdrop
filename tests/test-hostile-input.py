#!/usr/bin/env python3
"""Keep odd input and failed writes from costing the user anything.

A process named with a newline, a settings.json that does not parse, markup in
a title, a web shortcut with no host, a task save that fails, a mail read from
a search and an encrypted drive, each against the real service.
"""
from pathlib import Path
import importlib.util
import subprocess
import tempfile

from test_support import ROOT, copy_shell, fixture_root, shell_env

NOTIFY = '''pragma Singleton
import Quickshell
Singleton {
    property var sent: []
    function send(summary, body, options) { sent = sent.concat([[summary, body]]); }
}'''

BROKEN = '{\n    "font": "Inter"\n    "terminal": "kitty"\n}\n'

SHELL = r'''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 500; implicitHeight: 400
        Item { id: anchor; width: 40; height: 20 }
        PopupText { id: label; text: 'a <img src="http://127.0.0.1:9/x.png"> b' }
        TestCase {
            id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
            function said(summary) { return Notify.sent.filter(n => n[0] === summary); }
            function run() {
                check(Settings.userBroken && said("settings.json did not parse").length > 0, "a settings.json that does not parse is noticed");
                Settings.set("font", "Sans");
                check(said("Setting not saved").length === 1, "a change made meanwhile is refused out loud");
                Settings.userBroken = false;

                // What sys-sample.sh procs prints for a process called "a\n;echo PWNED; x".
                Sys.parseProcs("10 1 5 100 bash\n4242 (a 0  a\n;echo 1 0 300 ;echo PWNED; x\n11 10 7 200 Web Content\n");
                check(Sys._procs.map(p => p.pid).join() === "10,11", "a process named with a newline adds no rows");
                const find = Sys.exeCommand(["10", "11"]);
                check(find[2].indexOf("/proc/") < 0 && find.slice(-4).join() === "/proc/10,/proc/11,-maxdepth,1",
                    "process paths reach find as arguments, not as shell text");

                check(label.textFormat === Text.PlainText && label.implicitWidth > 200, "popup text draws markup as the words it is");

                Settings.user = Object.assign({}, Settings.user, {webShortcuts: [{key: "x", name: "No host", url: "example"}, {key: "y", name: "No url"}]});
                const rows = Launcher.engineResults(".", "x words");
                check(rows.length === 2 && rows[0].subtitle === "", "a web shortcut with no host still lists");

                check(Notifications.isFleeting({appName: "kitty", summary: "Claude Code needs you"})
                    && !Notifications.isFleeting({appName: "kitty", summary: "Build finished"}), "summary rules come from settings");

                Tasks.lists = [{id: "home", title: "Home"}];
                Tasks.tasks = [{id: "t", listId: "home", title: "Old title", notes: "Original notes", parent: "", position: "10"}];
                popup.beginEdit(Tasks.tasks[0]);
                wait(30);
                popup.draft = "Revised <title>\nNew notes just typed";
                popup.saveEdit();
                Tasks.calls[0].failed("No network", 0);
                wait(30);
                const lost = said("Task not saved");
                check(Tasks.tasks[0].notes === "Original notes" && lost.length === 1
                    && lost[0][1] === "Revised &lt;title&gt;\nNew notes just typed\nNo network", "a failed task save hands the new words back");

                Email.threads = [{id: "inbox-a"}, {id: "inbox-b"}];
                Email.total = 3; Email.other = 3; Email.otherThreads = [];
                Email.counted = ({"inbox-a": "total", "inbox-b": "total", "inbox-unloaded": "total", "other-unloaded": "other"});
                Email.markRead({id: "archived-unread", unread: true});
                check(Email.total === 3 && Email.other === 3, "reading an archived search result leaves the counts alone");
                Email.markRead({id: "other-unloaded", unread: true});
                check(Email.total === 3 && Email.other === 2, "an Other mail read before its rows load comes off Other");
                Email.markRead({id: "inbox-unloaded", unread: true});
                check(Email.total === 2 && Email.threads.length === 2, "an inbox mail beyond the loaded rows comes off the badge");
                Email.markRead(Email.threads[0]);
                check(Email.total === 1 && Email.threads.length === 1, "a loaded row comes off the badge and the list");

                const inner = {path: "/dev/mapper/unlocked", type: "crypt", fstype: "ext4", label: "Backup", mountpoint: "/media/Backup", fssize: 1900000000, fsused: 123000000};
                const usb = children => JSON.stringify({blockdevices: [{path: "/dev/fixture", type: "disk", tran: "usb", size: 2000000000, children: children}]});
                const open = Drives.parse(usb([{path: "/dev/fixture1", type: "part", fstype: "crypto_LUKS", mountpoint: null, children: [inner]}]))[0];
                check(open.name === "Backup" && open.total === 1900000000 && open.volumes.length === 1 && open.volumes[0].mountpoint === "/media/Backup"
                    && open.unlocked.join() === "/dev/fixture1", "an unlocked encrypted drive shows the filesystem inside it");
                const shut = Drives.parse(usb([{path: "/dev/fixture1", type: "part", fstype: "crypto_LUKS", mountpoint: null}]))[0];
                check(shut.volumes.length === 0 && shut.unlocked.length === 0, "a locked one offers nothing to mount");
                const plain = Drives.parse(usb([{path: "/dev/fixture1", type: "part", fstype: "vfat", mountpoint: "/media/Stick", fssize: 10, fsused: 4}]))[0];
                check(plain.used === 4 && plain.volumes[0].path === "/dev/fixture1" && plain.unlocked.length === 0, "a plain stick reads as before");
                console.log("DONE");
            }
        }
    }
    TasksPopup { id: popup; visible: true; anchorItem: anchor }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch (error) { console.log("FAIL: " + error + "\n" + error.stack); }
        Qt.quit();
    } }
}'''


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tests' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def main():
    with tempfile.TemporaryDirectory(prefix='qs-hostile-input-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'src/services/GoogleService.qml').write_text(module('test-tasks').BASE)
        (target / 'src/core/Notify.qml').write_text(NOTIFY)
        # Only the parser is asked: no real disks, and none of their events.
        drives = target / 'src/services/Drives.qml'
        drives.write_text(drives.read_text().replace('running: true', 'running: false'))
        (target / 'settings.json').write_text(BROKEN)
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end='')
        assert result.returncode == 0 and 'DONE' in output and 'FAIL:' not in output, 'hostile input probes failed'
        assert (target / 'settings.json').read_text() == BROKEN, 'a settings.json that did not parse was written over'
        print('PASS: the settings.json that did not parse is still the one on disk')


if __name__ == '__main__':
    main()
