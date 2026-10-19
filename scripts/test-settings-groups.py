#!/usr/bin/env python3
"""Exercise settings discovery, display selection and the newly exposed values."""

from pathlib import Path
import os
import subprocess
import tempfile

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.modules
import qs.services
ShellRoot {
    SettingsMenu { id: menu }
    FileView { id: saved; path: Quickshell.shellPath("settings.json"); blockLoading: true }
    property int shots: 0
    TestCase {
        id: test
        when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function rows() { return menu.pages.reduce((out, p) => out.concat(...p.sections.map(s => s.rows)), []); }
        function row(id) { const r = rows().find(r => r.id === id); if (!r) throw Error("Missing setting " + id); return r; }
        function find(item, predicate) {
            if (predicate(item)) return item;
            for (const child of item.children ?? []) { const hit = find(child, predicate); if (hit) return hit; }
            return null;
        }
        function hits(query) { menu.query = query; return menu.entries.filter(e => e.setting).map(e => e.setting.id); }
        function run() {
            menu.contentAlpha = 1; menu.widthRatio = 1;
            saved.reload();
            check(saved.text().trim() === "{}", "opening settings does not write effective defaults");
            check(menu.pages.map(p => p.title).join("|") === "Bar|Appearance|Date & Time|Launcher|Apps & Services|Accessibility", "six tabs appear in the agreed order");
            const ids = rows().map(r => r.id);
            check(new Set(ids).size === ids.length, "settings and generated rows appear once");
            const covered = new Set(ids.concat(["layoutNames", "hiddenApps", "webApps", "mailCategories", "datePosition", "weatherPosition", "timePosition", "wallpaperParallaxZoom"]));
            const missing = Object.keys(Settings.defaults).filter(key => !covered.has(key));
            check(missing.length === 0, "every default preference is reachable (missing: " + missing.join(", ") + ")");
            const bar = menu.pages[0].sections;
            check(bar[bar.length - 1].title === "Tray Icons" && bar[bar.length - 2].title === "Module Visibility", "long bar lists follow the short settings");
            check(menu.pages[3].sections.slice(-1)[0].title === "Apps" && menu.pages[4].sections.slice(-1)[0].title === "Mail Inbox Tabs", "application and inbox lists are last on their pages");
            check(hits("mail primary").includes("mail:primary"), "search includes section context");
            check(hits("music socket").includes("mpdSocket"), "search finds a service by feature");
            check(hits("wallpaper folder").includes("wallpaperDir"), "short labels retain their section context");
            check(hits("24h").includes("twelveHour"), "search includes choice labels");
            check(hits("gmail").includes("webApp:gmail"), "search finds the app name behind Open With");
            menu.page = 2; menu.query = "";
            check(menu.entries.filter(e => e.setting).length === 6, "clearing search restores the selected page");

            row("screens").set(false);
            check(Settings.screens.join("|") === "DP-1|HDMI-A-1", "specific display mode starts with connected displays");
            row("screen:HDMI-A-1").set(false);
            check(Settings.screens.join("|") === "DP-1" && !row("screen:DP-1").enabled, "the last connected bar display cannot be unchecked");
            menu.query = "DP-1"; wait(80);
            const display = find(menu.contentItem, i => i.setting?.id === "screen:DP-1" && i.controls !== undefined);
            check(display !== null && !display.enabled, "the final display control is disabled in the UI");
            mouseClick(display, display.width / 2, display.height / 2);
            check(Settings.screens.join("|") === "DP-1", "clicking the disabled control preserves display selection");
            menu.setDisplay("DP-1", false);
            check(Settings.screens.join("|") === "DP-1", "display setter also protects the final connected display");
            Settings.set("screens", ["DP-1", "OLD-DISPLAY"]);
            check(row("screen:OLD-DISPLAY").get() && !row("screen:DP-1").enabled, "disconnected display choices remain saved without weakening the connected-display guard");
            row("screen:OLD-DISPLAY").set(false);
            row("screens").set(true);
            check(Settings.screens.length === 0 && menu.displayRows.length === 1, "All Displays restores the empty-array default");

            check(row("groupWindowBadgeStyle").get() === "hide", "group indicators are opt-in");
            Settings.set("groupWindowBadges", true);
            check(row("groupWindowBadgeStyle").get() === "badge", "legacy group counts remain enabled");
            for (const style of ["badge", "hide", "dot"]) {
                row("groupWindowBadgeStyle").set(style);
                check(Settings.groupWindowBadgeStyle === style, "group indicator choice overrides the legacy preference: " + style);
            }

            Settings.set("font", "Unavailable Test Family");
            check(row("font").options.some(o => o.value === "Unavailable Test Family" && o.label.endsWith("(Unavailable)")), "missing saved font remains selectable");
            row("font").set(Settings.defaults.font);
            check(menu.layoutRows.map(r => r.id).join("|") === "layout:Greek|layout:English (US)", "keyboard labels show only configured layouts in keyboard order");
            Settings.set("layoutNames", {Greek: "GR", Offline: "ZZ"});
            row("layout:Greek").set("EL");
            check(Settings.layoutNames.Greek === "EL" && Settings.layoutNames.Offline === "ZZ", "editing one keyboard label preserves other saved labels");
            row("layout:Greek").set("");
            check(!("Greek" in Settings.layoutNames) && row("layout:Greek").placeholder === "GR", "clearing a label restores abbreviation fallback");
            check(!rows().some(r => r.id === "layout:Offline") && Settings.layoutNames.Offline === "ZZ", "unused layout labels stay saved without adding settings rows");
            Keyboard.layouts = [];
            check(menu.layoutRows.length === 0, "no configured layouts produces no label rows");
            Keyboard.layouts = [{name: "Greek"}, {name: "English (US)"}];
            check(!ids.includes("layoutChangeShowModule"), "reveal-only setting is folded into Show And Bounce");
            Settings.user = Object.assign({}, Settings.user, {layoutChangeShowModule: true, layoutChangeBounce: false});
            check(Settings.layoutChangeBounce, "old reveal-only preference enables combined feedback");
            row("layoutChangeBounce").set(false);
            check(!Settings.layoutChangeBounce && !("layoutChangeShowModule" in Settings.user), "combined feedback can be disabled after migration");
            for (const id of ["layoutChangeNotification", "layoutChangeBounce"]) {
                row(id).set(true); check(Settings[id], "new keyboard feedback preference remains editable: " + id);
            }
            row("editor").set("");
            check(Settings.values.editor === "" && Settings.editor === (Quickshell.env("EDITOR") || "nvim"), "editor fallback is displayed without storing its resolved value");

            // Exercise the actual text controls and field commits across relocated sections.
            for (const [id, value] of [["terminal", "test-terminal"], ["editor", "test-editor"], ["fileManager", "test-files --new-window"],
                    ["mpdSocket", "$XDG_RUNTIME_DIR/test mpd.sock"], ["scriptsDir", "~/test helpers"], ["downloadsDir", "~/test attachments"],
                    ["screenshotCommand", "printf should-not-run"]]) {
                menu.query = row(id).title;
                wait(80);
                const field = find(menu.contentItem, i => i.stored !== undefined && i.parent?.setting?.id === id);
                check(field !== null, "text control renders: " + id);
                field.text = value; field.editingFinished();
                check(Settings.values[id] === value, "text control saves raw value: " + id);
            }
            check(Settings.mpdSocket.endsWith("/test mpd.sock") && !Settings.mpdSocket.includes("$XDG_RUNTIME_DIR"), "socket path expansion is preserved");
            check(!rows().some(r => r.id === "wallpaperParallaxZoom") && hits("parallax zoom").length === 0, "parallax zoom remains exclusively in the wallpaper popup");
            Settings.set("wallpaperParallaxZoom", 1.22);
            menu.connectedScreens = [];
            check(!row("screens").enabled, "display selection is disabled when no connected display is known");
            menu.connectedScreens = ["DP-1", "HDMI-A-1"];
            wait(200); saved.reload();
            tryVerify(() => {
                const persisted = Settings.parse(saved.text());
                return persisted.editor === "test-editor" && persisted.layoutNames?.Offline === "ZZ" && persisted.wallpaperParallaxZoom === 1.22;
            }, 2000);
            check(true, "new preference shapes persist alongside one another");
            menu.query = "";
            if (Quickshell.env("SETTINGS_PREVIEW_DIR")) capture();
            else { console.log("PASS: settings groups complete"); Qt.quit(); }
        }
        function capture() {
            if (shots === menu.pages.length) { console.log("PASS: settings groups complete"); Qt.quit(); return; }
            menu.page = shots; wait(100);
            const labels = [];
            function collect(item) {
                if (item.text === menu.pages[shots].title && item.font !== undefined) labels.push(item);
                for (const c of item.children ?? []) collect(c);
            }
            collect(menu.contentItem);
            check(labels.some(i => i.implicitWidth <= 132), "sidebar title fits: " + menu.pages[shots].title);
            menu.auditBox.grabToImage(result => {
                result.saveToFile(Quickshell.env("SETTINGS_PREVIEW_DIR") + "/settings-" + shots + ".png");
                shots++; capture();
            });
        }
    }
    Timer { interval: 150; running: true; onTriggered: { try { test.run(); } catch(e) { console.log("FAIL: " + e + "\\n" + e.stack); Qt.quit(); } } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-settings-groups-") as folder:
        target = Path(folder)
        copy_shell(target)
        menu = target / "modules/SettingsMenu.qml"
        source = menu.read_text().replace('    id: root', '    id: root\n    property alias auditBox: box', 1)
        source = source.replace('readonly property var connectedScreens: Quickshell.screens.map(s => s.name).filter(name => name)',
                                'property var connectedScreens: ["DP-1", "HDMI-A-1"]')
        # Software rendering cannot draw the existing scroll-edge shader.
        source = source.replace('layer.enabled: contentHeight + topMargin + bottomMargin > height', 'layer.enabled: false')
        menu.write_text(source)
        (target / "components/OverlayWindow.qml").write_text('import QtQuick\nimport QtQuick.Window\nWindow { required property bool shown; required property string name; required property Item inputItem; signal dismissed; readonly property bool opened: shown; width: 1100; height: 800; visible: true }')
        (target / "components/BackdropProbe.qml").write_text('import QtQuick\nItem { property var screen; property rect area; property bool active; property bool ringOnly: false; property real luma: 0.5 }')
        (target / "services/Keyboard.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var layouts: [{name: "Greek"}, {name: "English (US)"}] }')
        (target / "services/Power.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var actions: [{key: "lock", name: "Lock", glyph: ""}] }')
        (target / "services/Tasks.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var lists: [{id: "list", title: "My Tasks"}]; property var defaultList: ({id: "list"}) }')
        (target / "shell.qml").write_text(QML)
        preview = os.environ.get("SETTINGS_PREVIEW_DIR", "")
        if preview:
            Path(preview).mkdir(parents=True, exist_ok=True)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
            env=shell_env(target, SETTINGS_PREVIEW_DIR=preview), capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: settings groups complete" in output and not any(
            error in output for error in ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop")), output
        # Check committed values survive a fresh Settings singleton, not just its in-memory cache.
        (target / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs
ShellRoot { Timer { interval: 100; running: true; onTriggered: {
    const ok = Settings.values.terminal === "test-terminal" && Settings.values.editor === "test-editor"
        && Settings.layoutNames.Offline === "ZZ" && Settings.layoutChangeBounce && Settings.wallpaperParallaxZoom === 1.22
        && Settings.groupWindowBadgeStyle === "dot";
    console.log(ok ? "PASS: settings reopen" : "FAIL: settings reopen"); Qt.quit();
} } }''')
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end="")
        assert result.returncode == 0 and "PASS: settings reopen" in output and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
