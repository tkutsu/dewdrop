pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The one Google sign-in the bar has, shared by everything that talks to a
// Google API (Tasks and Agenda so far).
//
// ~/_scripts/gtasks-setup walks the consent once and leaves a refresh token in
// the file read below, granted for every scope the bar uses. Everything after
// that happens here: the refresh token is traded for an access token that lasts
// an hour, kept in memory and never written down — a copy on disk would only
// be a second thing able to go stale.
//
// What each service keeps for itself is what it fetches and what it makes of a
// failure. `send` hands a reply to `then` or a reason to `fail`, so no caller
// has to remember to check a status code. The shape of a service — polling,
// gathering, trouble — is GoogleService.qml, which both build on.
Singleton {
    id: root

    readonly property string tokenEndpoint: "https://oauth2.googleapis.com/token"

    property string accessToken: ""
    property real tokenExpiry: 0
    property bool refreshing: false
    // Every caller waiting on the refresh in the air, the one that started it
    // included. They are run when it lands rather than turned away: a tick
    // dropped here would leave the row gone from the bar and still open on the
    // phone until the next poll put it back, which reads as the bar losing a
    // click.
    property var waiting: []
    // How the refresh in the air is ended, whichever of the reply, the XHR
    // timeout or the watchdog gets there first. Null when none is running.
    property var settleRefresh: null
    readonly property int refreshTimeoutMs: 15000

    readonly property bool configured: adapter.refresh_token !== ""

    // Fired once the credentials are read. A service that constructed this
    // singleton before the file landed has nothing to do until then; one that
    // arrived later finds `configured` already true and just goes.
    signal ready

    readonly property string reconnect: "Google needs reconnecting: run ~/_scripts/gtasks-setup"

    // --- days ----------------------------------------------------------------
    // Google's APIs speak in calendar days, and both services compare them as
    // ISO strings: they sort lexicographically, so "before today" is just "<".
    function dayString(date: var): string {
        const pad = n => n < 10 ? "0" + n : String(n);
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    // Recomputed at midnight rather than per read, so a bar left up overnight
    // does not still think yesterday is today. SystemClock at Hours is the
    // cheapest thing that notices.
    readonly property date now: clock.date
    readonly property string today: root.dayString(clock.date)

    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }

    // --- requests ------------------------------------------------------------
    // One place that knows about headers and status codes. `then` is handed the
    // parsed body; anything that is not a 2xx goes to `fail` with a reason and
    // the status it came from.
    function send(method: string, url: string, body: var, then: var, fail: var): void {
        // A 401 means the token died in flight: rather than reporting it and
        // waiting for the next poll, the token is dropped and the request goes
        // again once behind a fresh one. Once, because a second 401 with a
        // token Google just issued is not going to be cured by a third.
        const attempt = function (retry) {
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status === 401) {
                    root.accessToken = "";
                    root.tokenExpiry = 0;
                    if (retry)
                        root.authorised(() => attempt(false), fail);
                    else
                        fail("Google rejected the token", 401);
                    return;
                }
                if (xhr.status < 200 || xhr.status >= 300) {
                    fail(xhr.status === 0 ? "No network" : `Google said ${xhr.status}`, xhr.status);
                    return;
                }
                let parsed = null;
                if (String(xhr.responseText).trim() !== "")
                    try {
                        parsed = JSON.parse(xhr.responseText);
                    } catch (e) {
                        fail("Google sent something unreadable", xhr.status);
                        return;
                    }
                then(parsed);
            };
            xhr.open(method, url);
            xhr.setRequestHeader("Authorization", "Bearer " + root.accessToken);
            if (body !== null) {
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.send(JSON.stringify(body));
            } else {
                xhr.send();
            }
        };
        attempt(true);
    }

    // Get a usable access token, then do the thing. A minute of margin, because
    // a token that expires while the request is in the air is a 401 for no
    // reason anyone could have acted on.
    function authorised(then: var, fail: var): void {
        if (!root.configured)
            return;
        if (root.accessToken !== "" && Date.now() < root.tokenExpiry - 60000) {
            then();
            return;
        }
        // Only ever one refresh in the air. Several calls arriving together at
        // startup would otherwise each start their own, and Google counts every
        // one of them.
        root.waiting = root.waiting.concat([{
                go: then,
                bad: fail
            }]);
        if (root.refreshing)
            return;
        root.refreshing = true;

        const xhr = new XMLHttpRequest();
        // Runs exactly once however the refresh ends. A refresh that never
        // ended used to leave `refreshing` up for good, and every call after
        // it joined the queue and stayed there — the bar sat on "Connecting…"
        // until restarted. Every exit now goes through here and empties the
        // queue, with a failure or a token.
        let settled = false;
        root.settleRefresh = function (why) {
            if (settled)
                return;
            settled = true;
            root.settleRefresh = null;
            watchdog.stop();
            root.refreshing = false;
            const queued = root.waiting;
            root.waiting = [];
            if (why !== "") {
                xhr.abort();
                for (const held of queued)
                    held.bad(why, 0);
                return;
            }
            for (const held of queued)
                held.go();
        };
        xhr.timeout = root.refreshTimeoutMs;
        xhr.ontimeout = root.refreshTimedOut;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || settled)
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                // 400 here is the refresh token itself being dead — revoked, or
                // expired because the app was left in Testing. Nothing the bar
                // can do about that, so it says which one it is rather than
                // retrying every two minutes forever.
                root.settleRefresh(xhr.status === 400 || xhr.status === 401 ? root.reconnect : (xhr.status === 0 ? "No network" : `Sign-in failed (${xhr.status})`));
                return;
            }
            let parsed;
            try {
                parsed = JSON.parse(xhr.responseText);
            } catch (e) {
                root.settleRefresh("Sign-in sent something unreadable");
                return;
            }
            root.accessToken = parsed.access_token ?? "";
            root.tokenExpiry = Date.now() + (parsed.expires_in ?? 3600) * 1000;
            root.settleRefresh("");
        };
        watchdog.restart();
        xhr.open("POST", root.tokenEndpoint);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.send(`client_id=${encodeURIComponent(adapter.client_id)}&client_secret=${encodeURIComponent(adapter.client_secret)}&refresh_token=${encodeURIComponent(adapter.refresh_token)}&grant_type=refresh_token`);
    }

    function refreshTimedOut(): void {
        if (root.settleRefresh)
            root.settleRefresh("Sign-in timed out");
    }

    // Second line behind xhr.timeout, for the case where the XHR never reports
    // back at all: a refresh that hangs must end somehow, or every service
    // queues behind it forever.
    Timer {
        id: watchdog
        interval: root.refreshTimeoutMs + 5000
        onTriggered: root.refreshTimedOut()
    }

    // --- credentials ---------------------------------------------------------
    // Written once by ~/_scripts/gtasks-setup. No watchChanges: the file only
    // moves when that script runs, and running it ends with a note to reload
    // the bar anyway.
    FileView {
        path: Quickshell.env("HOME") + "/.local/share/quickshell/gtasks.json"
        printErrors: false

        onLoaded: root.ready()

        JsonAdapter {
            id: adapter

            property string client_id: ""
            property string client_secret: ""
            property string refresh_token: ""
        }
    }
}
