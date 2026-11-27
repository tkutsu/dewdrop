#!/usr/bin/env python3
"""Header buttons flash before they act; refresh arrows turn once, on the spot."""

from pathlib import Path
import subprocess
import tempfile

from PIL import Image

from test_support import copy_shell, shell_env


SHELL = r'''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.components
ShellRoot {
    id: shell
    QtObject {
        id: feed
        property double updatedAt: Date.now() / 1000
        property bool loading: false
        property bool retryable: false
        property string trouble: ""
        property int refreshes: 0
        property int retries: 0
        function refresh() { refreshes++; }
        function retryNow() { retries++; }
    }
    QtObject {
        id: broken
        property bool loading: false
        property bool retryable: true
        property int retries: 0
        function retryNow() { retries++; }
    }
    FloatingWindow {
        // What Popup.qml gives every popup.
        readonly property ChoiceBlink choice: ChoiceBlink {}
        implicitWidth: 420
        implicitHeight: 60
        color: "black"
        Row {
            id: scene
            x: 10; y: 10
            spacing: 10
            PopupHeader {
                width: 200
                title: "Feed"
                PopupButton { id: other; framed: true; label: "Clear"; property int hits: 0; onTapped: hits++ }
                RefreshStamp { id: stamp; service: feed }
            }
            RetryButton { id: retry; service: broken }
            PopupButton { id: plain; glyph: Theme.glyph.close; property int hits: 0; onTapped: hits++ }
            PopupButton { id: quiet; framed: true; label: "Open"; property int hits: 0; onTapped: hits++ }
        }
    }
    TestCase { id: test; when: false }
    function check(ok, why) { if (!ok) throw Error(why); console.log("PASS: " + why); }
    function grab(name, then) {
        stamp.grabToImage(result => { result.saveToFile(Quickshell.shellPath(name)); then(); });
    }
    function run() {
        stamp.press();
        check(feed.refreshes === 0 && stamp.chosen && !stamp.blinkOn, "a header button goes dark first instead of acting");
        test.wait(Theme.blinkMs + 20);
        check(feed.refreshes === 0 && stamp.blinkOn, "then lights again, still waiting");
        test.tryVerify(() => feed.refreshes === 1, Theme.blinkMs + 200);
        test.wait(60);
        check(!stamp.chosen && stamp.glyphTurn > 0, "and acts once the flash is over, turning its arrows");
        stamp.press();
        stamp.press();
        test.tryVerify(() => feed.refreshes === 2, Theme.spinMs + 500);
        test.wait(Theme.blinkMs * 3);
        check(feed.refreshes === 2, "a press during the flash is not a second one");
        test.tryVerify(() => stamp.glyphTurn === 360, Theme.spinMs + 500);

        plain.press();
        check(plain.hits === 1, "an unframed row control acts at once");
        quiet.press();
        check(quiet.hits === 1 && !quiet.chosen, "a framed button outside the header acts at once");
        stamp.press();
        other.press();
        check(stamp.chosen && !other.chosen, "one choice at a time in a popup");
        test.tryVerify(() => feed.refreshes === 3, Theme.blinkMs * 2 + 200);
        test.wait(Theme.blinkMs * 3);
        check(other.hits === 0, "a press on another button mid-flash is dropped");
        test.tryVerify(() => stamp.glyphTurn === 360, Theme.spinMs + 500);
        other.press();
        test.tryVerify(() => other.hits === 1, Theme.blinkMs * 2 + 200);
        check(true, "then the next press flashes and acts");

        const stampWidth = stamp.width;
        stamp.tapped();
        test.wait(Theme.spinMs / 4);
        stamp.confirm();
        feed.retryable = true;
        test.wait(30);
        check(stamp.warn && stamp.shownGlyph === Theme.glyph.refresh,
            "mid-turn the arrows stay arrows, whatever the request brought");
        test.tryVerify(() => stamp.glyphTurn === 360, Theme.spinMs + 500);
        test.wait(30);
        check(stamp.shownGlyph === Theme.glyph.check, "then the turn ends on the check");
        check(stamp.width === stampWidth, "the check takes the arrows' room: " + stampWidth + " -> " + stamp.width);
        feed.retryable = false;
        test.wait(1300);
        check(stamp.shownGlyph === Theme.glyph.refresh, "and the check gives way to the arrows");

        const wide = stamp.width;
        feed.retryable = true;
        test.wait(30);
        check(stamp.shownGlyph === Theme.glyph.warning, "a failed fetch shows the warning");
        check(stamp.width === wide, "the warning takes the arrows' room: " + wide + " -> " + stamp.width);
        stamp.tapped();
        test.wait(Theme.spinMs / 4);
        check(stamp.shownGlyph === Theme.glyph.refresh && stamp.glyphTurn > 0, "a retry turns the arrows, not the warning");
        test.tryVerify(() => stamp.glyphTurn === 360, Theme.spinMs + 500);
        test.wait(30);
        check(stamp.shownGlyph === Theme.glyph.warning, "then the warning is back while it still fails");
        feed.retryable = false;
        test.tryVerify(() => stamp.shownGlyph === Theme.glyph.refresh, 1500);

        feed.refreshes = 0;
        stamp.tapped();
        check(feed.refreshes === 1, "a press asks for one fetch");
        test.wait(Theme.spinMs / 2);
        check(stamp.glyphTurn > 0 && stamp.glyphTurn < 360, "the arrows are turning while the request goes");
        test.tryVerify(() => stamp.glyphTurn === 360, Theme.spinMs + 500);
        check(true, "the arrows land after one full turn");
        stamp.tapped();
        test.wait(30);
        check(feed.refreshes === 2 && stamp.glyphTurn < 90, "every press turns them again from the start");

        retry.tapped();
        check(broken.retries === 1, "retry asks once");
        test.wait(Theme.spinMs / 2);
        check(retry.glyphTurn > 0 && retry.glyphTurn < 360, "retry turns its arrows too");
        test.tryVerify(() => stamp.glyphTurn === 360 && retry.glyphTurn === 360, Theme.spinMs + 500);

        stamp.glyphTurn = 0;
        test.wait(50);
        grab("turn-0.png", () => {
            stamp.glyphTurn = 180;
            test.wait(50);
            grab("turn-180.png", () => { console.log("PASS: refresh spin"); Qt.quit(); });
        });
    }
    Timer { interval: 600; running: true; onTriggered: {
        try { shell.run(); } catch (error) { console.log("FAIL: " + error + "\n" + error.stack); Qt.quit(); }
    } }
}
'''


