#!/usr/bin/env python3
"""Exercise the real notice-to-bell handoff in both bar pills."""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from test_support import ROOT, copy_shell, shell_env


def block(source, marker, opening):
    start = source.rindex(opening, 0, source.index(marker))
    at = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[at] == "{") - (source[at] == "}")
        at += 1
    return source[start:at]


NOTIFICATIONS = '''pragma Singleton
import QtQuick
import qs
QtObject {
    property var latest: ({summary: "A notification", body: "", appName: "Test", image: ""})
    property var list: []
    readonly property int count: list.length
    property bool showing: false
    property bool held: false
    property bool urgent: false
    property int burst: 0
    readonly property int waiting: count - (showing && latest && list.includes(latest) ? 1 : 0)
    readonly property string label: waiting ? String(waiting) : ""
    readonly property string icon: Theme.glyph.notif
    property string tooltip: "Notifications"
    signal centreRequested(bool toggle)
    function plain(value) { return value; }
    function keyOf(value) { return ""; }
    function pictureOf(value) { return value.appIcon || ""; }
    function url(value) { return value || ""; }
    function dismissNotice(value) { showing = false; }
    function clearAll() { list = []; showing = false; }
}
'''

QML = '''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.components
import qs.modules
import qs.services
import qs.services as Services
import "Drops.js" as Drops
ShellRoot {
    id: bar
    readonly property var drops: Drops.geometry(Theme)
    readonly property var movableModules: [bell]
    readonly property var centreKeys: ["bell"]
    PLACE_MODULES
    property real noticeEdge: clockPill.x + clockPill.width
    QtObject { id: drawer; property bool out: false }
    QtObject { id: countdown; property bool stowed: true; property real reveal: 0 }
    QtObject { id: countdownPill; property real dropReveal: 0 }
    readonly property real leftLip: 0
    RIGHT_LIP
    CLOCK_GLASS
    FloatingWindow {
        id: window; implicitWidth: 1000; implicitHeight: 100
        Pill {
            id: clockPill; side: Pill.Side.Centre; centreOn: clock.keyBox
            order: ["clock", "bell", "tail"]
            CENTRE_MOTION
            BarItem { id: clock; settingsKey: "clock"; BarText { text: "Clock" } }
            BarItem { id: tail; settingsKey: "tail"; stowed: true; Glyph { text: "X" } }
        }
        Pill { id: rightPill; side: Pill.Side.Right; BELL }
        NOTICE
        TestCase {
            id: test; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function until(predicate, message) {
                for (let i = 0; i < 200 && !predicate(); i++) wait(10);
                check(predicate(), message);
            }
            function reset() {
                Notifications.showing = false; Notifications.list = [];
                drawer.out = false; DrawerPins.setMode("bell", "auto");
                wait(1200);
                check(bell.stowed && !bell.visible, "empty bell is hidden");
                Notifications.list = [Notifications.latest]; Notifications.showing = true;
                wait(Theme.dropMs + 100);
                check(notice.reveal === 1 && bell.stowed, "a single notice leaves the bell hidden");
            }
            function handoff(closing) {
                const restX = clockPill.x;
                Notifications.showing = !closing;
                const source = notice.keyBox.children.find(item => item instanceof BadgedGlyph);
                const sender = notice.keyBox.children.find(item => item instanceof AppIcon);
                const target = bell.keyBox.children[0];
                let frames = 0, fading = false, scaling = false, recoiling = false, pillTravel = 0;
                for (let i = 0; i < 55; i++) {
                    wait(16);
                    if (closing && i === 6)
                        check(sender.opacity >= 0.35 && sender.scale < 0.96,
                              "notification app icon remains legible while shrinking on exit");
                    const recoil = bar.drops.lip(noticePill.dropReveal, notice.stowed);
                    recoiling = recoiling || Math.abs(bar.rightLip) > 0.001;
                    pillTravel = Math.max(pillTravel, Math.abs(clockPill.x - restX));
                    check(Math.abs(clockPill.x - clockPill._centreLeft - clockPill.centreShift - clockPill._rightHold) < 0.01,
                          "notification recoil moves the whole centre pill");
                    check(Math.abs(bar.rightLip - recoil) < 0.001
                          && Math.abs(bar.clockGlass.z - clockPill.width - recoil) < 0.01
                          && Math.abs(bar.clockGlass.x - clockPill.x) < 0.01,
                          "receiving glass edge follows the same recoil curve as MPD/MPRIS");
                    const progress = notice.iconHandoff.progress;
                    const phase = Math.max(0, Math.min(1, (0.38 - notice.reveal) / 0.18));
                    check(Math.abs(progress - phase * phase * (3 - 2 * phase)) < 0.00001,
                          "bell follows the media handoff timing");
                    check(!noticePill.bounceBeforeCollapse && notice.foldDuration === Theme.dropMs,
                          "notification uses the media glass timing");
                    check(sender.scale >= 0.8 && sender.scale <= 1 && source.scale === 1,
                          "sender scales without bouncing and bell retains its size");
                    check(Math.abs(sender.opacity - Theme.moduleOpacity(notice.senderInk)) < 0.001
                          && Math.abs(sender.scale - Theme.moduleScale(notice.senderInk)) < 0.001,
                          "sender shares the module fade and scale");
                    fading = fading || (sender.opacity > 0 && sender.opacity < 1);
                    scaling = scaling || (sender.scale > 0.8 && sender.scale < 1);
                    if (progress === 0) {
                        const position = source.mapToItem(notice, 0, 0);
                        check(Math.abs(position.x + source.width
                              - notice.glassLeft - notice.glassWidth + notice.iconInset) < 0.1,
                              "bell follows the moving right edge before the handoff");
                    }
                    if (progress > 0 && progress < 1) {
                        frames++;
                        const a = source.mapToItem(window.contentItem, 0, 0);
                        const b = target.mapToItem(window.contentItem, 0, 0);
                        check(Math.abs(a.x - b.x) < 0.1 && Math.abs(a.y - b.y) < 0.1,
                              "bell copies coincide during " + (closing ? "merge" : "expansion")
                              + ": " + JSON.stringify({a, b, progress}));
                        check(Math.abs(source.opacity + target.opacity - 1) < 0.001,
                              "bell crossfade has no opacity gap");
                        check(Math.abs(bell.implicitWidth - Math.round(bell._fullWidth * progress)) < 0.01,
                              "central slot follows the same media handoff");
                    }
                }
                if (closing) check(recoiling, "receiving edge recoils during notification merging");
                if (closing) check(pillTravel > 1, "whole centre pill visibly recoils on the bell merge");
                check(frames > 2 && fading && scaling, "sampled the bell handoff and sender fade/scale");
                check(closing ? !noticePill.visible && bell.visible : noticePill.visible && !bell.visible,
                      "handoff ends with one visible bell");
                if (!closing) {
                    const body = notice.keyBox.children.find(item => item.visible && item !== source && item !== sender);
                    check(sender.x + sender.width < body.x && body.x + body.width < source.x,
                          "notification shows app icon, then text, then bell");
                    check(notice.width <= notice.room, "the extra bell stays within the available room");
                }
            }
            function run() {
                bell.settingsKey = "bell"; bell.visibilityKey = "bell";
                wait(Theme.startMs + 50);
                bar.placeModules();
                DrawerPins.setMode("bell", "auto");
                if (CLEAR_ONLY) {
                    for (const remaining of [false, true]) {
                        for (const showing of [false, true]) {
                            for (const fromBell of [false, true]) {
                                Notifications.latest = Object.assign({}, Notifications.latest, {
                                    dismiss: () => { Notifications.list = Notifications.list.filter(n => n !== Notifications.latest); Notifications.showing = false; }
                                });
                                Notifications.list = remaining ? [Notifications.latest, {}] : [Notifications.latest]; Notifications.showing = true;
                                wait(Theme.dropMs + 100);
                                Notifications.showing = showing;
                                wait(1200);
                                const restingX = clock.keyBox.mapToItem(window.contentItem, 0, 0).x;
                                if (fromBell) bell.actions[Qt.RightButton]();
                                else Notifications.latest.dismiss();
                                for (let i = 0; i < 75; i++) {
                                    wait(16);
                                    const clockX = clock.keyBox.mapToItem(window.contentItem, 0, 0).x;
                                    check(Math.abs(clockX - restingX) < 0.01,
                                          "clearing notifications keeps the centre pill still (notice=" + showing
                                          + ", bell=" + fromBell + ", remaining=" + remaining + "): clock=" + clockX + ", rest=" + restingX);
                                }
                            }
                        }
                    }
                    console.log("PASS: clearing notifications keeps the centre pill still");
                    return;
                }
                Notifications.list = [Notifications.latest]; Notifications.showing = true;
                wait(Theme.dropMs + 100);
                const sender = notice.keyBox.children.find(item => item instanceof AppIcon);
                const source = notice.keyBox.children.find(item => item instanceof BadgedGlyph);
                const body = notice.keyBox.children.find(item => item.visible && item !== source && item !== sender);
                check(!sender.hasIcon && !sender.visible, "a sender without an icon does not duplicate the notification bell");
                check(Math.abs(source.x - body.x - body.width - notice.spacing) < 0.01
                      && Math.abs(body.x) < 0.01,
                      "a hidden sender leaves the text first and only one gap before the bell");
                Notifications.latest = Object.assign({}, Notifications.latest, {appIcon: Qt.resolvedUrl("sender.svg").toString()});
                Notifications.list = [Notifications.latest];
                until(() => sender.hasIcon, "sender artwork loads");
                wait(100);
                check(sender.visible, "real sender artwork remains visible beside the bell");
                Notifications.showing = false;
                let placedFrames = 0, peakLip = 0, reboundLip = 0;
                for (let i = 0; i < 55; i++) {
                    wait(16);
                    peakLip = Math.max(peakLip, bar.rightLip);
                    reboundLip = Math.min(reboundLip, bar.rightLip);
                    const progress = notice.iconHandoff.progress;
                    if (progress > 0 && progress < 1) {
                        placedFrames++;
                        check(bell.visible, "Auto bell must remain visible throughout the live placement handoff: "
                              + JSON.stringify({progress, stowed: bell.stowed, reveal: bell.reveal,
                                  handingOff: bell.handingOff, duration: bell.foldDuration}));
                        const source = notice.keyBox.children.find(item => item instanceof BadgedGlyph);
                        const target = bell.keyBox.children[0];
                        const from = source.mapToItem(window.contentItem, 0, 0);
                        const to = target.mapToItem(window.contentItem, 0, 0);
                        check(Math.abs(from.x - to.x) < 0.1 && Math.abs(from.y - to.y) < 0.1,
                              "Auto bell icon copies coincide after real module placement");
                    }
                }
                check(placedFrames > 2, "sampled Auto bell handoff after real module placement");
                check(peakLip > 1 && reboundLip < 0, "receiving edge swells and rebounds with Auto bell visible");
                if (PLACEMENT_ONLY) {
                    console.log("PASS: media bell handoff after real module placement in Auto mode");
                    return;
                }
                bell.parent = clockPill.moduleHost;
                DrawerPins.setMode("bell", "pinned");
                Notifications.list = [Notifications.latest];
                wait(700);
                check(bell.visible, "bell starts at the centre pill's right edge");
                handoff(false); handoff(true); handoff(false);
                Notifications.showing = false; wait(80);
                Notifications.showing = true; wait(Theme.dropMs + 100);
                check(notice.reveal === 1 && !bell.visible, "interrupted merge returns the bell to the bubble");
                Notifications.showing = false; wait(Theme.dropMs + 100);
                for (const central of [false, true]) {
                    tail.stowed = !central;
                    bell.parent = central ? clockPill.moduleHost : rightPill.moduleHost;
                    bell.pinKey = central ? "" : "bell";
                    wait(700);
                    reset();
                    check(!bell.handingOff, "bells outside the centre pill's right edge keep normal motion");
                    Notifications.showing = false;
                    let frames = 0;
                    while (notice.reveal > 0 && noticePill.foldBox.x + noticePill.foldBox.z > -Theme.pillSpread) {
                        check(bell.stowed && !bell.visible, "bell appeared before the notice merged (central=" + central + ")");
                        wait(10); frames++;
                    }
                    check(frames > 10, "sampled the animated contraction");
                    until(() => !bell.stowed && bell.reveal > 0 && bell.reveal < 1, "bell eases in after the merge");
                    const glyph = bell.keyBox.children[0];
                    let framesIn = 0, fading = false, scaled = false;
                    while (framesIn++ < 30) {
                        check(bell.reveal >= 0 && bell.reveal <= 1, "slot stays bounded while the glass can bounce");
                        check(!bell.clip, "bell grows in place, unclipped");
                        const rect = glyph.mapToItem(bell, 0, 0, glyph.width, glyph.height);
                        fading = fading || (bell.keyBox.opacity > 0 && bell.keyBox.opacity < 1);
                        scaled = scaled || (rect.width > glyph.width * 0.8 && rect.width < glyph.width * 0.899);
                        check(rect.width <= glyph.width + 0.01, "icon never grows beyond its resting size");
                        check(Math.abs(clockPill.x - clockPill._centreLeft - clockPill.centreShift - clockPill._rightHold) < 0.01, "central pill follows its position animation");
                        wait(10);
                    }
                    check(fading && scaled && bell.reveal === 1, "bell fades and scales into its full-size slot: fade=" + fading + ", scale=" + scaled + ", reveal=" + bell.reveal + ", transforms=" + glyph.transform.length + ", width=" + glyph.width);
                    check(Math.abs(glyph.mapToItem(bell, 0, 0).x - bell.padLeft - bell._leftGap) < 0.01,
                          "bell settles at its normal inset");
                    Notifications.list = [];
                    const fullWidth = bell.width;
                    wait(75);
                    check(!bell.clip && bell.keyBox.opacity > 0 && bell.keyBox.opacity < 1 && bell.appearanceScale < 1,
                          "exit fades and shrinks the icon in place");
                    wait(Theme.moduleRetireMs);
                    check(bell.keyBox.opacity === 0 && bell.width < fullWidth, "slot closes after the quick fade");
                    wait(Theme.moduleCloseMs + 30);
                    check(!bell.visible, "exit finishes cleanly");
                    Notifications.list = [Notifications.latest]; wait(Theme.moduleOpenMs + 30);
                    check(Notifications.waiting === 1, "handoff preserves the notification count");

                    reset();
                    Notifications.showing = false; wait(80);
                    Notifications.list = [Notifications.latest, {}]; wait(30);
                    check(!bell.stowed, "another notification shows the bell during contraction");

                    reset();
                    drawer.out = true; wait(100);
                    check(!bell.stowed, "drawer can reveal the bell before merge");

                    reset();
                    DrawerPins.setMode("bell", "pinned"); wait(100);
                    check(!bell.stowed, "pinned bell stays available before merge");

                    reset();
                    Notifications.showing = false; wait(80);
                    Notifications.list = []; wait(Theme.dropMs + 100);
                    check(bell.stowed && !bell.visible, "expired notice leaves no bell");

                    reset();
                    Notifications.showing = false; wait(80);
                    Notifications.showing = true; wait(Theme.dropMs + 100);
                    check(bell.stowed && !bell.visible && notice.reveal === 1, "new notice cancels the handoff");
                }
                Settings.set("reduceMotion", true);
                tail.stowed = true;
                bell.parent = clockPill.moduleHost; bell.pinKey = "";
                reset();
                Notifications.showing = false;
                until(() => bell.reveal === 1 && notice.reveal === 0, "reduced motion completes the handoff");
                wait(30);
                const glyph = bell.keyBox.children[0];
                check(Math.abs(glyph.mapToItem(bell, 0, 0).x - bell.padLeft - bell._leftGap) < 0.01,
                      "bell settles in its usual position with reduced motion");
                check(Math.abs(clockPill.x - clockPill._centreLeft - clockPill._rightHold) < 0.01,
                      "reduced motion keeps the central pill still");
                console.log("PASS: media bell handoff in both directions, sender fade/scale, interruption, other positions and reduced motion");
            }
        }
        Timer { interval: 100; running: true; onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    bar = (ROOT / "Bar.qml").read_text()
    placement = re.search(r"^    function placeModules\(\): void \{.*?^    \}", bar, re.M | re.S)
    qml = QML.replace("PLACE_MODULES", placement[0]).replace("PLACEMENT_ONLY", "true" if "--placement" in sys.argv else "false")
    qml = qml.replace("CLEAR_ONLY", "true" if "--clear" in sys.argv else "false")
    qml = qml.replace("BELL", block(bar, "id: bell", "NotificationBell {"))
    qml = qml.replace("NOTICE", block(bar, "id: noticePill", "SidePill {"))
    motion_start = bar.index("        animatePosition:")
    motion_end = bar.index("        // Quiet capture controls", motion_start)
    qml = qml.replace("CENTRE_MOTION", bar[motion_start:motion_end])
    for placeholder, name in (("RIGHT_LIP", "rightLip"), ("CLOCK_GLASS", "clockGlass")):
        declaration = re.search(r"^    readonly property [^\n]+ " + name + r": .+$", bar, re.M)
        qml = qml.replace(placeholder, declaration[0])
    with tempfile.TemporaryDirectory(prefix="qs-notification-merge-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "sender.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="red"/></svg>')
        (target / "services/Notifications.qml").write_text(NOTIFICATIONS)
        (target / "components/NotificationsPopup.qml").write_text("import QtQuick\nItem {}\n")
        (target / "shell.qml").write_text(qml)
        env = shell_env(target)
        if "--wayland" in sys.argv:
            runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
            display = str(Path(runtime) / os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
            env.update(QT_QPA_PLATFORM="wayland", QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                       WAYLAND_DISPLAY=display)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=50)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Binding loop", "Unable to assign", "Cannot assign", "Failed to load configuration")
        passed = "PASS: clearing notifications" if "--clear" in sys.argv else "PASS: media bell handoff"
        ok = result.returncode == 0 and passed in output and not any(e in output for e in errors)
        success = "PASS: Auto bell visibility, alignment, edge swell and rebound after real module placement" if "--placement" in sys.argv else "PASS: media bell handoff in both directions, sender fade/scale, interruption, other positions and reduced motion"
        if "--clear" in sys.argv:
            success = "PASS: bell clear and individual dismissal keep the centre pill still, with and without an active notice"
        print(success if ok else output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
