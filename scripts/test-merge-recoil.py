#!/usr/bin/env python3
"""Compare bell recoil with the actual MPD and MPRIS merge paths."""

import argparse
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

from PIL import Image
from test_support import ROOT, copy_shell, shell_env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    fixture = runpy.run_path(str(ROOT / "scripts/test-notification-merge.py"))
    bar = (ROOT / "Bar.qml").read_text()
    qml = fixture["QML"]
    placement = re.search(r"^    function placeModules\(\): void \{.*?^    \}", bar, re.M | re.S)[0]
    qml = qml.replace("PLACE_MODULES", placement).replace("PLACEMENT_ONLY", "false")
    qml = qml.replace("BELL", fixture["block"](bar, "id: bell", "NotificationBell {"))
    qml = qml.replace("NOTICE", fixture["block"](bar, "id: noticePill", "SidePill {"))
    motion_start = bar.index("        // Mirror a leading media slot")
    motion_end = bar.index("        // Quiet capture controls", motion_start)
    qml = qml.replace("CENTRE_MOTION", bar[motion_start:motion_end])
    for placeholder, name in (("RIGHT_LIP", "rightLip"), ("CLOCK_GLASS", "clockGlass")):
        qml = qml.replace(placeholder, re.search(r"^    readonly property [^\n]+ " + name + r": .+$", bar, re.M)[0])
    qml = qml.replace("    id: bar", """    id: bar
    readonly property real width: window.width
    readonly property real height: window.height
    readonly property real clockRight: clockPill.x + clockPill.width
    readonly property vector4d countdownDrop: Qt.vector4d(0,0,0,0)
    readonly property vector4d noticeDrop: drops.drop(noticeEdge, 1, noticePill.width, noticePill.dropReveal, notice.stowed)
""", 1)
    glass = fixture["block"](bar, "id: rightGlass", "Liquid {")
    glass = glass.replace("backdrop: wallpaperImage", "backdrop: null")
    glass = glass.replace("id: rightGlass", """id: rightGlass
            fill: Qt.vector4d(0.2,0.65,1,1)
            rimTop: fill; rimBottom: fill; sheen: Qt.vector4d(0,-1,0,0)""")
    qml = qml.replace("        id: window;", glass + "\n        id: window;", 1)
    references = ""
    for name, module, note, y in (("music", "Music", "musicNote", 65), ("nowPlaying", "NowPlaying", "nowPlayingNote", 125)):
        note_qml = fixture["block"](bar, "id: " + note, "BarItem {")
        # No session player is needed to drive the real MPRIS module's stowed state.
        note_qml = note_qml.replace("!Settings.showMpris || nowPlaying.player === null || ", "")
        # Compare motion with equal receiver widths; the production icons have different artwork widths.
        note_qml = note_qml.replace("Layout.fillHeight: true", "Layout.fillHeight: true; Layout.preferredWidth: bell.keyBox.children[0].width")
        references += f"""
        Pill {{
            id: {name}Centre; side: Pill.Side.Centre; animatePosition: true
            anchors.topMargin: {y}; moduleGap: clockPill.moduleGap
            centreOn: {name}Clock.keyBox
            {note_qml}
            BarItem {{ id: {name}Clock; BarText {{ text: "Clock" }} }}
        }}
        SidePill {{
            id: {name}Side; control: {name}; side: Pill.Side.Right; slidesContent: true
            anchors.topMargin: {y}; edgeOffset: window.width - {name}Centre.x + Theme.pillSpread
            {module} {{ id: {name}; stowed: false; mergedIcon: {note}.keyBox.children[0]
                foldDuration: Theme.dropMs; foldEasing: Easing.Linear }}
        }}
"""
    qml = qml.replace("implicitHeight: 100", "implicitHeight: 190")
    qml = qml.replace("        TestCase {", references + "        TestCase {", 1)
    run = r'''            function run() {
                bell.settingsKey = "bell"; bell.visibilityKey = "bell";
                wait(Theme.startMs + 50);
                bar.placeModules(); DrawerPins.setMode("bell", "auto");
                Notifications.list = [Notifications.latest]; Notifications.showing = true;
                wait(Theme.dropMs + 100);
                const restingX = clockPill.x;
                const mpdRest = musicClock.keyBox.mapToItem(window.contentItem, 0, 0).x;
                const mprisRest = nowPlayingClock.keyBox.mapToItem(window.contentItem, 0, 0).x;
                const started = Date.now();
                music.stowed = true; nowPlaying.stowed = true;
                Notifications.showing = false;
                for (let i = 0; i < 180; i++) {
                    wait(16);
                    const frame = grabImage(rightGlass);
                    frame.save(Quickshell.shellPath("frame-" + i + ".png"));
                    console.log("FRAME: " + JSON.stringify({i, elapsed: Date.now() - started, reveal: notice.reveal,
                        edge: clockPill.x + clockPill.width, lip: bar.rightLip,
                        pillX: clockPill.x, restX: restingX, mpd: musicClock.keyBox.mapToItem(window.contentItem, 0, 0).x - mpdRest,
                        mpris: nowPlayingClock.keyBox.mapToItem(window.contentItem, 0, 0).x - mprisRest,
                        clockX: clock.keyBox.mapToItem(window.contentItem, 0, 0).x}));
                    if (notice.reveal === 0 && !clockPill.animating && !musicCentre.animating && !nowPlayingCentre.animating
                            && Date.now() - started > Theme.dropMs) break;
                }
                console.log("PASS: captured receiving glass");
            }'''
    qml = re.sub(r"            function run\(\) \{.*?^            \}", lambda _: run, qml, count=1, flags=re.M | re.S)
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
    display = str(Path(runtime) / os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
    with tempfile.TemporaryDirectory(prefix="qs-merge-recoil-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/Notifications.qml").write_text(fixture["NOTIFICATIONS"])
        (target / "components/NotificationsPopup.qml").write_text("import QtQuick\nItem {}\n")
        mpd_fixture = runpy.run_path(str(ROOT / "scripts/test-pill-top-edge.py"))
        for name, contents in mpd_fixture["STUBS"].items():
            (target / name).write_text(contents)
        (target / "shell.qml").write_text(qml)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], capture_output=True, text=True, timeout=30,
            env=shell_env(target, QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", WAYLAND_DISPLAY=display))
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration")
        if result.returncode or "PASS: captured" not in output or any(e in output for e in errors):
            print(output)
            return 1
        samples = [json.loads(line.split("FRAME: ", 1)[1]) for line in output.splitlines() if "FRAME: " in line]
        images = [Image.open(target / f"frame-{sample['i']}.png").convert("RGBA") for sample in samples]
        def edge(image):
            y = 4 + 30 // 2
            pixels = [image.getpixel((x,y)) for x in range(image.width)]
            return min(x for x, (r,g,b,a) in enumerate(pixels) if a > 127 and b > r + 60 and g > r + 20)
        resting = edge(images[-1])
        offsets = [edge(im) - resting for im in images]
        excursion = max(abs(offset) for offset in offsets)
        clock_rest = samples[-1]["clockX"]
        clock_excursion = max(abs(s["clockX"] - clock_rest) for s in samples)
        errors = {name: max(abs(s["pillX"] - s["restX"] + s[name]) for s in samples) for name in ("mpd", "mpris")}
        print(f"Whole-pill excursion: rendered glass={excursion}px, clock contents={clock_excursion:.2f}px")
        for name in errors:
            peak = max(abs(s[name]) for s in samples)
            print(f"Actual {name.upper()} clock excursion: {peak:.2f}px; bell trajectory difference: {errors[name]:.2f}px")
        print(f"Final position error: {abs(samples[-1]['pillX'] - samples[-1]['restX']):.2f}px")
        if args.preview:
            args.preview.parent.mkdir(parents=True, exist_ok=True)
            durations = [max(1, samples[i+1]["elapsed"] - s["elapsed"]) for i,s in enumerate(samples[:-1])] + [300]
            images[0].save(args.preview, save_all=True, append_images=images[1:], duration=durations, loop=0, disposal=2)
            print("Preview:", args.preview)
        ok = excursion >= 1 and clock_excursion >= 1 and max(errors.values()) < 1.5 and abs(samples[-1]["pillX"] - samples[-1]["restX"]) < 0.5
        print(("PASS:" if ok else "FAIL:") + " whole-pill recoil uses the actual MPD/MPRIS merge displacement and settles")
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
