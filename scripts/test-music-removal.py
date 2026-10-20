#!/usr/bin/env python3
"""Remove real queue rows and verify fade, movement and popup resize ordering."""

import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("queue_harness", Path(__file__).with_name("test-music-queue-scroll.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

CASES = '''
                popup.springs = false; popup.growX = 1; popup.growY = 1;
                Mpd.applyRemovals = true;
                const list = popup.auditList;
                function verify(ok, message) { if (!ok) throw Error(message); }
                function row(title) {
                    for (let index = 0; index < list.count; index++) {
                        const item = list.itemAtIndex(index);
                        if (item?.modelData.title === title) return item;
                    }
                    return null;
                }
                function y(title) { return row(title).mapToItem(list, 0, 0).y; }
                function until(predicate, message) {
                    const deadline = Date.now() + 1500;
                    while (!predicate() && Date.now() < deadline) wait(10);
                    check(predicate(), message);
                }
                for (const count of [3, 12]) {
                    Mpd.queueChanging();
                    Mpd.queue = Array.from({length: count}, (_, pos) => ({pos, title: "Track " + pos, artist: "Artist", duration: 120}));
                    wait(1000);
                    list.positionViewAtBeginning(); list.forceLayout();
                    const first = row("Track 0");
                    const button = named(first, "Remove Track 0 from queue");
                    mouseMove(button, button.width / 2, button.height / 2); wait(30);
                    const beforeY = y("Track 1"), beforeHeight = list.height;
                    const surface = popup.height, width = popup.width, top = popup.chromeItem.y;
                    const position = list.mapToItem(popup.contentItem, 0, 0);
                    mouseClick(button, button.width / 2, button.height / 2);
                    wait(Theme.blinkMs);
                    check(Mpd.queue.length === count && first.opacity === 1 && y("Track 1") === beforeY,
                        "acknowledgement keeps queue rows still");
                    wait(Theme.blinkMs + 30);
                    check(Mpd.queue.length === count && first.opacity < 1,
                        "track fades before removal or replacement");
                    check(y("Track 1") === beforeY && list.height === beforeHeight,
                        "neighbours and popup hold their space during fade");
                    until(() => first.opacity === 0, "track is invisible before neighbours move");
                    let moved = false;
                    for (let elapsed = 0; elapsed < Theme.fadeMs - 20; elapsed += 10) {
                        const nextY = y("Track 1");
                        moved = moved || (nextY > 0.1 && nextY < beforeY - 0.1);
                        verify(Math.abs(list.height - beforeHeight) < 0.1,
                            "list height stays fixed while neighbours move");
                        wait(10);
                    }
                    check(moved, "following track moves through intermediate positions");
                    until(() => Mpd.queue.length === count - 1, "MPD removal follows the row exit");
                    until(() => Math.abs(y("Track 1")) < 0.1, "following track lands in the empty slot");
                    let sag = 0;
                    for (let frame = 0; frame < 70; frame++) {
                        const p = list.mapToItem(popup.contentItem, 0, 0);
                        verify(popup.height === surface && popup.width === width,
                            "removal keeps the compositor surface fixed");
                        verify(popup.chromeItem.y === top && Math.abs(p.x - position.x) < 0.01 && Math.abs(p.y - position.y) < 0.01,
                            "popup top edge and content stay anchored");
                        if (Math.abs(popup.chromeItem.height - popup.chromeHeight) > 0.05)
                            verify(popup.chromeItem.sag === 0, "border stays rigid until resize lands");
                        sag = Math.max(sag, popup.chromeItem.sag);
                        wait(16);
                    }
                    check(list.height === Math.min(count - 1, 8) * 22, "queue height settles to its row count");
                    check(Math.abs(popup.chromeItem.height - popup.chromeHeight) < 0.05, "popup border lands at the content height");
                    check(count > 8 || sag > 0.1, "short queue shrink uses the shared border flex");
                    console.log("PASS: staged music removal for " + count + " tracks");
                }
                function reset(count) {
                    Mpd.queueChanging();
                    Mpd.queue = Array.from({length: count}, (_, pos) => ({pos, title: "Track " + pos, artist: "Artist", duration: 120}));
                    wait(800); list.forceLayout();
                }
                function remove(index) {
                    const button = named(list.itemAtIndex(index), "Remove Track " + index + " from queue");
                    mouseMove(button, button.width / 2, button.height / 2); wait(30);
                    mouseClick(button, button.width / 2, button.height / 2);
                }
                reset(1);
                const surface = popup.height;
                remove(0);
                until(() => Mpd.queue.length === 0, "last track exits before the queue becomes empty");
                wait(1000);
                check(list.height === 0 && popup.height === surface && popup.requestedVisible,
                    "empty queue keeps the music controls and compositor surface in place: "
                    + JSON.stringify({list: list.height, surface, now: popup.height, requested: popup.requestedVisible, reserve: popup.reserveHeight}));
                reset(12);
                list.positionViewAtIndex(11, ListView.End); wait(30);
                const beforeScroll = list.contentY;
                remove(8);
                until(() => Mpd.queue.length === 11, "scrolled queue removes the selected track");
                wait(800);
                check(list.contentY === Math.min(beforeScroll, list.contentHeight - list.height),
                    "scrolled removal preserves browsing within the new queue bounds: "
                    + JSON.stringify({beforeScroll, now: list.contentY, content: list.contentHeight, origin: list.originY, height: list.height}));
                reset(3);
                remove(0); wait(180);
                const calls = Mpd.removeCalls;
                Mpd.queueChanging(); Mpd.queue = Mpd.queue.slice();
                wait(700);
                check(Mpd.removeCalls === calls && list.itemAtIndex(0).opacity === 1 && list.itemAtIndex(0).height === 22,
                    "refresh during fade cancels the stale removal and restores the row");
                Settings.set("reduceMotion", true);
                remove(0);
                until(() => Mpd.queue.length === 2, "reduced motion removes the track");
                check(list.height === 44 && popup.departureFade === 0 && popup.departureFold === 0,
                    "reduced motion skips fade and fold delays");
                Settings.set("reduceMotion", false);
                reset(3);
                Mpd.applyRemovals = false;
                const unanswered = Mpd.removeCalls;
                remove(0);
                until(() => Mpd.removeCalls === unanswered + 1, "row exit sends exactly one removal request");
                check(list.itemAtIndex(0).opacity === 0 && list.heldHeight > 0,
                    "departed track stays hidden while MPD's reply is pending");
                wait(1300);
                check(!popup.removingTrack && list.enabled && list.itemAtIndex(0).opacity === 1
                    && list.itemAtIndex(0).height === 22 && list.height === 66,
                    "missing MPD reply restores the track and unlocks the queue");
'''

start = harness.SHELL.index("                const list = popup.auditList;", harness.SHELL.index("            function run()"))
end = harness.SHELL.index('                console.log("DONE: queue scroll");', start)
harness.SHELL = harness.SHELL[:start] + CASES + harness.SHELL[end:]
harness.SHELL = harness.SHELL.replace("import qs.components", "import qs\nimport qs.components")

if __name__ == "__main__":
    raise SystemExit(harness.main())
