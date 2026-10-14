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
        function musicSlider(item) {
            if (item.name === "Music volume") return item;
            for (const child of item.children || []) {
                const found = musicSlider(child);
                if (found) return found;
            }
            return null;
        }
        function run() {
            const slider = musicSlider(popup.contentItem);
            check(slider !== null, "music volume slider is present");
            function scroll(delta) {
                mouseWheel(slider, slider.width / 2, slider.height / 2, 0, delta);
            }
            Mpd.volume = 53;
            scroll(-120);
            check(Mpd.volume === 55, "scroll down snaps 53% to 55% (got " + Mpd.volume + "%)");
            scroll(-120);
            check(Mpd.volume === 60, "the next notch advances by five percentage points");
            Mpd.volume = 53;
            scroll(120);
            check(Mpd.volume === 50, "scroll up snaps 53% to 50%");
            Mpd.volume = 53;
            scroll(-360);
            check(Mpd.volume === 65, "three notches reach the third multiple of five");
            Mpd.volume = 53;
            scroll(360);
            check(Mpd.volume === 40, "three reverse notches reach the third multiple of five");
            Mpd.volume = 53;
            scroll(-60);
            check(Mpd.volume === 53, "half a notch leaves volume unchanged");
            scroll(-60);
            check(Mpd.volume === 55, "fractional wheel events accumulate to one step");
            Mpd.volume = 99; scroll(-120);
            check(Mpd.volume === 100, "volume clamps at 100%");
            Mpd.volume = 1; scroll(120);
            check(Mpd.volume === 0, "volume clamps at 0%");
            for (let percent = 0; percent <= 100; percent += 5) {
                Mpd.volume = percent; scroll(-120);
                if (Mpd.volume !== Math.min(100, percent + 5)) throw Error("forward step from " + percent + "%");
                Mpd.volume = percent; scroll(120);
                if (Mpd.volume !== Math.max(0, percent - 5)) throw Error("reverse step from " + percent + "%");
            }
            check(true, "every multiple of five advances and reverses correctly");
            mouseClick(slider, slider.width * 0.53, slider.height / 2);
            check(Mpd.volume === 53, "pointer adjustment still allows arbitrary percentages");
            mouseWheel(relative, relative.width / 2, relative.height / 2, 0, -120);
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
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines()
                        if any(marker in line for marker in ("PASS:", "DONE:", *errors))))
        return 0 if result.returncode == 0 and "DONE: music volume" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
