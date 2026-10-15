#!/usr/bin/env python3
"""Exercise delayed song changes, waveform blending and hover previews."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from test_support import ROOT, copy_shell, shell_env

spec = importlib.util.spec_from_file_location("titles", ROOT / "scripts/test-music-titles.py")
titles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(titles)

SHELL = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services
ShellRoot {
    readonly property var popup: popupHost.item
    FileView { id: decodeLog; path: Quickshell.shellPath("decode.log"); blockLoading: true; printErrors: false }
    FloatingWindow {
        id: win; implicitWidth: 600; implicitHeight: 300
        Item { id: anchor; width: 40; height: 20 }
        TestCase {
            id: test; when: false
            function check(ok,message) { if(!ok) throw Error(message); console.log("PASS: "+message); }
            function named(item,name) {
                if(item.objectName===name) return item;
                for(const child of item.children||[]) { const result=named(child,name); if(result) return result; }
                return null;
            }
            function run() {
                tryVerify(()=>popup && popup.auditWaveform.loaded.endsWith("a.wav"),2000);wait(250);
                const source=popup.auditWaveform;
                const slider=named(popup.contentItem,"playback");
                const ripple=named(slider,"ripple");
                function raster() { return Array.from(ripple.getContext("2d").getImageData(0,0,ripple.width,ripple.height).data); }
                function at(index) {
                    const count=Math.floor(ripple.width/3);
                    return Math.floor((ripple.width-count*3)/2)+index*3+1;
                }
                function alpha(index) { return ripple.getContext("2d").getImageData(at(index),ripple.height-2,1,1).data[3]; }
                function barHeight(index) {
                    const data=ripple.getContext("2d").getImageData(at(index),0,1,ripple.height).data;
                    let result=0; for(let y=0;y<ripple.height;y++) if(data[y*4+3]>0) result++;
                    return result;
                }
                mouseMove(popup.contentItem,popup.contentItem.width-2,popup.contentItem.height-2);wait(250);
                const oldHeight=barHeight(2);
                check(barHeight(Math.floor(ripple.width/3)-3)>=10 && oldHeight<=4,"waveform stays large with pronounced peaks and valleys");
                const still=raster();
                const played=alpha(3), future=alpha(30), later=alpha(Math.floor(ripple.width/3)-3);
                mouseMove(slider,slider.width*0.65,slider.height/2);wait(250);
                const hovered=raster();
                check(still.every((v,i)=> i%4!==3 || (v>0)===(hovered[i]>0)),"hover never changes bar heights");
                check(alpha(3)===played && alpha(30)>future && alpha(Math.floor(ripple.width/3)-3)===later,
                    "hover lightens only unplayed bars up to the pointer");
                mouseMove(slider,slider.width*0.1,slider.height/2);wait(50);
                check(alpha(30)===future,"hovering behind the playhead leaves future bars grey");
                mouseMove(popup.contentItem,popup.contentItem.width-2,popup.contentItem.height-2);wait(250);
                const previous=JSON.stringify(source.samples);
                check(slider.waving,"first song waveform is visible");
                Mpd.file="b.wav";wait(75);
                check(source.samples.length===256 && JSON.stringify(source.samples)===previous && slider.waving && slider.waveAmount===1,
                    "song change holds the old waveform while the new one decodes");
                tryVerify(()=>source.loaded.endsWith("b.wav"),2000);
                tryVerify(()=>ripple.blend>=0.35 && ripple.blend<=0.7,500);
                ripple.auditMorph.pause();wait(30);
                check(ripple.blend>0 && ripple.blend<1 && barHeight(2)>oldHeight && barHeight(2)<11,
                    "replacement waveform blends through an intermediate shape after decoding");
                ripple.auditMorph.resume();
                tryCompare(ripple,"blend",1,1000);
                check(ripple.blend===1,"song transition settles on the new waveform");
                check(JSON.stringify(source.samples)!==previous,"new song waveform replaces the old one");
                Mpd.file="a.wav";
                tryVerify(()=>source.loaded.endsWith("a.wav"),2000);wait(80);
                check(ripple.blend>0 && ripple.blend<1,"rapid song changes can interrupt an in-progress blend");
                const previousBlend=ripple.blend;
                const visible=ripple.toSamples.map((value,i)=> {
                    const start=ripple.fromSamples[i]??value;
                    return start+(value-start)*previousBlend;
                });
                ripple.replaceSamples(Array(256).fill(0.65));
                check(ripple.fromSamples.every((value,i)=>Math.abs(value-visible[i])<0.000001),
                    "interrupted transition starts from the currently visible waveform");
                Mpd.file="b.wav";wait(60);Mpd.file="c.wav";
                tryVerify(()=>source.loaded.endsWith("c.wav"),2000);wait(450);
                check(source.samples.every(value=>value===0.65),"rapid skipping ignores superseded decoder output");
                Mpd.file="b.wav";wait(60);Mpd.file="c.wav";wait(450);
                check(source.loaded.endsWith("c.wav") && source.samples.every(value=>value===0.65) && source.beats[0]===1.5,
                    "returning to the displayed song retains its waveform and beat timings");
                Settings.set("reduceMotion",true);wait(30);
                ripple.replaceSamples(Array(256).fill(0.4));
                check(ripple.blend===1 && slider.waving,"Reduce motion replaces the waveform without animation or blanking");

                const samples=JSON.stringify(source.samples), beats=JSON.stringify(source.beats), loaded=source.loaded;
                decodeLog.reload();
                const decodes=decodeLog.text();
                popupHost.open=false;
                tryVerify(()=>popup===null,2000);
                check(popup===null,"closing music fully unloads the popup");
                popupHost.open=true;
                tryVerify(()=>popup!==null,1000);
                check(popup.auditWaveform.loaded===loaded && JSON.stringify(popup.auditWaveform.samples)===samples
                    && JSON.stringify(popup.auditWaveform.beats)===beats,"recreated music popup has the cached waveform immediately");
                wait(450);decodeLog.reload();
                check(decodeLog.text()===decodes,"reopening the same song starts no decoder");

                Mpd.file="https://example.invalid/stream";Mpd.duration=0;wait(250);
                const reopenedSlider=named(popup.contentItem,"playback");
                check(popup.auditWaveform.samples.length===0 && !reopenedSlider.waving && !reopenedSlider.enabled,
                    "streams use the existing flat tracker fallback");
                Mpd.file="c.wav";Mpd.duration=120;wait(250);decodeLog.reload();
                check(popup.auditWaveform.loaded===loaded && JSON.stringify(popup.auditWaveform.samples)===samples
                    && decodeLog.text()===decodes,"returning from a stream reuses the last local waveform");
                console.log("DONE: song transition");
            }
        }
    }
    HoverPopup { id: popupHost; anchorItem: anchor; open: true; popup: Component { MusicPopup {} } }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch(error) { console.log("FAIL: "+error+"\\n"+error.stack); }
        Qt.quit();
    } }
}'''

DECODER = '''import json,sys,time
from pathlib import Path
name=Path(sys.argv[1]).name
with Path(sys.argv[1]).with_name("decode.log").open("a") as log:
    log.write(name+"\\n")
time.sleep(0.35 if name=="b.wav" else 0.02)
bars=[0.15+0.85*i/255 if name=="a.wav" else 1-0.85*i/255 if name=="b.wav" else 0.65 for i in range(256)]
print(json.dumps({"bars":bars,"beats":[0.5 if name=="a.wav" else 1 if name=="b.wav" else 1.5],"duration":120}))
'''


def main():
    """Run the real popover against a controllably delayed song decoder."""
    with tempfile.TemporaryDirectory(prefix="qs-song-transition-") as folder:
        target = Path(folder)
        copy_shell(target)
        mpd = titles.MPD.replace('property string state: "play"', 'property string state: "pause"')
        mpd = mpd.replace('property string file: ""; property string musicDir: ""',
                          'property string file: "a.wav"; property string musicDir: ' + json.dumps(str(target) + '/'))
        (target / "services/Mpd.qml").write_text(mpd)
        (target / "services/Launcher.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property string musicPrefix: "#"; function openWith(prefix) {} }')
        (target / "scripts/music-waveform.py").write_text(DECODER)
        path = target / "components/Slider.qml"
        path.write_text(path.read_text().replace('id: ripple',
            'id: ripple\n            objectName: "ripple"\n            property alias auditMorph: morph'))
        path = target / "components/MusicPopup.qml"
        path.write_text(path.read_text().replace('id: root', 'id: root\n    property alias auditWaveform: waveform', 1)
            .replace('name: "Playback position"', 'objectName: "playback"\n                    name: "Playback position"'))
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines()
                        if any(marker in line for marker in ("PASS:", "DONE:", *errors))))
        return 0 if result.returncode == 0 and "DONE: song transition" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
