import QtQuick
import Quickshell

// What a service built on the Google sign-in looks like from the outside, and
// the plumbing both of them (Tasks, Agenda) would otherwise carry twice: it
// polls, it says whether anything has been heard back yet, it keeps one line of
// trouble, and it fetches a set of things in parallel and publishes them in one
// go. The service itself only says what to fetch and what to make of it.
Singleton {
    id: base

    // The service's name in a message that has to say which API is at fault.
    property string service: "Google"
    property int pollMs: 5 * 60000

    // Whether anything has been heard back yet. Modules dim themselves until
    // this turns — a count of zero because the network is down should not
    // read as a clear list.
    property bool loaded: false
    property string trouble: ""

    readonly property bool configured: Google.configured
    readonly property string today: Google.today

    // What a refresh does once a token is in hand.
    signal fetch

    function dayString(date: var): string {
        return Google.dayString(date);
    }

    function authorised(then: var): void {
        Google.authorised(then, base.fail);
    }

    function refresh(): void {
        base.authorised(function () {
            base.trouble = "";
            base.fetch();
        });
    }

    // The sign-in and the status codes are Google.qml's; what is kept here is
    // what a failure means for the bar. `fail` is optional and defaults to
    // setting `trouble`; a caller that gives its own still has to do that.
    function send(method: string, url: string, body: var, then: var, fail: var): void {
        Google.send(method, url, body, function (parsed) {
            base.trouble = "";
            then(parsed);
        }, fail ?? base.fail);
    }

    function fail(why: string, status: int): void {
        // 403 is the one failure with a specific cause: the API is not enabled
        // on the project, or the token was granted before its scope was added.
        base.trouble = status === 403 ? `${base.service} not granted: enable the API and re-run ~/_scripts/gtasks-setup` : why;
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
    Component.onCompleted: if (base.configured)
        base.refresh()

    Connections {
        target: Google

        function onReady(): void {
            base.refresh();
        }
    }

    Timer {
        interval: base.pollMs
        running: base.configured
        repeat: true
        onTriggered: base.refresh()
    }
}
