#!/usr/bin/env python3
"""Switch settings pages and searches after scrolling, including wheel momentum."""

from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs.modules
ShellRoot {
    SettingsMenu { id: menu }
    TestCase {
        id: test
        parent: menu.contentItem
        when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function checkTop(message) {
            wait(350);
            const view = menu.auditList;
            check(Math.abs(view.contentY - (view.originY - view.topMargin)) <= 1,
                message + " (offset " + (view.contentY - view.originY + view.topMargin) + ")");
            check(view.itemAtIndex(0) !== null, "first heading is rendered");
            check(Math.abs(view.itemAtIndex(0).y - view.contentY - view.topMargin) <= 1, "first heading keeps its top padding");
        }
        function run() {
            menu.contentAlpha = 1; menu.widthRatio = 1;
            menu.requestActivate();
            const view = menu.auditList;
            const longPages = [];
            for (let p = 0; p < menu.pages.length; p++) {
                menu.page = p; wait(80);
                view.positionViewAtEnd(); view.forceLayout(); wait(30);
                console.log("HEIGHT: " + menu.pages[p].title + " " + Math.round(view.contentHeight + view.topMargin + view.bottomMargin) + "/" + view.height);
                if (!["Modules", "Web Search", "Launcher Apps"].includes(menu.pages[p].title))
                    check(view.contentHeight + view.topMargin + view.bottomMargin <= view.height, "short preferences fit on one page: " + menu.pages[p].title);
                const overflow = view.contentHeight + view.topMargin + view.bottomMargin > view.height;
                check(menu.auditPageBar.visible === overflow, "page scrollbar reflects overflow: " + menu.pages[p].title);
                if (view.contentHeight + view.topMargin + view.bottomMargin > view.height + 100)
                    longPages.push(p);
            }
            check(longPages.length >= 2, "fixture has two long pages");
            menu.page = longPages[0]; wait(80);
            const bar = menu.auditPageBar;
            const gripY = bar.contentItem.y + bar.contentItem.height / 2;
            mousePress(bar, bar.width / 2, gripY);
            mouseMove(bar, bar.width / 2, gripY + 60, 30);
            mouseRelease(bar, bar.width / 2, gripY + 60);
            check(view.contentY > view.originY && bar.position > 0, "dragging the scrollbar scrolls the settings page");
            const shortPage = menu.pages.findIndex(p => p.title === "Appearance");
            for (const destination of [longPages[1], shortPage, longPages[0]]) {
                menu.page = longPages[0]; wait(80);
                view.positionViewAtEnd(); wait(30);
                check(view.contentY > view.originY + 100, "source page is scrolled down");
                menu.page = destination;
                if (destination === longPages[0]) menu.query = "mail";
                checkTop("new tab or search starts at the top");
                menu.query = "";
                wait(80);
            }
            menu.page = longPages[0]; wait(80);
            const wheel = view.contentItem.children.find(c => c.animation !== undefined && c.view === view);
            mouseWheel(view, view.width - 3, view.height / 2, 0, -120);
            wait(30);
            check(wheel.animation.running, "wheel animation is active before switching");
            menu.page = longPages[1];
            checkTop("tab change cancels wheel momentum");
            view.positionViewAtEnd(); wait(30);
            menu.query = "a"; checkTop("search starts at the top");
            view.positionViewAtEnd(); wait(30);
            menu.query = ""; checkTop("clearing search starts the page at the top");
            menu.boxHeight = 360; wait(80);
            const sidebar = menu.auditSidebar;
            check(menu.auditTabBar.visible && menu.auditTabBar.size < 1, "sidebar scrollbar appears when tabs extend below the window");
            sidebar.contentY = 0;
            mouseWheel(sidebar, sidebar.width / 2, sidebar.height / 2, 0, -120);
            wait(350);
            check(sidebar.contentY > 0 && menu.auditTabBar.position > 0, "sidebar and scrollbar move with the wheel");
            menu.page = 0; wait(80);
            menu.auditFilter.forceActiveFocus();
            keyClick(Qt.Key_Backtab); wait(80);
            check(menu.page === menu.pages.length - 1, "keyboard navigation reaches the last tab");
            const lastTab = menu.auditTabs.itemAt(menu.page);
            check(lastTab.y >= sidebar.contentY && lastTab.y + lastTab.height <= sidebar.contentY + sidebar.height + 1, "selecting a tab reveals it below the fold");
            keyClick(Qt.Key_Tab); wait(80);
            check(sidebar.contentY === 0, "selecting the first tab reveals the top of the sidebar");
            console.log("PASS: settings scroll complete");
        }
    }
    Timer { interval: 150; running: true; onTriggered: {
        try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-settings-scroll-") as folder:
        target = Path(folder)
        copy_shell(target)
        menu = target / "modules/SettingsMenu.qml"
        source = menu.read_text().replace("    id: root", "    id: root\n    property alias auditList: list\n    property alias auditPageBar: pageScroll\n    property alias auditSidebar: sidebar\n    property alias auditTabBar: tabScroll\n    property alias auditTabs: tabs\n    property alias auditFilter: filter", 1)
        source = source.replace("readonly property int boxHeight: 560", "property int boxHeight: 560")
        source = source.replace("layer.enabled: contentHeight + topMargin + bottomMargin > height", "layer.enabled: false")
        menu.write_text(source)
        (target / "components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
        (target / "services/Keyboard.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [{name: "Greek"}, {name: "English (US)"}] }')
        (target / "services/Power.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var actions: Array.from({length: 6}, (_, i) => ({key: "fixture" + i, name: "Action " + i, glyph: ""})) }')
        (target / "services/Tasks.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: []; property var defaultList: ({id: ""}) }')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: settings scroll complete" in output and not any(
            error in output for error in ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop")), output


if __name__ == "__main__":
    main()
