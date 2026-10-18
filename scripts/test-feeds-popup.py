#!/usr/bin/env python3
"""Exercise exclusive feed headers and reversible folding in the real popup body."""

from pathlib import Path
import runpy
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 800
        FeedsPopup { id: popup }
        TestCase {
            id: test; when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function find(item, predicate) {
                if (predicate(item)) return item;
                for (const child of item.children) {
                    const found = find(child, predicate);
                    if (found) return found;
                }
                return null;
            }
            function header(section) { return find(popup, i => i.section === section && i.open !== undefined); }
            function body(fold) { return fold.parent.children.find(i => i.clip); }
            function run() {
                const now = Date.now();
                Feeds.videos = [0, 1].map(i => ({id: "v" + i, title: "Video " + i,
                    channel: "Channel", published: now, duration: 120, thumb: "", url: ""}));
                Feeds.sources = [{url: "rss", title: "Stories", items: [0, 1].map(i => ({
                    id: "s" + i, title: "Story " + i, published: now, points: 3,
                    replies: 1, comments: "", url: ""}))}];
                wait(50);
                const videos = header("videos"), stories = header("rss");
                check(videos && stories, "both headers are present");
                // Older versions could remember several open headers.
                check(videos.open !== stories.open, "legacy state restores only one open header: " + videos.open + ", " + stories.open);
                wait(Theme.foldMs + 80);
                (videos.open ? videos : stories).tapped();
                wait(Theme.foldMs + 80);
                const videoBody = body(videos), storyBody = body(stories);
                const closedHeight = popup.height;
                check(videoBody.height === 0 && storyBody.height === 0, "all headers can close");

                videos.tapped();
                wait(80);
                check(videoBody.height > 0 && videoBody.height < videoBody.children[0].implicitHeight,
                    "opening shows an intermediate clipped height");
                check(popup.height > closedHeight, "popup grows with its rows");
                check(header("videos") === videos && header("rss") === stories,
                    "opening preserves header delegates");
                wait(Theme.foldMs + 80);
                const fullHeight = videoBody.height;
                check(fullHeight > 0 && find(videoBody, i => i.name === "Video 0"), "video rows finish opening");

                const videoTop = videos.parent.y;
                stories.tapped();
                check(!videos.open && stories.open && !videoBody.enabled, "another header closes and disables old rows");
                wait(80);
                check(videoBody.height > 0 && videoBody.height < fullHeight && storyBody.height > 0,
                    "old rows close while new rows open");
                check(videos.parent.y > 0 && videos.parent.y < videoTop, "closed header moves upward through intermediate positions");
                check(find(videoBody, i => i.name === "Video 0"), "closing rows survive for the transition");
                const shrinking = videoBody.height;
                videos.tapped();
                check(videoBody.height === shrinking, "reversal continues from the current height");
                wait(Theme.foldMs + 80);
                check(videoBody.height === fullHeight && storyBody.height === 0, "rapid reversal finishes correctly");
                check(stories.parent.y < videos.parent.y, "closed stories move above open videos");
                check(!find(storyBody, i => i.name === "Story 0"), "closed rows are released");

                Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                stories.tapped();
                wait(30);
                check(videoBody.height === 0 && storyBody.height > 0, "reduced motion switches immediately");
                check(videos.parent.y < stories.parent.y, "closed videos move above open stories");
                stories.tapped();
                wait(30);
                check(storyBody.height === 0 && popup.height === closedHeight, "reduced motion closes without leftover space");
                Feeds.markAllSeen();
                wait(30);
                check(!header("videos") && !header("rss"), "seen sections leave the list");
                Feeds.undo();
                wait(30);
                check(header("videos") && header("rss"), "undo restores both sections");
                header("rss").tapped();
                wait(30);
                check(body(header("rss")).height > 0, "restored sections can open");
                console.log("PASS: feed header folding");
            }
        }
        Timer { interval: 300; running: true; onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-feeds-popup-") as folder:
        target = Path(folder)
        copy_shell(target)
        popup = runpy.run_path(str(ROOT / "scripts/test-popup-standards.py"))["POPUP"]
        (target / "components/Popup.qml").write_text(popup)
        (target / "settings.json").write_text('{"feedUrls": []}\n')
        state = target / "state/quickshell"
        state.mkdir(parents=True)
        (state / "feeds.json").write_text('{"unfolded": {"videos": true, "rss": true}}\n')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
                                env=shell_env(target), capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign",
                  "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "PASS: feed header folding" in output and not any(e in output for e in errors)
        print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
