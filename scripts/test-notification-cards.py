#!/usr/bin/env python3
"""Click the real notification popup with isolated notification and window state."""

import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib


ROOT = Path(__file__).resolve().parents[1]


def png(width, height):
    """A plain red PNG: rasters are what the picture rule measures."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + b"\xff\0\0" * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def main():
    popup = (ROOT / "components/NotificationsPopup.qml").read_text()
    # Fake notification objects substitute for D-Bus objects; card behavior is unchanged.
    popup = popup.replace("readonly property Notification n:", "readonly property var n:")
    popup = popup.replace("id: card\n", 'id: card\n        objectName: "notification-card"\n')
    popup = popup.replace("id: cards\n", 'id: cards\n        objectName: "notification-list"\n')
    popup = popup.replace("text: Notifications.styled(card.n?.summary)", 'objectName: "summary-label"\n                    text: Notifications.styled(card.n?.summary)')
    popup = popup.replace("text: Notifications.styled(card.n?.body)", 'objectName: "body-label"\n                    text: Notifications.styled(card.n?.body)')
    popup = popup.replace("id: preview\n", 'id: preview\n                        objectName: "preview"\n')
    popup = popup.replace("id: content\n", 'id: content\n            objectName: "card-content"\n')
    popup = popup.replace("id: group\n", 'id: group\n        objectName: "notification-group"\n')
    popup = popup.replace("id: groupHeader\n", 'id: groupHeader\n                objectName: "group-header"\n')
    service = (ROOT / "services/Notifications.qml").read_text()
    functions = service[service.index("    function activate(n)"):service.index("    // What AppIcon")]
    with tempfile.TemporaryDirectory(prefix="quickshell-notification-cards-") as folder:
        target = Path(folder)
        (target / "services").mkdir()
        (target / "NotificationsPopup.qml").write_text(popup)
        for name in ("PopupButton", "PopupText", "PopupHeader", "PopupNote", "PopupRow", "SwipeRow", "NotificationPicture", "ChoiceBlink", "SmoothScroll"):
            (target / f"{name}.qml").write_text((ROOT / f"components/{name}.qml").read_text())
        (target / "PressGlass.qml").write_text('import QtQuick\nQtObject { required property Item icon; required property var area; property bool down: false; property bool textPress: false; property real scale: 1 }\n')
        (target / "ScrollUnder.qml").write_text('import QtQuick\nItem { required property Flickable view; required property Item box }\n')
        (target / "Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property color label: "white"; property color label2: "grey"; property color label3: "grey"
    property color warn: "red"; property color fg: "white"; property color stroke: "grey"
    property color selection: "#222222"; property color selectionStrong: "#444444"
    property int popupInset: 6; property int popupPadding: 6; property int popupRadius: 10; property int popupWideWidth: 400;
    property int selectionRadius: 4; property int fadeMs: 100; property int captionSize: 14
    property int blinkMs: 60
    property int foldMs: 180; property real drawerSpring: 3; property real drawerDamping: 0.3
    property bool reduceMotion: false
    property int popupTextSize: 16; property int glyphSizeLarge: 16; property int pillBorder: 1
    property string bodyFont: "sans-serif"; property var figures: ({})
    property var glyph: ({notif: "N", close: "X", plus: "+", clearAll: "C", check: "Y"})
}
''')
        (target / "Popup.qml").write_text('''import QtQuick
Item {
    property var screen: ({height: 1080})
    property var anchorItem: null
    property real reserveHeight: 0
    property bool dismissWhenEmpty: false
    property bool requestedVisible: true
    readonly property bool animateContents: !Theme.reduceMotion
    readonly property real chromeHeight: body.implicitHeight
    readonly property Item chromeItem: body
    property alias spacing: body.spacing
    default property alias content: body.data
    width: body.implicitWidth; height: body.implicitHeight
    Column { id: body }
}
''')
        (target / "Glyph.qml").write_text('import QtQuick\nItem { property int fontSize: 16; property alias text: label.text; property alias color: label.color; implicitWidth: label.implicitWidth; Text { id: label; font.pixelSize: parent.fontSize } }\n')
        (target / "Badge.qml").write_text('import QtQuick\nText {}\n')
        (target / "services/OpenPopup.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool dismissed: false
    function close(item) { dismissed = true; }
    function dismiss() { dismissed = true; }
}
''')
        (target / "services/Notifications.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
QtObject {
    id: root
    property var list: []
    readonly property int count: list.length
    property var centreFocus: null
    property int invoked: 0
    function iconFor(n) { return ""; }
    function url(s) { return s || ""; }
    function ago(n, now) { return "now"; }
''' + functions + "}\n")
        (target / "preview.png").write_bytes(png(200, 400))
        (target / "avatar.png").write_bytes(png(96, 96))
        (target / "shell.qml").write_text(r'''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
ShellRoot {
    id: root
    QtObject {
        id: notice
        property string appName: "Card test"
        property string summary: "Summary ".repeat(30)
        property string body: "Detailed notification text ".repeat(100)
        property string desktopEntry: ""
        property string image: Qt.resolvedUrl("preview.png")
        property int urgency: 1
        property bool resident: false
        property var actions: []
        function dismiss() { Notifications.list = Notifications.list.filter(n => n !== notice); }
    }
    Window {
        visible: true; width: 500; height: 900
        NotificationsPopup { id: popup }
        TestCase {
            id: test; name: "NotificationCards"; when: false
            function check(ok, message) { if (!ok) throw Error(message); }
            function checkSoon(predicate, message) {
                const deadline = Date.now() + 1000;
                while (!predicate() && Date.now() < deadline) wait(10);
                check(predicate(), message);
            }
            function named(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = named(child, name);
                    if (found) return found;
                }
                return null;
            }
            function button(item, label) {
                if (item.label === label) return item;
                for (const child of item.children || []) {
                    const found = button(child, label);
                    if (found) return found;
                }
                return null;
            }
            function cardCount(item) {
                let count = item.objectName === "notification-card" && item.visible ? 1 : 0;
                for (const child of item.children || []) count += cardCount(child);
                return count;
            }
            function notificationCard(item, entry) {
                if (item.objectName === "notification-card" && item.n === entry) return item;
                for (const child of item.children || []) {
                    const found = notificationCard(child, entry);
                    if (found) return found;
                }
                return null;
            }
            function dragCard(card, left, distance) {
                const start = left ? card.width - 15 : 15;
                const end = start + (left ? -distance : distance);
                mousePress(card, start, 30);
                mouseMove(card, start + (left ? -25 : 25), 30, 30);
                mouseMove(card, end, 30, 30);
                check(card.tracking && (left ? card.swipe < 0 : card.swipe > 0), "mouse drag tracks the card");
                const content = named(card, "card-content");
                check(Math.abs(content.x - 10 - card.swipe) < 1, "card content follows the swipe");
                mouseRelease(card, end, 30);
            }
            function checkDismissalSequence() {
                notice.summary = "First notification"; notice.body = ""; notice.image = "";
                const next = {appName: "Next sender", summary: "Next notification", body: "", actions: [], image: "",
                    dismiss: () => Notifications.list = Notifications.list.filter(n => n !== next)};
                const last = {appName: "Last sender", summary: "Last notification", body: "", actions: [], image: ""};
                const list = named(popup, "notification-list");
                for (const mode of ["single", "expanded", "collapsed", "capped"]) {
                    next.appName = ["expanded", "collapsed"].includes(mode) ? notice.appName : "Next sender";
                    popup.screen = {height: mode === "capped" ? 180 : 1080};
                    Notifications.list = [notice, next, last];
                    popup.expandedGroup = mode === "expanded" ? notice.appName : "";
                    wait(350);
                    const card = notificationCard(popup, notice);
                    const following = notificationCard(popup, mode === "collapsed" ? last : next);
                    const beforeY = following.mapToItem(list, 0, 0).y;
                    const beforeHeight = list.height;
                    mouseMove(card, 12, 30); wait(30);
                    const clear = button(card, "");
                    mouseClick(clear, clear.width / 2, clear.height / 2);
                    wait(Theme.blinkMs);
                    check(Notifications.count === 3 && card.opacity === 1,
                          "blink keeps the card and its neighbours in place");
                    wait(Theme.blinkMs + 30);
                    check(Notifications.count === 3 && card.opacity < 1,
                          "the card fades out after the blink before removal");
                    check(Math.abs(following.mapToItem(list, 0, 0).y - beforeY) < 0.1 && list.height === beforeHeight,
                          "neighbour and popup height stay still until the card is gone");
                    checkSoon(() => card.opacity === 0, "notification fades away before the rows move");
                    let moved = false;
                    const positions = [];
                    for (let elapsed = 0; elapsed < Theme.fadeMs - 20; elapsed += 10) {
                        const y = following.mapToItem(list, 0, 0).y;
                        positions.push([y, list.contentY, list.originY]);
                        moved = moved || (y > 1 && y < beforeY - 1);
                        check(Math.abs(list.height - beforeHeight) < 0.1, "popup keeps its height while neighbours move");
                        wait(10);
                    }
                    check(moved, "the following notification moves through intermediate positions: " + JSON.stringify({mode, beforeY, positions}));
                    checkSoon(() => following.mapToItem(list, 0, 0).y < 0.1, "following notification reaches the vacated position");
                    checkSoon(() => Notifications.count === (mode === "collapsed" ? 1 : 2), "notification is dismissed after the rows move");
                    if (mode !== "capped")
                        checkSoon(() => list.height < beforeHeight - 1, "popup shrinks after movement finishes");
                    checkSoon(() => Math.abs(list.height - Math.min(list.contentHeight, popup.listMax)) < 0.1,
                              "popup settles at its content height, capped at its scroll limit");
                }
                wait(Theme.fadeMs + 30);
                Theme.reduceMotion = true;
                popup.screen = {height: 1080};
                Notifications.list = [notice, last]; wait(50);
                popup.clear([notice]); wait(50);
                check(Notifications.count === 1 && Math.abs(list.height - list.contentHeight) < 0.1,
                      "reduced motion dismisses and resizes without animation delays");
                console.log("PASS: notification cards dismissal sequence");
                Theme.reduceMotion = false;
                for (const items of [[notice], [notice, next]]) {
                    Notifications.list = items;
                    OpenPopup.dismissed = false;
                    wait(350);
                    popup.clear(items);
                    check(Notifications.count === 0 && OpenPopup.dismissed,
                        "clearing the last items dismisses the whole popup immediately");
                    check(popup.departing.length === 0 && popup.departureFade === 0 && popup.departureFold === 0,
                        "the final items skip the card fade and fold animations");
                }
                console.log("PASS: final notifications use popup dismissal");
                Notifications.list = [];
                wait(150);
            }
            function run() {
                check(popup.bodyWidth === Theme.popupWideWidth, "the centre is as wide as mail and tasks");
                checkDismissalSequence();
                if (DISMISSAL_ONLY) return;
                // A sender's shortened payload must not be mistaken for UI elision.
                notice.appName = "kitty";
                notice.summary = "Done. Groups now collapse when you click their header, open another group, open a notification outside them, or close the popover. Intera...";
                notice.body = ""; notice.image = "";
                Notifications.list = [notice]; wait(150);
                let card = named(popup, "notification-card");
                const title = named(card, "summary-label");
                check(title.text === notice.summary && !title.truncated, "a card shows the entire message, including a sender's literal ellipsis");
                check(card.height >= title.mapToItem(card, 0, title.height).y, "the whole title fits inside its card");
                Notifications.list = []; wait(130);
                notice.appName = "Card test";
                notice.summary = "Summary ".repeat(100);
                notice.body = "Detailed notification text ".repeat(100);
                notice.image = Qt.resolvedUrl("preview.png");
                Notifications.list = [notice]; wait(150);
                card = named(popup, "notification-card");
                const body = named(card, "body-label");
                const summary = named(card, "summary-label");
                check(summary.lineCount === 10 && body.lineCount === 10, "long text shows ten lines before eliding");
                check(summary.font.weight === Font.Normal && body.font.weight === Font.Normal, "plain notification text uses normal weight");
                check(named(card, "preview").height > 140, "an image is shown whole");
                check(card.icon === "", "content stays out of the icon slot");
                // A small square picture is the sender's mark: on the left, never a preview.
                notice.image = Qt.resolvedUrl("avatar.png"); wait(150);
                check(card.icon === notice.image && !named(card, "preview").parent.visible, "a small square picture goes in the icon slot");
                notice.image = "image://icon/dialog-information"; wait(150);
                check(card.icon === notice.image && !named(card, "preview").parent.visible, "a theme icon goes in the icon slot");
                notice.image = Qt.resolvedUrl("preview.png"); wait(150);
                // A click with a default action runs it once and clears the card.
                notice.actions = [{identifier: "default", text: " ", invoke: () => Notifications.invoked++}]; wait(130);
                check(button(card, "open sender") === null && button(card, "default") === null, "the default action has no button of its own");
                mouseClick(card, 12, 45);
                check(Notifications.invoked === 0 && Notifications.count === 1, "card stays until the acknowledgement finishes");
                card.open();
                checkSoon(() => Notifications.invoked === 1 && OpenPopup.dismissed && Notifications.count === 0, "a click runs the default action once and clears the card");
                // Without one it goes to the sender (nothing to focus here) and still clears.
                OpenPopup.dismissed = false;
                notice.actions = [];
                Notifications.list = [notice]; wait(150);
                mouseClick(notificationCard(popup, notice), 12, 45);
                checkSoon(() => Notifications.invoked === 1 && OpenPopup.dismissed && Notifications.count === 0, "a click with no action clears the card");
                // Other actions keep their buttons.
                OpenPopup.dismissed = false;
                notice.actions = [{identifier: "default", text: "Open", invoke: () => Notifications.invoked++}, {identifier: "reply", text: "Reply", invoke: () => Notifications.invoked += 10}];
                Notifications.list = [notice]; wait(150);
                card = notificationCard(popup, notice);
                const list = named(popup, "notification-list");
                list.contentY = Math.max(0, list.contentHeight - list.height); wait(130);
                const reply = button(card, "Reply");
                check(reply !== null && reply.visible, "the sender's other actions remain available");
                mouseClick(reply, reply.width / 2, reply.height / 2);
                checkSoon(() => Notifications.invoked === 11 && OpenPopup.dismissed && Notifications.count === 0, "another action runs once and clears its notification");
                // The close button clears without following.
                OpenPopup.dismissed = false;
                Notifications.list = [notice]; wait(150);
                card = notificationCard(popup, notice);
                list.contentY = 0; wait(130);
                const clear = button(card, "");
                mouseMove(card, 12, 45); wait(130);
                check(clear !== null && clear.visible, "hover exposes the dismiss control");
                mouseClick(clear, clear.width / 2, clear.height / 2);
                checkSoon(() => Notifications.count === 0 && Notifications.invoked === 11, "the dismiss control clears without running anything");
                // Groups: a closed group's card opens it rather than acting.
                notice.actions = [];
                notice.summary = "First notification"; notice.body = ""; notice.image = "";
                const second = {appName: notice.appName, desktopEntry: "", summary: "Second notification", body: "Other text", actions: [], image: "",
                    dismiss: () => Notifications.list = Notifications.list.filter(n => n !== second)};
                Notifications.list = [notice, second]; OpenPopup.dismissed = false; wait(150);
                check(cardCount(popup) === 1, "a sender's group starts closed");
                mouseClick(named(popup, "notification-card"), 12, 30); wait(130);
                check(cardCount(popup) === 2 && Notifications.count === 2 && !OpenPopup.dismissed, "clicking a closed group opens it without acting");
                check(button(popup, "show less") === null, "the group header needs no collapse button");
                const header = named(popup, "group-header");
                mouseClick(header, 20, header.height / 2); wait(130);
                check(cardCount(popup) === 1, "clicking the header closes the group");
                mouseClick(named(popup, "notification-card"), 12, 30); wait(130);
                mouseClick(notificationCard(popup, second), 12, 30);
                checkSoon(() => Notifications.count === 1 && Notifications.list[0] === notice && OpenPopup.dismissed, "a card in an open group acts on that notification alone");
                Notifications.list = [notice, second]; wait(150);
                card = named(popup, "notification-card");
                mouseMove(card, 12, 30); wait(130);
                const groupClear = button(card, "");
                mouseClick(groupClear, groupClear.width / 2, groupClear.height / 2);
                checkSoon(() => Notifications.count === 0, "a closed group's dismiss control clears all of it");
                // One group open at a time, and the focused one's group opens.
                const other = {appName: "Other sender", summary: "Other notification", body: "", actions: [], image: ""};
                const otherSecond = {appName: other.appName, summary: "Second other notification", body: "", actions: [], image: ""};
                const single = {appName: "Single sender", summary: "Single notification", body: "", actions: [], image: ""};
                Notifications.list = [notice, second, other, otherSecond, single]; wait(150);
                mouseClick(notificationCard(popup, notice), 12, 30); wait(130);
                check(popup.expandedGroup === notice.appName && cardCount(popup) === 4, "opening a group shows only its own cards");
                mouseClick(notificationCard(popup, other), 12, 30); wait(130);
                check(popup.expandedGroup === other.appName && cardCount(popup) === 4, "opening another group closes the first");
                Notifications.centreFocus = second; wait(130);
                check(popup.expandedGroup === notice.appName, "opening on a focused notification opens its group");
                const headerClear = button(named(popup, "group-header"), "Clear");
                mouseClick(headerClear, headerClear.width / 2, headerClear.height / 2);
                checkSoon(() => Notifications.count === 3 && Notifications.list.includes(single), "the header's clear clears only its group");
                // Short drags spring back; either full swipe clears without activation.
                notice.actions = [{identifier: "default", text: "Open", invoke: () => Notifications.invoked++}];
                Notifications.centreFocus = null;
                Notifications.list = [notice]; OpenPopup.dismissed = false; wait(150);
                card = notificationCard(popup, notice);
                const invoked = Notifications.invoked;
                dragCard(card, true, 70);
                tryCompare(card, "swipe", 0, 4000);
                check(Notifications.count === 1 && Notifications.invoked === invoked && !OpenPopup.dismissed,
                    "short swipe keeps the notification without activating it");
                for (const left of [true, false]) {
                    if (Notifications.count === 0) {
                        Notifications.list = [notice]; OpenPopup.dismissed = false; wait(150);
                        card = notificationCard(popup, notice);
                    }
                    dragCard(card, left, card.width * 0.75);
                    checkSoon(() => Notifications.count === 0, "full swipe clears in either direction");
                    check(Notifications.invoked === invoked && OpenPopup.dismissed, "swiping the last card closes without activating");
                }
                // Collapsed groups clear together; expanded cards clear individually.
                Notifications.list = [notice, second]; OpenPopup.dismissed = false; wait(150);
                card = notificationCard(popup, notice);
                dragCard(card, true, card.width * 0.75);
                checkSoon(() => Notifications.count === 0, "swiping a collapsed group clears every notification in it");
                Notifications.list = [notice, second]; OpenPopup.dismissed = false; wait(150);
                mouseClick(notificationCard(popup, notice), 12, 30); wait(130);
                card = notificationCard(popup, second);
                dragCard(card, false, card.width * 0.75);
                checkSoon(() => Notifications.count === 1, "swiping an expanded group's card clears only that notification");
                check(Notifications.list[0] === notice && !OpenPopup.dismissed && Notifications.invoked === invoked,
                    "the remaining notification stays available without activation");
                console.log("PASS: notification cards, actions, dismissal and grouping");
            }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try { test.run(); } catch (error) { console.log("FAIL: " + error + "\n" + error.stack); }
            Qt.quit();
        }
    }
}
'''.replace("DISMISSAL_ONLY", "true" if "--dismissal" in sys.argv else "false"))
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=25)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "Binding loop", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot assign")
        return 0 if result.returncode == 0 and "PASS: notification cards" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
