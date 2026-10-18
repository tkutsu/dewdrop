import QtQuick
import Quickshell
import Quickshell.Io
import qs

// One Google sign-in: a credentials file with a refresh token in it, traded
// for an access token that lasts an hour, kept in memory and never written
// down (a copy on disk would only be a second thing able to go stale).
// scripts/gtasks-auth writes the file and the popups run it to reconnect.
//
// Google.qml is the bar's main account (Tasks, Agenda, Email);
// YouTubeAccount.qml is a second one, because the channel whose
// subscriptions are followed can be a brand account with no mail at all.
//
// `send` hands a reply to `then` or a reason to `fail`, so no caller has to
// remember to check a status code. The shape of a service (polling,
// gathering, trouble) is GoogleService.qml.
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
    readonly property int refreshTimeoutMs: 15000
    readonly property int requestTimeoutMs: 15000

    readonly property bool configured: adapter.refresh_token !== ""

    // Fired once the credentials are read. A service that constructed this
    // singleton before the file landed has nothing to do until then; one that
    // arrived later finds `configured` already true and just goes.
    signal ready

    // The credentials file under Paths.data, and what gtasks-auth is told
    // so it asks for this account's scopes and writes that file.
    property string file: "gtasks.json"
    property var consentArgs: []
    // Scopes of which the token must hold at least one, checked on every
    // refresh: a token without them is as good as missing.
    property var requireAny: []

    readonly property string reconnect: "Google needs reconnecting"

    // Whether the sign-in needs you: there are no credentials, the refresh
    // token is dead, a request came back 403 for a scope the token was never
    // granted (one added to gtasks-auth since), or the token is for an
    // account the API has nothing for (a brand account asked for Gmail). All
    // are cured by the consent script, which the popups offer as a
    // "reconnect" button.
    property bool scopeMissing: false
    property bool wrongAccount: false
    readonly property bool needsConsent: !root.configured || root.tokenDead || root.scopeMissing || root.wrongAccount
    property bool tokenDead: false
    readonly property bool consenting: consent.running

    function reconsent(): void {
        consent.running = true;
    }

    // In a terminal, because the script talks — it prints the consent URL in
    // case the browser does not open, and asks for the client id on a machine
    // that has none saved. Held open only when it fails, so the reason can be
    // read; "(floating)" is the window rule in hypr/configs/wrules.lua.
    Process {
        id: consent

        command: Settings.inTerminal(["sh", "-c", '"$1" || { printf "\nPress Enter to close. "; read _; }', "sh", Quickshell.shellPath("scripts/gtasks-auth"), ...root.consentArgs], "Google sign-in (floating)")

        // Whatever it did, the file is the truth now: forget the token in
        // memory and read the credentials again. Their `loaded` is `ready`,
        // which has every service fetch again under the new grant.
        onExited: {
            root.accessToken = "";
            root.tokenExpiry = 0;
            root.tokenDead = false;
            root.scopeMissing = false;
            root.wrongAccount = false;
            credentials.reload();
        }
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
            Http.send(method, url, body, {Authorization: "Bearer " + root.accessToken}, root.requestTimeoutMs, function (xhr) {
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
                    // A 403 is either an API switched off in the console or a
                    // token without the scope; only the second is reconnecting's
                    // to cure, and Google names it in the body.
                    if (xhr.status === 403 && /ACCESS_TOKEN_SCOPE_INSUFFICIENT|insufficientPermissions/.test(xhr.responseText)) {
                        root.scopeMissing = true;
                        fail(root.reconnect, 403);
                        return;
                    }
                    // Signed in as an account the service does not exist
                    // for: Gmail says this to a YouTube brand account.
                    if (xhr.status === 400 && /FAILED_PRECONDITION/.test(xhr.responseText) && /service not enabled/i.test(xhr.responseText)) {
                        root.wrongAccount = true;
                        fail(root.reconnect, 400);
                        return;
                    }
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
            }, fail);
        };
        attempt(true);
    }

    // Get a usable access token, then do the thing. A minute of margin, because
    // a token that expires while the request is in the air is a 401 for no
    // reason anyone could have acted on.
    function authorised(then: var, fail: var): void {
        if (root.needsConsent) {
            fail(root.reconnect, 0);
            return;
        }
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

        // Clear the queue before callbacks, so a caller may safely request another refresh.
        const settle = function (why, status) {
            root.refreshing = false;
            const queued = root.waiting;
            root.waiting = [];
            for (const held of queued) {
                try {
                    if (why !== "")
                        held.bad(why, status ?? 0);
                    else
                        held.go();
                } catch (error) {
                    console.warn("Google token callback failed:", error);
                }
            }
        };
        Http.sendForm(root.tokenEndpoint, {
            client_id: adapter.client_id,
            client_secret: adapter.client_secret,
            refresh_token: adapter.refresh_token,
            grant_type: "refresh_token"
        }, root.refreshTimeoutMs, function (xhr) {
            if (xhr.status < 200 || xhr.status >= 300) {
                // 400 here is the refresh token itself being dead — revoked, or
                // expired because the app was left in Testing. Nothing the bar
                // can do about that, so it says which one it is rather than
                // retrying every two minutes forever.
                const dead = xhr.status === 400 || xhr.status === 401;
                root.tokenDead = dead;
                settle(dead ? root.reconnect : (xhr.status === 0 ? "No network" : `Sign-in failed (${xhr.status})`), xhr.status);
                return;
            }
            let parsed;
            try {
                parsed = JSON.parse(xhr.responseText);
            } catch (e) {
                settle("Sign-in sent something unreadable", xhr.status);
                return;
            }
            if (typeof parsed.scope === "string" && root.requireAny.length > 0) {
                const granted = parsed.scope.split(/\s+/);
                if (!root.requireAny.some(scope => granted.includes("https://www.googleapis.com/auth/" + scope))) {
                    root.scopeMissing = true;
                    settle(root.reconnect, 403);
                    return;
                }
            }
            root.accessToken = parsed.access_token ?? "";
            root.tokenExpiry = Date.now() + (parsed.expires_in ?? 3600) * 1000;
            settle("");
        }, function (why, status) {
            settle(why === "Request timed out" ? "Sign-in timed out" : why, status);
        });
    }

    // --- credentials ---------------------------------------------------------
    // Written by the consent script. No watchChanges: the file only moves when
    // that runs, and a run from the popups reloads it when it exits.
    FileView {
        id: credentials

        path: Paths.data(root.file)
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
