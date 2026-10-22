#!/usr/bin/env python3
"""Check jack filtering and labels without touching the live audio server."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


spec = importlib.util.spec_from_file_location("standards", ROOT / "scripts/test-popup-standards.py")
standards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(standards)

SHELL = r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 400; implicitHeight: 500
        AudioPopup { id: popup }
    }
    FileView { id: backend; path: Quickshell.shellPath("ports.json") }
    TestCase { id: test; when: false }
    function check(ok, message) {
        if (!ok) throw Error(message);
        console.log("PASS: " + message);
    }
    function rows(item) {
        let result = [];
        if (item.modelData && item.text !== undefined && item.current !== undefined && item.visible)
            result.push(item.text);
        for (const child of item.children || []) result = result.concat(rows(child));
        return result;
    }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) {
            const found = find(child, predicate);
            if (found) return found;
        }
        return null;
    }
    function refresh(snapshot, event) {
        backend.setText(JSON.stringify(snapshot));backend.waitForJob();
        Audio.auditEvents.read(event);
        test.wait(150);
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                backend.waitForJob();
                const snapshot = JSON.parse(backend.text());
                function node(entry, type) {
                    return {id:entry.name.length, name:entry.name, description:entry.description, type:type};
                }
                MockPipewire.nodes.values = snapshot.sinks.map(e => node(e, MockPipewire.AudioSink))
                    .concat(snapshot.sources.map(e => node(e, MockPipewire.AudioSource)));
                test.wait(100);
                check(Audio.availableSinks.length === 2, "unplugged motherboard outputs and undetectable S/PDIF are hidden");
                check(Audio.availableSources.length === 1, "unplugged microphone and line input are hidden");
                check(rows(popup).join('|') === 'External USB Headset|JBL Earbuds|JBL Earbuds',
                    "connected Bluetooth and external USB devices retain their names, including a sole input");
                const expected = ['Digital Output (S/PDIF)', 'Speakers', 'Front Headphones', 'Line In', 'Microphone'];
                const onboard = snapshot.sinks.slice(0, 3).concat(snapshot.sources.slice(0, 2));
                check(onboard.every((entry, i) => Audio.deviceName(entry) === expected[i]),
                    "motherboard ports have clear names");
                MockPipewire.defaultAudioSink = Audio.sinks.find(n => n.name === 'headphones');
                check(!Audio.connected, "an unplugged default output keeps the disconnected bar icon");

                snapshot.sources[1].ports[0].availability = 'available';
                refresh(snapshot, "Event 'change' on source #66");
                check(Audio.availableSources.length === 2 && rows(popup).includes('Microphone'),
                    "a source event reveals a plugged microphone in the popup");
                snapshot.sinks[2].ports[0].availability = 'available';
                refresh(snapshot, "Event 'change' on sink #64");
                check(Audio.availableSinks.length === 3 && rows(popup).includes('Front Headphones'),
                    "a sink event reveals plugged headphones in the popup");
                check(Audio.connected, "plugging the default output also updates the bar icon");
                check(rows(popup)[0] === 'Front Headphones', "selected output sorts ahead of other devices");
                const selected = find(popup, item => item.modelData === Audio.sink && item.current === true);
                const master = find(popup, item => item.name === 'Output' && item.sliderWidth !== undefined);
                check(selected.mapToItem(master.parent, 0, 0).y === master.y + master.height + popup.spacing,
                    "ticked output sits directly below its volume slider (" + selected.mapToItem(master.parent, 0, 0).y
                    + " vs " + (master.y + master.height + popup.spacing) + ")");
                check(!find(popup, item => item.title === 'Output'), "redundant Output header is removed");
                snapshot.sinks[2].ports[0].availability = 'not available';
                snapshot.sources[1].ports[0].availability = 'not available';
                refresh(snapshot, "Event 'change' on card #50");
                check(Audio.availableSinks.length === 2 && Audio.availableSources.length === 1
                    && !rows(popup).includes('Microphone') && !rows(popup).includes('Front Headphones'),
                    "unplugging removes both devices again");
                check(!Audio.connected, "unplugging the default output restores the disconnected bar icon");
                check(!Audio.deviceAvailable({name:'auto_null'}), "dummy output stays hidden");
                console.log("DONE: audio devices");
            } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}'''


def main():
    """Run the actual service and popup against an isolated pactl snapshot."""
    def port(name, kind, availability="not available"):
        return {"name": name, "description": "USB Audio " + name,
                "properties": {"alsa.components": "USB0b05:1a5c"},
                "ports": [{"name": name, "type": kind, "availability": availability}],
                "active_port": name}

    snapshot = {
        "sinks": [port("spdif", "SPDIF", "availability unknown"), port("speakers", "Speaker"),
                  port("headphones", "Headphones"),
                  {"name": "earbuds", "description": "JBL Earbuds", "ports": []},
                  {"name": "headset", "description": "External USB Headset", "ports": []}],
        "sources": [port("line", "Line"), port("mic", "Mic"),
                    {"name": "earbuds-mic", "description": "JBL Earbuds", "ports": []}],
    }
    with tempfile.TemporaryDirectory(prefix="qs-audio-devices-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "components/Popup.qml").write_text(standards.POPUP)
        for name in ("services/Audio.qml", "components/AudioPopup.qml"):
            path = target / name
            source = path.read_text().replace("import Quickshell.Services.Pipewire", "import qs.services")
            source = source.replace("PwObjectTracker {", "Item {\n        property var objects")
            source = source.replace("property var objects\n        objects:", "property var objects:")
            if name.startswith("services/"):
                source = source.replace("property PwNode", "property var")
                source = source.replace("Pipewire.", "MockPipewire.").replace("PwNodeType.", "MockPipewire.")
                source = source.replace("id: root", "id: root\n    property alias auditEvents: subscription.stdout", 1)
            path.write_text(source)
        (target / "services/MockPipewire.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    enum NodeType { AudioSink, AudioSource, AudioOutStream }
    property QtObject nodes: QtObject { property var values: [] }
    property var defaultAudioSink: null
    property var defaultAudioSource: null
    property var preferredDefaultAudioSink: null
    property var preferredDefaultAudioSource: null
}''')
        (target / "ports.json").write_text(json.dumps(snapshot))
        (target / "pactl").write_text('''#!/usr/bin/env python3
from pathlib import Path
import sys
import time
if "subscribe" in sys.argv:
    time.sleep(60)
else:
    print(Path(__file__).with_name("ports.json").read_text())
''')
        (target / "pactl").chmod(0o700)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(
            ["qs", "-p", str(target), "--no-color"],
            env=shell_env(target, PATH=str(target) + os.pathsep + os.environ["PATH"]),
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines()
                        if any(marker in line for marker in ("PASS:", "DONE:", *errors))))
        return 0 if result.returncode == 0 and "DONE: audio devices" in output \
            and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
