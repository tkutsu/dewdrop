#!/usr/bin/env python3
"""Feeds: reading YouTube's Atom and hnrss's RSS, the live and premiere
filter, and what counts as seen, offscreen and without the network."""

import json
from pathlib import Path
import subprocess
import tempfile

from test_support import copy_shell, shell_env

# Trimmed from real replies (2026-10-18).
YOUTUBE = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <title>Uploads from Someone</title>
 <entry>
  <id>yt:video:AAAAAAAAAAA</id>
  <yt:videoId>AAAAAAAAAAA</yt:videoId>
  <title>Fish &amp; chips, &quot;properly&quot;</title>
  <author>
   <name>Some Channel</name>
  </author>
  <published>PUBLISHED_A</published>
 </entry>
 <entry>
  <id>yt:video:BBBBBBBBBBB</id>
  <yt:videoId>BBBBBBBBBBB</yt:videoId>
  <title>Live: the whole day</title>
  <author>
   <name>Some Channel</name>
  </author>
  <published>PUBLISHED_B</published>
 </entry>
 <entry>
  <id>yt:video:CCCCCCCCCCC</id>
  <yt:videoId>CCCCCCCCCCC</yt:videoId>
  <title>Too old to show</title>
  <author>
   <name>Some Channel</name>
  </author>
  <published>2020-01-01T00:00:00+00:00</published>
 </entry>
</feed>'''

HN = ('<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><title>Hacker News: Front Page</title>'
      '<item><title><![CDATA[Gold is now the top U.S. export]]></title><description><![CDATA[\n<p>Points: 329</p>\n<p># Comments: 179</p>\n]]></description>'
      '<pubDate>PUBDATE</pubDate><link>https://example.com/gold</link><dc:creator>someone</dc:creator>'
      '<comments>https://news.ycombinator.com/item?id=1</comments><guid isPermaLink="false">https://news.ycombinator.com/item?id=1</guid></item>'
      '</channel></rss>')

QML = '''import QtQuick
import Quickshell
import qs
import qs.services

