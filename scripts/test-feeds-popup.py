#!/usr/bin/env python3
"""Feed sections retain closed positions and animate opening at the bottom."""

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
            property int heightChanges: 0
            Connections {
                target: popup
                function onHeightChanged() { test.heightChanges++; }
            }
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
            function settle() { wait(popup.sectionFadeMs * 3 + popup.sectionFoldMs * 2 + 100); }
            function order() { return popup.sectionOrder.map(s => s.section).join(","); }
            function run() {
                const now = Date.now();
                Feeds.videos = [0, 1].map(i => ({id: "v" + i, title: "Video " + i,
                    channel: "Channel", published: now, duration: 120, thumb: "", url: ""}));
                Feeds.sources = [{url: "rss", title: "Stories", items: [0, 1].map(i => ({
                    id: "s" + i, title: "Story " + i, published: now, points: 3,
                    summary: i === 0 ? "A longer article preview with enough words to wrap across several lines. ".repeat(30) : "",
                    thumb: i === 0 ? Qt.resolvedUrl("preview.svg").toString() : "",
                    replies: 1, comments: "https://example.com/comments", url: ""}))}];
                wait(50);
                const videos = header("videos"), stories = header("rss");
                check(videos && stories, "both headers are present");
                check(find(stories, i => i.text === "Stories" && String(i.color) === String(Theme.label2)),
                    "feed headings are grey");
                Settings.user = Object.assign({}, Settings.user, {feedTitles: {rss: "Custom Stories"}});
                wait(30);
                check(stories.title === "Custom Stories" && header("rss") === stories,
                    "custom titles update the existing header immediately");
                Settings.user = Object.assign({}, Settings.user, {feedTitles: {}});
                wait(30);
                check(stories.title === "Stories", "clearing a custom title restores the supplied feed title: "
                    + stories.title + " " + JSON.stringify(Settings.feedTitles));
                check(videos.open && !stories.open, "the remembered header opens alone: " + videos.open + ", " + stories.open);
                settle();
                const restoredOrder = order();
                (videos.open ? videos : stories).tapped();
                settle();
                const videoBody = body(videos), storyBody = body(stories);
                const closedHeight = popup.height;
                check(popup.sectionFadeMs === Math.round(Theme.fadeMs * 2 / 3)
                    && popup.sectionFoldMs === Math.round(Theme.foldMs * 2 / 3),
                    "feed animation durations are one third shorter");
                check(videoBody.height === 0 && storyBody.height === 0, "all headers can close");
                check(order() === restoredOrder, "closing a restored drawer preserves order");

                const videoMoves = popup.sectionOrder[popup.sectionOrder.length - 1].section !== "videos";
                test.heightChanges = 0;
                videos.tapped();
                if (videoMoves) wait(popup.sectionFadeMs * 2 + popup.sectionFoldMs);
                wait(80);
                check(videoBody.height > 0, "selected drawer opens");
                check(videoBody.height === videoBody.children[0].implicitHeight + 3
                    && videoBody.opacity > 0 && videoBody.opacity < 1 && videos.x === 0,
                    "opening content fades in at full height after its header arrives");
                check(popup.height === closedHeight, "popover keeps its starting height until the content fade finishes");
                check(test.heightChanges === 0, "opening sends no intermediate popup height changes");
                check(header("videos") === videos && header("rss") === stories,
                    "opening preserves header delegates");
                wait(popup.sectionFadeMs - 80 + 70);
                check(popup.height > closedHeight && popup.height < closedHeight + videoBody.height,
                    "popover grows gradually after the content fade finishes: "
                    + [popup.height, closedHeight, videoBody.height, popup.heldListHeight, popup.sectionOpacity]);
                // The viewport updates before the fixture Column's next layout pass.
                const resizingView = find(popup, item => item.contentY !== undefined && item.contentHeight !== undefined);
                const resizingHeight = resizingView.height;
                stories.tapped();
                wait(60);
                check(resizingView.height === resizingHeight,
                    "switching during the final resize holds the current viewport height: "
                    + [resizingHeight, resizingView.height, popup.heldListHeight]);
                videos.tapped();
                settle();
                check(popup.height > closedHeight, "popover takes its final height after the animation finishes");
                check(test.heightChanges > 1 && popup.heldListHeight === -1,
                    "opening animates the popup height and releases the height lock");
                const fullHeight = videoBody.height;
                check(fullHeight > 0 && find(videoBody, i => i.name === "Video 0"), "video rows finish opening");

                const videoTop = videos.parent.y;
                const switchHeight = popup.height;
                test.heightChanges = 0;
                const storySlot = stories.parent.implicitHeight;
                stories.tapped();
                check(!videos.open && stories.open && !videoBody.enabled, "another header closes and disables old rows");
                wait(80);
                check(storyBody.height === 0, "next drawer stays closed while outgoing rows fade");
                check(videoBody.height === fullHeight && videoBody.opacity > 0 && videoBody.opacity < 1,
                    "closing rows fade in place before the layout changes");
                check(videos.parent.y === videoTop, "outgoing drawer stays still throughout its fade");
                check(stories.x < 0 && stories.x > -popup.bodyWidth && stories.parent.height === storySlot,
                    "incoming header exits left before its old slot shrinks");
                wait(popup.sectionFadeMs);
                check(stories.parent.height > 0 && stories.parent.height < storySlot && storyBody.height === 0,
                    "old header slot collapses while the next drawer stays closed");
                wait(popup.sectionFoldMs - 40);
                check(stories.x < 0 && stories.x > -popup.bodyWidth && videos.parent.y < stories.parent.y,
                    "moved header enters from the left at the bottom");
                check(storyBody.height === 0 && storyBody.opacity === 0,
                    "content stays hidden while its header slides in");
                let incomingFade = false;
                for (let i = 0; i < 30; i++) {
                    wait(16);
                    if (popup.heldListHeight >= 0 && popup.sectionOpacity < 1)
                        check(popup.height === switchHeight && test.heightChanges === 0,
                            "switching keeps the popup height fixed throughout the transition");
                    check(!(videoBody.height > 0 && storyBody.height > 0), "drawers never overlap during a switch");
                    if (storyBody.height > 0) {
                        check(videoBody.height === 0, "old drawer is gone before the next opens");
                        check(stories.x === 0, "content appears only after the header finishes sliding");
                        check(storyBody.height === storyBody.children[0].implicitHeight + 3,
                            "incoming content keeps its full height throughout the fade");
                        incomingFade = incomingFade || (storyBody.opacity > 0 && storyBody.opacity < 1);
                    }
                }
                check(incomingFade && storyBody.opacity === 1,
                    "incoming content finishes fading in after its title arrives");
                check(videos.parent.y < stories.parent.y, "closed videos move above open stories");
                check(!find(videoBody, i => i.name === "Video 0"), "closed rows are released");
                const previewRow = find(storyBody, i => i.name === "Story 0");
                const plainRow = find(storyBody, i => i.name === "Story 1");
                const preview = find(previewRow, i => i.maximumLineCount === 3);
                const artwork = find(previewRow, i => i.status !== undefined && i.sourceSize !== undefined);
                const thumbnail = find(previewRow, i => i.radius !== undefined && i.width === 64 && i.height === 36);
                check(!find(previewRow, i => i.name === "Comments"), "stories have no comments button");
                const plainTitle = find(plainRow, i => i.text === "Story 1");
                check(preview && preview.visible && preview.textFormat === Text.PlainText
                    && preview.lineCount === 3 && preview.truncated, "preview is plain text capped at three lines");
                check(artwork && artwork.status === Image.Ready && artwork.width === 64 && artwork.height === 36,
                    "story thumbnail loads at the YouTube thumbnail size");
                check(previewRow.height > plainRow.height && plainTitle.parent.x === Theme.popupInset,
                    "text-only stories keep compact rows without image space");
                check(previewRow.height >= preview.parent.height + 8, "row contains the whole preview and metadata");
                const imageX = thumbnail.x;
                previewRow.track(20);
                wait(30);
                check(Math.abs(thumbnail.x - imageX - previewRow.swipe) < 1
                    && Math.abs(preview.parent.x - (Theme.popupInset + 64 + 8) - previewRow.swipe) < 1,
                    "image and preview follow the swipe together");
                previewRow.release();
                artwork.source = Qt.resolvedUrl("missing.svg");
                wait(100);
                check(artwork.status === Image.Error && !thumbnail.visible && previewRow.textInset === Theme.popupInset,
                    "failed thumbnails fall back to full-width text");

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
                wait(popup.sectionFadeMs * 2 + popup.sectionFoldMs + 60);
                check(storyBody.height === storyBody.children[0].implicitHeight + 3
                    && storyBody.opacity > 0 && storyBody.opacity < 1, "incoming content is partway through fading in");
                videos.tapped();
                wait(60);
                check(videoBody.height === 0, "interrupting a fade keeps the next drawer hidden");
                settle();
                check(videoBody.height === fullHeight && storyBody.height === 0 && videoBody.opacity === 1,
                    "interrupting a fade settles on the last drawer");

                const beforeClose = order();
                const openHeight = popup.height;
                test.heightChanges = 0;
                videos.tapped();
                wait(80);
                check(videoBody.height === fullHeight && videoBody.opacity > 0 && videoBody.opacity < 1,
                    "closing the last drawer fades it out in place");
                check(popup.height === openHeight && test.heightChanges === 0,
                    "closing keeps the popup height fixed until the fade finishes");
                wait(popup.sectionFadeMs - 80 + 70);
                check(popup.height < openHeight && popup.height > closedHeight,
                    "popover shrinks gradually after the outgoing content fade");
                settle();
                check(videoBody.height === 0 && popup.height === closedHeight, "closing removes the drawer after its fade");
                check(test.heightChanges > 1 && popup.heldListHeight === -1,
                    "closing animates its height after the content fade and releases the height lock");
                check(order() === beforeClose && stories.parent.y < videos.parent.y,
                    "closing without opening another feed keeps every header in place");

                videos.tapped();
                wait(80);
                check(videos.x === 0 && videos.parent.height === videos.parent.implicitHeight
                    && videoBody.height === fullHeight && videoBody.opacity > 0 && videoBody.opacity < 1,
                    "opening the last feed fades its content in without sliding its header");
                settle();
                videos.tapped();
                settle();

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

                const items = Array.from({length: 45}, (_, i) => ({id: "page" + i, title: "Paged story " + i,
                    published: now - i * 60000, points: -1, replies: -1, comments: "", url: "https://example.com/" + i}));
                Feeds.sources = [{url: "rss", title: "Stories", items: items}];
                wait(50);
                const pagedBody = body(header("rss"));
                const more = find(pagedBody, i => i.name === "Load More");
                check(find(pagedBody, i => i.name === "Paged story 19")
                    && !find(pagedBody, i => i.name === "Paged story 20"), "first page shows twenty unread stories");
                check(more && more.visible && find(more, i => i.text === "Load More" && String(i.color) === String(Theme.label2)),
                    "more available stories have a grey text link");
                more.tapped();
                wait(30);
                check(find(pagedBody, i => i.name === "Paged story 39")
                    && !find(pagedBody, i => i.name === "Paged story 40") && more.visible, "Load More adds twenty stories");
                Feeds.markSeen([items[0]]);
                wait(30);
                check(!find(pagedBody, i => i.name === "Paged story 0")
                    && find(pagedBody, i => i.name === "Paged story 40"), "clicked stories disappear and unread stories fill their places");
                more.tapped();
                wait(30);
                check(find(pagedBody, i => i.name === "Paged story 44") && !more.visible, "last page hides Load More");
                Feeds.markAllSeen();
                wait(30);
                check(!header("rss"), "Mark All Seen clears all RSS pages");
                Feeds.undo();
                wait(30);
                check(header("rss") && Feeds.unseenSources[0].items.length === 44, "Undo restores unread pages without clicked stories");

                const originalSource = Feeds.sources[0];
                const extraSources = ["second", "third"].map(key => ({url: key, title: key,
                    items: [{id: key, title: key, published: now, points: -1, replies: -1, url: ""}]}));
                Feeds.sources = [originalSource].concat(extraSources);
                wait(30);
                const beforeMiddleOpen = popup.sectionOrder.map(s => s.section);
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: false});
                header("second").tapped();
                settle();
                check(order() === beforeMiddleOpen.filter(key => key !== "second").concat(["second"]).join(","),
                    "opening a middle feed preserves all other relative positions");
                const movedOrder = order();
                header("second").tapped();
                settle();
                Feeds.sources = extraSources.slice().reverse().concat([originalSource]);
                wait(30);
                check(order() === movedOrder, "closing and source refresh retain the displayed order");
                console.log("PASS: feed drawers keep closed order and animate opening last");
            }
        }
        Timer { interval: 300; running: true; onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''



# Exercise the actual PopupWindow as well as the drawer-only fixture above.
WINDOW_QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 800; implicitHeight: 800
        Item { id: anchor; width: 20; height: 20 }
        FeedsPopup {
            id: popup; anchorItem: anchor; visible: true; probes: false; grows: false
            requestedVisible: OpenPopup.owner === anchor
        }
        Component.onCompleted: OpenPopup.set(anchor)
        // Layout can resize the window and undo it before the next frame.
        Connections {
            target: popup
            function onHeightChanged() { test.surfaceChanges++; }
        }
        TestCase {
            id: test; when: false
            property int surfaceChanges: 0
            function check(ok, why) { if (!ok) throw Error(why); }
            function find(item, predicate) {
                if (predicate(item)) return item;
                for (const child of item.children) {
                    const found = find(child, predicate);
                    if (found) return found;
                }
                return null;
            }
            function run() {
                Feeds.videos = [0, 1].map(i => ({id: "window" + i, title: "Window video " + i,
                    channel: "Channel", published: Date.now(), duration: 120, thumb: "", url: ""}));
                wait(100);
                const edge = find(popup.chromeItem, item => item.fadeBottom !== undefined && item.boxHeight !== undefined);
                check(edge, "the feed scroll effect is present");
                const surfaceHeight = popup.height, closedChrome = popup.chromeHeight;
                surfaceChanges = 0;
                Feeds.toggle("videos");
                let rowY = null, growing = false, expansionSag = 0, expansionRecoil = 0;
                for (let i = 0; i < 70; i++) {
                    wait(16);
                    check(popup.height === surfaceHeight,
                        "feed animation resizes the surface: " + surfaceHeight + " -> " + popup.height);
                    if (popup.heldListHeight >= 0)
                        check(edge.fadeBottom === 0, "bottom gradient covers the header before the viewport expands: " + edge.fadeBottom);
                    const title = find(popup.chromeItem, item => item.text === "Window video 0");
                    if (title) {
                        const y = title.mapToItem(popup.chromeItem, 0, 0).y;
                        if (rowY === null) rowY = y;
                        check(Math.abs(y - rowY) < 0.01, "resizing shifts visible content vertically");
                    }
                    growing = growing || (popup.sectionOpacity === 1 && popup.heldListHeight >= 0
                        && popup.chromeHeight > closedChrome);
                    if (popup.chromeItem.height !== popup.chromeHeight)
                        check(popup.chromeItem.sag === 0, "the feed border stays straight until expansion lands");
                    const sag = popup.chromeItem.sag;
                    check(expansionSag > 0 || sag >= 0, "an opening feed bows down first");
                    expansionSag = Math.max(expansionSag, sag);
                    expansionRecoil = Math.min(expansionRecoil, sag);
                }
                const openChrome = popup.chromeHeight;
                check(surfaceChanges === 0, "surface changes between rendered frames: " + surfaceChanges);
                check(rowY !== null && growing && openChrome > closedChrome && popup.heldListHeight === -1,
                    "the visible box still grows after the feed fades in");
                check(expansionSag > 0.2 && expansionSag <= 5 && expansionRecoil < -0.005
                    && Math.abs(expansionRecoil) < expansionSag / 4,
                    "opening a feed gently bows down and recoils: " + [expansionSag, expansionRecoil]);
                Feeds.markSeen([Feeds.unseenVideos[0]]);
                let maximumSag = 0, minimumSag = 0, eased = false;
                for (let i = 0; i < 65; i++) {
                    wait(16);
                    const drawn = popup.chromeItem.height, target = popup.chromeHeight;
                    if (Math.abs(drawn - target) > 0.05)
                        check(popup.chromeItem.sag === 0,
                            "a removed feed entry flexes the border only after it reaches its destination");
                    eased = eased || drawn > target + 1;
                    maximumSag = Math.max(maximumSag, popup.chromeItem.sag);
                    minimumSag = Math.min(minimumSag, popup.chromeItem.sag);
                    check(popup.height === surfaceHeight && surfaceChanges === 0,
                        "removing a feed entry keeps the surface fixed");
                }
                check(eased && maximumSag > 0.2 && maximumSag <= 5 && minimumSag < -0.005,
                    "removing a feed entry gently bends and rebounds the bottom border: "
                        + JSON.stringify({eased, maximumSag, minimumSag}));
                check(Math.abs(popup.chromeItem.height - popup.chromeHeight) < 0.05,
                    "the box settles after removing a feed entry");
                surfaceChanges = 0;
                Feeds.toggle("videos");
                let shrinking = false;
                for (let i = 0; i < 30; i++) {
                    wait(16);
                    check(popup.height === surfaceHeight, "closing resizes the surface");
                    shrinking = shrinking || (popup.heldListHeight >= 0 && popup.chromeHeight < openChrome);
                }
                check(shrinking && popup.chromeHeight === closedChrome && popup.heldListHeight === -1,
                    "the visible box shrinks to its original size");
                check(surfaceChanges === 0, "closing changes the surface between rendered frames: " + surfaceChanges);
                // A scrolled long feed must also settle before resizing a short one.
                Feeds.videos = Array.from({length: 25}, (_, i) => ({id: "long" + i, title: "Long video " + i,
                    channel: "Channel", published: Date.now(), duration: 120, thumb: "", url: ""}));
                Feeds.sources = [{url: "tiny", title: "Tiny", items: [{id: "tiny", title: "Tiny story",
                    published: Date.now(), points: -1, replies: -1, url: ""}]}];
                Feeds.toggle("videos");
                wait(popup.sectionFadeMs * 3 + popup.sectionFoldMs * 2 + 100);
                const view = find(popup.chromeItem, item => item.contentY !== undefined && item.contentHeight !== undefined);
                check(edge.fadeBottom > 0, "a settled overflowing feed retains its bottom gradient");
                view.contentY = view.contentHeight - view.height;
                check(view.contentY > 0, "long feed is scrolled before switching");
                const longSurface = popup.height;
                surfaceChanges = 0;
                Feeds.toggle("tiny");
                let tinyY = null;
                for (let i = 0; i < 70; i++) {
                    wait(16);
                    check(popup.height === longSurface, "switching a scrolled feed resizes the surface");
                    if (popup.heldListHeight >= 0)
                        check(edge.fadeBottom === 0, "switching feeds shows the bottom gradient before settling");
                    if (popup.sectionOpacity === 1 && popup.movingSection === "" && popup.shownSection === "tiny") {
                        const title = find(popup.chromeItem, item => item.text === "Tiny story");
                        check(title, "the short feed's content is present");
                        const y = title.mapToItem(popup.chromeItem, 0, 0).y;
                        if (tinyY === null) tinyY = y;
                        check(Math.abs(y - tinyY) < 0.01, "scroll rebound moves content during the final resize");
                    }
                }
                check(tinyY !== null, "scrolled switch reached the final resize");
                check(surfaceChanges === 0, "switching changes the surface between rendered frames: " + surfaceChanges);
                const finalHeight = popup.chromeItem.height, finalSurface = popup.height;
                Feeds.markAllSeen();
                check(OpenPopup.owner === null && !popup.requestedVisible,
                    "clearing the final feed items uses normal popup dismissal");
                wait(40);
                check(popup.revealProgress > 0 && popup.revealProgress < 1,
                    "the empty feed popup uses its existing fade");
                check(popup.chromeItem.height === finalHeight && popup.height === finalSurface && popup.chromeItem.sag === 0,
                    "the empty feed popup keeps its size without flexing during the fade");
                wait(160);
                check(popup.revealProgress === 0, "the empty feed popup finishes fading out");
                console.log("PASS: feed resize keeps surface and content positions fixed");
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
        (target / "settings.json").write_text('{"feedUrls": []}\n')
        (target / "shell.qml").write_text(WINDOW_QML)
        window = subprocess.run(["qs", "-p", str(target), "--no-color"],
                                env=shell_env(target), capture_output=True, text=True, timeout=10)
        window_output = window.stdout + window.stderr
        print("\n".join(line for line in window_output.splitlines()
                        if "This plugin does not support setting window masks" not in line))
        if window.returncode != 0 or "PASS: feed resize keeps surface and content positions fixed" not in window_output or "FAIL:" in window_output:
            return 1
        popup = runpy.run_path(str(ROOT / "scripts/test-popup-standards.py"))["POPUP"]
        (target / "components/Popup.qml").write_text(popup)
        (target / "settings.json").write_text('{"feedUrls": []}\n')
        (target / "preview.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="72"><rect width="128" height="72" fill="#777"/></svg>')
        state = target / "state/quickshell"
        state.mkdir(parents=True, exist_ok=True)
        (state / "feeds.json").write_text('{"open": "videos"}\n')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"],
                                env=shell_env(target), capture_output=True, text=True, timeout=25)
        output = result.stdout + result.stderr
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign",
                  "Cannot assign", "Failed to load configuration")
        ok = result.returncode == 0 and "PASS: feed drawers keep closed order and animate opening last" in output and not any(e in output for e in errors)
        print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
