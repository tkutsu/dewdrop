#!/usr/bin/env python3
"""Replay workspace transitions with the real layout and mocked compositor and artwork."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
root=Path(__file__).resolve().parents[1]
folder=tempfile.TemporaryDirectory(prefix='workspace-test-')
target=Path(folder.name)
(target/'services').mkdir()
(target/'components').mkdir()
(target/'runtime').mkdir(mode=0o700)
(target/'Theme.qml').write_text((root/'Theme.qml').read_text())
(target/'Settings.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool groupWindows: true; property bool reduceMotion: false; property bool reduceTransparency: false; property string font: "sans"; property string monoFont: "monospace" }')
(target/'services/Hyprland.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
 property QtObject workspaces: QtObject { property var values: [] }
 property QtObject toplevels: QtObject { property var values: [] }
 property var focusedWorkspace: null
 property var activeToplevel: null
 signal rawEvent(var event)
 property var commands: []
 function dispatch(cmd) { commands = [...commands, cmd]; console.log("dispatch", cmd); }
 function refreshWorkspaces() {}
 function refreshToplevels() {}
 function refreshMonitors() {}
}''')
(target/'services/WorkspaceSync.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool settled: true }')
(target/'components/BarItem.qml').write_text('''import QtQuick
import QtQuick.Layouts
Item { id: root; default property alias content: layout.data
property bool contentAnimating: false; property bool _started: true
property int padLeft: 0; property int padRight: 0; property string name; property bool scrolls
signal clicked; signal scrollUp; signal scrollDown
implicitWidth: layout.implicitWidth; width: implicitWidth
RowLayout { id: layout; height: root.height }
}''')
(target/'components/AppIcon.qml').write_text('''import QtQuick
Item { property string windowClass; property bool focused; property bool urgent; property bool pressed
property real inkOpacity; readonly property real shift: 0
property var entry: null; property real token: Math.random()
implicitWidth: 16; implicitHeight: 30 }
''')
(target/'components/HoverPopup.qml').write_text('import QtQuick\nItem { property Item anchorItem; property bool hovered; property bool pressed; property bool open; property Component popup; property var item: null; property string text }')
(target/'OpenPopup.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var selected: null; property var owner: null; function toggle(owner) {} function browse(owner, hovered) {} }')
(target/'components/FlowMark.qml').write_text('''import QtQuick
import qs
Item { property bool held; property real slabY; property real slabHeight; property bool atFirst; property bool atLast
property real wallLeft; property real wallRight; property real wantLeft; property real wantRight; property bool resizing
property real spring; property real damping; property int inset: Theme.markInset; property bool animating: false }''')
if '--marks' in sys.argv or '--mark-input' in sys.argv:
    (target/'components/FlowMark.qml').write_text((root/'components/FlowMark.qml').read_text())
    # Inspect the real animation's shader geometry without requiring a GPU.
    (target/'components/Liquid.qml').write_text('''import QtQuick
Item {
 property vector4d box0; property vector4d box1; property vector4d box2; property vector4d box3
 property real reach; property vector4d reaches; property vector4d fill; property vector4d rimTop
 property real rimFrom; property real rimTo
}''')
(target/'components/BarText.qml').write_text('import QtQuick\nText { property bool tightWidth; property int fontSize }')
(target/'components/Bounce.qml').write_text((root/'components/Bounce.qml').read_text())
(target/'components/DropLine.qml').write_text((root/'components/DropLine.qml').read_text())
if '--real-icons' in sys.argv:
    for name in ('AppIcon', 'FittedIcon', 'InkProbe', 'Glyph', 'BarText'):
        source=(root/f'components/{name}.qml').read_text()
        if name == 'AppIcon':
            source=source.replace('id: root', 'id: root\n    property real token: Math.random()', 1)
        (target/f'components/{name}.qml').write_text(source)
    for name in ('AppIcons', 'IconInk', 'GlyphInk'):
        (target/f'services/{name}.qml').write_text((root/f'services/{name}.qml').read_text())
    (target/'assets').symlink_to(root/'assets', target_is_directory=True)
if '--real-bar' in sys.argv:
    for name in ('BarItem', 'ClickArea', 'Rim', 'Badge'):
        (target/f'components/{name}.qml').write_text((root/f'components/{name}.qml').read_text())
    (target/'components/Pill.qml').write_text('import QtQuick\nItem { property bool dragging: false; property Item dragSource: null }')
    (target/'DrawerPins.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function pinned(key) { return false; } function kept(key) { return false; } function toggle(key) {} }')
workspaces_source=Path(sys.argv[sys.argv.index('--workspaces')+1]) if '--workspaces' in sys.argv else root/'modules/Workspaces.qml'
src=workspaces_source.read_text().replace('import Quickshell.Hyprland','').replace('event: HyprlandEvent','event')
src=src.replace('id: root','''id: root
    property alias auditStrip: strip
    property alias auditButtons: buttons
    property alias auditWorkspaces: workspaces
    property alias auditGhost: ghost
    property alias auditTracker: positionTracker
    property alias auditNewWorkspace: newWorkspace''',1)
if '--marks' in sys.argv or '--mark-input' in sys.argv:
    src=src.replace('id: root', 'id: root\n    property alias auditMark: mark', 1)
src=src.replace('id: button\n','id: button\n                    property alias auditRow: row\n',1)
(target/'Workspaces.qml').write_text(src)

shell_source=r"""import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
ShellRoot {
 id: suite
 property var failures: []
 Component { id: workspace; QtObject { property int id; property string name; property bool active: false; property bool urgent: false; property var lastIpcObject: ({}) } }
 Component { id: toplevel; QtObject { property string address; property var workspace; property var wayland; property var lastIpcObject: ({}); property bool urgent: false } }
 Window { id: scene; visible: true; width: 800; height: 100; Workspaces { id: pill; width: implicitWidth; height: 38 } }
 TestCase { id: test; when: false }
 function check(ok,message) { if (!ok) { failures.push(message); console.log('FAIL: '+message); } }
 function ws(id) { return workspace.createObject(suite,{id:id,name:String(id),active:id===1}); }
 function win(address,ws,cls) { return toplevel.createObject(suite,{address:address,workspace:ws,wayland:{appId:cls}}); }
 function move(window,destination) { Hyprland.rawEvent({name:'movewindowv2',data:window.address+','+destination.id+','+destination.name});window.workspace=destination; }
 function button(id) { for (let i=0;i<pill.auditWorkspaces.count;i++) { const b=pill.auditWorkspaces.itemAt(i);if(b.workspaceInfo.id===id)return b; } return null; }
 function icons(button) { return button.auditRow.children.filter(c=>c.icon!==undefined); }
 function icon(button,address) { return icons(button).find(c=>c.modelData===address); }
 function instant(app,message) { check(app && app.opacity===1 && app.shift===0 && !pill.auditGhost.visible,message); }
 function left(item) { return item.mapToItem(pill.auditStrip,0,0).x; }
 function reset(windows,workspaces) { Hyprland.workspaces.values=workspaces;Hyprland.focusedWorkspace=workspaces[0];Hyprland.toplevels.values=windows;test.wait(1200); }
 Timer { interval:100;running:true;onTriggered:{
 try {
 test.tryCompare(pill,'_started',true,Theme.startMs+500);
 const w1=ws(1),w2=ws(2),w3=ws(3);
 const a=win('a',w2,'incoming'),b=win('b',w3,'existing'),c=win('c',w1,'other');
 reset([b,c,a],[w1,w2,w3]);
 const oldB=left(icon(button(3),'b'));
 move(a,w3);test.wait(35);
 const dest=button(3);
 check(Math.abs(left(icon(dest,'b'))-oldB)<Theme.workspaceGap,'surviving icon stays near its old position as collapse begins');
 check(Math.abs(icon(dest,'a').drawnX-icon(dest,'a').x)<1,'moved icon appears directly in its destination slot');
 const rightEdge=pill.auditStrip.mapFromItem(pill,pill.width-2,19).x;
 const hitPoint=Qt.point(Math.min(rightEdge,left(dest)+dest.width-4),19);
 check(pill.buttonAt(hitPoint)===dest,'drop target covers the drawn workspace');
 check(pill.buttonAt(Qt.point(dest.x+2,19))!==dest,'drop target rejects vacated workspace area');
 instant(icon(dest,'a'),'compositor transfer immediately shows the destination without a ghost or animation');
 test.wait(185);
 instant(icon(dest,'a'),'compositor transfer remains visible without a delayed animation');
 test.wait(1500);
 check(Math.abs(left(dest)-dest.x)<1,'workspace settles to its layout position');
 check(Math.abs(left(icon(dest,'a'))-(dest.x+icon(dest,'a').x))<1,'moved icon settles in destination slot');
 test.wait(1500);check(!pill.auditTracker.running,'position sampling stops at rest');

 a.workspace=w2;a.wayland={appId:'same'};b.wayland={appId:'same'};
 reset([b,c,a],[w1,w2,w3]);
 const group=button(3);
 check(Math.abs(group.slotX('same','a')-(icon(group,'b').x+icon(group,'b').width/2))<1,'grouped drop points at the existing application icon');
 move(a,w3);test.wait(220);
 check(icon(group,'a').icon.folded,'grouped arrival uses the existing representative');
 instant(icon(group,'b'),'grouped arrival leaves its representative visible and still');
 Hyprland.toplevels.values=[a,b,c];test.wait(1500);
 const tokenA=icon(group,'a').token,tokenB=icon(group,'b').token;
 pill.expand(w3,'same');test.wait(100);
 check(icon(group,'b').reveal>0 && icon(group,'b').reveal<1,'group expansion animates');
 test.wait(300);pill.collapse();test.wait(300);
 check(icon(group,'b').reveal===0 && icon(group,'a').token===tokenA && icon(group,'b').token===tokenB,'group folding preserves delegates');
 pill.expand(w3,'same');test.wait(300);
 WorkspaceSync.settled=false;
 w3.id=2;test.wait(40);
 check(pill.expandedWorkspace===3,'frozen expansion keeps its original workspace ID');
 check(button(3)!==null && icon(button(3),'a')!==undefined,'frozen IDs retain their icons through renumbering');
 WorkspaceSync.settled=true;test.wait(1500);
 check(button(2)!==null && button(3)===null && icon(button(2),'a')!==undefined,'settled snapshot reflects new workspace IDs');

 // Exercise release while compositor acknowledgement is delayed.
 a.workspace=w2;w2.id=3;w2.name='3';a.wayland={appId:'dragged'};b.wayland={appId:'existing'};
 reset([b,c,a],[w1,w3,w2]);
 const source=button(3),destination=button(2),dragged=icon(source,'a');
 pill.dragSource=dragged;pill.dragAddress='a';pill.dragWorkspace=w2;pill.dragWorkspaceId=3;
 pill.dragPoint=Qt.point(left(destination)+destination.width/2,19);pill.dragging=true;
 pill.finishDrag(pill.dragPoint);
 check(!pill.dragging && !pill.auditGhost.visible,'release immediately removes the drag preview');
 test.wait(60);
 instant(icon(button(3),'a'),'source remains visible while compositor acknowledgement is pending');
 move(a,w3);test.wait(35);
 instant(icon(button(2),'a'),'acknowledgement immediately shows the destination icon');
 check(button(3)===null || icon(button(3),'a')===undefined,'acknowledgement removes the source icon');
 test.wait(400);
 instant(icon(button(2),'a'),'transfer stays still after acknowledgement');

 Settings.reduceMotion=true;move(a,w2);test.wait(35);
 instant(icon(button(3),'a'),'reduced motion transfer is immediately visible and still');
 test.wait(700);
 instant(icon(button(3),'a'),'reduced motion transfer has no delayed pulse');
 Settings.reduceMotion=false;

 // Append a workspace through the empty drag slot.
 a.workspace=w2;reset([b,c,a],[w1,w3,w2]);
 pill.dragSource=icon(button(3),'a');pill.dragAddress='a';pill.dragWorkspace=w2;pill.dragWorkspaceId=3;
 pill.dragPoint=Qt.point(0,19);pill.dragging=true;test.wait(1200);
 const freshSlot=pill.auditNewWorkspace;
 check(freshSlot.visible && pill.nextWorkspaceId()===4,'drag offers the next workspace ID');
 pill.dragPoint=Qt.point(Math.min(pill.width-2,freshSlot.x+freshSlot.width/2),19);
 pill.finishDrag(pill.dragPoint);
 check(!pill.auditGhost.visible,'append release immediately removes the drag preview');
 const fourth=ws(4);Hyprland.workspaces.values=[w1,w3,w2,fourth];move(a,fourth);
 test.wait(35);
 check(button(4)!==null && icon(button(4),'a')!==undefined,'appended workspace receives the icon');
 instant(icon(button(4),'a'),'appended workspace immediately shows its icon');
 test.wait(465);
 test.wait(1200);

 // Insert into a gap while the existing workspaces are renumbered.
 pill.dragSource=icon(button(4),'a');pill.dragAddress='a';pill.dragWorkspace=fourth;pill.dragWorkspaceId=4;
 pill.dragPoint=Qt.point((left(button(1))+button(1).width+left(button(2)))/2,19);pill.dragging=true;
 test.wait(300);
 check(pill.insertAt===1 && button(2).gapBefore>0,'hover opens the insertion gap');
 pill.finishDrag(pill.dragPoint);WorkspaceSync.settled=false;
 Hyprland.rawEvent({name:'changeworkspaceid',data:'4,5'});Hyprland.rawEvent({name:'changeworkspaceid',data:'2,3'});
 w3.id=3;w3.name='3';fourth.id=5;fourth.name='5';
 const inserted=ws(2);Hyprland.workspaces.values=[w1,inserted,w3,fourth];move(a,inserted);
 test.wait(40);
 check(icon(button(4),'a')!==undefined && !pill.auditGhost.visible,'insertion freezes the old placement without a ghost');
 WorkspaceSync.settled=true;test.wait(600);
 check(button(2)!==null && icon(button(2),'a')!==undefined && icon(button(3),'b')!==undefined && button(4)===null,'insertion remaps icons to their new workspace IDs');
 instant(icon(button(2),'a'),'inserted workspace shows its icon without an arrival effect');

 // Freeze after the IPC models have already started to disagree.
 test.wait(1500);
 const placeholder=ws(-1);a.workspace=placeholder;WorkspaceSync.settled=false;
 test.wait(40);
 check(pill.frozen.placement.a===2 && icon(button(2),'a')!==undefined,'late freeze restores the last drawn placement instead of capturing a placeholder');
 a.workspace=inserted;WorkspaceSync.settled=true;test.wait(300);

 console.log(failures.length ? 'FAIL: '+failures.length+' workspace checks' : 'PASS: workspace collapse, transfers, targeting, grouping and freeze');
 }catch(e){console.log('FAIL: '+e);}
 Qt.quit();
 } }
}
"""
if '--marks' in sys.argv:
    shell_source=shell_source.replace('import qs.services', 'import qs.services\nimport qs.components', 1)
    shell_source=shell_source.replace(' property var failures: []', ''' property var failures: []
 Component { id: sharedMark; FlowMark { width: 600; height: 38; slabHeight: Theme.barHeight; wallLeft: 0; wallRight: 600; wantLeft: 30; wantRight: 60 } }
''', 1)
    start=shell_source.index(" const w1=ws(1)")
    end=shell_source.index(" console.log(failures.length", start)
    shell_source=shell_source[:start]+r'''
 const w1=ws(1),w2=ws(2),w3=ws(3),empty=ws(4);
 const a=win('a',w1,'first'),b=win('b',w2,'second'),c=win('c',w3,'third');
 reset([a,b,c],[w1,w2,w3]);
 const mark=pill.auditMark;
 empty.active=true;w1.active=false;
 Hyprland.workspaces.values=[w1,w2,w3,empty];Hyprland.focusedWorkspace=empty;
 let extraMarks=0,maxError=0;
 for(let ms=0;ms<800;ms+=10) {
   test.wait(10);
   if(mark.box2.z!==0 || mark.box3.z!==0 || Math.abs(mark.box0.x-mark.frontLeft)>0.001 || Math.abs(mark.box1.z-mark.bulbWidth)>0.001) extraMarks++;
   if(ms===140) check(Math.abs(mark.headLeft-mark.wantLeft)>2,'slower workspace mark is still travelling after 150ms');
   if(ms>=350) maxError=Math.max(maxError,Math.abs(mark.headLeft-mark.wantLeft),Math.abs(mark.headRight-mark.wantRight));
 }
 console.log('TRACE: new empty workspace: extra mark samples='+extraMarks+', error after 350ms='+maxError.toFixed(2));
 check(extraMarks===0,'first-to-last jump draws only the active mark and wall bulge');
 check(maxError<1,'workspace mark settles within 350ms');
 check(mark.placedOn===button(4),'new empty workspace receives the mark');

 // Adjacent moves and interrupted reversals retain spring motion.
 empty.active=false;w3.active=true;Hyprland.focusedWorkspace=w3;test.wait(60);
 check(mark.animating,'adjacent workspace change retains spring motion');
 check(mark.box2.z===0 && mark.box3.z===0,'adjacent workspace change has no trailing mark or connector');
 test.wait(300);
 check(Math.abs(mark.headLeft-mark.wantLeft)<1 && Math.abs(mark.headRight-mark.wantRight)<1,'mark follows layout after removing the empty slot');
 empty.active=true;w3.active=false;Hyprland.focusedWorkspace=empty;test.wait(60);
 w3.active=true;empty.active=false;Hyprland.focusedWorkspace=w3;test.wait(300);
 check(Math.abs(mark.headRight-mark.wantRight)<1 && Math.abs(mark.headLeft-mark.wantLeft)<1,'interrupted adjacent move settles promptly');
 Settings.reduceMotion=true;Hyprland.focusedWorkspace=w1;test.wait(300);
 check(Math.abs(mark.headLeft-mark.wantLeft)<1 && Math.abs(mark.headRight-mark.wantRight)<1,'reduced motion reaches its destination promptly');
 Settings.reduceMotion=false;
 const power=sharedMark.createObject(scene),keys=sharedMark.createObject(scene,{spring:Theme.keyMarkSpring,damping:Theme.keyMarkDamping});
 test.wait(50);power.placed=true;keys.placed=true;
 power.wantLeft=160;power.wantRight=190;keys.wantLeft=160;keys.wantRight=190;
 test.wait(280);
 check(Math.abs(power.headLeft-power.wantLeft)<1 && Math.abs(power.headRight-power.wantRight)<1,'shared power selector motion settles promptly');
 check(Math.abs(keys.headLeft-keys.wantLeft)<1 && Math.abs(keys.headRight-keys.wantRight)<1,'keyboard selection motion settles promptly');

 // Overshoot still compresses the mark against the pill's ends.
 const edge=sharedMark.createObject(scene,{atLast:true,wallRight:190});test.wait(50);
 edge.placed=true;
 edge.wantLeft=160;edge.wantRight=190;
 let peakPress=0,escaped=false;
 for(let ms=0;ms<300;ms+=10) {
   test.wait(10);peakPress=Math.max(peakPress,edge.press);
   escaped=escaped || edge.frontRight>edge.wallRight;
 }
 check(peakPress>0 && !escaped,'spring overshoot keeps the right-wall bounce inside the pill');
 edge.atLast=false;edge.atFirst=true;edge.wantLeft=0;edge.wantRight=30;
 peakPress=0;escaped=false;
 for(let ms=0;ms<300;ms+=10) {
   test.wait(10);peakPress=Math.max(peakPress,edge.press);
   escaped=escaped || edge.frontLeft<edge.wallLeft;
 }
 check(peakPress>0 && !escaped,'spring overshoot keeps the left-wall bounce inside the pill');
 console.log(failures.length ? 'FAIL: '+failures.length+' mark checks' : 'PASS: workspace mark geometry and timing');
 Qt.quit();return;
''' + shell_source[end:]
if '--mark-input' in sys.argv:
    start=shell_source.index(" const w1=ws(1)")
    end=shell_source.index(" console.log(failures.length", start)
    shell_source=shell_source[:start]+r'''
 const w1=ws(1),w2=ws(2),w3=ws(3);
 const a=win('a',w1,'first'),b=win('b',w2,'second'),c=win('c',w3,'third');
 reset([a,b,c],[w1,w2,w3]);
 const mark=pill.auditMark;
 function background(id) { const item=button(id); return left(item)+item.width+4; }
 function pressBackground(id) { test.mousePress(pill,background(id),19); test.wait(20); }
 let x=background(1);
 test.mouseClick(pill,x,19);test.wait(20);
 check(Hyprland.commands.length===0,'background click on the current workspace remains a click');
 const originalLeft=mark.wantLeft,originalRight=mark.wantRight;
 pressBackground(1);
 test.mouseMove(pill,x+2,19,20);
 test.mouseMove(pill,x+40,19,20);test.wait(20);
 check(mark.wantLeft===originalLeft && mark.wantRight===originalRight && mark.placedOn===button(1),
   'dragging the workspace background does not move the selection mark');
 check(!pill.dragging && Hyprland.commands.length===0,'background gesture neither drags windows nor switches workspaces');
 test.mouseRelease(pill,-40,19);test.wait(500);
 check(Hyprland.commands.length===0 && mark.placedOn===button(1),'release outside the pill keeps the focused workspace');

 test.mouseClick(pill,background(2),19);test.wait(30);
 check(Hyprland.commands.length===1 && Hyprland.commands[0]==='hl.dsp.focus({ workspace = 2 })',
   'background click on another workspace still requests one focus switch');
 check(mark.placedOn===button(1),'mark follows compositor focus rather than the pointer');
 w1.active=false;w2.active=true;Hyprland.focusedWorkspace=w2;test.wait(500);
 check(mark.placedOn===button(2),'compositor focus moves the selection mark');
 OpenPopup.selected=button(3);test.wait(500);
 check(mark.placedOn===button(3),'keyboard selection still moves the mark');
 OpenPopup.selected=null;test.wait(500);
 check(mark.placedOn===button(2),'leaving keyboard selection restores the focused mark');

 Hyprland.commands=[];
 pressBackground(2);test.mouseMove(pill,background(3),19,20);test.wait(20);
 WorkspaceSync.settled=false;test.wait(20);
 test.mouseRelease(pill,background(3),19);WorkspaceSync.settled=true;test.wait(500);
 check(Hyprland.commands.length===0,'workspace renumbering cancels background input without switching focus');

 const app=icon(button(2),'b');
 test.mousePress(app,app.width/2,19);
 test.mouseMove(pill,left(app)+app.width/2+30,19,20);test.wait(30);
 check(pill.dragging,'icon gesture still drags its window');
 test.mouseRelease(pill,-40,80);test.wait(30);
 check(!pill.dragging,'window drag still releases normally');
 console.log(failures.length ? 'FAIL: '+failures.length+' mark input checks' : 'PASS: fixed mark, workspace clicks, keyboard selection and window dragging');
 Qt.quit();return;
''' + shell_source[end:]
if '--regressions' in sys.argv:
    shell_source=shell_source.replace(' property var failures: []', ''' property var failures: []
 property string captureAddress: ""
 property var samples: []
 property var frameUpdate: null
 FrameAnimation { running: suite.frameUpdate !== null; onTriggered: {
   const update=suite.frameUpdate;suite.frameUpdate=null;update();
 } }
 FrameAnimation { running: suite.captureAddress !== "" }
 Connections { target: scene; function onFrameSwapped() {
   if (!suite.captureAddress) return;
   for (let i=0;i<pill.auditWorkspaces.count;i++) {
     const b=pill.auditWorkspaces.itemAt(i),app=icon(b,suite.captureAddress);
     const before=pill.auditWorkspaces.itemAt(i-1);
     if (app && app.visible) suite.samples.push({x:left(app),width:app.width,right:pill.auditStrip.implicitWidth,beforeEnd:before?left(before)+before.width:0,offset:app.shift,opacity:app.opacity,ghost:pill.auditGhost.visible,workspace:b.workspaceInfo.id});
   }
 } }
''')
    start=shell_source.index(" const w1=ws(1)")
    end=shell_source.index(" console.log(failures.length", start)
    shell_source=shell_source[:start]+r'''
 const w1=ws(1),w2=ws(2),w3=ws(3);
 const a=win('a',w2,'incoming'),b=win('b',w3,'existing'),c=win('c',w1,'other');
 reset([b,c,a],[w1,w2,w3]);suite.samples=[];suite.captureAddress='a';
 move(a,w3);test.wait(30);
 WorkspaceSync.settled=false;
 Hyprland.rawEvent({name:'changeworkspaceid',data:'3,2'});
 const compacted=ws(2);Hyprland.workspaces.values=[w1,compacted];
 a.workspace=compacted;b.workspace=compacted;test.wait(35);
 WorkspaceSync.settled=true;test.wait(200);
 test.wait(800);suite.captureAddress='';
 check(suite.samples.length>0 && suite.samples.every(s=>s.offset===0 && s.opacity===1 && !s.ghost),'move and compaction never bounce, fade or retain a ghost');
 instant(icon(button(2),'b'),'compaction leaves the surviving icon still');

 // Use separate, contiguous source and destination IDs for a newly appended workspace.
 a.workspace=w2;w2.id=3;w2.name='3';reset([b,c,a],[w1,compacted,w2]);
 pill.dragSource=icon(button(3),'a');pill.dragAddress='a';pill.dragWorkspace=w2;pill.dragWorkspaceId=3;
 pill.dragPoint=Qt.point(0,19);pill.dragging=true;test.wait(300);
 const slot=pill.auditNewWorkspace;
 pill.dragPoint=Qt.point(Math.min(pill.width-2,slot.x+slot.width/2),19);pill.finishDrag(pill.dragPoint);
 suite.samples=[];suite.captureAddress='a';
 const appended=ws(4);suite.frameUpdate=()=>{
   Hyprland.workspaces.values=[w1,compacted,w2,appended];a.workspace=appended;
   // Exercise the existing frame callback before Qt polishes newly created delegates.
   pill.auditTracker.triggered();
 };
 test.wait(900);suite.captureAddress='';
 const endIcon=icon(button(4),'a'),endX=left(endIcon);
 const destinationSamples=suite.samples.filter(s=>s.workspace===4);
 console.log('TRACE: appended icon first frames: '+JSON.stringify(destinationSamples.slice(0,8))+'; settled x='+endX);
 check(destinationSamples.length>0 && destinationSamples.every(s=>s.x>=s.beforeEnd),'an appended icon never crosses earlier workspaces from the beginning of the strip');
 check(destinationSamples.every(s=>s.x+s.width<=s.right+2),'an appended icon stays inside the drawn strip');
 check(destinationSamples.every(s=>s.offset===0 && s.opacity===1 && !s.ghost),'appended icon is fully visible without a bounce, fade or ghost in every rendered frame');
''' + shell_source[end:]
    if '--real-icons' in sys.argv:
        shell_source=shell_source.replace("win('a',w2,'incoming'),b=win('b',w3,'existing'),c=win('c',w1,'other')", "win('a',w2,'kitty'),b=win('b',w3,'firefox'),c=win('c',w1,'thunar')")
(target/'shell.qml').write_text(shell_source)
env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(target/'runtime'))
for key in ('WAYLAND_DISPLAY','HYPRLAND_INSTANCE_SIGNATURE'):env.pop(key,None)
res=subprocess.run(['quickshell','-p',str(target),'--no-color'],env=env,capture_output=True,text=True,timeout=30)
out=res.stdout+res.stderr
print(out,end='')
folder.cleanup()
errors=('ReferenceError:', 'TypeError:', 'Binding loop', 'Cannot assign', 'Unable to assign', 'Failed to load configuration')
raise SystemExit(0 if res.returncode==0 and 'PASS:' in out and 'FAIL:' not in out and not any(error in out for error in errors) else 1)
