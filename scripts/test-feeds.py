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
            root.check(story.summary === "" && story.thumb === "", "metadata-only feed has no duplicate preview");

            const commentsOnly = '<description><![CDATA[<p><a href="https://lobste.rs/s/example">Comments</a></p>]]></description>';
            const lobsters = Feeds.parseStories(hn.replace(/<description>[\\s\\S]*?<\\/description>/, commentsOnly), 'https://lobste.rs/rss').items[0];
            root.check(lobsters.summary === "", "Lobsters comments-only descriptions stay hidden");
            const discussion = commentsOnly.replace('<p><a', '<p>An actual discussion about comments.</p><p><a');
            const described = Feeds.parseStories(hn.replace(/<description>[\\s\\S]*?<\\/description>/, discussion), 'https://lobste.rs/rss').items[0];
            root.check(described.summary === "An actual discussion about comments.", "Lobsters article text survives boilerplate removal");

            const comic = `<description><![CDATA[<a href="https://www.smbc-comics.com/comic/example"><img src="https://www.smbc-comics.com/comics/example.png"/><br/><br/>Click here to go see the bonus panel!</a><p>Hovertext:<br/>The actual comic text.</p><br/>Today's News:<br/>\n]]></description>`;
            const smbc = Feeds.parseStories(hn.replace(/<description>[\\s\\S]*?<\\/description>/, comic), 'https://www.smbc-comics.com/comic/rss').items[0];
            root.check(smbc.summary === "Click here to go see the bonus panel! Hovertext: The actual comic text.", "SMBC empty news heading is hidden");
            root.check(smbc.thumb === "https://www.smbc-comics.com/comics/example.png", "SMBC comic image survives text cleanup");
            root.check(Feeds.summary("<p>Today's News:<br/>Actual news.</p>", 'https://www.smbc-comics.com/comic/rss').includes("Actual news."), "nonempty SMBC news is preserved");
            root.check(Feeds.summary("<p>Today's News:</p>", 'https://example.com/rss') === "Today's News:", "other feeds keep their own headings");

            const description = '<description>&lt;p&gt;First &lt;b&gt;paragraph&lt;/b&gt;.&lt;/p&gt;'
                + '&lt;p&gt;Second&amp;nbsp;line &amp;copy;.&lt;/p&gt;'
                + '&lt;img src=&quot;/comic.png?a=1&amp;amp;b=2&quot; /&gt;</description>';
            const preview = Feeds.parseStories(hn.replace(/<description>[\\s\\S]*?<\\/description>/, description)).items[0];
            root.check(preview.summary === "First paragraph. Second line ©.", "HTML preview becomes readable plain text: " + preview.summary);
            root.check(preview.thumb === "https://example.com/comic.png?a=1&b=2", "escaped comic image and relative URL");

            const content = '<description><![CDATA[<img src="file:///private.png">]]></description>'
                + '<content:encoded><![CDATA[<style>hidden</style><script>hidden</script><!-- hidden -->'
                + '<p>Full article preview.</p><img src="//images.example/comic.jpg">]]></content:encoded>';
            const full = Feeds.parseStories(hn.replace(/<description>[\\s\\S]*?<\\/description>/, content)).items[0];
            root.check(full.summary === "Full article preview.", "full content fallback omits non-content markup");
            root.check(full.thumb === "https://images.example/comic.jpg", "unsafe image skipped for content image");
            const media = Feeds.parseStories(hn.replace('</item>', '<media:thumbnail url="https://images.example/thumb.jpg"/></item>')).items[0];
            root.check(media.thumb === "https://images.example/thumb.jpg", "media thumbnail");
            const enclosed = Feeds.parseStories(hn.replace('</item>', "<enclosure type='image/png' url='../cover.png'/></item>")).items[0];
            root.check(enclosed.thumb === "https://example.com/cover.png", "image enclosure and parent-relative path");
            const audio = Feeds.parseStories(hn.replace('</item>', '<enclosure type="audio/mpeg" url="https://example.com/audio.mp3"/></item>')).items[0];
            root.check(audio.thumb === "", "audio enclosures are not images");

            const atom = Feeds.parseStories('<feed><title>Articles</title><entry><id>atom:1</id><title>Article</title>'
                + `<link rel="self" href="https://example.com/feed/1"/><link href='/posts/1' rel='alternate'/>`
                + '<updated>2026-10-19T12:00:00Z</updated><summary type="html">&lt;p&gt;Atom summary.&lt;/p&gt;'
                + '&lt;img src="cover.png"/&gt;</summary></entry></feed>', 'https://example.com/feed').items[0];
            root.check(atom.url === "https://example.com/posts/1", "Atom alternate link resolves against feed");
            root.check(atom.summary === "Atom summary." && atom.thumb === "https://example.com/posts/cover.png", "Atom summary and image");

            // Preserve ranking and all entries; pagination happens after read filtering.
            const item = hn.match(/<item>[\\s\\S]*?<\\/item>/)[0];
            const start = hn.slice(0, hn.indexOf("<item>"));
            const entries = Array.from({ length: Feeds.storiesShown + 1 }, (_, i) => item
                .replace("Points: 329", "Points: " + (i === Feeds.storiesShown ? 900 : 300))
                .replace(/<pubDate>[\\s\\S]*?<\\/pubDate>/, "<pubDate>" + new Date(Date.now() - i * 60000).toUTCString() + "</pubDate>")
                .replace('item?id=1</guid>', 'item?id=' + i + '</guid>'));
            const ranked = Feeds.parseStories(start + entries.join("") + "</channel></rss>").items;
            root.check(ranked.length === Feeds.storiesShown + 1 && ranked[0].points === 900,
                "all stories retained for pagination, highest points first");
            root.check(ranked[1].published > ranked[2].published, "equal points: newest first");
            const unscored = Feeds.parseStories(start + entries.slice().reverse().join("").replace(/Points: \\d+/g, "No score") + "</channel></rss>").items;
            root.check(unscored.every((entry, i) => i === 0 || unscored[i - 1].published >= entry.published),
                "feeds without points: newest first");

            root.check(Feeds.seconds("PT1H2M3S") === 3723 && Feeds.seconds("PT45S") === 45 && Feeds.seconds("P0D") === 0, "durations");
            root.check(Feeds.clock(3723) === "1:02:03" && Feeds.clock(605) === "10:05", "duration readout");
            const now = Date.now();
            root.check(Feeds.age(now - 30000, now) === "now" && Feeds.age(now - 7200000, now) === "2h" && Feeds.age(now - 3 * 86400000, now) === "3d", "ages");

            const oldStory = {id: "old-rss", title: "Older article", published: now - 20 * 86400000, url: "https://example.com/old"};
            Feeds.sources = [{url: "older", title: "Older feed", items: [oldStory]}];
            root.check(Feeds.count === 1, "RSS predating the legacy cutoff is unread");
            root.check(Feeds.links(Feeds.unseenItems()).includes(oldStory.url), "old RSS links are checked in browser history");
            Feeds.markSeen([oldStory]);
            Feeds.sources = [];
            Feeds.prune(now - 7 * 86400000);
            Feeds.sources = [{url: "older", title: "Older feed", items: [oldStory]}];
            root.check(Feeds.count === 0, "clicked RSS stays hidden after leaving the feed and video pruning");
            Feeds.sources = [];

            // The API calls B a live and says nothing of C (outside the window).
            const asked = [];
            Feeds.stub = function (path, then, fail) {
                asked.push(path);
                then({ items: [
                    { id: "AAAAAAAAAAA", contentDetails: { duration: "PT12M5S" } },
                    { id: "BBBBBBBBBBB", contentDetails: { duration: "PT8H" }, liveStreamingDetails: { actualStartTime: "x" } }
                ] });
            };
            Feeds.store.channels = { UCxxxxxxxxxxxxxxxxxxxxxx: { t: now, videos: videos } };
            Feeds.classify();
            root.check(asked.length === 1 && asked[0].includes("id=AAAAAAAAAAA,BBBBBBBBBBB&"), "one videos.list for the window: " + asked[0]);
            root.check(Feeds.videos.length === 1 && Feeds.videos[0].video === "AAAAAAAAAAA", "lives and premieres left out");
            root.check(Feeds.videos[0].duration === 725, "duration kept");

            // Asked once: a second pass sends nothing.
            Feeds.classify();
            root.check(asked.length === 1, "verdicts remembered");
            const apiStub = Feeds.stub;

            // Left out by the API (private, removed): not asked again until staleMs.
            const omitted = Feeds.video("DDDDDDDDDDD", "Private now", "Some Channel", now - 3600000);
            Feeds.stub = function (path, then, fail) { asked.push(path); then({ items: [] }); };
            Feeds.store.channels = { UCxxxxxxxxxxxxxxxxxxxxxx: { t: now, videos: videos.concat([omitted]) } };
            Feeds.classify();
            Feeds.classify();
            root.check(asked.length === 2 && asked[1].includes("id=DDDDDDDDDDD&"), "an omitted video is asked about once per staleMs: " + asked.slice(1));
            root.check(!Feeds.videos.some(v => v.video === "DDDDDDDDDDD"), "an omitted video stays hidden");

            // The API out of reach: the unasked show, without a duration.
            const unasked = Feeds.video("EEEEEEEEEEE", "Unasked", "Some Channel", now - 3600000);
            Feeds.stub = function (path, then, fail) { fail("No network", 0); };
            Feeds.store.channels = { UCxxxxxxxxxxxxxxxxxxxxxx: { t: now, videos: videos.concat([unasked]) } };
            Feeds.classify();
            const shown = Feeds.videos.find(v => v.video === "EEEEEEEEEEE");
            root.check(shown && shown.duration === -1 && Feeds.videos.find(v => v.video === "AAAAAAAAAAA").duration === 725,
                "unasked videos show while the API is unreachable");
            Feeds.trouble = "";

            // A spent quota: told apart from other 403s, and nothing asked until the reset.
            Feeds.fail("Google said 403", 403, "accessNotConfigured");
            root.check(Feeds.trouble === "Enable the YouTube Data API v3 in the Google console", "API switched off");
            Feeds.fail("Google said 403", 403, "forbidden");
            root.check(Feeds.trouble === "Google said 403", "other 403s say so: " + Feeds.trouble);
            Feeds.fail("Google said 403", 403, "quotaExceeded");
            root.check(Feeds.store.quotaUntil > now && Feeds.trouble.startsWith("YouTube quota used up until"), "quota spent: " + Feeds.trouble);
            let refused = "";
            Feeds.get("channels?part=id", () => refused = "asked", (why, status, reason) => refused = reason);
            root.check(refused === "quotaExceeded", "a spent quota refuses without asking");
            root.check(Feeds.quotaReset(Date.UTC(2026, 9, 19, 7, 59)) === Date.UTC(2026, 9, 19, 8)
                && Feeds.quotaReset(Date.UTC(2026, 9, 19, 8)) === Date.UTC(2026, 9, 20, 8), "quota resets at 08:00 UTC");
            Feeds.store.quotaUntil = 0;
            Feeds.trouble = "";

            // Handles: looked up once and kept; one naming nobody is believed for a day.
            const lookups = [];
            Feeds.stub = function (path, then, fail) {
                lookups.push(path);
                then(path.includes("known") ? { items: [{ id: "UCknownknownknownknown12" }] } : {});
            };
            let resolved = [];
            Feeds.resolve(["@known", "@nobody", "UCidididididididididid12"], ids => resolved = ids);
            root.check(lookups.length === 2 && resolved.length === 2 && resolved.includes("UCknownknownknownknown12")
                && resolved.includes("UCidididididididididid12"), "handles looked up: " + resolved);
            Feeds.resolve(["@known", "@nobody"], ids => resolved = ids);
            root.check(lookups.length === 2 && resolved.length === 1, "handles kept, misses too");
            Feeds.stub = function (path, then, fail) { lookups.push(path); fail("No network", 0); };
            Feeds.resolve(["@flaky"], ids => resolved = ids);
            Feeds.resolve(["@flaky"], ids => resolved = ids);
            root.check(lookups.length === 4 && resolved.length === 0, "a failed lookup is asked again");

            // A failed public feed tries the channel's own, then waits out staleMs
            // on what it had, and only then pays for the API.
            const recovered = Array.from({length: 9}, (_, i) => ({snippet: {
                resourceId: {videoId: "RECOVER000" + i}, title: "Recovered " + i,
                videoOwnerChannelTitle: "Recovered channel",
                publishedAt: new Date(now - 3600000).toISOString()}}));
            const own = youtube.replace(/<entry>[\\s\\S]*?<\\/entry>/g, entry => !entry.includes("AAAAAAAAAAA") ? ""
                : entry.replace(/AAAAAAAAAAA/g, "OWNFEED0001") + entry.replace(/AAAAAAAAAAA/g, "SHORTSHORT1")
                    .replace("<title>", '<link rel="alternate" href="https://www.youtube.com/shorts/SHORTSHORT1"/><title>'));
            const fallbackCalls = [];
            const fetched = [];
            Feeds.feedStub = function (method, url, payload, headers, timeout, accepted, failed) {
                fetched.push(url);
                if (url.includes("UULFworking"))
                    accepted({status: 200, responseText: youtube.replace(/<entry>[\\s\\S]*?<\\/entry>/g,
                        entry => entry.includes("AAAAAAAAAAA") ? entry : "")});
                else if (url.includes("channel_id=UCchannel"))
                    accepted({status: 200, responseText: own});
                else
                    accepted({status: 404, responseText: ""});
            };
            Feeds.stub = function (path, then, fail) {
                if (path.startsWith("playlistItems?")) {
                    fallbackCalls.push(path);
                    then({items: recovered});
                } else {
                    const ids = path.match(/&id=([^&]+)/)[1].split(",");
                    then({items: ids.map(id => ({id: id, contentDetails: {duration: "PT5M"}}))});
                }
            };
            Feeds.store.channels = {};
            Feeds.readChannels(["UCworking", "UCchannel", "UCrejected"]);
            root.check(fetched.filter(url => url.includes("working")).length === 1, "an answering playlist feed is enough");
            root.check(Feeds.store.channels.UCchannel.videos.map(v => v.video).join() === "OWNFEED0001",
                "the channel's own feed stands in, Shorts dropped");
            root.check(fallbackCalls.length === 1 && fallbackCalls[0].includes("playlistId=UULFrejected"),
                "only a channel with nothing from either feed pays for the API");
            root.check(Feeds.unseenVideos.length === 11, "every channel's videos listed (" + Feeds.unseenVideos.length + ")");
            Feeds.readChannels(["UCrejected"]);
            root.check(fallbackCalls.length === 1 && Feeds.store.channels.UCrejected.videos.length === 9,
                "a channel heard from within staleMs keeps its videos and waits");
            const read = now - Feeds.staleMs - 1;
            Feeds.store.channels = { UCrejected: Object.assign({}, Feeds.store.channels.UCrejected, { t: read }) };
            Feeds.stub = function (path, then, fail) { fallbackCalls.push(path); fail("No network", 0); };
            Feeds.readChannels(["UCrejected"]);
            root.check(fallbackCalls.length === 2 && Feeds.store.channels.UCrejected.t === read && Feeds.unseenVideos.length === 9,
                "past staleMs it asks, and a failed ask keeps the channel's videos");
            Feeds.store.channels = { UCxxxxxxxxxxxxxxxxxxxxxx: { t: now, videos: videos } };
            Feeds.stub = apiStub;
            Feeds.classify();
            Feeds.trouble = "";

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
            const late = Object.assign({}, story, { id: "late", published: now - 7200000 });
            Feeds.sources = [{ url: "x", title: "x", items: stories.items.concat([late]) }];
            root.check(Feeds.count === 1, "a story reaching the feed after Mark All Seen is new, however old");
            Feeds.sources = [Object.assign({ url: "x" }, stories)];
            Feeds.undo();
            root.check(Feeds.count === 1, "mark all seen undone");

            // What the browser's history is asked about, and what it says back.
            const links = Feeds.links(Feeds.unseenItems());
            root.check(links.length === 2 && links.includes(story.url) && links.includes(story.comments), "links to look for: " + links);
            Feeds.seenInBrowser(story.comments + "\nhttps://elsewhere.example/\n");
            root.check(Feeds.count === 0 && Feeds.undos.length === 0, "opened in the browser counts as seen, with nothing to undo");

            // A story seen is forgotten once gone from every feed and a month old.
            const day = 86400000;
            const seenBefore = Feeds.store.seen;
            Feeds.store.seen = { "gone-old": now - 40 * day, "listed-old": now - 40 * day, "gone-new": now - day, "yt:old": now - 40 * day };
            Feeds.sources = [{ url: "y", title: "y", items: [{ id: "listed-old", title: "Listed", published: now - 40 * day, url: "" }] }];
            Feeds.forgetStories(now - 30 * day);
            root.check(Object.keys(Feeds.store.seen).sort().join() === "gone-new,listed-old,yt:old",
                "forgotten: " + Object.keys(Feeds.store.seen));
            Feeds.store.seen = seenBefore;
            Feeds.sources = [];

            // Sections start folded and remember being opened.
            root.check(!Feeds.unfolded("videos"), "folded at first");
            Feeds.toggle("videos");
            root.check(Feeds.unfolded("videos") && !Feeds.unfolded("x"), "one section opened");
            Feeds.toggle("x");
            root.check(!Feeds.unfolded("videos") && Feeds.unfolded("x"), "opening another section closes the first");
            Feeds.toggle("x");
            root.check(!Feeds.unfolded("videos") && !Feeds.unfolded("x"), "open section can close");

            // No youtube.json: the feeds still work, YouTube waits to be connected.
            const refreshed = Feeds.refreshes;
            Settings.set("feedUrls", []);
            root.check(Feeds.refreshes > refreshed, "changing feed addresses refreshes immediately");
            const refreshedChannels = Feeds.refreshes;
            Settings.set("feedChannels", ["@sample"]);
            root.check(Feeds.refreshes > refreshedChannels, "changing extra channels refreshes immediately");
            root.check(!Feeds.connected && !YouTubeAccount.configured, "YouTube unconnected without its file");
            root.check(YouTubeAccount.file === "youtube.json" && Google.file === "gtasks.json", "two sign-ins, two files");

            console.log(root.failures === 0 ? "PASS: feeds" : "RESULT: " + root.failures + " failures");
            finish.start();
        }
    }
    Timer { id: finish; interval: 100; onTriggered: Qt.quit() }
}
'''

RESTORE_QML = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    readonly property bool feedsRestored: Feeds.restored
    Timer { interval: 300; running: true; onTriggered: {
        const published = Date.now() - 20 * 86400000;
        const unread = {id: "other-old-rss", published: published, url: "https://example.com/other-old"};
        Feeds.sources = [{url: "older", title: "Older feed", items: [unread, {id: "old-rss",
            published: published, url: "https://example.com/old"}]}];
        const ok = feedsRestored && Feeds.count === 1 && Feeds.unseenSources[0].items[0].id === unread.id;
        console.log(ok ? "PASS: clicked RSS survives restart" : "FAIL: RSS restart read-state");
        console.log(Feeds.store.channels.UCxxxxxxxxxxxxxxxxxxxxxx?.videos.length === 3 && Feeds.store.verdicts.AAAAAAAAAAA
            ? "PASS: channels and verdicts survive restart" : "FAIL: channel cache lost on restart");
        Qt.quit();
    } }
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
        service.write_text(text.replace(call, 'root.stub(`videos').replace('root.get(`playlistItems', 'root.stub(`playlistItems')
                           .replace('root.get(`channels', 'root.stub(`channels').replace('Http.send("GET", job.urls[i]', 'root.feedStub("GET", job.urls[i]')
                           .replace("    property var videos: []", "    property var stub: null\n    property var feedStub: null\n    property int refreshes: 0\n    property alias store: store\n    property var videos: []")
                           .replace("    function refresh(): void {", "    function refresh(): void {\n        root.refreshes++;"))
        # No feeds to fetch: the fixture never touches the network.
        (target / "settings.json").write_text('{"feedUrls": []}\n')
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        print(output)
        assert "PASS: feeds" in output and "FAIL:" not in output, output
        own = [line for line in output.splitlines() if "Feeds.qml" in line and ("WARN" in line or "ERROR" in line)]
        assert not own, "\n".join(own)
        (target / "shell.qml").write_text(RESTORE_QML)
        restarted = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                   capture_output=True, text=True, timeout=15)
        output = restarted.stdout + restarted.stderr
        print(output)
        assert restarted.returncode == 0 and "PASS: clicked RSS survives restart" in output and "FAIL:" not in output


if __name__ == "__main__":
    main()
