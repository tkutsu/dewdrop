import QtQuick
import Quickshell

// Shared polling, token acquisition, retries, and parallel fetches for Google services.
Singleton {
    id: base

    // The service's name in a message that has to say which API is at fault.
    property string service: "Google"
    property int pollMs: 5 * 60000
    property bool polling: true

    // Whether anything has been heard back yet. Modules dim themselves until
    // this turns — a count of zero because the network is down should not
    // read as a clear list.
    property bool loaded: false
    property string trouble: ""
    property int requests: 0
    property bool checking: false
    property bool checkFailed: false
    readonly property bool loading: requests > 0
    readonly property bool retryable: trouble !== "" && !Google.needsConsent
    readonly property bool stale: !loaded || trouble !== "" || Google.needsConsent

    Retry {
        id: recovery
        active: base.configured && base.polling && !Google.needsConsent && !base.loading
        onTriggered: base.refresh()
    }

    readonly property bool configured: Google.configured
    readonly property string today: Google.today

    // What a refresh does once a token is in hand.
    signal fetch

    function dayString(date: var): string {
        return Google.dayString(date);
    }

    function authorised(then: var, fail: var): void {
        base.requests++;
        Google.authorised(base.settle(then), base.settle(fail ?? base.fail));
    }

    function refresh(): void {
        if (base.loading)
            return;
        recovery.cancel();
        base.checking = true;
        base.checkFailed = false;
        base.authorised(() => base.fetch());
    }

    function retryNow(): void {
        recovery.retryNow();
    }

    // Count the whole callback chain, so pages and parallel GETs finish before
    // declaring recovery. One successful reply cannot hide another's failure.
    function settle(callback: var): var {
        return function (...args) {
            try {
                callback(...args);
            } finally {
                base.requests--;
                if (base.requests === 0 && base.checking) {
                    base.checking = false;
                    if (!base.checkFailed) {
                        base.trouble = "";
                        recovery.reset();
                    }
                }
            }
        };
    }

    // The sign-in and the status codes are Google.qml's; what is kept here is
    // what a failure means for the bar. `fail` is optional and defaults to
    // setting `trouble`; a caller that gives its own still has to do that.
    function send(method: string, url: string, body: var, then: var, fail: var): void {
        // A parallel success must not erase another request's failure.
        base.requests++;
        const rejected = base.settle(fail ?? base.fail);
        Google.authorised(() => Google.send(method, url, body, base.settle(then), rejected), rejected);
    }

    function fail(why: string, status: int): void {
        // A 403 that is not a missing scope (Google.send says which) is the
        // API switched off on the project, which only the console can fix.
        base.trouble = status === 403 && why !== Google.reconnect ? `${base.service} API not enabled in the Google console` : why;
        base.checkFailed = true;
        if (!Google.needsConsent && why !== Google.reconnect && (status === 0 || status === 408 || status === 429 || status >= 500))
            recovery.schedule();
        else
            recovery.reset();
    }

    // --- gathering -----------------------------------------------------------
    // Several GETs at once, every page of each, handed on together when the
    // last one lands. The replies arrive in whatever order the network gives
    // them, so a list built up as they came would reorder itself under the
    // pointer on every poll; `done` gets them all at once instead.
    //
    // `sources` is a list of {url, ...} — the rest is context, given back to
    // `item(raw, source)` along with each raw item so it can be mapped, or
    // dropped by returning null. `done(items, failed)` gets what arrived and
    // the statuses of the requests that did not, so the caller can decide
    // whether a partial answer is worth publishing.
    //
    // Generations, one per key: a gather started later for the same key makes
    // every reply from an earlier one stale. Without that a slow poll could
    // land after the refetch that followed a tick and put the ticked row back.
    property var generations: ({})

    function gather(key: string, sources: var, item: var, done: var): void {
        const gen = (base.generations[key] ?? 0) + 1;
        base.generations[key] = gen;

        const gathered = [];
        const failed = [];
        let outstanding = sources.length;
        const current = () => base.generations[key] === gen;
        const landed = function () {
            outstanding--;
            if (outstanding === 0)
                done(gathered, failed);
        };

        // Each source is walked page by page: Google caps a reply at a few
        // hundred items and hands back a token for the rest, and a list longer
        // than one page is exactly the one whose tail matters.
        const page = function (source, token) {
            const url = token === "" ? source.url : `${source.url}&pageToken=${encodeURIComponent(token)}`;
            base.send("GET", url, null, function (body) {
                if (!current())
                    return;
                for (const raw of body.items ?? []) {
                    const mapped = item(raw, source);
                    if (mapped !== null)
                        gathered.push(mapped);
                }
                if (body.nextPageToken)
                    page(source, body.nextPageToken);
                else
                    landed();
            }, function (why, status) {
                if (!current())
                    return;
                base.fail(why, status);
                failed.push(status);
                landed();
            });
        };

        if (sources.length === 0) {
            done(gathered, failed);
            return;
        }
        for (const source of sources)
            page(source, "");
    }

    // --- lifecycle -----------------------------------------------------------
    // Google.qml reads the credentials; this only has to notice when they have
    // arrived. Both paths, because which one runs depends on whether the file
    // landed before or after the singleton was first touched.
    Component.onCompleted: if (base.configured && base.polling)
        base.refresh()

    onPollingChanged: if (base.polling && base.configured)
        base.refresh()

    Connections {
        target: Google

        function onReady(): void {
            if (base.polling)
                base.refresh();
        }
    }

    Connections {
        target: Google
        function onNeedsConsentChanged(): void {
            if (Google.needsConsent)
                recovery.reset();
        }
    }

    Connections {
        target: WallClock
        function onWokeUp(): void {
            if (base.configured && base.polling && !Google.needsConsent)
                base.refresh();
        }
    }

    Timer {
        interval: base.pollMs
        running: base.configured && base.polling && !Google.needsConsent && !base.loading && !recovery.pending
        repeat: true
        onTriggered: base.refresh()
    }
}
