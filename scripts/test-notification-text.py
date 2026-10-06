#!/usr/bin/env python3
"""Check notification text through the popup's real labels in an isolated shell."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    service = (ROOT / "services/Notifications.qml").read_text()
    start = service.index("    // --- presentation helpers")
    end = service.index("    // What AppIcon", start)
    popup = (ROOT / "components/NotificationsPopup.qml").read_text()
    labels = re.findall(r"                PopupText \{\n.*?\n                \}", popup, re.S)
    labels = [label for label in labels if "card.n?.summary" in label or "card.n?.body" in label]
    assert len(labels) == 2
    labels[0] = labels[0].replace("PopupText {", "PopupText {\n                    id: summaryLabel", 1)
    labels[1] = labels[1].replace("PopupText {", "PopupText {\n                    id: bodyLabel", 1)
    test = '''import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs
import qs.services
ShellRoot {
    id: root
    property string sample: "**xxx**"
    QtObject { id: card; property var n: ({summary: root.sample, body: root.sample, urgency: 1}) }
    component PopupText: Text { font.pixelSize: 16 }
    Column {
        width: 300
        LABELS
    }
    Text { id: expected; font.pixelSize: 16; textFormat: Text.StyledText; text: "<b>xxx</b>" }
    function check(ok, message) { if (!ok) throw Error(message); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                check(Math.abs(bodyLabel.contentWidth - expected.contentWidth) < 1, "body renders bold xxx without literal asterisks");
                check(Math.abs(summaryLabel.contentWidth - expected.contentWidth) < 1, "summary renders xxx without literal asterisks");
                check(Notifications.plain("**xxx**") === "xxx", "bar notice removes bold markers");
                const cases = [
                    ["*italic* and `code` and ~~gone~~", "italic and code and gone"],
                    ["[label](https://example.com)", "label"],
                    ["[**bold** and `code`](https://example.com)", "bold and code"],
                    ["__bold__ and _italic_", "bold and italic"],
                    ["<b>bold</b><br>next &amp; last", "bold next & last"],
                    ["2 < 3 and 5 > 4", "2 < 3 and 5 > 4"],
                    ["snake_case and file_name.txt", "snake_case and file_name.txt"],
                    ["`**literal**`", "**literal**"],
                    ["2 * 3 * 4 and 2*3*4", "2 * 3 * 4 and 2*3*4"],
                    ["it&#39;s &#x2014; fine &amp;#39;", "it's — fine &#39;"],
                    [null, ""]
                ];
                for (const [input, plain] of cases)
                    check(Notifications.plain(input) === plain, "notice text: " + input);
                const markup = [
                    ["2 * 3 * 4", "2 * 3 * 4"],
                    ["<p>first</p><p>second</p>", "first<br><br>second"],
                    ["one<br/>two\n", "one<br>two"],
                    ["a\n\n\n\nb", "a<br><br>b"],
                    ["*it* **bold**", "<i>it</i> <b>bold</b>"]
                ];
                for (const [input, styled] of markup)
                    check(Notifications.styled(input) === styled, "card text: " + input + " -> " + Notifications.styled(input));
                root.sample = "<b>xxx</b>";
                bodyLabel.forceLayout();
                check(Math.abs(bodyLabel.contentWidth - expected.contentWidth) < 1, "existing HTML bold is preserved");
                root.sample = "2 < 3 and 5 > 4";
                check(Notifications.plain(root.sample) === root.sample, "comparison signs stay literal");
                check(bodyLabel.text === "2 &lt; 3 and 5 &gt; 4", "popup escapes comparison signs");
                root.sample = "[link](https://example.com)";
                check(bodyLabel.linkColor.toString() === Theme.label2.toString(), "popup links use the grey theme colour");
                root.sample = "**long bold text** ".repeat(100);
                bodyLabel.forceLayout();
                summaryLabel.forceLayout();
                check(bodyLabel.truncated && bodyLabel.lineCount === 10, "body elides after ten lines");
                check(summaryLabel.truncated && summaryLabel.lineCount === 10, "summary elides after ten lines");
                root.sample = "plain text";
                check(bodyLabel.font.weight === Font.Normal && summaryLabel.font.weight === Font.Normal, "plain text has no forced bold weight");
                console.log("PASS: notification formatting and bar preview");
            } catch (error) { console.log("FAIL: " + error); }
            Qt.quit();
        }
    }
}
'''.replace("LABELS", "\n".join(labels))
    with tempfile.TemporaryDirectory(prefix="quickshell-notification-test-") as folder:
        target = Path(folder)
        (target / "services").mkdir()
        (target / "services/Notifications.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n    id: root\n" + service[start:end] + "}\n")
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property color label: "white"; property color label2: "grey"; property color warn: "red" }\n')
        (target / "shell.qml").write_text(test)
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output, end="")
        return 0 if result.returncode == 0 and "PASS: notification formatting" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())
