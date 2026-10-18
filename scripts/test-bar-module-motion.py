#!/usr/bin/env python3
"""Check full-size text, reversible icon motion, and the real MPRIS icon handoff."""

import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env

QML = '''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
ShellRoot {
    FloatingWindow {
        id: window; implicitWidth: 1200; implicitHeight: 140
        Pill {
            id: centre; side: Pill.Side.Centre; centreOn: clock.keyBox; drawsSlab: false
            BarItem {
                id: note; folds: false; foldDuration: 0
                stowed: player.iconHandoff.progress === 0
                implicitWidth: Math.round(_fullWidth * player.iconHandoff.progress)
                AppIcon {
                    id: merged; tightWidth: true; Layout.fillHeight: true
                    windowClass: player.shownApp
                    opacity: player.iconHandoff.progress
                    transform: Translate { x: player.iconHandoff.targetX }
                }
            }
            BarItem { id: clock; BarText { text: "Clock" } }
            BarItem {
                id: mixed; stowed: true
                Glyph { id: symbol; Layout.fillHeight: true; text: "X" }
                BarText { id: label; Layout.fillHeight: true; text: "A module label" }
            }
        }
        Pill {
            id: right; side: Pill.Side.Right; drawsSlab: false
            stretch: modules.reduce((sum, m) => sum + (m.here ? m.overrun : 0), drawer.windup)
            Drawer { id: drawer; holding: true }
            BarItem {
                id: drawerModule; settingsKey: "test"; stowed: !drawer.out
                Glyph { id: drawerIcon; text: "X" }
                BarText { text: "Drawer module" }
            }
        }
        SidePill {
            id: side; control: player; slidesContent: true; side: Pill.Side.Right
            edgeOffset: window.width - centre.x + Theme.pillSpread
            NowPlaying {
                id: player; stowed: false; mergedIcon: merged
                shownLabel: "A test track"; shownApp: ""
                foldDuration: Theme.dropMs; foldEasing: Easing.Linear
            }
        }
        TestCase {
            id: test; when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function sourceIcon(item) {
                if (item instanceof AppIcon) return item;
                for (const child of item.children) { const found = sourceIcon(child); if (found) return found; }
                return null;
            }
            function handoff(closing) {
                player.stowed = closing;
                const source = sourceIcon(player);
                let frames = 0;
                for (let frame = 0; frame < 50; frame++) {
                    wait(16);
                    const progress = player.iconHandoff.progress;
                    check(source.scale === 1, "MPRIS icon retains its size");
                    if (progress > 0 && progress < 1) {
                        frames++;
                        const a = source.mapToItem(window.contentItem, 0, 0);
                        const b = merged.mapToItem(window.contentItem, 0, 0);
                        check(Math.abs(a.x-b.x) < 0.1 && Math.abs(a.y-b.y) < 0.1,
                              "MPRIS icon copies coincide in both directions");
                        check(Math.abs(source.opacity + merged.opacity - 1) < 0.001,
                              "MPRIS icon has no opacity gap");
                    }
                }
                check(frames > 2, "sampled MPRIS " + (closing ? "merge" : "expansion"));
                check(closing ? !side.visible && note.visible : side.visible && !note.visible,
                      "MPRIS handoff ends with one visible icon");
            }
            function run() {
                wait(Theme.startMs + 100);
                mixed.stowed = false;
                let scaled = false, clipped = false, centrePeak = 0;
                for (let frame = 0; frame < 30; frame++) {
                    wait(10);
                    const icon = symbol.mapToItem(mixed, 0, 0, symbol.width, symbol.height);
                    const text = label.mapToItem(mixed, 0, 0, label.width, label.height);
                    scaled = scaled || icon.width < symbol.width * 0.999;
                    centrePeak = Math.max(centrePeak, mixed.overrun);
                    if (mixed.reveal > 0 && mixed.reveal < 1) {
                        clipped = clipped || mixed.clip;
                        check(Math.abs(mixed.keyBox.x + mixed.keyBox.width - mixed.width + mixed.padRight + mixed._rightGap) < 0.01,
                              "contents slide behind the clipped left edge at natural width");
                    }
                    check(Math.abs(text.width - label.width) < 0.01, "text always stays at full size");
                    check(icon.width <= symbol.width + 0.01, "icon never overshoots");
                }
                check(centrePeak > 1 && clipped, "centre modules keep their spring and clipped slide");
                check(scaled && mixed.keyBox.opacity === 1, "module icon scales while its text fades");
                mixed.stowed = true; wait(50); mixed.stowed = false; tryVerify(() => !mixed.animating, 2500);
                check(mixed.reveal === 1 && mixed.keyBox.opacity === 1 && !mixed.animating,
                      "interrupted exit returns to a clean resting state");
                for (const opening of [true, false]) {
                    drawer.open = opening;
                    wait(40);
                    check(drawer.out === !opening && (opening ? drawer.windup < 0 : drawer.windup > 0),
                          "drawer winds up before changing its modules");
                    let peak = 0, landed = false;
                    for (let frame = 0; frame < 90; frame++) {
                        wait(10);
                        peak = Math.max(peak, opening ? right.stretch : -right.stretch);
                        check(drawerModule.reveal >= 0 && drawerModule.reveal <= 1,
                              "spring never refolds an icon after it lands");
                        const target = opening ? 1 : 0;
                        if (landed) check(drawerModule.reveal === target, "landed slot stays put during the bounce");
                        landed = landed || drawerModule.reveal === target;
                        check(Math.abs(right.slabRect.width - (right.width - Theme.barMargin + right.stretch)) < 0.01,
                              "actual glass geometry receives the spring travel");
                        if (!opening && frame === 11)
                            check(drawerModule.reveal > 0 && drawerModule.reveal < 1 && drawerModule.keyBox.opacity >= 0.35,
                                  "exit stays legible as its contents slide into the drawer");
                        const icon = drawerIcon.mapToItem(drawerModule, 0, 0, drawerIcon.width, drawerIcon.height);
                        check(icon.width <= drawerIcon.width + 0.01 && drawerModule.clip === (drawerModule.reveal < 1),
                              "glass bounces while partially folded contents are clipped");
                    }
                    check(peak > 1, "right pill glass must bounce on " + (opening ? "expansion" : "contraction") + ": peak=" + peak);
                    console.log("PASS: right pill " + (opening ? "expansion" : "contraction") + " bounces by " + peak.toFixed(1) + " px");
                    tryVerify(() => !right.animating, 1800);
                    check(Math.abs(right.stretch) < 0.01 && drawer.turned === (opening ? 1 : 0),
                          "drawer glass and handle settle cleanly");
                }
                drawer.open = true; wait(80); drawer.open = false; wait(80); drawer.open = true;
                tryVerify(() => !right.animating, 2500);
                check(drawerModule.reveal === 1 && Math.abs(right.stretch) < 0.01,
                      "interrupted spring settles open");
                handoff(true); handoff(false);
                Settings.set("reduceMotion", true);
                drawer.open = false;
                check(right.stretch === 0, "reduced motion disables drawer bounce");
                mixed.stowed = true; wait(50);
                check(drawerModule.reveal === 0 && right.stretch === 0, "reduced motion closes drawer without spring travel");
                check(mixed.reveal === 0 && mixed.keyBox.opacity > 0 && mixed.keyBox.opacity < 1,
                      "reduced motion changes layout immediately and fades ink: reveal=" + mixed.reveal + ", opacity=" + mixed.keyBox.opacity);
                check(mixed.appearanceScale === 1, "reduced motion disables icon scaling");
                wait(200); check(!mixed.visible, "reduced motion finishes the fade");
                console.log("PASS: full-size text, icon scaling, interruption, reduced motion and MPRIS handoff");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-module-motion-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "PASS: full-size text" in output and not any(e in output for e in errors)
        print("PASS: full-size text, icon scaling, interruption, reduced motion and MPRIS handoff" if ok else output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
