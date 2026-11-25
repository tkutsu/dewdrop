#!/usr/bin/env python3
"""An icon that changes with its state keeps one width through every state."""

import json
import re
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env

# Each icon the bar swaps, as the module spells its states and its size.
GROUPS = {
    "vpn": ("[Theme.glyph.vpn, Theme.glyph.vpnOff]", "Theme.trayGlyphSize - 1"),
    "bluetooth": ("[Theme.glyph.bluetooth, Theme.glyph.bluetoothOff]", "Theme.trayGlyphSize"),
    "network": ("[Theme.glyph.wifiStrength[4], Theme.glyph.wifiOff, Theme.glyph.wired]", "Theme.trayGlyphSize"),
    "caffeine": ("[Theme.glyph.idleOn, Theme.glyph.idleOff]", "Theme.glyphSizeLarge"),
    "night": ("[Theme.glyph.nightOn, Theme.glyph.nightOff]", "Theme.glyphSize - 1"),
    "mail": ("[Theme.glyph.mailUnread, Theme.glyph.mailRead]", "Theme.glyphSizeLarge"),
    "timer": ("[Theme.glyph.timer, Theme.glyph.timerPaused, Theme.glyph.timerRing, Theme.glyph.alarm]", "Theme.glyphSizeLarge"),
    "recording": ("[Theme.glyph.mic, Theme.glyph.micMuted, Theme.glyph.screenShare]", "Theme.glyphSize"),
    "play": ("[Theme.glyph.playing, Theme.glyph.paused]", "Theme.glyphSize"),
    "weather": ("Object.keys(Weather.tints)", "Theme.trayGlyphSize - 1"),
}

GROUP = '''
            Row {
                id: NAME
                readonly property var states: STATES
                Repeater {
                    model: NAME.states
                    Glyph { required property string modelData; text: modelData; fontSize: SIZE }
                }
                Repeater {
                    model: NAME.states
                    Glyph { required property string modelData; text: modelData; fontSize: SIZE; alternates: NAME.states }
                }
            }'''

QML = '''import QtQuick
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 600
        Column {
            id: scene
GROUPS
        }
        Timer {
            interval: 2500; running: true
            onTriggered: {
                const report = {};
                for (const row of scene.children) {
                    const count = row.states.length;
                    const glyphs = row.children.filter(item => item instanceof Glyph);
                    report[row.NAMEOF] = {
                        bare: glyphs.slice(0, count).map(item => item.implicitWidth),
                        slotted: glyphs.slice(count).map(item => item.implicitWidth),
                        ink: glyphs.slice(count).map(item => item.inkWidth)
                    };
                }
                console.log("SLOTS " + JSON.stringify(report));
                Qt.quit();
            }
        }
    }
}
'''


def main():
    rows = "".join(
        GROUP.replace("NAME", name).replace("STATES", states).replace("SIZE", size)
            .replace("id: " + name, f"id: {name}\n                readonly property string label: \"{name}\"")
        for name, (states, size) in GROUPS.items())
    with tempfile.TemporaryDirectory(prefix="qs-icon-slots-") as folder:
        copy_shell(folder)
        with open(f"{folder}/shell.qml", "w") as shell:
            shell.write(QML.replace("GROUPS", rows).replace("NAMEOF", "label"))
        result = subprocess.run(["qs", "-p", folder, "--no-color"],
                                env=shell_env(folder), capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        found = re.search(r"SLOTS (\{.*\})", output)
        assert found, output
        failed = 0
        for name, widths in json.loads(found[1]).items():
            bare, slotted, ink = widths["bare"], widths["slotted"], widths["ink"]
            ok = min(bare) > 0 and set(slotted) == {max(bare)} and ink == bare
            failed += not ok
            print(f"{'PASS' if ok else 'FAIL'}: {name}: inks {bare} share a slot of {slotted}")
        # The modules ask for these slots, in the words the groups above use.
        sources = {
            "Tray.qml": "alternates: entry.glyph ? [Theme.glyph.vpn, Theme.glyph.vpnOff] : []",
            "Bluetooth.qml": "alternates: [Theme.glyph.bluetooth, Theme.glyph.bluetoothOff]",
            "Network.qml": "alternates: [Theme.glyph.wifiStrength[4], Theme.glyph.wired]",
            "IdleInhibit.qml": "alternates: [Theme.glyph.idleOn, Theme.glyph.idleOff]",
            "NightMode.qml": "alternates: [Theme.glyph.nightOn, Theme.glyph.nightOff]",
            "Email.qml": "alternates: [Theme.glyph.mailUnread, Theme.glyph.mailRead]",
            "Timers.qml": "alternates: Services.Timers.glyphs",
            "Countdown.qml": "alternates: Timers.glyphs",
            "Recording.qml": "alternates: [Theme.glyph.mic, Theme.glyph.micMuted, Theme.glyph.screenShare]",
            "Music.qml": "alternates: [Theme.glyph.playing, Theme.glyph.paused]",
            "NowPlaying.qml": "alternates: [Theme.glyph.playing, Theme.glyph.paused]",
            "Weather.qml": "alternates: Object.keys(Services.Weather.tints)",
        }
        for module, line in sources.items():
            ok = line in (ROOT / "src/modules" / module).read_text()
            failed += not ok
            print(f"{'PASS' if ok else 'FAIL'}: {module} reserves its icon's slot")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
