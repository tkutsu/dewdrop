#!/usr/bin/env python3
"""Render sliding pill contents against their actual glass in both directions."""

import argparse
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

from PIL import Image, ImageDraw
from test_support import ROOT, copy_shell, shell_env

QML = '''import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.components
import qs.modules
ShellRoot {
    PanelWindow {
        anchors.bottom: true; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:lab"
        mask: Region {}
        implicitWidth: 640; implicitHeight: 280; color: "black"
        Item {
            id: capture; anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "black" }
            property var frames: [1,.95,.9,.85,.8,.75,.65,.5,.3,.25,0,.25,.3,.5,.65,.75,.8,.85,.9,.95,1]
            property int index: 0
            property bool liveTiming: false
            property bool liveExpansion: false
            property double motionStarted: 0
            property var firstFade: [0,0]
            property var smallest: [1,1]
            property var largest: [1,1]
            property var firstGrow: [0,0]
            property var fullOpacity: [0,0]
            property var firstVisible: [0,0]
            readonly property bool leaving: liveTiming ? !liveExpansion : index < 11
            ROWS
            function save(name, next) {
                grabToImage(result => { result.saveToFile(Quickshell.shellPath(name)); next(); });
            }
            function anchor(item) {
                if (item.objectName === "anchorIcon") return item;
                for (const child of item.children) {
                    const found = anchor(child);
                    if (found) return found;
                }
                return null;
            }
            function checkBounce() {
                for (const pill of [musicPill, noticePill, timerPill, recordingPill]) {
                    const icon = anchor(pill);
                    const expected = pill === musicPill ? 1 : pill === noticePill
                        ? 0.9 + 0.1 * control1.senderInk : pill.iconScale;
                    if (icon.scale !== expected) {
                        console.log("FAIL: pill icon does not follow its motion policy");
                        Qt.quit();
                        return false;
                    }
                    if (pill !== noticePill && Math.abs(icon.scale - 1) > 0.000001 && (capture.leaving || pill.control.reveal >= 0.04)) {
                        for (let item = icon; item && item !== pill; item = item.parent) {
                            if (item.opacity < 0.999999) {
                                console.log("FAIL: icon bounce overlaps its fade at frame " + capture.index);
                                Qt.quit();
                                return false;
                            }
                        }
                    }
                }
                for (const pill of [timerPill]) {
                    const phase = Math.max(0, 2 * pill.control.reveal - 1);
                    const icon = anchor(pill);
                    const text = anchorText(pill);
                    let opacity = 1;
                    for (let item = icon; item && item !== pill; item = item.parent)
                        opacity *= item.opacity;
                    const progress = capture.leaving ? 2 * (1 - pill.control.reveal)
                        : 2 * Math.max(0, pill.control.reveal - 0.25);
                    const expectedScale = pill.geometry.iconScale(progress);
                    const expectedOpacity = capture.leaving
                        ? pill.geometry.contents(Math.min(1, pill.control.reveal * 2))
                        : Math.min(1, Math.max(0, pill.control.reveal - 0.25) / 0.04);
                    if (Math.abs(icon.scale - expectedScale) > 0.000001
                        || Math.abs(opacity - expectedOpacity) > 0.000001
                        || (phase > 0 && Math.abs(pill.foldBox.z - pill.width) > 0.001)
                        || text.width > (text.contentWidth + 1) * phase + 0.001
                        || (phase > 0 && phase < 1 && text.width >= text.contentWidth)) {
                        console.log("FAIL: staged bounce, fade or covered entry at frame " + capture.index
                            + ": " + JSON.stringify({phase, scale: icon.scale, expectedScale, opacity, expectedOpacity,
                                glass: pill.foldBox.z, width: pill.width, text: text.width, content: text.contentWidth}));
                        Qt.quit();
                        return false;
                    }
                }
                if (capture.index === 20)
                    console.log("PASS: both directions run the icon spring forward without scaling the glass or text");
                return true;
            }
            function anchorText(item) {
                if (item.objectName === "sequenceText") return item;
                for (const child of item.children) {
                    const found = anchorText(child);
                    if (found) return found;
                }
                return null;
            }
            function beginTiming() {
                liveTiming = true;
                timingStart.start();
            }
            function startMotion() {
                firstFade = [0,0];
                firstGrow = [0,0];
                fullOpacity = [0,0];
                firstVisible = [0,0];
                smallest = [1,1];
                largest = [1,1];
                motionStarted = Date.now();
                control1._eased = liveExpansion ? 1 : 0;
                control2._eased = liveExpansion ? 1 : 0;
                timing.start();
            }
            function checkTiming() {
                const elapsed = Date.now() - motionStarted;
                for (const [i, pill] of [timerPill].entries()) {
                    const icon = anchor(pill);
                    smallest[i] = Math.min(smallest[i], icon.scale);
                    largest[i] = Math.max(largest[i], icon.scale);
                    let opacity = 1;
                    for (let item = icon; item && item !== pill; item = item.parent)
                        opacity *= item.opacity;
                    if (!firstVisible[i] && opacity > 0.01) firstVisible[i] = elapsed;
                    if (liveExpansion && ((pill.control.reveal <= 0.25 && (opacity !== 0 || icon.scale !== 1))
                        || (opacity > 0 && icon.mapToItem(pill, 0, 0).x < -Theme.pillSpread))) {
                        console.log("FAIL: entry icon is visible or bouncing during its covered travel through the central pill");
                        Qt.quit();
                        return;
                    }
                    if (!firstGrow[i] && opacity > 0.01 && icon.scale > 1.01) firstGrow[i] = elapsed;
                    if (!fullOpacity[i] && opacity >= 0.999999) fullOpacity[i] = elapsed;
                    if (!firstFade[i] && opacity < 0.999999) firstFade[i] = elapsed;
                    if (!liveExpansion && elapsed < Theme.dropMs / 2 - 50 && (opacity !== 1 || Math.abs(pill.foldBox.z - pill.width) > 0.001)) {
                        console.log("FAIL: live icon faded or glass collapsed before its bounce finished");
                        Qt.quit();
                        return;
                    }
                    // Allow three frames for Qt's animation clock and wall clock to align.
                    if (elapsed > Theme.dropMs + 100 && ((!liveExpansion && (firstFade[i] < Theme.dropMs / 2 - 50 || firstFade[i] > Theme.dropMs / 2 + 100))
                        || (liveExpansion && (!fullOpacity[i] || fullOpacity[i] - firstVisible[i] > 65
                            || firstGrow[i] - firstVisible[i] > 50))
                        || !firstGrow[i] || (!liveExpansion && firstGrow[i] > 100)
                        || smallest[i] > 0.96 || largest[i] < 1.15 || pill.control.reveal !== (liveExpansion ? 1 : 0))) {
                        console.log("FAIL: live bounce timing " + JSON.stringify({firstFade: firstFade[i],
                            firstVisible: firstVisible[i], firstGrow: firstGrow[i], fullOpacity: fullOpacity[i], expansion: liveExpansion,
                            smallest: smallest[i], largest: largest[i], reveal: pill.control.reveal}));
                        Qt.quit();
                        return;
                    }
                }
                if (elapsed > Theme.dropMs + 100) {
                    if (!liveExpansion) {
                        console.log("PASS: contraction completes its bounce before fading in the " + Theme.dropMs + " ms transition");
                        timing.stop();
                        liveExpansion = true;
                        timingStart.start();
                    } else {
                        console.log("PASS: expansion stays hidden during covered travel, then springs as icons emerge at " + firstVisible.join("/")
                            + " ms; first visible growth at " + firstGrow.join("/") + " ms");
                        Qt.quit();
                    }
                }
            }
            function checkNotice() {
                if (control1.reveal <= 0) return true;
                const icons = control1.keyBox.children.filter(item => item.windowClass !== undefined);
                const icon = icons[0];
                const bell = control1.keyBox.children.find(item => item instanceof BadgedGlyph);
                const body = control1.keyBox.children.find(item => item.visible && item !== icon && item !== bell);
                const text = body.children[0];
                const iconX = icon.mapToItem(noticePill, icon.width / 2, 0).x;
                const expectedX = control1.glassLeft + control1.iconInset + bell.width + control1.spacing + icon.width / 2;
                const gathering = text.width < text.implicitWidth && text.width > 0;
                if (icons.length !== 1 || !icon.hasIcon || icon.source === "" || icon.x + icon.width > body.x
                    || Math.abs(iconX - expectedX) > 1 || (text.width > 0 && text.leftFade !== 0)
                    || (gathering && (text.rightFade <= 0 || text.travel !== 0))
                    || noticePill.contentOpacity !== 1) {
                    console.log("FAIL: notification hides text through a right gradient at frame " + capture.index);
                    Qt.quit();
                    return false;
                }
                if (capture.index === 20)
                    console.log("PASS: notification places its fading sender beside the bell; timer keeps its covered spring");
                return true;
            }
            Timer { interval: 300; running: true; onTriggered: delay.start() }
            Timer { id: timingStart; interval: 100; onTriggered: capture.startMotion() }
            Timer { id: timing; interval: 16; repeat: true; onTriggered: capture.checkTiming() }
            Timer {
                id: delay; interval: 60
                onTriggered: {
                    if (!capture.checkBounce() || !capture.checkNotice()) return;
                    capture.save("combined-" + capture.index + ".png", () => {
                        for (const pill of [musicPill, noticePill, timerPill, recordingPill]) pill.opacity = 0;
                        bare.start();
                    });
                }
            }
            Timer {
                id: bare; interval: 30
                onTriggered: capture.save("glass-" + capture.index + ".png", () => {
                    for (const pill of [musicPill, noticePill, timerPill, recordingPill]) pill.opacity = 1;
                    if (capture.index + 1 < capture.frames.length) {
                        capture.index++;
                        delay.start();
                    }
                    else capture.beginTiming();
                })
            }
        }
    }
}
'''

