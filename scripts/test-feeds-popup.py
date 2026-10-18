#!/usr/bin/env python3
"""Feed sections fade out before the next section expands into view."""

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
            function settle() { wait(Theme.fadeMs + Theme.foldMs + 100); }
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
                settle();
                (videos.open ? videos : stories).tapped();
                settle();
                const videoBody = body(videos), storyBody = body(stories);
                const closedHeight = popup.height;
                check(videoBody.height === 0 && storyBody.height === 0, "all headers can close");

                videos.tapped();
                wait(80);
                check(videoBody.height > 0, "selected drawer opens");
                check(videoBody.height < videoBody.children[0].implicitHeight + 3 && videoBody.opacity === 1,
                    "opening drawer expands at full opacity");
                check(popup.height > closedHeight, "popup grows with its rows");
                check(header("videos") === videos && header("rss") === stories,
                    "opening preserves header delegates");
                settle();
                const fullHeight = videoBody.height;
                check(fullHeight > 0 && find(videoBody, i => i.name === "Video 0"), "video rows finish opening");

                const videoTop = videos.parent.y;
                stories.tapped();
                check(!videos.open && stories.open && !videoBody.enabled, "another header closes and disables old rows");
                wait(80);
                check(storyBody.height === 0, "next drawer stays closed while outgoing rows fade");
                check(videoBody.height === fullHeight && videoBody.opacity > 0 && videoBody.opacity < 1,
                    "closing rows fade in place before the layout changes");
                check(videos.parent.y === videoTop, "outgoing drawer stays still throughout its fade");
                let incomingExpansion = false;
                for (let i = 0; i < 30; i++) {
                    wait(16);
                    check(!(videoBody.height > 0 && storyBody.height > 0), "drawers never overlap during a switch");
                    if (storyBody.height > 0) {
                        check(videoBody.height === 0, "old drawer is gone before the next opens");
                        check(storyBody.opacity === 1, "incoming rows stay opaque while expanding");
                        incomingExpansion = incomingExpansion || storyBody.height < storyBody.children[0].implicitHeight + 3;
                    }
                }
                check(incomingExpansion && storyBody.height === storyBody.children[0].implicitHeight + 3,
                    "incoming drawer expands to its full height after the fade");
                check(videos.parent.y < stories.parent.y, "closed videos move above open stories");
                check(!find(videoBody, i => i.name === "Video 0"), "closed rows are released");

                videos.tapped();
                wait(60);
                stories.tapped();
                wait(30);
                videos.tapped();
                settle();
                check(videoBody.height === fullHeight && storyBody.height === 0 && videoBody.opacity === 1,
                    "rapid changes finish on the last selected drawer");
                check(stories.parent.y < videos.parent.y, "closed stories move above open videos");
                check(!find(storyBody, i => i.name === "Story 0"), "closed rows are released");

                stories.tapped();
                wait(Theme.fadeMs + 60);
                check(storyBody.height > 0 && storyBody.height < storyBody.children[0].implicitHeight + 3
                    && storyBody.opacity === 1, "incoming drawer is partway through expanding");
                videos.tapped();
                wait(60);
                check(videoBody.height === 0, "interrupting an expansion keeps the next drawer hidden");
                settle();
                check(videoBody.height === fullHeight && storyBody.height === 0 && videoBody.opacity === 1,
                    "interrupting an expansion settles on the last drawer");

                videos.tapped();
                wait(80);
                check(videoBody.height === fullHeight && videoBody.opacity > 0 && videoBody.opacity < 1,
                    "closing the last drawer fades it out in place");
                settle();
                check(videoBody.height === 0 && popup.height === closedHeight, "closing removes the drawer after its fade");

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
                console.log("PASS: feed drawers fade closed and expand open");
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
                                env=shell_env(target), capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign",
                  "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "PASS: feed drawers fade closed and expand open" in output and not any(e in output for e in errors)
        print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
