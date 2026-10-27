#!/usr/bin/env python3
"""Check music volume wheel steps without changing the live player's volume."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


spec = importlib.util.spec_from_file_location("titles", ROOT / "scripts/test-music-titles.py")
titles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(titles)

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.components
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 600; implicitHeight: 300
        Item { id: anchor; width: 40; height: 20 }
        Slider {
            id: relative; y: 100; width: 200; value: 0.53; wheelStep: 0.05
            onMoved: value => relative.value = value
        }
    }
    MusicPopup { id: popup; visible: true; anchorItem: anchor }
    TestCase {
        id: test; when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children || []) {
                const found = find(child, predicate);
                if (found) return found;
            }
            return null;
        }
        function run() {
            const slider = find(popup.contentItem, item => item.name === "Music volume");
            const control = find(popup.contentItem, item => item.objectName === "musicVolumeControl");
            const metadata = find(popup.contentItem, item => item.objectName === "musicMetadata");
            check(slider !== null, "music volume slider is present");
            check(!slider.visible && metadata.visible, "music starts with artist and album instead of the slider");
            mouseMove(control, control.width / 2, control.height / 2); wait(50);
            check(!slider.visible, "hover alone does not reveal volume");
            check(Math.abs(control.mapToItem(metadata.parent, 0, control.height / 2).y
                - (metadata.y + metadata.height / 2)) < 1, "volume icon and percentage sit beside artist and album");
            const playback = find(popup.contentItem, item => item.name === "Playback position");
            const time = find(playback.parent, item => item !== playback && item.keyPress && item.text);
            check(time && Math.abs(time.y + time.height / 2 - playback.y - playback.height / 2) < 1,
                "playback slider and time share a vertical center");
            check(playback.y >= 4, "playback slider sits lower in its row");
            function scroll(delta) {
                mouseWheel(control, control.width / 2, control.height / 2, 0, delta);
            }
            Mpd.volume = 53;
            scroll(120);
            check(Mpd.volume === 55, "scroll up snaps 53% to 55% (got " + Mpd.volume + "%)");
            check(slider.visible && !metadata.visible, "scrolling the volume readout replaces artist and album with the slider");
            scroll(120);
            check(Mpd.volume === 60, "the next notch advances by five percentage points");
            Mpd.volume = 53;
            scroll(-120);
            check(Mpd.volume === 50, "scroll down snaps 53% to 50%");
            Mpd.volume = 53;
            scroll(360);
            check(Mpd.volume === 65, "three notches reach the third multiple of five");
            Mpd.volume = 53;
            scroll(-360);
            check(Mpd.volume === 40, "three reverse notches reach the third multiple of five");
            Mpd.volume = 53;
            scroll(60);
            check(Mpd.volume === 53, "half a notch leaves volume unchanged");
            scroll(60);
            check(Mpd.volume === 55, "fractional wheel events accumulate to one step");
            Mpd.volume = 99; scroll(120);
            check(Mpd.volume === 100, "volume clamps at 100%");
            Mpd.volume = 1; scroll(-120);
            check(Mpd.volume === 0, "volume clamps at 0%");
            for (let percent = 0; percent <= 100; percent += 5) {
                Mpd.volume = percent; scroll(120);
                if (Mpd.volume !== Math.min(100, percent + 5)) throw Error("forward step from " + percent + "%");
                Mpd.volume = percent; scroll(-120);
                if (Mpd.volume !== Math.max(0, percent - 5)) throw Error("reverse step from " + percent + "%");
            }
            check(true, "every multiple of five advances and reverses correctly");

            Mpd.volume = 53;
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, 120);
            check(Mpd.volume === 55, "scroll up on the music slider matches the volume readout");
            mouseWheel(slider, slider.width / 2, slider.height / 2, 0, -120);
            check(Mpd.volume === 50, "scroll down on the music slider lowers volume");
            mouseClick(slider, slider.width * 0.53, slider.height / 2);
            check(Mpd.volume === 53, "pointer adjustment still allows arbitrary percentages");
            wait(100);
            mouseMove(slider, slider.width / 2, slider.height / 2);
            mousePress(slider, slider.width / 2, slider.height / 2);
            check(slider.pressed, "press reaches the volume slider");
            wait(2100);
            check(slider.visible && !metadata.visible, "holding the slider keeps it visible past the feedback timeout: "
                + JSON.stringify({pressed: slider.pressed, visible: slider.visible, metadata: metadata.visible}));
            mouseRelease(slider, slider.width / 2, slider.height / 2); wait(2100);
            check(slider.visible, "stationary hover keeps the volume slider visible after release");
            mouseMove(control, control.width / 2, control.height / 2); wait(2100);
            check(slider.visible, "hovering the volume percentage also holds the slider open");
            mouseMove(popup.contentItem, popup.contentItem.width - 2, popup.contentItem.height - 2); wait(1300);
            check(slider.visible, "volume feedback lasts longer than the former 1.2 seconds");
            mouseMove(slider, slider.width / 2, slider.height / 2); wait(50);
            mouseMove(popup.contentItem, popup.contentItem.width - 2, popup.contentItem.height - 2); wait(1300);
            check(slider.visible, "hovering resets the full idle duration");
            wait(800);
            check(!slider.visible && metadata.visible, "idle restores artist and album and hides the volume slider");
            mouseWheel(metadata, metadata.width / 2, metadata.height / 2, 0, -120);
            check(!slider.visible, "scrolling artist and album does not reveal volume");
            Mpd.volume = -1; wait(10);
            check(!control.visible && !slider.visible && metadata.visible, "a player without a mixer keeps metadata and hides volume");
            mouseWheel(relative, relative.width / 2, relative.height / 2, 0, 120);
            check(Math.abs(relative.value - 0.58) < 0.000001, "other sliders retain relative wheel steps");
            console.log("DONE: music volume");
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}'''


def main():
    """Run the real popup with an isolated, synchronous MPD volume model."""
    with tempfile.TemporaryDirectory(prefix="qs-music-volume-") as folder:
        target = Path(folder)
        copy_shell(target)
        mpd = titles.MPD.replace(
            "function toggle() {}",
            "function setVolume(value) { volume = Math.round(value * 100); }\n    function toggle() {}",
        )
        (target / "services/Mpd.qml").write_text(mpd)
        (target / "services/Launcher.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property string musicPrefix: "#"; function openWith(prefix) {} }'
        )
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(
            ["qs", "-p", str(target), "--no-color"], env=shell_env(target),
            capture_output=True, text=True, timeout=20,
        )
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines()
                        if any(marker in line for marker in ("PASS:", "DONE:", *errors))))
        return 0 if result.returncode == 0 and "DONE: music volume" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