NOTIFICATIONS = '''pragma Singleton
import QtQuick
import Quickshell
import qs
QtObject {
    property bool showing: true; property bool held: false; property bool urgent: false
    property int burst: 2
    property string icon: Theme.glyph.notif
    property string label: ""
    property var latest: ({summary: "A notification with a longer message", body: "", appName: "Test", image: ""})
    function plain(value) { return value; }
    function url(value) { return value || ""; }
    function keyOf(value) { return "test-app"; }
    function pictureOf(value) { return "file://" + Quickshell.shellPath("sender.svg"); }
}
'''
PRIVACY = '''pragma Singleton
import QtQuick
QtObject {
    property bool active: true; property bool listening: true; property bool sharing: true
    property bool microphonesMuted: false; property bool recording: true
    property string summary: "Microphone and screen"
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    rows = []
    for i, (name, module, right, extra) in enumerate([
        ("music", "Music", True, ""), ("notice", "Notice", False, "room: 215"),
        ("timer", "Countdown", False, ""), ("recording", "Recording", True, ""),
    ]):
        rows.append(f'''Item {{
            y: {i * 70}; width: parent.width; height: 60
            Liquid {{
                anchors.fill: parent
                fill: Qt.vector4d(1,0,0,1); rimTop: fill; rimBottom: fill
                sheen: Qt.vector4d(0,-1,0,0)
                box0: Qt.vector4d(300,Theme.barInset,100,Theme.barHeight)
                box1: {name}Pill.geometry.drop({300 if right else 400},{-1 if right else 1},
                    {name}Pill.width, {name}Pill.dropReveal, control{i}.stowed)
            }}
            SidePill {{
                id: {name}Pill; control: control{i}; slidesContent: true
                bounceBeforeCollapse: {str(module == 'Countdown').lower()}
                side: Pill.Side.{'Right' if right else 'Left'}; edgeOffset: {356 if right else 416}
                {module} {{
                    id: control{i}; foldDuration: capture.liveTiming ? Theme.dropMs : 0; foldEasing: Easing.Linear; {extra}
                    stowed: capture.leaving; _eased: capture.frames[capture.index]
                }}
            }}
        }}''')
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
    display = str(Path(runtime) / os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
    with tempfile.TemporaryDirectory(prefix="qs-pill-icons-") as folder:
        target = Path(folder)
        copy_shell(target)
        for module, icon in (("Music", "note"), ("Notice", "icon"), ("Countdown", "glyph"), ("Recording", "microphone")):
            path = target / f"modules/{module}.qml"
            path.write_text(path.read_text().replace(f"id: {icon}\n", f'id: {icon}\n        objectName: "anchorIcon"\n', 1))
        for module, text in (("Notice", "body"), ("Countdown", "labelText")):
            path = target / f"modules/{module}.qml"
            path.write_text(path.read_text().replace(f"id: {text}\n", f'id: {text}\n            objectName: "sequenceText"\n', 1))
        stubs = runpy.run_path(str(ROOT / "scripts/test-pill-top-edge.py"))["STUBS"]
        for path in ("services/Mpd.qml", "services/Timers.qml"):
            source = stubs[path]
            if path.endswith("Timers.qml"):
                source = source.replace("import QtQuick", "import QtQuick\nimport qs").replace('property string glyph: "T"', 'property string glyph: Theme.glyph.timer')
            (target / path).write_text(source)
        (target / "services/Notifications.qml").write_text(NOTIFICATIONS)
        (target / "services/Privacy.qml").write_text(PRIVACY)
        (target / "sender.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect x="2" y="2" width="20" height="20" rx="5" fill="#aaeaff"/><path d="M7 8h10v7H7z" fill="#404080"/></svg>')
        (target / "shell.qml").write_text(QML.replace("ROWS", "\n".join(rows)))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
            env=shell_env(target, QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                          QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=display),
            capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Cannot assign", "Unable to assign")
        if result.returncode or not (target / "combined-20.png").exists() or "PASS: expansion stays hidden during covered travel" not in output or any(e in output for e in errors):
            print(output)
            return 1
        print("\n".join(line for line in output.splitlines() if "PASS:" in line))
        scenes, ghosts = [], []
        for i in range(21):
            scene = Image.open(target / f"combined-{i}.png").convert("RGB")
            glass = Image.open(target / f"glass-{i}.png").convert("RGB")
            scenes.append(scene)
            ghosts.append(sum(1 for (_,g,b),(r,_,_) in zip(scene.get_flattened_data(), glass.get_flattened_data())
                              if r == 0 and max(g,b) > 8))
        def ink(index, y):
            return any(max(g,b) > 8 for _,g,b in scenes[index].crop((0,y,640,y+40)).get_flattened_data())
        icon_survives = all(ink(i,y) for i in (7,13) for y in (0,210))
        empty_circles = (not ink(9,70) and not ink(11,70) and ink(17,70)
                         and not ink(9,140) and not ink(11,140) and ink(12,140))
        full_icons = all(ink(i,y) for i in (0,20) for y in (70,140))
        print(("PASS: " if icon_survives else "FAIL: ") + "music and recording retain their travelling icons")
        print(("PASS: " if empty_circles and full_icons else "FAIL: ") + "notification and timer icons fade after text on exit and appear promptly on entry")
        print(("PASS: " if not any(ghosts) else "FAIL: ") + "all four pills keep their contents inside the moving glass")
        if any(ghosts):
            print("Outside pixels by frame:", ghosts)
        if args.preview:
            preview = Image.new("RGB", (1280, 310 * 6), "#202020")
            draw = ImageDraw.Draw(preview)
            for row, (a,b) in enumerate(zip([0,3,5,7,8,9], [20,17,15,13,12,11])):
                for col, index in enumerate((a,b)):
                    preview.paste(scenes[index], (col * 640, row * 310))
                    draw.text((col * 640 + 10, row * 310 + 283),
                              ("Collapse" if col == 0 else "Expand") + f" — frame {index}", fill="white")
            preview.save(args.preview)
            print("Preview:", args.preview)
        return int(any(ghosts) or not icon_survives or not empty_circles or not full_icons)


if __name__ == "__main__":
    raise SystemExit(main())
