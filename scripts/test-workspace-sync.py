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
 property int refreshCount: 0
 function refreshWorkspaces() { refreshCount++; }
 function refreshToplevels() {}
 function refreshMonitors() {}
}''')
    snapshots = [
        [{'id': 1, 'name': '1'}, {'id': 2, 'name': '2'}],
        [{'address': '0xa', 'mapped': True, 'workspace': {'id': 2}, 'title': 'An escaped\n\nnewline and ] [ brackets'}],
        [{'name': 'fixture', 'focused': True, 'activeWorkspace': {'id': 1}}],
    ]
    (target / 'snapshot.txt').write_text('\n\n\n'.join(json.dumps(part, indent=2) for part in snapshots))
    (target / 'mode.txt').write_text('ok')
    (target / 'attempts.txt').write_text('')
    (target / 'hyprctl').write_text("""#!/usr/bin/python
from pathlib import Path
import sys
import time
folder = Path(__file__).parent
mode = (folder / 'mode.txt').read_text()
with (folder / 'attempts.txt').open('a') as log:
    print(mode, file=log)
if mode == 'hang':
    time.sleep(5)
else:
    time.sleep(0.08)
if mode == 'error':
    sys.exit(1)
print('malformed' if mode == 'malformed' else (folder / 'snapshot.txt').read_text())
""")
    (target / 'hyprctl').chmod(0o700)
    (target / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 id: root
 FileView { id: mode; path: Quickshell.shellPath('mode.txt'); printErrors: false }
 FileView { id: attempts; path: Quickshell.shellPath('attempts.txt'); printErrors: false }
 Timer {
  id: eventStorm;interval:50;repeat:true
  onTriggered: Hyprland.rawEvent({name:'movewindowv2',data:''})
 }
 Component { id: workspace; QtObject { property int id; property string name; property bool active: false; property var lastIpcObject: ({}) } }
 Component { id: toplevel; QtObject { property string address; property var workspace } }
 Component { id: monitor; QtObject { property string name; property var activeWorkspace } }
 TestCase { id: test; when: false }
 function check(ok,message) { if (!ok) throw Error(message); }
 function until(predicate, timeout, message) {
  const start=Date.now();
  while (!predicate() && Date.now()-start<timeout) test.wait(25);
  check(predicate(),message);
 }
 function probeCount() { attempts.reload();attempts.waitForJob();return attempts.text().trim().split('\\n').length; }
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

 // Unmapped XWayland windows (Steam's helpers) enter the model without a workspace and never leave it.
 const ghost=toplevel.createObject(root,{address:'b',workspace:null});
 Hyprland.toplevels.values=[window,ghost];WorkspaceSync.unsettle();test.wait(700);
 check(WorkspaceSync.settled,'windows without a workspace do not keep the strip frozen');
 Hyprland.toplevels.values=[window];

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
 later.id=3;later.name='3';WorkspaceSync.unsettle();
 until(() => WorkspaceSync.failed===true,6500,'persistent disagreement reaches an explicit failed state');
 check(!WorkspaceSync.settled && WorkspaceSync.tries===WorkspaceSync.retryLimit,'exhaustion preserves the unverified freeze');
 const stopped=Hyprland.refreshCount;const probes=probeCount();test.wait(900);
 check(Hyprland.refreshCount===stopped && probeCount()===probes,'failed synchronization stops refreshing and spawning CLI probes');
 later.id=2;later.name='2';Hyprland.rawEvent({name:'workspacev2',data:''});
 check(!WorkspaceSync.failed && WorkspaceSync.tries===0,'a fresh compositor event resets the failure and retry budget');
 until(() => WorkspaceSync.settled,1000,'a fresh compositor event recovers after retry exhaustion');

 later.id=3;later.name='3';WorkspaceSync.unsettle();eventStorm.start();
 until(() => WorkspaceSync.failed,6500,'event bursts cannot postpone retry exhaustion forever');
 eventStorm.stop();
 check(WorkspaceSync.tries===WorkspaceSync.retryLimit,'overlapping events retain the original attempt budget');
 later.id=2;later.name='2';Hyprland.rawEvent({name:'workspacev2',data:''});
 until(() => WorkspaceSync.settled,1000,'synchronization recovers after an event burst');

 for (const failure of ['malformed','error','hang']) {
  mode.setText(failure);mode.waitForJob();
  const before=probeCount();WorkspaceSync.unsettle();
  until(() => WorkspaceSync.failed,20000,failure+' reaches the retry limit');
  check(!WorkspaceSync.settled && WorkspaceSync.tries===WorkspaceSync.retryLimit,failure+' cannot falsely settle');
  check(probeCount()===before+WorkspaceSync.retryLimit,failure+' spawns only the bounded number of probes');
  const after=probeCount();test.wait(400);
  check(probeCount()===after,failure+' stops probing after exhaustion');
  mode.setText('ok');mode.waitForJob();
  Hyprland.rawEvent({name:'configreloaded',data:''});
  until(() => WorkspaceSync.settled && !WorkspaceSync.failed,1500,failure+' recovers on a fresh event');
 }
 console.log('PASS: verified replies, stale models, monitor focus, overlapping events, placeholder recovery and bounded retries');
 }catch(e){console.log('FAIL: '+e);}
 Qt.quit();
 } }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(target / 'runtime'), PATH=str(target) + os.pathsep + os.environ['PATH'])
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    result = subprocess.run(['quickshell', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=75)
    output = result.stdout + result.stderr
    print(output, end='')
    errors = ('ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign', 'Unable to assign', 'Failed to load configuration')
    raise SystemExit(0 if result.returncode == 0 and 'PASS:' in output and 'FAIL:' not in output and not any(error in output for error in errors) else 1)
