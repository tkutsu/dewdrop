#!/usr/bin/env python3
"""Exercise music queue scrolling, removal and hold-to-reorder gestures."""

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
        implicitWidth: 600; implicitHeight: 400
        Item { id: anchor; width: 40; height: 20 }
        TestCase {
            id: test; when: false
            function check(ok, message) {
                if (!ok) throw Error(message);
                console.log("PASS: " + message);
            }
            function named(item, name) {
                if (item.objectName === name || item.name === name) return item;
                for (const child of item.children || []) {
                    const found = named(child, name);
                    if (found) return found;
                }
                return null;
            }
            function inView() {
                const list = popup.auditList;
                const row = list.itemAtIndex(Mpd.songPos);
                return row !== null && row.y >= list.contentY - 0.1
                    && row.y + row.height <= list.contentY + list.height + 0.1;
            }
            function press(name, expected) {
                const button = named(popup.contentItem, name);
                mouseClick(button, button.width / 2, button.height / 2);
                tryCompare(Mpd, "songPos", expected, 1000);
                wait(50);
                check(inView(), name + " keeps track " + expected + " fully visible");
            }
            function run() {
                const list = popup.auditList;
                list.forceLayout();
                check(inView(), "opening the popup shows the current track");
                list.positionViewAtIndex(0, ListView.Beginning);
                wait(30);
                press("Next track", 8);
                const y = list.contentY;
                press("Previous track", 7);
                check(list.contentY === y, "an already visible track preserves the scroll position");
                list.positionViewAtIndex(23, ListView.End);
                wait(30);
                press("Previous track", 6);
                Mpd.nextPos = 23;
                press("Next track", 23);
                press("Next track", 0);
                press("Previous track", 23);
                Mpd.nextPos = 12;
                Mpd.replaceQueue = true;
                press("Next track", 12);
                list.positionViewAtIndex(0, ListView.Beginning);
                wait(30);
                check(!inView(), "manual scrolling can browse away from the current track");
                const browsing = list.contentY;
                Mpd.queueChanging();
                Mpd.queue = Mpd.queue.slice();
                wait(50);
                check(list.contentY === browsing, "queue refresh without a track change preserves browsing");
                Mpd.songPos = -1;
                wait(30);
                check(list.contentY === browsing, "no current track leaves the scroll position alone");
                list.positionViewAtIndex(0, ListView.Beginning);
                wait(30);
                // Exercise hit targets independently of the staged exit animation.
                Settings.set("reduceMotion", true);
                const remove = named(list.itemAtIndex(0), "Remove Track 0 from queue");
                check(remove !== null, "queue remove button found");
                for (const x of [remove.width / 2, 1, remove.width - 1]) {
                    mouseMove(remove, x, remove.height / 2);
                    wait(30);
                    check(remove.visible, "remove target at x=" + x + " is visible");
                    const calls = Mpd.removeCalls;
                    mouseClick(remove, x, remove.height / 2);
                    wait(400);
                    check(Mpd.removeCalls === calls + 1,
                        "remove click at x=" + x + " reaches remove once (remove=" + Mpd.removeCalls
                        + ", play=" + Mpd.playCalls + ", lifted=" + popup.auditReorder.showing + ")");
                    check(Mpd.playCalls === 0 && !popup.auditReorder.showing,
                        "remove click at x=" + x + " does not play or lift the track");
                }
                mousePress(remove, 1, remove.height / 2);
                wait(350);
                check(!popup.auditReorder.dragging, "holding remove does not lift the track");
                mouseRelease(remove, 1, remove.height / 2);
                tryCompare(Mpd, "removeCalls", 4, 500);
                const second = named(list.itemAtIndex(1), "Remove Track 1 from queue");
                mouseMove(second, second.width / 2, second.height / 2);
                wait(30);
                mouseClick(second, second.width / 2, second.height / 2);
                Mpd.queueChanging(); Mpd.queue = Mpd.queue.slice();
                wait(400);
                check(Mpd.removeCalls === 4, "refresh during remove feedback cancels the stale removal");
                const refreshed = named(list.itemAtIndex(1), "Remove Track 1 from queue");
                mouseMove(refreshed, refreshed.width / 2, refreshed.height / 2);
                wait(30);
                mouseClick(refreshed, refreshed.width / 2, refreshed.height / 2);
                tryCompare(Mpd, "removeCalls", 5, 500);
                check(Mpd.removed.join(",") === "0,0,0,0,1", "remove uses the clicked track's MPD position");
                Settings.set("reduceMotion", false);
                mouseClick(list, 25, 11);
                check(Mpd.playCalls === 1, "queue tap plays exactly once");
                mousePress(list, 25, 33);
                wait(350);
                check(popup.auditReorder.dragging, "queue hold starts shared drag");
                mouseMove(list, 25, 77);
                mouseRelease(list, 25, 77);
                check(Mpd.moves.length === 1 && Mpd.moves[0].from === 1 && Mpd.moves[0].to === 3, "queue drop moves the original track");
                wait(300);
                check(!popup.auditReorder.showing, "queue reply ends drop settle");
                const first = Mpd.queue[0];
                mousePress(list, 25, 11);
                wait(350);
                const start = list.contentY;
                mouseMove(list, 25, list.height - 2);
                wait(250);
                check(list.contentY > start, "shared queue drag scrolls at the edge");
                Mpd.queueChanging(); Mpd.queue = Mpd.queue.slice();
                mouseRelease(list, 25, list.height - 2);
                wait(300);
                check(Mpd.moves.length === 1, "refresh during a hold cancels the stale move");
                console.log("DONE: queue scroll");
            }
        }
    }
    MusicPopup { id: popup; visible: true; anchorItem: anchor }
    Timer { interval: 100; running: true; onTriggered: {
        try { test.run(); } catch(error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    """Click the real transport with delayed MPD replies in an isolated shell."""
    with tempfile.TemporaryDirectory(prefix="qs-queue-scroll-") as folder:
        target = Path(folder)
        copy_shell(target)
        mpd = titles.MPD.replace("property var queue: []; property int songPos: 0", '''
    property var queue: Array.from({length: 24}, (_, pos) => ({
        pos: pos, title: "Track " + pos, artist: "Artist", duration: 120
    }))
    property int songPos: 7
    property int nextPos: -1
    property bool replaceQueue: false
    property int playCalls: 0
    property int removeCalls: 0
    property var removed: []
    property bool applyRemovals: false
    property var moves: []
    function removeAt(pos) {
        removeCalls++; removed = removed.concat([pos]);
        if (applyRemovals) Qt.callLater(() => {
            const next = queue.filter(song => song.pos !== pos);
            queueChanging();
            queue = next.map((song, index) => Object.assign({}, song, {pos: index}));
        });
    }
    function playAt(pos) { playCalls++; songPos = pos; }
    function moveTo(from, to) {
        moves = moves.concat([{from: from, to: to}]);
        Qt.callLater(() => {
            const next = queue.slice();
            next.splice(to, 0, next.splice(from, 1)[0]);
            queueChanging();
            queue = next.map((song, pos) => Object.assign({}, song, {pos: pos}));
        });
    }''')
        mpd = mpd.replace("function prev() {} function next() {}", '''
    function change(pos) {
        Qt.callLater(() => {
            songPos = pos;
            if (replaceQueue) {
                queueChanging();
                queue = queue.slice();
                replaceQueue = false;
            }
        });
    }
    function prev() { change((songPos + queue.length - 1) % queue.length); }
    function next() {
        change(nextPos >= 0 ? nextPos : (songPos + 1) % queue.length);
        nextPos = -1;
    }''')
        (target / "services/Mpd.qml").write_text(mpd)
        (target / "services/Launcher.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property string musicPrefix: "#"; function openWith(prefix) {} }')
        path = target / "components/MusicPopup.qml"
        path.write_text(path.read_text()
            .replace("id: root", "id: root\n    property alias auditList: list\n    property alias auditReorder: reorder", 1)
            .replace("height: root.transportBand\n\n                                Glyph",
                     'height: root.transportBand\n                                objectName: modelData.name\n\n                                Glyph', 1))
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign",
                  "Binding loop", "Failed to load configuration")
        print("\n".join(line for line in output.splitlines()
                        if any(marker in line for marker in ("PASS:", "DONE:", *errors))))
        return 0 if result.returncode == 0 and "DONE: queue scroll" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