def glyph_centre(path):
    """Centre of the bright ink in the stamp's glyph column (right of its label)."""
    image = Image.open(path).convert("L")
    width, height = image.size
    # The glyph sits on the right of the framed button; its label is on the left.
    columns = range(width // 2, width - 3)
    points = [(x, y) for x in columns for y in range(3, height - 3) if image.getpixel((x, y)) > 140]
    assert points, f"no glyph ink in {path}"
    xs = [x for x, _ in points]
    ys = [y for _, y in points]
    return ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-refresh-spin-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Failed to load configuration")
        if "PASS: refresh spin" not in output or any(error in output for error in errors):
            return 1
        still = glyph_centre(target / "turn-0.png")
        turned = glyph_centre(target / "turn-180.png")
        before = Image.open(target / "turn-0.png").convert("L")
        after = Image.open(target / "turn-180.png").convert("L")
        half = (before.width // 2, 0, before.width, before.height)
        assert before.crop(half).tobytes() != after.crop(half).tobytes(), "a half turn left the glyph unchanged"
        drift = max(abs(a - b) for a, b in zip(still, turned))
        assert drift <= 1, f"the arrows orbit instead of turning in place: {still} -> {turned}"
        print(f"PASS: the arrows turn on their own middle (drift {drift}px)")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
