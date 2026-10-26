#!/usr/bin/env python3
"""Exercise scroll feedback with the real module and popup, using fake volume."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


AUDIO = '''pragma Singleton
import QtQuick
import qs
QtObject {
    property int volume: 53
    property bool muted: false
    property bool connected: true
    readonly property bool silent: muted || volume === 0
    readonly property string icon: Theme.glyph.vol[Math.ceil(volume * 6 / 100)]
    property var sinks: []
    property var sources: []
    property var availableSinks: []
    property var availableSources: []
    property var outStreams: []
    property var streams: []
    property var source: null
    property var sink: null
    property int micVolume: 0
    property bool micMuted: false
    function step(up) {
        volume = Math.max(0, Math.min(100, up ? (Math.floor(volume / 5) + 1) * 5 : Math.floor((volume - 1) / 5) * 5));
    }
    function toggleMute() { muted = !muted; }
}'''

SHELL = r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules as Modules
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 150
        Modules.Audio {
            id: audio
            x: 100; y: 20; width: implicitWidth; height: implicitHeight
            folds: false
            pinKey: "audio"
        }
    }
    TestCase { id: test; when: false }
    Connections {
        id: opening
        target: null
        property int opens: 0
        property int closes: 0
        function onOpenedChanged() {
            if (target.opened) opens++;
            else closes++;
        }
    }
    function check(ok, message) {
        if (!ok) throw Error(message);
        console.log("PASS: " + message);
    }
    function scroll(delta) {
        test.mouseWheel(audio, audio.width / 2, audio.height / 2, 0, delta);
    }
    function level() {
        return audio.children.find(child => child.item && child.item.takesKeys === false);
    }
    function row(item) {
        if (item.level !== undefined || item.volume !== undefined) return item;
        for (const child of item.children || []) {
            const found = row(child);
            if (found) return found;
        }
        return null;
    }
    function slider(item) {
        if (item.name === 'Output volume' && item.value !== undefined) return item;
        for (const child of item.children || []) {
            const found = slider(child);
            if (found) return found;
        }
        return null;
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                check(!level(), "volume feedback starts hidden");
                check(audio.opacity === 1, "audible output keeps its full-opacity bar icon");
                Audio.muted = true;test.wait(Theme.fadeMs + 50);
                check(audio.opacity === 1 && !audio.quiet && audio.showsClosed && audio.visible,
                    "muted output stays visible at full opacity without a pin");
                Audio.volume = 0;test.wait(Theme.fadeMs + 50);
                check(audio.opacity === 1,
                    "muted output stays fully opaque even at zero volume");
                Audio.muted = false;
                Audio.volume = 0;test.wait(Theme.fadeMs + 50);
                check(Math.abs(audio.opacity - Theme.label2.a) < 0.01,
                    "zero volume uses the same no-sound opacity");
                Audio.volume = 53;test.wait(Theme.fadeMs + 50);
                scroll(60);
                check(Audio.volume === 53 && !level(), "partial wheel notch waits without showing feedback");
                scroll(60);test.wait(30);
                const hud = level();
                check(Audio.volume === 55 && hud?.open, "scroll up raises volume and opens the mini popover");
                check(hud.item.anchorItem === audio && !hud.item.takesKeys && !hud.item.probes,
                    "mini popover anchors under the audio icon without taking focus");
                check(row(hud.item.contentItem).level === 55 && !audio.tooltipEnabled,
                    "mini popover tracks volume and suppresses the plain tooltip");
                const firstPopup = hud.item;
                const miniRow = row(firstPopup.contentItem);
                const miniSlider = slider(miniRow);
                const percent = miniRow.children.find(child => child.visible && child.text === '55%');
                check(percent && percent.y + percent.height <= miniSlider.parent.y,
                    "mini volume percentage sits above its track");
                check(!miniRow.children.some(child => child.visible && child.fontSize !== undefined),
                    "mini volume readout has no speaker icon");
                const empty = miniSlider.mapToItem(miniRow, 0, miniSlider.height / 2);
                const full = miniSlider.mapToItem(miniRow, miniSlider.width, miniSlider.height / 2);
                check(full.y < empty.y && Math.abs(full.x - empty.x) < 0.01
                    && miniSlider.parent.height > miniSlider.parent.width
                    && firstPopup.chromeHeight > firstPopup.chromeItem.width,
                    "compact vertical volume track fills from bottom to top");
                opening.target = firstPopup;
                test.wait(800);scroll(-120);test.wait(30);
                check(Audio.volume === 50 && row(hud.item.contentItem).level === 50,
                    "scroll down lowers the visible volume tracker");
                const position = miniRow.mapToItem(firstPopup.chromeItem, 0, 0);
                const top = position.y;
                const bottom = firstPopup.chromeHeight - position.y - miniRow.height;
                const left = position.x;
                const right = firstPopup.chromeItem.width - position.x - miniRow.width;
                check(hud.item === firstPopup && opening.opens === 0 && opening.closes === 0,
                    "another scroll never closes or reopens the visible popover (same instance: "
                    + (hud.item === firstPopup) + "; opens: " + opening.opens + "; closes: " + opening.closes
                    + ")");
                check(top === bottom && left === right && top === left,
                    "vertical readout has equal padding on all sides (" + [top, right, bottom, left].join(', ') + ")");
                test.wait(500);
                check(hud.open, "another scroll extends the display time");
                test.wait(900);
                check(!hud.open && !hud.item && audio.tooltipEnabled,
                    "idle feedback fades away and releases its surface");

                scroll(120);test.wait(30);
                audio.togglePopup();test.wait(30);
                check(audio.popupOpen && !hud.open, "opening the full menu dismisses mini feedback");
                const master = row(audio.popupItem.contentItem);
                const masterSlider = master.children.find(child => child.name === 'Output volume');
                check(masterSlider.rotation === 0 && masterSlider.width > masterSlider.height,
                    "full sound popover keeps its horizontal slider");
                scroll(-120);
                check(!hud.open && Audio.volume === 50,
                    "scrolling with the full menu open adjusts volume without a second popover");
                OpenPopup.dismiss();test.wait(200);
                Audio.connected = false;scroll(120);
                test.wait(Theme.fadeMs + 50);
                check(!hud.open, "missing output never shows volume feedback");
                check(audio.quiet && Math.abs(audio.opacity - Theme.label2.a) < 0.01,
                    "missing output is quiet and dims the icon even while it remains visible");
                Audio.connected = true;
                Settings.user = Object.assign({}, Settings.user, {reduceMotion:true});
                scroll(-120);test.wait(30);
                check(hud.open && hud.item.growX === 1 && hud.item.growY === 1,
                    "mini feedback respects Reduce Motion");
                console.log("DONE: audio feedback");
            } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}'''


def main():
    """Keep wheel and popup interactions away from the user's audio server."""
    with tempfile.TemporaryDirectory(prefix="qs-audio-feedback-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "services/Audio.qml").write_text(AUDIO)
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
        return 0 if result.returncode == 0 and "DONE: audio feedback" in output \
            and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