ShellRoot {
    id: root
    property int failures: 0
    function check(ok, what) {
        if (!ok) { failures++; console.log("FAIL: " + what); }
    }

    Timer {
        interval: 300
        running: true
        onTriggered: {
            const youtube = YOUTUBE_JSON;
            const hn = HN_JSON;

            const videos = Feeds.parseVideos(youtube);
            root.check(videos.length === 3, "every entry is read (" + videos.length + ")");
            root.check(videos[0].title === 'Fish & chips, "properly"', "entities decoded: " + videos[0].title);
            root.check(videos[0].channel === "Some Channel", "channel from the author");
            root.check(videos[0].url === "https://www.youtube.com/watch?v=AAAAAAAAAAA", "watch link");
            root.check(videos[0].thumb.endsWith("/AAAAAAAAAAA/mqdefault.jpg"), "16:9 thumbnail");

            const stories = Feeds.parseStories(hn);
            const story = stories.items[0];
            root.check(stories.title === "Hacker News: Front Page", "feed title");
            root.check(story.title === "Gold is now the top U.S. export", "CDATA title");
            root.check(story.points === 329 && story.replies === 179, "hnrss points and comments");
            root.check(story.comments === "https://news.ycombinator.com/item?id=1", "comments link");
            root.check(!isNaN(story.published), "RFC 2822 date parses");

            root.check(Feeds.seconds("PT1H2M3S") === 3723 && Feeds.seconds("PT45S") === 45 && Feeds.seconds("P0D") === 0, "durations");
            root.check(Feeds.clock(3723) === "1:02:03" && Feeds.clock(605) === "10:05", "duration readout");
            const now = Date.now();
            root.check(Feeds.age(now - 30000, now) === "now" && Feeds.age(now - 7200000, now) === "2h" && Feeds.age(now - 3 * 86400000, now) === "3d", "ages");

            // The API calls B a live and says nothing of C (outside the window).
            const asked = [];
            Feeds.stub = function (path, then, fail) {
                asked.push(path);
                then({ items: [
                    { id: "AAAAAAAAAAA", contentDetails: { duration: "PT12M5S" } },
                    { id: "BBBBBBBBBBB", contentDetails: { duration: "PT8H" }, liveStreamingDetails: { actualStartTime: "x" } }
                ] });
            };
            Feeds.byChannel = { UCxxxxxxxxxxxxxxxxxxxxxx: videos };
            Feeds.classify();
            root.check(asked.length === 1 && asked[0].includes("id=AAAAAAAAAAA,BBBBBBBBBBB&"), "one videos.list for the window: " + asked[0]);
            root.check(Feeds.videos.length === 1 && Feeds.videos[0].video === "AAAAAAAAAAA", "lives and premieres left out");
            root.check(Feeds.videos[0].duration === 725, "duration kept");

            // Asked once: a second pass sends nothing.
            Feeds.classify();
            root.check(asked.length === 1, "verdicts remembered");

            // Unread until opened or marked; the badge counts both kinds.
            Feeds.sources = [Object.assign({ url: "x" }, stories)];
            root.check(Feeds.count === 2, "video and story both new (" + Feeds.count + ")");
            Feeds.markSeen([Feeds.videos[0]]);
            root.check(Feeds.count === 1 && Feeds.label === "1", "seen video leaves the count");
            root.check(Feeds.unseenVideos.length === 0 && Feeds.unseenSources.length === 1, "seen video leaves the list");

            // A swipe hides with an undo, and so does Mark All Seen.
            Feeds.hide(Feeds.unseenSources[0].items[0]);
            root.check(Feeds.count === 0 && Feeds.unseenSources.length === 0, "swiped story leaves list and badge");
            Feeds.undo();
            root.check(Feeds.count === 1 && Feeds.undos.length === 0, "undo brings it back");
            Feeds.markAllSeen();
            root.check(Feeds.count === 0 && Feeds.label === "", "mark all seen clears the badge");
            Feeds.undo();
            root.check(Feeds.count === 1, "mark all seen undone");

            // What the browser's history is asked about, and what it says back.
            const links = Feeds.links(Feeds.unseenItems());
            root.check(links.length === 2 && links.includes(story.url) && links.includes(story.comments), "links to look for: " + links);
            Feeds.seenInBrowser(story.comments + "\nhttps://elsewhere.example/\n");
            root.check(Feeds.count === 0 && Feeds.undos.length === 0, "opened in the browser counts as seen, with nothing to undo");

            // Sections start folded and remember being opened.
            root.check(!Feeds.unfolded("videos"), "folded at first");
            Feeds.toggle("videos");
            root.check(Feeds.unfolded("videos") && !Feeds.unfolded("x"), "one section opened");
            Feeds.toggle("x");
            root.check(!Feeds.unfolded("videos") && Feeds.unfolded("x"), "opening another section closes the first");
            Feeds.toggle("x");
            root.check(!Feeds.unfolded("videos") && !Feeds.unfolded("x"), "open section can close");

            // No youtube.json: the feeds still work, YouTube waits to be connected.
            root.check(!Feeds.connected && !YouTubeAccount.configured, "YouTube unconnected without its file");
            root.check(YouTubeAccount.file === "youtube.json" && Google.file === "gtasks.json", "two sign-ins, two files");

            console.log(root.failures === 0 ? "PASS: feeds" : "RESULT: " + root.failures + " failures");
            Qt.quit();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-feeds-") as tmp:
        target = Path(tmp)
        copy_shell(target)
        import datetime
        now = datetime.datetime.now(datetime.timezone.utc)
        youtube = (YOUTUBE.replace("PUBLISHED_A", (now - datetime.timedelta(hours=3)).isoformat())
                   .replace("PUBLISHED_B", (now - datetime.timedelta(hours=5)).isoformat()))
        hn = HN.replace("PUBDATE", (now - datetime.timedelta(hours=1)).strftime("%a, %d %b %Y %H:%M:%S +0000"))
        qml = QML.replace("YOUTUBE_JSON", json.dumps(youtube)).replace("HN_JSON", json.dumps(hn))
        (target / "shell.qml").write_text(qml)
        # videos.list goes to the fixture's stub instead of Google.
        service = target / "services/Feeds.qml"
        text = service.read_text()
        call = 'root.get(`videos'
        assert call in text
        service.write_text(text.replace(call, 'root.stub(`videos')
                           .replace("    property var videos: []", "    property var stub: null\n    property var videos: []"))
        # No feeds to fetch: the fixture never touches the network.
        (target / "settings.json").write_text('{"feedUrls": []}\n')
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        print(output)
        assert "PASS: feeds" in output and "FAIL:" not in output, output
        own = [line for line in output.splitlines() if "Feeds.qml" in line and ("WARN" in line or "ERROR" in line)]
        assert not own, "\n".join(own)


if __name__ == "__main__":
    main()
