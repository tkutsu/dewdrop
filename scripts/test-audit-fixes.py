#!/usr/bin/env python3
"""Exercise the audit's small correctness and lifecycle fixes in isolation."""

import json
import ctypes
import os
from pathlib import Path
import runpy
import shutil
import stat
import subprocess
import tempfile
import time
from unittest.mock import patch

from test_support import offscreen_ink

ROOT = Path(__file__).resolve().parents[1]

GOOGLE = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool configured: false
    property bool needsConsent: false
    property bool consenting: false
    property date now: new Date(2026, 9, 13, 12)
    property string today: "2026-10-13"
    signal ready
    function dayString(at) { return Qt.formatDate(at, "yyyy-MM-dd"); }
}'''

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    id: suite
    property real saved: 0
    property int writes: 0
    property int invalidSources: 0
    FloatingWindow {
        implicitWidth: 500; implicitHeight: 100
        Item { id: fixtureAnchor; property string settingsKey: "drives"; width: 20; height: 20 }
        Glyph { id: glyph; text: "A"; height: 30 }
        Connections {
            target: glyph
            function onAuditArtChanged() { suite.checkArtSource(); }
        }
        Connections {
            target: glyph.auditArt
            function onSourceChanged() { suite.checkArtSource(); }
        }
        BarText { id: inkText; text: "audit measured text"; opticalCentre: true; visible: false }
        TestCase { id: test; when: false }
        Component { id: sliderFactory; SettingSlider {} }
    }
    Component { id: calendarFactory; Calendar { anchorItem: fixtureAnchor; visible: false; requestedVisible: false; probes: false } }
    function checkArtSource() {
        const source = String(glyph.auditArt?.source ?? "");
        if (source !== "" && !source.startsWith("file:")) suite.invalidSources++;
    }
    function fittedIcons(item) {
        return (item.objectName === "audit-fitted-icon" ? 1 : 0)
            + item.children.reduce((count, child) => count + fittedIcons(child), 0);
    }
    function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                test.tryVerify(() => Drives.drives.length === 1, 1000);
                check(Drives.drives.length === 1 && Drives.drives[0].disk === "/dev/fixture", "drive monitor reads isolated lsblk data");
                let refreshes = Drives.auditRefreshes;
                test.wait(120);
                check(Drives.auditRefreshes === refreshes, "drive usage is not polled with its popup closed");
                OpenPopup.owner = fixtureAnchor;
                test.wait(120);
                check(Drives.auditRefreshes >= refreshes + 2, "opening Devices refreshes and keeps usage polling");
                OpenPopup.owner = null;
                refreshes = Drives.auditRefreshes;
                test.wait(120);
                check(Drives.auditRefreshes === refreshes, "closing Devices stops usage polling");
                Drives.auditSettle.restart(); test.wait(90);
                check(Drives.auditRefreshes === refreshes + 1, "hotplug still refreshes drives with the popup closed");
                for (const title of ["we need milk", "mo money", "tom needs milk"])
                    check(Tasks.parse(title).title === title && Tasks.parse(title).day === "", "ordinary task title: " + title);
                check(Tasks.parse("tomorrow milk").day === "2026-10-14", "tomorrow remains a date keyword");
                check(Tasks.parse("fri call").day === "2026-10-16", "three-letter weekdays remain supported");
                check(Tasks.parse("friday call").day === "2026-10-16", "full weekdays remain supported");
                check(Tasks.parse("2028-02-29 leap").day === "2028-02-29", "valid leap day is accepted");
                for (const date of ["2026-99-99", "2026-02-29", "2026-04-31", "2026-00-10", "2026-01-00"])
                    check(!Tasks.parse(date + " tax").ok && Tasks.parse(date + " tax").error !== "", "impossible task date: " + date);
                check(!Tasks.parse("today").ok, "a date still needs a task title");

                const names = ["constructor", "__proto__", "toString", "Ordinary"];
                Library.build(names.map((name, i) => `${i}/track.flac\\t${name}\\t${name}\\tAlbum\\tTrack\\t2026\\t10`).join("\\n"));
                check(Library.artists.length === 4 && Library.albums.length === 4, "inherited object names retain their artists and albums");
                check(Library.artists.every(a => a.tracks === 1 && a.albums.length === 1), "artist and album membership stays correct");

                const control = sliderFactory.createObject(fixtureAnchor, {setting: {
                    from: 0, to: 1, step: 0.01, get: () => suite.saved,
                    set: value => { suite.saved = value; suite.writes++; }
                }});
                control.children.find(child => typeof child.moved === "function").moved(0.73);
                check(suite.writes === 0, "slider defers writes while dragging");
                control.destroy(); test.wait(20);
                check(suite.saved === 0.73 && suite.writes === 1, "fast slider close saves the pending value once");

                const calendar = calendarFactory.createObject(suite);
                calendar.offset = 2; test.wait(20);
                check(Agenda.lastShown === "2026-12", "calendar tracks the browsed month");
                calendar.destroy(); test.wait(20);
                check(Agenda.lastShown === "", "closing the calendar releases its browsed month");

                check(fittedIcons(glyph) === 0, "font glyphs allocate no artwork objects");
                const artwork = String(Qt.resolvedUrl("fixture.svg"));
                glyph.text = artwork;
                check(glyph.shown === "A" && glyph.auditLabel.visible && glyph.auditArt === null,
                    "font glyph stays displayed while artwork is pending");
                Ink.remember(artwork, 1, 0, 1); test.wait(50);
                check(glyph.shown === artwork && glyph.auditArt.visible && !glyph.auditLabel.visible, "measured artwork replaces the font glyph");
                check(fittedIcons(glyph) === 1, "settled artwork holds one picture");
                glyph.text = "B"; test.wait(50);
                check(glyph.shown === "B" && glyph.auditLabel.visible && glyph.auditArt === null, "switching back to a font unloads artwork");
                check(fittedIcons(glyph) === 0, "returning to a font leaves no artwork objects");
                check(suite.invalidSources === 0, "artwork never receives a font codepoint as its source");
                glyph.text = artwork + "#em";
                check(Ink._queue.some(job => job.source === artwork + "#em" && job.size === glyph.fontSize), "pending font-cut artwork is measured at the font size");
                Ink.remember(artwork + "#em", 1, 0, 1); test.wait(50);
                check(glyph.auditArt.size === glyph.fontSize, "displayed font-cut artwork keeps its font size");
                glyph.text = artwork;
                check(glyph.shown === artwork, "an already measured drawing replaces the font cut at once");
                test.wait(50);
                check(glyph.auditArt.size === Math.round(glyph.fontSize * Theme.iconSize / Theme.glyphSize), "ordinary artwork uses the theme icon size");

                const unseen = String(Qt.resolvedUrl("fixture-unseen.svg"));
                glyph.text = unseen;
                check(glyph.shown === artwork && fittedIcons(glyph) === 1, "unmeasured replacement keeps the displayed artwork");
                test.tryVerify(() => glyph.shown === unseen && Ink.extentOf(unseen) > 0, 2000);
                check(fittedIcons(glyph) === 1 && Math.abs(Ink.extentOf(unseen) - 14 / 20) < 0.08, "Ink measures the artwork's ink, not its box");
                check(glyph.implicitWidth === glyph.auditArt.inkWidth
                    && glyph.auditArt.mapToItem(glyph, 0, 0).x === -glyph.auditArt.inkX,
                    "lazy artwork keeps tight ink layout");
                check(glyph.auditArt.mapToItem(glyph, 0, 0).y === Math.floor((glyph.height - glyph.auditArt.height) / 2),
                    "lazy artwork stays vertically centred");
                glyph.tightWidth = false;
                check(glyph.implicitWidth === glyph.auditArt.implicitWidth, "ordinary box width remains available");
                glyph.tightWidth = true;
                glyph.text = String(Qt.resolvedUrl("fixture-aborted.svg")); test.wait(1);
                glyph.text = "C"; test.wait(50);
                check(glyph.shown === "C" && fittedIcons(glyph) === 0, "aborted artwork releases its measurement and returns to a font");
                check(suite.invalidSources === 0, "lazy artwork never receives a font codepoint");

                check(!(("glyph:" + inkText.inkKey) in Ink._asked), "hidden text is not measured");
                inkText.visible = true;
                test.tryVerify(() => inkText.inked !== null, 2000);
                check(inkText.inked.top >= Ink.glyphPad && inkText.inked.bottom < inkText.auditDrawn.height, "visible text is measured inside its padded Text");
                inkText.visible = false;

                GlassLight.track(fixtureAnchor, Qt.point(20, 10)); test.wait(1400);
                check(GlassLight.presence === 1 && !GlassLight.auditFrames.running, "stationary hover stops per-frame lighting work");
                GlassLight.track(fixtureAnchor, Qt.point(40, 20));
                check(GlassLight.auditFrames.running, "pointer movement restarts lighting");
                test.wait(800);
                check(GlassLight.x === 40 && GlassLight.y === 20 && !GlassLight.auditFrames.running, "lighting snaps to the new position and stops");
                GlassLight.leave(fixtureAnchor); test.wait(1400);
                check(GlassLight.presence === 0 && !GlassLight.auditFrames.running, "pointer leave finishes fading and stops");
                console.log("PASS: audit fixes");
            } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
            Qt.quit();
        }
    }
}'''


