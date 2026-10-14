#!/usr/bin/env python3
"""Browse real morph popups using the music and timer pill bindings from Bar."""

import os
from pathlib import Path
import re
import subprocess
import tempfile

from test_support import offscreen_ink


ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / "Bar.qml").read_text()
    functions = '    readonly property var drops: Drops.geometry(Theme)\n    function morph(box, s) { return bar.drops.morph(box, s); }\n    function morphContents(s) { return bar.drops.morphContents(s); }'
    pills = []
    for name in ("music", "countdown"):
        block = source.split(f"id: {name}Pill", 1)[1].split(f"id: {name}\n", 1)[0]
        bindings = "\n".join(line for line in block.splitlines() if re.match(
            r"\s*(contentOpacity|contentScale|contentSink|interactive|trackReady):", line))
        pills.append(f"""
        Morph {{ id: {name}Morph; open: {name}.popupOpen }}
        SidePill {{
            control: {name}; morphValue: {name}Morph.value
            id: {name}Pill; drawsSlab: false; side: Pill.Side.Left
            edgeOffset: {100 if name == 'music' else 350}
            {bindings}
            BarItem {{
                id: {name}
                popup: Popup {{ morphs: true; probes: false; Rectangle {{ implicitWidth: 180; implicitHeight: 80 }} }}
                Rectangle {{ implicitWidth: 120; implicitHeight: 20 }}
            }}
        }}
""")
    qml = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import "Drops.js" as Drops
ShellRoot {
    FloatingWindow {
        id: bar; implicitWidth: 700; implicitHeight: 100
        function contents(reveal) { return 1; }
        FUNCTIONS
        Item { id: ordinary; width: 30; height: 40 }
        PILLS
        TestCase {
            id: test; when: false
            property int failures: 0
            function check(ok, message) {
                console.log((ok ? "PASS: " : "FAIL: ") + message);
                if (!ok) failures++;
            }
            function browse(item) {
                OpenPopup.browse(item, true);
                wait(OpenPopup.browseDelayMs + 80);
                check(OpenPopup.owner === item, "hover dwell transfers popup ownership");
            }
            function shown(pill, item, morph, label) {
                check(morph.value === 0 && pill.contentOpacity === 1 && pill.contentScale === 1,
                      label + " pill remains visible at full size");
                check(pill.enabled, label + " pill remains interactive alongside popup");
                check(pill.trackReady, label + " pill keeps its progress track");
                const popup = item.popupItem;
                check(popup?.opened && !popup.morphRun, label + " popup fades during handover");
                if (popup) {
                    const y = item.mapToItem(null, 0, 0).y + popup.anchor.rect.height + popup.shadowTop;
                    const expected = Theme.pillTop(item.height) + Theme.barHeight + Theme.popupGap;
                    check(Math.abs(y - expected) < 0.01,
                          label + " popup stays at pill bottom + gap (got " + y + ", expected " + expected + ")");
                }
            }
            function run() {
                OpenPopup.set(ordinary);
                browse(music);
                shown(musicPill, music, musicMorph, "music");
                browse(countdown);
                shown(countdownPill, countdown, countdownMorph, "timer");
                browse(music);
                shown(musicPill, music, musicMorph, "return to music");
                OpenPopup.dismiss(); wait(600);
                check(musicMorph.value === 0 && countdownMorph.value === 0, "browsed pills stay in place after dismissal");
                music.togglePopup(); wait(900);
                check(musicMorph.value === 2 && music.popupItem?.morphRun,
                      "direct music opening still morphs pill into popup");
                OpenPopup.dismiss(); wait(800);
                check(musicMorph.value === 0, "direct morph restores pill on close");
                countdown.togglePopup(); wait(900);
                check(countdownMorph.value === 2 && countdown.popupItem?.morphRun,
                      "direct timer opening still morphs pill into popup");
                browse(music);
                shown(musicPill, music, musicMorph, "music after direct timer morph");
                wait(800);
                check(countdownMorph.value === 0, "departing direct timer morph restores its pill");
                OpenPopup.dismiss(); wait(600);
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                OpenPopup.set(ordinary);
                browse(countdown);
                shown(countdownPill, countdown, countdownMorph, "timer with reduced motion");
                OpenPopup.dismiss(); wait(600);
                countdown.togglePopup(); wait(150);
                check(countdownMorph.value === 2 && !countdown.popupItem?.morphRun,
                      "direct opening with reduced motion still skips animation");
                OpenPopup.dismiss(); wait(150);
                check(countdownMorph.value === 0, "reduced motion restores pill immediately");
                console.log(failures ? "FAILED: popup browsing morph" : "PASS: popup browsing morph complete");
            }
        }
        Timer {
            interval: 150; running: true
            onTriggered: {
                try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
                Qt.quit();
            }
        }
    }
}
'''.replace("FUNCTIONS", functions).replace("PILLS", "\n".join(pills))
    with tempfile.TemporaryDirectory(prefix="qs-browse-") as folder:
        target = Path(folder)
        for item in ROOT.iterdir():
            if item.name not in (".git", "settings.json", "shell.qml"):
                (target / item.name).symlink_to(item)
        (target / "settings.json").write_text("{}\n")
        offscreen_ink(target)
        (target / "shell.qml").write_text(qml)
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(target / "state"),
                   XDG_CACHE_HOME=str(target / "cache"), XDG_DATA_HOME=str(target / "data"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "qml:" in line or "ERROR" in line))
        ok = result.returncode == 0 and "PASS: popup browsing morph complete" in output and "FAIL:" not in output
        for error in ("ReferenceError:", "TypeError:", "Binding loop", "Unable to assign"):
            ok = ok and error not in output
        if not ok:
            print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
