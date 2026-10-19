pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// New videos from YouTube channels and new stories from a few RSS feeds,
// counted on the bar until they have been opened.
//
// The channels are the subscriptions of the account YouTubeAccount signs in
// as (often a brand account, which is why it is not the main Google one),
// plus Settings.feedChannels, which can name ones you do not subscribe to.
// Their videos come from YouTube's public feeds rather than the API: those
// cost no quota, and the UULF playlist they are read from is a channel's
// uploads without its Shorts. Those feeds fail a random share of requests
// (two in three, 2026-10-19), whatever the channel, so a failed one tries the
// channel's own feed, Shorts dropped by their links, then keeps what it had.
// Only a channel not heard from in `staleMs` reads the playlist through the
// API. Lives and premieres are in it too, and only the API can tell them
// apart, so every new video is asked about once (videos.list, fifty to a
// request) and the answer is kept. Each list call costs one unit of the
// project's 10,000 a day; a refresh is otherwise free, so anything may ask
// for one.
//
// The RSS feeds need no sign-in and are read whether YouTube is connected or
// not, so this is its own service rather than a GoogleService.
//
// Seen is per item, and "Mark All Seen" sees each one listed. Only the unseen
// are listed and counted; opening one or swiping it away sees it, and so
// does opening it in a browser on this machine (its history, read by
// scripts/feeds-seen.py).
// YouTube's API dropped watch history, so a phone or a TV cannot tell.
Singleton {
    id: root

    readonly property string api: "https://www.googleapis.com/youtube/v3"
    readonly property string web: "https://www.youtube.com/feed/subscriptions"

    // A channel posts a few times a week; half an hour is plenty, and the
    // feeds are fetched without quota anyway.
    readonly property int pollMs: 30 * 60000
    readonly property int retryMs: 2 * 60000
    // How far back videos look, and how many RSS stories appear at a time.
    readonly property int days: 7
    readonly property int storiesShown: 20
    // Feeds fetched at once. Enough to finish a hundred channels in seconds,
    // few enough not to look like a crawler.
    readonly property int parallel: 6
    readonly property int timeoutMs: 15000
    // How long a channel's public feeds may keep failing before the API is
    // asked instead, and how long the subscriptions and a handle that names
    // no channel are believed. A video the API did not return (private,
    // removed, still processing) is asked about again after `staleMs` too.
    readonly property int staleMs: 2 * 3600000
    readonly property int subscriptionsMs: 6 * 3600000
    readonly property int unknownHandleMs: 24 * 3600000

    // --- state ---------------------------------------------------------------
    // Newest first: {id, video, title, channel, published, duration, url,
    // thumb}; duration is -1 when the API could not be asked.
    property var videos: []
    // One per feed URL, in settings order: {title, url, items}, each item
    // {id, title, url, summary, thumb, comments, points, replies, published}.
    property var sources: []

    // When the subscriptions (store.subscribed) were last read; zero reads
    // them next refresh.
    property real subscribedAt: 0

    // Whether anything has been heard back yet, and what went wrong since.
    // RetryButton reads `retryable`, `loading` and `retryNow`.
    property bool loaded: false
    property string trouble: ""
    property int requests: 0
    // A refresh asked for while one was out: run when it lands, so a sign-in
    // that finishes mid-read is not left until the next poll.
    property bool again: false
    readonly property bool loading: root.requests > 0
    readonly property bool stale: !root.loaded
    readonly property bool retryable: root.trouble !== "" && !YouTubeAccount.needsConsent
    readonly property bool connected: !YouTubeAccount.needsConsent

    // What the popup lists and the badge counts. Videos from before the
    // first run are not news; every story still in its feed is.
    readonly property var unseenVideos: root.videos.filter(v => v.published > store.since && root.unseen(v))
    readonly property var unseenSources: root.sources
        .map(s => Object.assign({}, s, {
            title: (Settings.feedTitles[s.url] ?? "").trim() || s.title,
            items: s.items.filter(i => root.unseen(i))
        }))
        .filter(s => s.items.length > 0)
    readonly property int count: root.unseenVideos.length + root.unseenSources.reduce((n, s) => n + s.items.length, 0)
    readonly property string icon: Theme.glyph.feeds
    readonly property string label: root.count === 0 ? "" : String(Math.min(root.count, 99))

    readonly property string tooltip: {
        if (root.trouble !== "")
            return root.trouble;
        if (!root.loaded)
            return "Reading feeds…";
        return root.count === 0 ? "Nothing new" : `${root.count} new`;
    }

    function unseen(item: var): bool {
        return !(item.id in store.seen);
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

    // Each one listed, not a cutoff: a story can reach hnrss's points
    // threshold hours after it was posted, and a video waiting on its
    // verdict has not been shown yet.
    function markAllSeen(): void {
        root.remember();
        root.markSeen(root.unseenItems());
    }

    // A swipe in the popup: seen, with an undo.
    function hide(item: var): void {
        root.remember();
        root.markSeen([item]);
    }

    // What seen was before each hide, latest last, for the popup's Undo.
    // Nothing is sent anywhere, so nothing has to wait: the popup clears
    // them as it closes.
    property var undos: []

    function remember(): void {
        root.undos = root.undos.concat([store.seen]);
    }

    function undo(): void {
        if (root.undos.length === 0)
            return;
        store.seen = root.undos[root.undos.length - 1];
        root.undos = root.undos.slice(0, -1);
        root.save();
    }

    // One section open in the popup, by "videos" or a feed's URL, remembered.
    function unfolded(section: string): bool {
        return store.open === section;
    }

    function toggle(section: string): void {
        store.open = root.unfolded(section) ? "" : section;
        root.save();
    }

    // --- polling -------------------------------------------------------------
    function refresh(): void {
        if (root.loading) {
            root.again = true;
            return;
        }
        root.trouble = "";
        retry.stop();
        root.hold(() => {
            root.readSources();
            if (root.connected && root.restored)
                root.readSubscriptions(() => root.resolve(Settings.feedChannels,
                    extra => root.readChannels(store.subscribed.concat(extra))));
        })();
    }

    function retryNow(): void {
        root.refresh();
    }

    // Wraps a callback so the module stays dim until the last request of a
    // refresh has landed, however the requests chain.
    function hold(callback: var): var {
        root.requests++;
        return function (...args) {
            try {
                callback(...args);
            } finally {
                if (--root.requests === 0) {
                    root.loaded = true;
                    if (root.again) {
                        root.again = false;
                        Qt.callLater(root.refresh);
                    }
                }
            }
        };
    }

    // One YouTube Data API GET. `fail` defaults to setting `trouble`. Once
    // the day's quota is gone it fails without asking, until the reset.
    function get(path: string, then: var, fail: var): void {
        // One hold, settled once whichever way it ends.
        const settle = root.hold((ok, args) => ok ? then(...args) : (fail ?? root.fail)(...args));
        const bad = (...args) => settle(false, args);
        if (Date.now() < store.quotaUntil)
            bad("Quota used up", 403, "quotaExceeded");
        else
            YouTubeAccount.authorised(() => YouTubeAccount.send("GET", `${root.api}/${path}`, null, (...args) => settle(true, args), bad), bad);
    }

    function fail(why: string, status: int, reason: var): void {
        if (reason === "quotaExceeded" || reason === "dailyLimitExceeded") {
            if (Date.now() >= store.quotaUntil) {
                store.quotaUntil = root.quotaReset(Date.now());
                root.save();
            }
            root.trouble = `YouTube quota used up until ${Qt.formatTime(new Date(store.quotaUntil), "HH:mm")}`;
        } else if (reason === "accessNotConfigured" || reason === "SERVICE_DISABLED") {
            root.trouble = "Enable the YouTube Data API v3 in the Google console";
        } else {
            root.trouble = why;
        }
        if (status === 0 || status === 408 || status === 429 || status >= 500 || /rateLimitExceeded/i.test(reason ?? ""))
            retry.restart();
    }

    // Quota resets at midnight Pacific, 07:00 or 08:00 UTC by the season;
    // the later, so a spent day never asks an hour early.
    function quotaReset(now: real): real {
        const reset = new Date(now);
        reset.setUTCHours(8, 0, 0, 0);
        return reset.getTime() > now ? reset.getTime() : reset.getTime() + 86400000;
    }

    Timer {
        interval: root.pollMs
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: retry
        interval: root.retryMs
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    // The sign-in landed, at startup or after Connect, maybe as another
    // account: read its subscriptions afresh.
    Connections {
        target: YouTubeAccount

        function onReady(): void {
            root.subscribedAt = 0;
            root.refresh();
        }
    }

    Connections {
        target: WallClock

        function onWokeUp(): void {
            root.refresh();
        }
    }

    Connections {
        target: Settings

        function onFeedUrlsChanged(): void { root.refresh(); }
        function onFeedChannelsChanged(): void { root.refresh(); }
    }

    // --- the browser's history -----------------------------------------------
    // Check all retained browser history for available items, including the
    // RSS stories beyond the first page. Run after each poll, on opening,
    // and every few minutes. Only the feed links are looked for.
    readonly property int historyMs: 5 * 60000

    // Every item listed, and the links each can be opened by.
    function unseenItems(): var {
        return root.unseenVideos.concat(...root.unseenSources.map(s => s.items));
    }

    function links(items: var): var {
        const all = new Set();
        for (const item of items)
            for (const link of [item.url, item.comments])
                if (link)
                    all.add(link);
        return [...all];
    }

    // All of the history for links not looked for before, else only what was
    // visited since the last look (a minute's overlap), which the script can
    // skip without opening a database that has not changed since. A look
    // counts once it read every history: the script exits 1 if one failed.
    property var checkedLinks: new Set()
    property real checkedAt: 0
    property var checking: null

    function checkHistory(): void {
        const links = root.links(root.unseenItems());
        if (history.running || links.length === 0)
            return;
        const since = links.every(link => root.checkedLinks.has(link)) ? Math.floor(root.checkedAt / 1000) - 60 : 0;
        root.checking = { links: new Set(links), at: Date.now() };
        history.command = ["python3", "-I", Quickshell.shellPath("scripts/feeds-seen.py"),
            String(Math.max(0, since)), ...links];
        history.running = true;
    }

    function seenInBrowser(text: string): void {
        const opened = new Set(text.split("\n").filter(line => line !== ""));
        const items = root.unseenItems().filter(i => opened.has(i.url) || opened.has(i.comments));
        if (items.length > 0)
            root.markSeen(items);
    }

    Process {
        id: history
        stdout: StdioCollector {
            onStreamFinished: root.seenInBrowser(text)
        }
        onExited: function (exitCode) {
            if (exitCode === 0) {
                root.checkedLinks = root.checking.links;
                root.checkedAt = root.checking.at;
            }
        }
    }

    Timer {
        interval: root.historyMs
        running: root.count > 0
        repeat: true
        onTriggered: root.checkHistory()
    }

    onLoadingChanged: if (!root.loading)
        root.checkHistory()

    // --- fetching ------------------------------------------------------------
    // The subscriptions, every page, unless read within `subscriptionsMs`.
    // A failed read keeps the last list, saved, so a restart that cannot read
    // them (the quota spent) drops no channel's videos.
    function readSubscriptions(then: var): void {
        if (Date.now() - root.subscribedAt < root.subscriptionsMs) {
            then();
            return;
        }
        root.readSubscriptionPage("", [], ids => {
            if (ids !== null) {
                store.subscribed = ids;
                root.subscribedAt = Date.now();
            }
            then();
        });
    }

    // Every page from `token` on, or null if one failed.
    function readSubscriptionPage(token: string, ids: var, then: var): void {
        const page = token === "" ? "" : `&pageToken=${encodeURIComponent(token)}`;
        root.get(`subscriptions?part=snippet&mine=true&maxResults=50&fields=nextPageToken,items/snippet(resourceId/channelId)${page}`, function (body) {
            const all = ids.concat((body?.items ?? []).map(item => item.snippet.resourceId.channelId));
            if (body?.nextPageToken)
                root.readSubscriptionPage(body.nextPageToken, all, then);
            else
                then(all);
        }, function (why, status, reason) {
            root.fail(why, status, reason);
            then(null);
        });
    }

    // Settings.feedChannels to channel ids: an id as it is, or inside a
    // /channel/ link; an @handle, bare or in a link, looked up once and kept
    // (store.handles). A handle that names no channel is believed for
    // `unknownHandleMs`; one whose lookup failed is asked again next time.
    function resolve(entries: var, then: var): void {
        const ids = [];
        const lookups = [];
        for (const entry of entries) {
            const id = String(entry).match(/UC[\w-]{22}/);
            const handle = String(entry).match(/@[\w.-]+/)?.[0];
            const known = handle ? store.handles[handle] : undefined;
            if (id)
                ids.push(id[0]);
            else if (known?.id)
                ids.push(known.id);
            else if (handle && !(known && Date.now() - known.t < root.unknownHandleMs))
                lookups.push(handle);
        }
        let outstanding = lookups.length;
        if (outstanding === 0) {
            then(ids);
            return;
        }
        const landed = function () {
            if (--outstanding === 0) {
                root.save();
                then(ids);
            }
        };
        for (const handle of lookups)
            root.get(`channels?part=id&forHandle=${encodeURIComponent(handle)}&fields=items/id`, function (body) {
                const id = body?.items?.[0]?.id ?? "";
                store.handles = Object.assign({}, store.handles, { [handle]: { id: id, t: Date.now() } });
                if (id)
                    ids.push(id);
                else
                    console.warn("Feeds: no channel called", handle);
                landed();
            }, function (why, status, reason) {
                console.warn("Feeds: could not look up", handle, why);
                if (reason === "quotaExceeded" || reason === "dailyLimitExceeded")
                    root.fail(why, status, reason);
                landed();
            });
    }

    // Each channel's videos within the window, merged into what it said
    // before (store.channels, {t, videos}), so a feed that fails, or a
    // channel feed crowded with Shorts, drops nothing already known. An ask
    // that fails waits out `staleMs` like one that answers, so a playlist the
    // API has not got, or an outage, is not paid for every poll.
    function readChannels(ids: var): void {
        const channels = [...new Set(ids)];
        const started = Date.now();
        const read = {};
        const asked = new Set();
        root.pool(channels.map(id => ({
                    urls: [`https://www.youtube.com/feeds/videos.xml?playlist_id=UULF${id.slice(2)}`,
                        `https://www.youtube.com/feeds/videos.xml?channel_id=${id}`],
                    got: text => read[id] = root.parseVideos(text),
                    failed: done => {
                        if (started - (store.channels[id]?.t ?? 0) < root.staleMs) {
                            done();
                            return;
                        }
                        asked.add(id);
                        root.get(`playlistItems?part=snippet&playlistId=UULF${id.slice(2)}&maxResults=15&fields=items/snippet(publishedAt,title,videoOwnerChannelTitle,resourceId/videoId)`, body => {
                            read[id] = (body?.items ?? []).map(item => root.video(item.snippet.resourceId.videoId,
                                item.snippet.title, item.snippet.videoOwnerChannelTitle ?? "", Date.parse(item.snippet.publishedAt)))
                                .filter(v => v.video && !isNaN(v.published));
                            done();
                        }, (why, status, reason) => {
                            // No long uploads at all: nothing to say.
                            if (status !== 404)
                                root.fail(why, status, reason);
                            done();
                        });
                    }
                })), () => {
            const cutoff = Date.now() - root.days * 86400000;
            const kept = {};
            for (const id of channels) {
                const before = store.channels[id];
                if (!read[id] && !asked.has(id) && !before)
                    continue;
                const merged = {};
                for (const v of (before?.videos ?? []).concat(read[id] ?? []))
                    if (v.published > cutoff)
                        merged[v.video] = { video: v.video, title: v.title, channel: v.channel, published: v.published };
                kept[id] = { t: read[id] || asked.has(id) ? started : before.t, videos: Object.values(merged) };
            }
            store.channels = kept;
            root.classify();
        });
    }

    // Ask the API about every video not asked about before, then publish.
    // One the API leaves out is asked about again after `staleMs`; if the
    // API cannot be asked at all, the unasked are shown rather than held
    // back, lives and all, until it can.
    function classify(): void {
        const now = Date.now();
        const cutoff = now - root.days * 86400000;
        const recent = [].concat(...Object.values(store.channels).map(c => c.videos)).filter(v => v.published > cutoff);
        const verdicts = Object.assign({}, store.verdicts);
        const unknown = recent.filter(v => !verdicts[v.video] || verdicts[v.video].retry < now);
        const batches = [];
        for (let i = 0; i < unknown.length; i += 50)
            batches.push(unknown.slice(i, i + 50));
        let outstanding = batches.length;
        let failed = false;
        const done = function () {
            // Older than the window, they will never be shown again.
            for (const [video, verdict] of Object.entries(verdicts))
                if (verdict.t < cutoff)
                    delete verdicts[video];
            store.verdicts = verdicts;
            root.videos = recent.filter(v => verdicts[v.video] ? verdicts[v.video].live === false : failed)
                .map(v => Object.assign(root.video(v.video, v.title, v.channel, v.published),
                    { duration: verdicts[v.video]?.duration ?? -1 }))
                .sort((a, b) => b.published - a.published);
            root.prune(cutoff);
            root.save();
        };
        if (outstanding === 0) {
            done();
            return;
        }
        for (const batch of batches) {
            root.get(`videos?part=contentDetails,liveStreamingDetails&id=${batch.map(v => v.video).join(",")}&fields=items(id,contentDetails/duration,liveStreamingDetails)`, function (body) {
                for (const v of batch)
                    verdicts[v.video] = { t: v.published, retry: now + root.staleMs };
                for (const item of body?.items ?? [])
                    verdicts[item.id] = {
                        live: item.liveStreamingDetails !== undefined,
                        duration: root.seconds(item.contentDetails?.duration ?? ""),
                        t: verdicts[item.id]?.t ?? now
                    };
                if (--outstanding === 0)
                    done();
            }, function (why, status, reason) {
                failed = true;
                root.fail(why, status, reason);
                if (--outstanding === 0)
                    done();
            });
        }
    }

    function readSources(): void {
        const urls = Settings.feedUrls;
        const read = {};
        root.pool(urls.map(url => ({
                    urls: [url],
                    got: text => read[url] = root.parseStories(text, url)
                })), () => {
            root.sources = urls.map(url => {
                const source = read[url] ?? root.sources.find(s => s.url === url);
                return source ? Object.assign({ url: url }, source) : null;
            }).filter(s => s !== null && s.items.length > 0);
            // With every feed in hand, forget stories seen that have left
            // their feed a month ago: they will not be listed again. An
            // empty answer is not in hand; it may be a broken page.
            if (urls.every(url => read[url]?.items.length > 0))
                root.forgetStories(Date.now() - 30 * 86400000);
        });
    }

    // Plain GETs, a few jobs at a time, held like the API's so the module
    // stays dim until they are in. A job tries its URLs in turn and, if none
    // answers, its `failed` (the caller's fallback); one dead channel is not
    // trouble worth a warning on the bar.
    function pool(jobs: var, done: var): void {
        let next = 0;
        let outstanding = jobs.length;
        if (outstanding === 0) {
            done();
            return;
        }
        const finish = root.hold(done);
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
            const attempt = function (i) {
                if (i >= job.urls.length) {
                    job.failed ? job.failed(landed) : landed();
                    return;
                }
                Http.send("GET", job.urls[i], null, {}, root.timeoutMs, function (xhr) {
                    if (xhr.status < 200 || xhr.status >= 300) {
                        attempt(i + 1);
                        return;
                    }
                    try {
                        job.got(String(xhr.responseText));
                    } catch (error) {
                        console.warn("Feeds: unreadable feed", job.urls[i], error);
                    }
                    landed();
                }, () => attempt(i + 1));
            };
            attempt(0);
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

    function video(id: string, title: string, channel: string, published: real): var {
        return {
            id: "yt:" + id,
            video: id,
            title: title,
            channel: channel,
            published: published,
            url: `https://www.youtube.com/watch?v=${id}`,
            // 16:9, where the feed's own hqdefault is letterboxed 4:3.
            thumb: `https://i.ytimg.com/vi/${id}/mqdefault.jpg`
        };
    }

    // A channel's own feed has its Shorts too, linked as /shorts/.
    function parseVideos(xml: string): var {
        return (xml.match(/<entry>[\s\S]*?<\/entry>/g) ?? [])
            .filter(entry => !/<link\b[^>]*\/shorts\//.test(entry))
            .map(entry => root.video(root.tag(entry, "yt:videoId"), root.tag(entry, "title"),
                root.tag(root.tag(entry, "author"), "name"), Date.parse(root.tag(entry, "published"))))
            .filter(v => v.video !== "" && !isNaN(v.published));
    }

    // Attributes occur in both XML media tags and decoded HTML images.
    function attribute(tag: string, name: string): string {
        const match = tag.match(new RegExp(`\\s${name}\\s*=\\s*(["'])([\\s\\S]*?)\\1`, "i"));
        return match ? root.text(match[2]) : "";
    }

    // Resolve feed links without letting embedded content load local files.
    function feedUrl(value: string, base: string): string {
        if (!value)
            return "";
        if (/^https?:\/\//i.test(value))
            return value;
        const origin = (base || "").match(/^(https?:)\/\/([^/]+)(\/[^?#]*)?/i);
        if (!origin || /^[a-z][a-z\d+.-]*:/i.test(value))
            return "";
        if (value.startsWith("//"))
            return origin[1] + value;
        const path = value.startsWith("/") ? value : (origin[3] || "/").replace(/[^/]*$/, "") + value;
        const parts = [];
        for (const part of path.split("/")) {
            if (part === "..") {
                if (parts.length > 1)
                    parts.pop();
            } else if (part !== ".")
                parts.push(part);
        }
        return origin[1] + "//" + origin[2] + parts.join("/");
    }

    // Feed HTML stays plain text; only the first few lines reach the popup.
    function summary(html: string, source: string): string {
        if (/^https?:\/\/(?:www\.)?lobste\.rs(?:[/:?#]|$)/i.test(source || ""))
            html = html.replace(/<p\b[^>]*>\s*<a\b[^>]*>\s*Comments\s*<\/a>\s*<\/p>/gi, "");
        if (/^https?:\/\/(?:www\.)?smbc-comics\.com(?:[/:?#]|$)/i.test(source || ""))
            html = html.replace(/Today['’]s News:\s*(?:<br\s*\/?>\s*)*$/i, "");
        const entities = { nbsp: " ", copy: "©", ndash: "–", mdash: "—", hellip: "…",
            lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”" };
        return root.text(html.replace(/<!--[\s\S]*?-->/g, " ")
            .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, " ")
            .replace(/<p\b[^>]*>\s*(?:Article URL|Comments URL|Points|# Comments):[\s\S]*?<\/p>/gi, " ")
            .replace(/<\/?(?:p|div|br|li|h[1-6])\b[^>]*>/gi, " ")
            .replace(/<[^>]*>/g, ""))
            .replace(/&([a-z]+);/gi, (match, name) => entities[name.toLowerCase()] ?? match)
            .replace(/\s+/g, " ").trim().slice(0, 600);
    }

    // Prefer feed media, then the image embedded in its description or content.
    function storyThumb(block: string, html: string, base: string): string {
        const media = block.match(/<(?:media:thumbnail|media:content|enclosure)\b[^>]*>/gi) ?? [];
        for (const tag of media) {
            const type = root.attribute(tag, "type");
            if (!/^<media:thumbnail\b/i.test(tag) && !type.startsWith("image/")
                    && root.attribute(tag, "medium") !== "image")
                continue;
            const url = root.feedUrl(root.attribute(tag, "url"), base);
            if (url)
                return url;
        }
        for (const tag of html.match(/<img\b[^>]*>/gi) ?? []) {
            const url = root.feedUrl(root.attribute(tag, "src"), base);
            if (url)
                return url;
        }
        return "";
    }

    // RSS items, or Atom entries for a feed that speaks Atom. Points and
    // comment counts are hnrss's, read from the description when they are
    // there. Scored stories rank highest first; the rest stay newest first.
    function parseStories(xml: string, feed: string): var {
        const atom = !/<item[\s>]/.test(xml);
        const blocks = xml.match(atom ? /<entry[\s>][\s\S]*?<\/entry>/g : /<item[\s>][\s\S]*?<\/item>/g) ?? [];
        const head = xml.slice(0, xml.search(atom ? /<entry[\s>]/ : /<item[\s>]/));
        const items = blocks.map(block => {
            const links = atom ? (block.match(/<link\b[^>]*>/g) ?? []) : [];
            const alternate = links.find(tag => ["", "alternate"].includes(root.attribute(tag, "rel"))) ?? "";
            const link = root.feedUrl(atom ? root.attribute(alternate, "href") : root.tag(block, "link"), feed);
            const about = root.tag(block, "description") || root.tag(block, "summary");
            const content = root.tag(block, "content:encoded") || root.tag(block, "content");
            const summary = root.summary(about, feed || link) || root.summary(content, feed || link);
            const points = about.match(/Points:\s*(\d+)/);
            const replies = about.match(/# Comments:\s*(\d+)/);
            return {
                id: root.tag(block, atom ? "id" : "guid") || link,
                title: root.tag(block, "title"),
                url: link,
                summary: summary,
                thumb: root.storyThumb(block, about + content, link || feed),
                comments: root.tag(block, "comments"),
                points: points ? Number(points[1]) : -1,
                replies: replies ? Number(replies[1]) : -1,
                published: Date.parse(root.tag(block, atom ? "published" : "pubDate") || root.tag(block, "updated"))
            };
        }).filter(i => i.id !== "" && !isNaN(i.published))
            .sort((a, b) => b.points - a.points || b.published - a.published);
        return {
            title: root.tag(head, "title"),
            items: items
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
    // Videos expire with their window; stories wait for forgetStories.
    function prune(cutoff: real): void {
        const seen = {};
        for (const [id, t] of Object.entries(store.seen))
            if (!id.startsWith("yt:") || t >= cutoff)
                seen[id] = t;
        store.seen = seen;
    }

    // A story seen stays seen while any feed still lists it, however old:
    // a blog's feed can hold a year of posts. Gone from them all and older
    // than `cutoff`, it is forgotten.
    function forgetStories(cutoff: real): void {
        const listed = new Set([].concat(...root.sources.map(s => s.items.map(i => i.id))));
        const seen = {};
        for (const [id, t] of Object.entries(store.seen))
            if (id.startsWith("yt:") || t >= cutoff || listed.has(id))
                seen[id] = t;
        store.seen = seen;
        root.save();
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

            // Videos start two days back; RSS has no date cutoff.
            property real since: 0
            // Item id to its published time.
            property var seen: ({})
            // Video id to {live, duration, t}, or {t, retry} when the API
            // left it out.
            property var verdicts: ({})
            // Channel id to {t: last read or asked, videos: [{video, title,
            // channel, published}]}, within the window.
            property var channels: ({})
            // The subscribed channel ids as last read.
            property var subscribed: []
            // @handle to {id, t}; id "" when it named no channel.
            property var handles: ({})
            // Until when the day's API quota is spent.
            property real quotaUntil: 0
            // The popup section left open.
            property string open: ""
        }
    }

    // What the channels said last is in, so a channel's age is known before
    // its feeds are read: only now do videos refresh.
    function restore(): void {
        if (root.restored)
            return;
        if (!store.since)
            store.since = Date.now() - 2 * 86400000;
        root.restored = true;
        root.save();
        root.refresh();
    }
}