def check_oauth_save(target):
    """Save fixture credentials over loose files and check failed-save cleanup."""
    save = runpy.run_path(str(ROOT / "scripts/gtasks-auth"))["save"]
    dest = target / "oauth/gtasks.json"
    dest.parent.mkdir()
    dest.write_text("old")
    dest.chmod(0o644)
    leftover = Path(str(dest) + ".new")
    leftover.write_text("unrelated leftover")
    leftover.chmod(0o644)
    save.__globals__["DEST"] = str(dest)
    save("fixture-id", "fixture-secret", "fixture-token")
    assert stat.S_IMODE(dest.stat().st_mode) == 0o600
    assert json.loads(dest.read_text())["refresh_token"] == "fixture-token"
    assert leftover.read_text() == "unrelated leftover"
    with patch.object(os, "replace", side_effect=OSError("fixture failure")):
        try:
            save("replacement", "fixture-secret", "fixture-token")
        except OSError:
            pass
        else:
            raise AssertionError("expected save failure")
    assert json.loads(dest.read_text())["client_id"] == "fixture-id"
    assert not list(dest.parent.glob("gtasks-*"))
    print("PASS: OAuth saves use private files and preserve the old token on failure")


def check_parent_death():
    """Kill only a fixture parent and reap its parent-death-protected helper."""
    assert ctypes.CDLL(None).prctl(36, 1, 0, 0, 0) == 0  # Adopt the fixture orphan for waitpid.
    parent_code = 'import subprocess,time; child=subprocess.Popen(["setpriv", "--pdeathsig", "TERM", "--", "sleep", "30"]); print(child.pid, flush=True); time.sleep(30)'
    parent = subprocess.Popen(["python3", "-c", parent_code], stdout=subprocess.PIPE, text=True)
    child = int(parent.stdout.readline())
    try:
        # Ensure setpriv has exec'd the helper before terminating its parent.
        deadline = time.monotonic() + 2
        while Path(f"/proc/{child}/comm").read_text().strip() != "sleep":
            assert time.monotonic() < deadline
            time.sleep(0.01)
        parent.kill()
        parent.wait(timeout=2)
        while True:
            ended, status = os.waitpid(child, os.WNOHANG)
            if ended:
                assert os.waitstatus_to_exitcode(status) == -15
                child = None
                break
            assert time.monotonic() < deadline
            time.sleep(0.01)
    finally:
        if parent.poll() is None:
            parent.kill()
            parent.wait(timeout=2)
        parent.stdout.close()
        if child is not None:
            os.kill(child, 9)
            os.waitpid(child, 0)
    print("PASS: monitor helper exits on TERM when its fixture parent dies")


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-audit-fixes-") as folder:
        target = Path(folder)
        files = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "--cached", "--others", "--exclude-standard"], text=True)
        for name in files.splitlines():
            source = ROOT / name
            if source.is_file():
                dest = target / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
        check_oauth_save(target)
        check_parent_death()
        (target / "settings.json").write_text("{}\n")
        (target / "services/Google.qml").write_text(GOOGLE)
        (target / "OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property Item owner: null; property bool switched: false; function dropKeys(item) {} }')
        (target / "services/Mpd.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: false; signal databaseChanged }')
        (target / "services/Network.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool online: false }')
        source = (target / "services/Drives.qml").read_text().replace("interval: 5000", "interval: 50").replace("interval: 800", "interval: 50")
        source = source.replace("id: root", "id: root\n    property int auditRefreshes: 0\n    property alias auditSettle: settle", 1)
        source = source.replace("function refresh(): void {", "function refresh(): void {\n        root.auditRefreshes++;")
        (target / "services/Drives.qml").write_text(source)
        (target / "bin").mkdir()
        monitor_log = target / "monitor.log"
        (target / "bin/udevadm").write_text('#!/bin/sh\nif [ ! -s "$QS_AUDIT_MONITOR_LOG" ]; then printf "first\\n" >> "$QS_AUDIT_MONITOR_LOG"; exit 1; fi\nprintf "retry\\n" >> "$QS_AUDIT_MONITOR_LOG"\nexec sleep 30\n')
        (target / "bin/lsblk").write_text('#!/bin/sh\nprintf \'{"blockdevices":[{"path":"/dev/fixture","type":"disk","size":1000,"tran":"usb","fstype":"ext4","mountpoint":"/fixture","fssize":1000,"fsused":200}]}\\n\'\n')
        for name in ("udevadm", "lsblk"):
            (target / "bin" / name).chmod(0o700)
        source = (target / "components/FittedIcon.qml").read_text().replace("id: root", 'id: root\n    objectName: "audit-fitted-icon"', 1)
        (target / "components/FittedIcon.qml").write_text(source)
        source = (target / "components/Glyph.qml").read_text().replace("id: root", "id: root\n    readonly property var auditArt: art.item\n    property alias auditLabel: label", 1)
        (target / "components/Glyph.qml").write_text(source)
        source = (target / "components/BarText.qml").read_text().replace("id: root", "id: root\n    property alias auditDrawn: drawn", 1)
        (target / "components/BarText.qml").write_text(source)
        source = (target / "GlassLight.qml").read_text().replace("id: root", "id: root\n    property alias auditFrames: frames", 1).replace("FrameAnimation {", "FrameAnimation {\n        id: frames", 1)
        (target / "GlassLight.qml").write_text(source)
        (target / "fixture.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="white"/></svg>')
        for name in ("fixture-unseen.svg", "fixture-aborted.svg"):
            (target / name).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="5" y="3" width="10" height="14" fill="white"/></svg>')
        offscreen_ink(target)
        (target / "shell.qml").write_text(SHELL)
        (target / "runtime").mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", LC_ALL="C.UTF-8", XDG_RUNTIME_DIR=str(target / "runtime"), XDG_DATA_HOME=str(target / "data"), XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"))
        env["PATH"] = str(target / "bin") + os.pathsep + env["PATH"]
        env["QS_AUDIT_MONITOR_LOG"] = str(monitor_log)
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        print(output, end="")
        assert monitor_log.read_text().splitlines() == ["first", "retry"], "drive monitor must restart after an unexpected exit"
        print("PASS: failed USB monitor restarts once and keeps running")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot open:")
        return 0 if result.returncode == 0 and "PASS: audit fixes" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
