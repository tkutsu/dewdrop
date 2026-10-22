#!/usr/bin/env python3
"""Check the real music/EQ view switch and ten vertical sliders without live audio."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


SPEC = importlib.util.spec_from_file_location('titles', ROOT / 'scripts/test-music-titles.py')
titles = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(titles)

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 600; implicitHeight: 500
        Item { id: anchor; width: 40; height: 20 }
    }
    MusicPopup {
        id: popup; visible: true; anchorItem: anchor
        requestedVisible: OpenPopup.owner === anchor
    }
    TestCase {
        id: test; when: false
        function check(ok, message) {
            if (!ok) throw Error(message);
            console.log("PASS: " + message);
        }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children || []) {
                const result = find(child, predicate);
                if (result) return result;
            }
            return null;
        }
        function event(data) { FakeHyprland.rawEvent({name: "custom", data}); }
        function selectPreset(selector, index) {
            mouseMove(selector, selector.width / 2, selector.height / 2);
            mouseClick(selector, selector.width / 2, selector.height / 2);
            tryVerify(() => selector.popup.visible);
            wait(100);
            const list = selector.popup.contentItem;
            check(list.contentHeight <= list.height && !list.moving,
                "all preset rows fit without scrolling");
            const option = selector.popup.contentItem.itemAtIndex(index);
            check(option !== null, "preset menu renders " + selector.model[index].label);
            check(option.y >= list.contentY && option.y + option.height <= list.contentY + list.height,
                "preset row is fully visible without scrolling");
            mouseMove(option, option.width / 2, option.height / 2);
            wait(30);
            event("click");
            mouseClick(option, option.width / 2, option.height / 2);
            event("click-release");
            wait(100);
            check(MpdEqualizer.preset === selector.model[index].value,
                "click selects " + selector.model[index].label);
            check(OpenPopup.owner === anchor && popup.requestedVisible,
                "preset selection keeps the music popup open");
            check(!selector.popup.visible, "only the preset menu closes");
        }
        function run() {
            OpenPopup.set(anchor);
            wait(250);
            const width = popup.width;
            Mpd.queue = [{pos: 0, title: "Queue track", duration: 120}];
            const queue = find(popup.contentItem, item => item.Accessible?.name === "Queue");
            const toggle = find(popup.contentItem, item => item.name === "Show equalizer");
            check(toggle && !popup.equalizerOpen, "music opens with an equalizer header button");
            check(toggle.label === "" && toggle.glyph === Theme.glyph.equalizer && toggle.glyphSize === 16,
                "equalizer header button shows only the larger slider icon");
            mouseClick(toggle, toggle.width / 2, toggle.height / 2);
            tryVerify(() => MpdEqualizer.ready && !MpdEqualizer.busy, 3000);
            check(popup.equalizerOpen && popup.width === width, "equalizer replaces the main display at the same width");
            check(!queue || !queue.visible, "queue is hidden in the equalizer view");
            let selector = find(popup.contentItem, item => item.objectName === "equalizerPresets");
            check(selector.count === 9, "all nine requested presets are present");
            for (let i = 0; i < 9; i++) {
                selectPreset(selector, i);
                check(selector.currentIndex === i, "preset selector shows its selected curve");
            }
            selectPreset(selector, 0);
            const bands = [];
            for (let i = 0; i < 10; i++) {
                const band = find(popup.contentItem, item => item.objectName === "equalizerBand" + i);
                check(band && band.rotation === -90, "vertical band " + (i + 1) + " is present");
                bands.push(band);
            }
            const bass = bands[0];
            mouseClick(bass, bass.width - 1, bass.height / 2);
            check(MpdEqualizer.gains[0] === 12 && MpdEqualizer.preset === "Custom", "top of vertical band boosts to +12 dB and selects Custom");
            mouseClick(bass, 1, bass.height / 2);
            check(MpdEqualizer.gains[0] === -12, "bottom of vertical band cuts to -12 dB (got " + MpdEqualizer.gains[0] + ")");
            mouseWheel(bass, bass.width / 2, bass.height / 2, 0, -120);
            check(MpdEqualizer.gains[0] === -11.5, "wheel adjusts a band in half-decibel steps");
            bands[9].keyStep(1);
            check(MpdEqualizer.gains[9] === 0.5, "keyboard adjusts the final band in half-decibel steps");
            check(MpdEqualizer.dirty, "edits remain unapplied until Apply");
            find(popup.contentItem, item => item.name === "Return to music").tapped(); wait(50);
            check(!popup.equalizerOpen && Mpd.queue.length === 1, "Music returns to the player with its queue intact");
            toggle.tapped(); wait(50);
            check(MpdEqualizer.gains[0] === -11.5, "unapplied edits survive switching views");
            MpdEqualizer.reset();
            tryVerify(() => !MpdEqualizer.busy, 3000);
            check(!MpdEqualizer.dirty && MpdEqualizer.legacy, "Reset reloads the active six-band EQ without applying");
            selector = find(popup.contentItem, item => item.objectName === "equalizerPresets");
            selectPreset(selector, 1);
            MpdEqualizer.reset();
            tryVerify(() => !MpdEqualizer.busy, 3000);
            const config = Settings.values.mpdConfig;
            Settings.set("mpdConfig", config + ".missing");
            MpdEqualizer.load();
            tryVerify(() => !MpdEqualizer.busy && MpdEqualizer.error !== "", 3000);
            check(!MpdEqualizer.ready, "missing config disables the equalizer with an error");
            MpdEqualizer.saved = [];
            MpdEqualizer.reset();
            tryVerify(() => !MpdEqualizer.busy, 3000);
            check(MpdEqualizer.gains.length === 10, "retry after a first-load error keeps all ten sliders valid");
            Settings.set("mpdConfig", config);
            MpdEqualizer.reset();
            tryVerify(() => !MpdEqualizer.busy && MpdEqualizer.ready, 3000);
            selectPreset(selector, 1);
            // Cancel the menu, then verify a fresh outside click still dismisses the popup.
            mouseClick(selector, selector.width / 2, selector.height / 2);
            tryVerify(() => selector.popup.visible);
            selector.popup.close(); wait(100);
            check(OpenPopup.owner === anchor, "cancelling the preset menu keeps music open");
            mouseMove(popup.contentItem, popup.width - 1, popup.height - 1); wait(30);
            event("click"); event("click-release"); wait(50);
            check(OpenPopup.owner === null && !popup.requestedVisible,
                "outside click still dismisses music after preset selection");
            OpenPopup.set(anchor); wait(200);
            if (Quickshell.env("MUSIC_EQ_HEADER_PREVIEW")) {
                popup.equalizerOpen = false;
                wait(100);
            }
            console.log("DONE: music equalizer UI");
        }
    }
    Timer {
        interval: 150; running: true
        onTriggered: {
            try {
                test.run();
                const preview = Quickshell.env("MUSIC_EQ_PREVIEW");
                if (preview) {
                    popup.chromeItem.grabToImage(result => {
                        if (!result.saveToFile(preview)) console.log("FAIL: preview was not saved");
                        OpenPopup.set(null); Qt.quit();
                    });
                } else { OpenPopup.set(null); Qt.quit(); }
            } catch (error) {
                console.log("FAIL: " + error);
                OpenPopup.set(null); Qt.quit();
            }
        }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='qs-equalizer-ui-') as directory:
        target = Path(directory)
        copy_shell(target)
        (target / 'services/Mpd.qml').write_text(titles.MPD)
        (target / 'services/Launcher.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property string musicPrefix: "#"; function openWith(prefix) {} }')
        outside = target / 'components/OutsideClick.qml'
        outside.write_text(outside.read_text().replace('import Quickshell.Hyprland', 'import qs.services')
                           .replace('target: Hyprland', 'target: FakeHyprland')
                           .replace('event: HyprlandEvent', 'event: var'))
        (target / 'services/FakeHyprland.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { signal rawEvent(var event) }\n')
        # Use a separate copy of the current graph; no helper command can target live MPD.
        graph = 'anequalizer=c0 f=60 w=80 g=-2 t=0|c1 f=60 w=80 g=-2 t=0'
        config = target / 'mpd.conf'
        config.write_text('filter { plugin "ffmpeg" name "eq" graph "' + graph
                          + '" }\naudio_output { type "null" name "Test" filters "eq" }\n')
        (target / 'settings.json').write_text(json.dumps({'mpdConfig': str(config),
                                                        'mpdSocket': str(target / 'unused.sock')}))
        (target / 'shell.qml').write_text(SHELL)
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target),
                                capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        errors = ('FAIL:', 'ReferenceError:', 'TypeError:', 'Unable to assign', 'Cannot assign',
                  'Binding loop', 'Failed to load configuration', 'is not available', 'is not a type')
        print('\n'.join(line for line in output.splitlines()
                        if any(marker in line for marker in ('PASS:', 'DONE:', *errors))))
        if 'DONE: music equalizer UI' not in output:
            print(output)
        return 0 if result.returncode == 0 and 'DONE: music equalizer UI' in output and not any(e in output for e in errors) else 1


if __name__ == '__main__':
    raise SystemExit(main())
