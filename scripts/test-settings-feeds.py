#!/usr/bin/env python3
"""Edit feed lists through the settings controls and reopen saved values."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules
import qs.services
ShellRoot {
    SettingsMenu { id: menu }
    TestCase {
        id: test
        when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children ?? []) {
                const found = find(child, predicate);
                if (found) return found;
            }
            return null;
        }
        function editor(id) { return find(menu.contentItem, i => i.setting?.id === id && i.commit !== undefined); }
        function field(list, index) { return find(list, i => i.index === index && i.input !== undefined)?.input; }
        function titleField(list, index) {
            const control = find(list, i => i.setting?.title === "Feed Title " + (index + 1));
            return find(control, i => i.stored !== undefined);
        }
        function draft(input, value) { input.forceActiveFocus(); input.text = value; input.textEdited(); }
        function enter(input, value) { draft(input, value); keyClick(Qt.Key_Return); wait(30); }
        function button(list, name) { return find(list, i => i.name === name && i.tapped !== undefined); }
        function click(item) { check(!!item, "control exists"); mouseClick(item, item.width / 2, item.height / 2); wait(30); }
        function run() {
            Preferences.shown = true;
            menu.requestActivate();
            menu.query = "feeds";
            wait(150);
            let rss = editor("feedUrls"), channels = editor("feedChannels");
            check(rss && channels, "search renders both feed list editors");
            check(rss.width > 400 && field(rss, 0).width > 350, "URLs use the full settings width");
            check(rss.values().length === 2 && channels.values()[0] === "@sample", "existing entries load separately");

            const firstUrl = Settings.feedUrls[0];
            enter(titleField(rss, 0), "  Hacker News  ");
            check(Settings.feedTitles[firstUrl] === "Hacker News", "custom feed titles are trimmed and saved");
            draft(titleField(rss, 0), "Discard this title");
            keyClick(Qt.Key_Escape);
            check(titleField(rss, 0).text === "Hacker News", "Escape restores the saved title");
            enter(titleField(rss, 0), "");
            check(!(firstUrl in Settings.feedTitles), "clearing a title restores the feed default");
            draft(titleField(rss, 0), "News");
            field(rss, 0).forceActiveFocus(); wait(30);
            check(Settings.feedTitles[firstUrl] === "News", "focus loss saves a feed title");

            enter(field(rss, 0), "not a URL");
            check(Settings.feedUrls[0] === "https://hnrss.org/frontpage?points=200", "invalid edits preserve the saved URL");
            check(find(rss, i => i.message?.includes("http://")), "invalid entry has an inline explanation");
            keyClick(Qt.Key_Escape);
            check(field(rss, 0).text === Settings.feedUrls[0], "Escape restores the saved entry");
            enter(field(rss, 0), "https://lobste.rs/rss");
            check(Settings.feedUrls.length === 2 && Settings.feedUrls[0].includes("hnrss"), "duplicate edits are rejected");
            keyClick(Qt.Key_Escape);

            click(button(rss, "Add RSS Feeds"));
            check(field(rss, 2)?.activeFocus && Settings.feedUrls.length === 2, "Add focuses an unsaved entry");
            keyClick(Qt.Key_Escape);
            check(!field(rss, 2) && Settings.feedUrls.length === 2, "Escape cancels a new entry");
            click(button(rss, "Add RSS Feeds"));
            enter(field(rss, 2), "  https://example.com/feed?q=one,two&limit=5  ");
            check(Settings.feedUrls[2] === "https://example.com/feed?q=one,two&limit=5", "saving trims whitespace and preserves URL punctuation");
            click(button(rss, "Remove RSS Feeds 2"));
            check(Settings.feedUrls.length === 2 && Settings.feedUrls[1].includes("example.com"), "Remove deletes only the chosen entry");
            enter(field(rss, 0), "");
            check(Settings.feedUrls[0].includes("hnrss"), "blank edits cannot erase a saved entry");
            keyClick(Qt.Key_Escape);
            draft(field(rss, 1), "https://example.com/updated.xml");
            field(rss, 0).forceActiveFocus(); wait(30);
            check(Settings.feedUrls[1] === "https://example.com/updated.xml", "focus loss saves a valid edit");

            enter(field(channels, 0), "https://example.com/@other");
            check(Settings.feedChannels[0] === "@sample", "non-YouTube channel links are rejected");
            keyClick(Qt.Key_Escape);
            enter(field(channels, 0), "https://www.youtube.com/@other/videos");
            check(Settings.feedChannels[0] === "https://www.youtube.com/@other/videos", "YouTube channel links are accepted");
            click(button(channels, "Add Extra YouTube Channels"));
            enter(field(channels, 1), "UC" + "a".repeat(22));
            check(Settings.feedChannels[1] === "UC" + "a".repeat(22), "channel IDs are accepted");

            draft(field(rss, 1), "https://example.com/closed.xml");
            menu.query = "terminal"; wait(100);
            check(Settings.feedUrls[1] === "https://example.com/closed.xml", "leaving the page saves a valid draft");
            menu.query = "rss feeds"; wait(100);
            rss = editor("feedUrls");
            check(field(rss, 1).text === Settings.feedUrls[1], "returning to the page restores saved entries");
            draft(field(rss, 1), "broken");
            menu.query = "terminal"; wait(100);
            check(Settings.feedUrls[1] === "https://example.com/closed.xml", "leaving the page discards invalid drafts");

            menu.query = "feeds"; wait(100);
            rss = editor("feedUrls");
            draft(titleField(rss, 0), "My News");
            menu.query = "terminal"; wait(100);
            check(Settings.feedTitles[firstUrl] === "My News", "leaving settings saves a title draft");
            menu.query = "feeds"; wait(100);
            if (Quickshell.env("SETTINGS_FEEDS_PREVIEW")) {
                menu.auditBox.grabToImage(result => {
                    result.saveToFile(Quickshell.env("SETTINGS_FEEDS_PREVIEW"));
                    console.log("PASS: feed list settings complete"); Qt.quit();
                });
            } else {
                console.log("PASS: feed list settings complete"); Qt.quit();
            }
        }
    }
    Timer { interval: 200; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e + "\n" + e.stack); Qt.quit(); }
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-settings-feeds-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "settings.json").write_text(json.dumps({
            "feedUrls": ["https://hnrss.org/frontpage?points=200", "https://lobste.rs/rss"],
            "feedChannels": ["@sample"],
        }))
        menu = target / "modules/SettingsMenu.qml"
        menu.write_text(menu.read_text().replace("    id: root", "    id: root\n    property alias auditBox: box", 1)
                        .replace("layer.enabled: contentHeight + topMargin + bottomMargin > height", "layer.enabled: false"))
        (target / "components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
        (target / "services/Keyboard.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [] }')
        (target / "services/Power.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var actions: [] }')
        (target / "services/Tasks.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: []; property var defaultList: ({id: ""}) }')
        (target / "shell.qml").write_text(QML)
        preview = os.environ.get("SETTINGS_FEEDS_PREVIEW", "")
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
            env=shell_env(target, SETTINGS_FEEDS_PREVIEW=preview), capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "Invalid property assignment")
        assert result.returncode == 0 and "PASS: feed list settings complete" in output and not any(error in output for error in errors), output
        (target / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs
ShellRoot { Timer { interval: 150; running: true; onTriggered: {
    const ok = Settings.feedUrls.length === 2 && Settings.feedUrls[1] === "https://example.com/closed.xml"
        && Settings.feedChannels.length === 2 && Settings.feedChannels[1] === "UC" + "a".repeat(22)
        && Settings.feedTitles[Settings.feedUrls[0]] === "My News";
    console.log(ok ? "PASS: feed settings reopen" : "FAIL: feed settings reopen"); Qt.quit();
} } }''')
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
            capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end="")
        assert "PASS: feed settings reopen" in output and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
