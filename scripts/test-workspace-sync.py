#!/usr/bin/env python3
"""Verify the real sync service against delayed models and read-only CLI replies."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix='workspace-sync-test-') as folder:
    target = Path(folder)
    (target / 'services').mkdir()
    (target / 'runtime').mkdir(mode=0o700)
    source = (ROOT / 'services/WorkspaceSync.qml').read_text().replace('import Quickshell.Hyprland', 'import qs.services').replace('event: HyprlandEvent', 'event')
    (target / 'services/WorkspaceSync.qml').write_text(source)
    (target / 'services/Hyprland.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
 property QtObject workspaces: QtObject { property var values: [] }
 property QtObject toplevels: QtObject { property var values: [] }
 property QtObject monitors: QtObject { property var values: [] }
 property var focusedWorkspace: null
 signal rawEvent(var event)
 function refreshWorkspaces() {}
 function refreshToplevels() {}
 function refreshMonitors() {}
}''')
    snapshots = [
        [{'id': 1, 'name': '1'}, {'id': 2, 'name': '2'}],
        [{'address': '0xa', 'mapped': True, 'workspace': {'id': 2}, 'title': 'An escaped\n\nnewline and ] [ brackets'}],
        [{'name': 'fixture', 'focused': True, 'activeWorkspace': {'id': 1}}],
    ]
    (target / 'snapshot.txt').write_text('\n\n\n'.join(json.dumps(part, indent=2) for part in snapshots))
    (target / 'hyprctl').write_text('#!/usr/bin/python\nfrom pathlib import Path\nimport time\ntime.sleep(0.08)\nprint(Path(__file__).with_name("snapshot.txt").read_text())\n')
    (target / 'hyprctl').chmod(0o700)
    (target / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
 id: root
 Component { id: workspace; QtObject { property int id; property string name; property bool active: false; property var lastIpcObject: ({}) } }
 Component { id: toplevel; QtObject { property string address; property var workspace } }
 Component { id: monitor; QtObject { property string name; property var activeWorkspace } }
 TestCase { id: test; when: false }
 function check(ok,message) { if (!ok) throw Error(message); }
 Timer { interval:100;running:true;onTriggered:{
 try {
 const one=workspace.createObject(root,{id:1,name:'1'});
 const later=workspace.createObject(root,{id:3,name:'3'});
 const window=toplevel.createObject(root,{address:'a',workspace:later});
 const screen=monitor.createObject(root,{name:'fixture',activeWorkspace:one});
 Hyprland.workspaces.values=[one,later];Hyprland.toplevels.values=[window];
 Hyprland.monitors.values=[screen];Hyprland.focusedWorkspace=one;
 WorkspaceSync.unsettle();test.wait(700);
 check(!WorkspaceSync.settled,'stale placement cannot release merely because placeholders are absent');
 later.id=2;later.name='2';screen.activeWorkspace=later;test.wait(500);
 check(!WorkspaceSync.settled,'late monitor refresh holds the freeze');
 screen.activeWorkspace=one;test.wait(700);
 check(WorkspaceSync.settled,'matching window, workspace and monitor replies release the freeze');

 const stale=workspace.createObject(root,{id:9,name:'9'});
 const unused=workspace.createObject(root,{id:-1,name:'unused'});
 Hyprland.workspaces.values=[one,later,stale,unused];WorkspaceSync.unsettle();test.wait(700);
 check(WorkspaceSync.settled,'unused stale IDs and placeholders do not keep the visible strip frozen');
 // The placeholder is inserted before a toplevel starts referring to it.
 window.workspace=unused;test.wait(40);
 check(!WorkspaceSync.settled,'a late placeholder reference automatically starts synchronization');
 window.workspace=later;Hyprland.workspaces.values=[one,later];test.wait(700);
 check(WorkspaceSync.settled,'automatic placeholder synchronization recovers');

 WorkspaceSync.unsettle();test.wait(140);
 Hyprland.rawEvent({name:'changeworkspaceid',data:''});test.wait(65);
 check(!WorkspaceSync.settled,'a verification reply from before a new renumber cannot release the freeze');
 test.wait(700);check(WorkspaceSync.settled,'a fresh verification releases after the overlapping renumber');

 later.id=-1;WorkspaceSync.unsettle();test.wait(1000);
 check(!WorkspaceSync.settled && WorkspaceSync.tries>=3,'placeholders remain frozen after three retries');
 later.id=2;test.wait(700);check(WorkspaceSync.settled,'retry recovers when the placeholder receives its ID');
 console.log('PASS: verified replies, stale models, monitor focus, overlapping events and placeholder recovery');
 }catch(e){console.log('FAIL: '+e);}
 Qt.quit();
 } }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(target / 'runtime'), PATH=str(target) + os.pathsep + os.environ['PATH'])
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run(['quickshell', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output, end='')
    errors = ('ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign', 'Unable to assign', 'Failed to load configuration')
    raise SystemExit(0 if result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output and not any(error in output for error in errors) else 1)
