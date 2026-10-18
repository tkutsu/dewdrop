pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// New videos from YouTube channels and new stories from a few RSS feeds,
// counted on the bar until they have been opened.
//
// The channels are the account's subscriptions (YouTube Data API, through the
// shared Google sign-in) plus Settings.feedChannels, which can name ones you
// do not subscribe to. Their videos come from YouTube's public feeds rather
// than the API: those cost no quota, and the UULF playlist they are read from
// is a channel's uploads without its Shorts. Lives and premieres are in it
// too, and only the API can tell them apart, so every new video is asked
// about once (videos.list, fifty to a request) and the answer is kept.
//
// Seen is per item, and anything published before `since` counts as seen:
// "Mark All Seen" only moves that instant.
GoogleService {
    id: root

    readonly property string api: "https://www.googleapis.com/youtube/v3"
    readonly property string scope: "youtube.readonly"
    readonly property string web: "https://www.youtube.com/feed/subscriptions"

    service: "YouTube"
    // A channel posts a few times a week; half an hour is plenty, and the
    // feeds are fetched without quota anyway.
    pollMs: 30 * 60000

    // How far back the popup looks, and how many stories a feed shows.
    readonly property int days: 7
    readonly property int storiesShown: 12
    // Feeds fetched at once. Enough to finish a hundred channels in seconds,
    // few enough not to look like a crawler.
    readonly property int parallel: 6
    readonly property int timeoutMs: 15000

    onFetch: root.collect()

    // --- state ---------------------------------------------------------------
    // Newest first: {id, title, channel, published, duration, url, thumb}.
    property var videos: []
    // One per feed URL, in settings order: {title, url, items}, each item
    // {id, title, url, comments, points, replies, published}.
    property var sources: []
    // The token predates the YouTube scope: the videos wait for a reconnect.
    // Kept apart from Google.scopeMissing, which would stop Mail, Tasks and the
    // calendar too until the consent ran.
    property bool needsYouTube: false

    // What each channel's feed said last, by channel id, so one feed failing
    // keeps its videos rather than dropping them for a poll.
    property var byChannel: ({})
    // @handles from the settings resolved to channel ids, for this session.
    property var handles: ({})
    property var subscribed: []

    readonly property int count: root.videos.filter(v => root.unread(v)).length
        + root.sources.reduce((n, s) => n + s.items.filter(i => root.unread(i)).length, 0)
    readonly property string icon: Theme.glyph.feeds
    readonly property string label: root.count === 0 ? "" : String(Math.min(root.count, 99))

    readonly property string tooltip: {
        if (!root.configured)
            return `Google not connected\nRun ${Google.setup}`;
        if (root.trouble !== "")
            return root.trouble;
        if (!root.loaded)
            return "Reading feeds…";
        return root.count === 0 ? "Nothing new" : `${root.count} new`;
    }

    function unread(item: var): bool {
        return item.published > store.since && !(item.id in store.seen);
    }

    function open(item: var, link: string): void {
        OpenPopup.dismiss();
        Quickshell.execDetached(["xdg-open", link || item.url]);
        root.markSeen([item]);
    }

    function openApp(): void {
        OpenPopup.dismiss();
        Quickshell.execDetached(["xdg-open", root.web]);
    }

    function markSeen(items: var): void {
        const seen = Object.assign({}, store.seen);
        for (const item of items)
            seen[item.id] = item.published;
        store.seen = seen;
        root.save();
    }

    function markAllSeen(): void {
        store.since = Date.now();
        store.seen = {};
        root.save();
    }

    // --- fetching ------------------------------------------------------------
    // Everything below runs inside the base's request count (base.send, or
    // `requests` held by hand round a plain GET), so `loading` stays up until
    // the last feed has landed and `loaded` means the whole picture.
    function collect(): void {
        root.readSources();
        root.needsYouTube = !Google.grants(root.scope);
        if (root.needsYouTube) {
            root.loaded = true;
            return;
        }
        root.gather("subscriptions", [{
                url: `${root.api}/subscriptions?part=snippet&mine=true&maxResults=50&fields=nextPageToken,items/snippet(resourceId/channelId)`
            }], raw => raw.snippet.resourceId.channelId, function (ids, failed) {
            if (failed.length === 0)
                root.subscribed = ids;
            root.resolve(Settings.feedChannels, extra => root.readChannels(root.subscribed.concat(extra)));
        });
    }

    // Settings.feedChannels to channel ids: an id as it is, or inside a
    // /channel/ link; an @handle, bare or in a link, looked up once.
    function resolve(entries: var, then: var): void {
        const ids = [];
        const lookups = [];
        for (const entry of entries) {
            const id = String(entry).match(/UC[\w-]{22}/);
            const handle = String(entry).match(/@[\w.-]+/);
            if (id)
                ids.push(id[0]);
            else if (handle && root.handles[handle[0]])
                ids.push(root.handles[handle[0]]);
            else if (handle)
                lookups.push(handle[0]);
        }
        let outstanding = lookups.length;
        if (outstanding === 0) {
            then(ids);
            return;
        }
        for (const handle of lookups)
            root.send("GET", `${root.api}/channels?part=id&forHandle=${encodeURIComponent(handle)}&fields=items/id`, null, function (body) {
                const id = body?.items?.[0]?.id;
                if (id) {
                    root.handles = Object.assign({}, root.handles, { [handle]: id });
                    ids.push(id);
                } else {
                    console.warn("Feeds: no channel called", handle);
                }
                if (--outstanding === 0)
                    then(ids);
            }, function (why) {
                console.warn("Feeds: could not look up", handle, why);
                if (--outstanding === 0)
                    then(ids);
            });
    }

    function readChannels(ids: var): void {
        const channels = [...new Set(ids)];
        const byChannel = {};
        for (const id of channels)
            if (root.byChannel[id])
                byChannel[id] = root.byChannel[id];
        root.pool(channels.map(id => ({
                    url: `https://www.youtube.com/feeds/videos.xml?playlist_id=UULF${id.slice(2)}`,
                    got: text => byChannel[id] = root.parseVideos(text)
                })), () => {
            root.byChannel = byChannel;
            root.classify();
        });
    }

    // Ask the API about every video not asked about before, then publish.
    function classify(): void {
        const cutoff = Date.now() - root.days * 86400000;
        const recent = [].concat(...Object.values(root.byChannel)).filter(v => v.published > cutoff);
        const unknown = recent.filter(v => !(v.video in store.verdicts));
        const batches = [];
        for (let i = 0; i < unknown.length; i += 50)
            batches.push(unknown.slice(i, i + 50));
        let outstanding = batches.length;
        const verdicts = Object.assign({}, store.verdicts);
        const done = function () {
            // Older than the window, they will never be shown again.
            for (const [video, verdict] of Object.entries(verdicts))
                if (verdict.t < cutoff)
                    delete verdicts[video];
            store.verdicts = verdicts;
            root.videos = recent.filter(v => verdicts[v.video] && !verdicts[v.video].live)
                .map(v => Object.assign({}, v, { duration: verdicts[v.video].duration }))
                .sort((a, b) => b.published - a.published);
            root.loaded = true;
            root.prune(cutoff);
            root.save();
        };
        if (outstanding === 0) {
            done();
            return;
        }
        for (const batch of batches) {
            root.send("GET", `${root.api}/videos?part=contentDetails,liveStreamingDetails&id=${batch.map(v => v.video).join(",")}&fields=items(id,contentDetails/duration,liveStreamingDetails)`, null, function (body) {
                // A video the API does not return yet (still processing, or
                // private) gets no verdict and is asked about next poll.
                for (const item of body?.items ?? []) {
                    const v = batch.find(b => b.video === item.id);
                    verdicts[item.id] = {
                        live: item.liveStreamingDetails !== undefined,
                        duration: root.seconds(item.contentDetails?.duration ?? ""),
                        t: v ? v.published : Date.now()
                    };
                }
                if (--outstanding === 0)
                    done();
            }, function (why, status) {
                root.fail(why, status);
                if (--outstanding === 0)
                    done();
            });
        }
    }

    function readSources(): void {
        const urls = Settings.feedUrls;
        const read = {};
        root.pool(urls.map(url => ({
                    url: url,
                    got: text => read[url] = root.parseStories(text)
                })), () => {
            root.sources = urls.map(url => {
                const source = read[url] ?? root.sources.find(s => s.url === url);
                return source ? Object.assign({ url: url }, source) : null;
            }).filter(s => s !== null && s.items.length > 0);
        });
    }

    // Plain GETs, a few at a time, each counted as a request of the base's
    // so the module stays dim until they are in. A feed that fails keeps
    // whatever it said last (the caller's fallback); one dead channel is not
    // trouble worth a warning on the bar.
    function pool(jobs: var, done: var): void {
        let next = 0;
        let outstanding = jobs.length;
        if (outstanding === 0) {
            done();
            return;
        }
        root.requests++;
        const finish = root.settle(done);
        const start = function () {
            if (next >= jobs.length)
                return;
            const job = jobs[next++];
            const landed = function () {
                if (--outstanding === 0)
                    finish();
                else
                    start();
            };
            Http.send("GET", job.url, null, {}, root.timeoutMs, function (xhr) {
                if (xhr.status >= 200 && xhr.status < 300)
                    try {
                        job.got(String(xhr.responseText));
                    } catch (error) {
                        console.warn("Feeds: unreadable feed", job.url, error);
                    }
                landed();
            }, landed);
        };
        for (let i = 0; i < Math.min(root.parallel, jobs.length); i++)
            start();
    }

    // --- reading the feeds ---------------------------------------------------
    // Regular expressions rather than a parser: both shapes are machine-made
    // and flat, and QML's XMLHttpRequest has no DOM worth the name.
    function tag(xml: string, name: string): string {
        const m = xml.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`));
        return m ? root.text(m[1]) : "";
    }

    function text(raw: string): string {
        return raw.replace(/^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/, "$1")
            .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
            .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
            .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&amp;/g, "&").trim();
    }

    function parseVideos(xml: string): var {
        return (xml.match(/<entry>[\s\S]*?<\/entry>/g) ?? []).map(entry => {
            const video = root.tag(entry, "yt:videoId");
            return {
                id: "yt:" + video,
                video: video,
                title: root.tag(entry, "title"),
                channel: root.tag(root.tag(entry, "author"), "name"),
                published: Date.parse(root.tag(entry, "published")),
                url: `https://www.youtube.com/watch?v=${video}`,
                // 16:9, where the feed's own hqdefault is letterboxed 4:3.
                thumb: `https://i.ytimg.com/vi/${video}/mqdefault.jpg`
            };
        }).filter(v => v.video !== "" && !isNaN(v.published));
    }

    // RSS items, or Atom entries for a feed that speaks Atom. Points and
    // comment counts are hnrss's, read from the description when they are
    // there.
    function parseStories(xml: string): var {
        const atom = !/<item[\s>]/.test(xml);
        const blocks = xml.match(atom ? /<entry[\s>][\s\S]*?<\/entry>/g : /<item[\s>][\s\S]*?<\/item>/g) ?? [];
        const head = xml.slice(0, xml.search(atom ? /<entry[\s>]/ : /<item[\s>]/));
        const items = blocks.map(block => {
            const link = atom ? (block.match(/<link[^>]*href="([^"]+)"/)?.[1] ?? "") : root.tag(block, "link");
            const about = root.tag(block, "description");
            const points = about.match(/Points:\s*(\d+)/);
            const replies = about.match(/# Comments:\s*(\d+)/);
            return {
                id: root.tag(block, atom ? "id" : "guid") || link,
                title: root.tag(block, "title"),
                url: root.text(link),
                comments: root.tag(block, "comments"),
                points: points ? Number(points[1]) : -1,
                replies: replies ? Number(replies[1]) : -1,
                published: Date.parse(root.tag(block, atom ? "published" : "pubDate") || root.tag(block, "updated"))
            };
        }).filter(i => i.id !== "" && !isNaN(i.published)).sort((a, b) => b.published - a.published);
        return {
            title: root.tag(head, "title"),
            items: items.slice(0, root.storiesShown)
        };
    }

    // ISO 8601 durations as YouTube writes them: P1DT2H3M4S at the most.
    function seconds(iso: string): int {
        const m = iso.match(/P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?/);
        return m ? ((Number(m[1] ?? 0) * 24 + Number(m[2] ?? 0)) * 60 + Number(m[3] ?? 0)) * 60 + Number(m[4] ?? 0) : 0;
    }

    function clock(total: int): string {
        const pad = n => n < 10 ? "0" + n : String(n);
        const h = Math.floor(total / 3600);
        const m = Math.floor(total % 3600 / 60);
        return h > 0 ? `${h}:${pad(m)}:${pad(total % 60)}` : `${m}:${pad(total % 60)}`;
    }

    // "now", "4m", "2h", "3d": the notification centre's short ages.
    function age(published: real, now: real): string {
        const s = Math.max(0, (now - published) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return `${Math.floor(s / 60)}m`;
        if (s < 86400)
            return `${Math.floor(s / 3600)}h`;
        return `${Math.floor(s / 86400)}d`;
    }

    // --- memory --------------------------------------------------------------
    // Only what is still in the window is worth remembering as seen.
    function prune(cutoff: real): void {
        const seen = {};
        for (const [id, t] of Object.entries(store.seen))
            if (t >= cutoff || root.sources.some(s => s.items.some(i => i.id === id)))
                seen[id] = t;
        store.seen = seen;
    }

    property bool restored: false

    function save(): void {
        if (root.restored)
            file.writeAdapter();
    }

    FileView {
        id: file

        path: Paths.state("feeds.json")
        printErrors: false
        onLoaded: root.restore()
        onLoadFailed: root.restore()

        JsonAdapter {
            id: store

            // Before the first run, two days back, so there is something to
            // see on day one without the whole week arriving as new.
            property real since: 0
            property var seen: ({})
            property var verdicts: ({})
        }
    }

    function restore(): void {
        if (root.restored)
            return;
        if (!store.since)
            store.since = Date.now() - 2 * 86400000;
        root.restored = true;
        root.save();
    }
}
