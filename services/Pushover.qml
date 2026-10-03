pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Emergency phone delivery and receipt tracking, independent of local ringing.
Singleton {
    id: root
    signal failed(reason: string)
    signal acknowledged(id: string, firedAt: real)

    function phoneFailed(reason: string): void { root.failed(reason); }

    function dismiss(): void {
        for (const alert of root.phoneAlerts) {
            alert.dismissed = true;
            root.cancelPhone(alert);
        }
    }

    // Credentials live beside the Google sign-in, outside the config repo.
    // A blocking first read covers a restored timer firing during startup;
    // later edits are picked up without restarting the shell.
    FileView {
        id: pushoverCredentials

        path: Paths.data("pushover.json")
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: pushoverCredentials.reload()
    }

    // The popup and sender read the same status, including edits made while
    // the shell is running. Never put credential values in the warning.
    readonly property var phoneCredentials: {
        try {
            return JSON.parse(pushoverCredentials.text());
        } catch (e) {
            return null;
        }
    }
    readonly property string phoneWarning: {
        const credentials = root.phoneCredentials;
        return credentials && /^[A-Za-z0-9]{30}$/.test(credentials.token ?? "") && /^[A-Za-z0-9]{30}$/.test(credentials.user ?? "")
            ? "" : "Phone alerts unavailable: Pushover credentials missing or invalid.";
    }

    // Bound every phone request and validate its response without logging
    // credentials or receipts.
    function phoneRequest(method: string, path: string, data: var, accepted: var, failed: var): void {
        Http.send(method, "https://api.pushover.net/1/" + path, data, {}, 15000, function (xhr) {
            if (xhr.status !== 200) {
                failed(xhr.status === 0 ? "No network" : `Pushover returned HTTP ${xhr.status}`);
                return;
            }
            let response;
            try {
                response = JSON.parse(xhr.responseText);
            } catch (e) {
                failed("Pushover sent an unreadable response");
                return;
            }
            if (response.status !== 1) {
                failed("Pushover rejected the request");
                return;
            }
            accepted(response);
        }, failed);
    }

    // Receipts outlive the local sound's one-minute limit. Each one belongs to
    // an occurrence, so acknowledging yesterday's alarm cannot hush today's.
    property var phoneAlerts: []

    function forgetPhone(alert: var): void {
        root.phoneAlerts = root.phoneAlerts.filter(a => a !== alert);
    }

    // One phone alert per expiry. Retrying an ambiguous send could duplicate
    // it; receipt checks and cancellation can safely retry instead.
    function notifyPhone(title: string, body: string, entry: var): void {
        if (root.phoneWarning !== "") {
            root.phoneFailed(root.phoneWarning);
            return;
        }
        const credentials = root.phoneCredentials;
        const alert = {
            id: entry.id,
            firedAt: entry.firedAt,
            token: credentials.token,
            receipt: "",
            dismissed: false,
            busy: false,
            warned: false,
            expiresAt: Date.now() + 10800000
        };
        root.phoneAlerts = root.phoneAlerts.concat([alert]);
        root.phoneRequest("POST", "messages.json", {
            token: credentials.token,
            user: credentials.user,
            title: title,
            message: body,
            // Server retries stop on phone acknowledgment. Pushover requires
            // at least 30 seconds and caps an emergency alert at 50 retries.
            priority: 2,
            retry: 30,
            expire: 10800,
            timestamp: Math.floor(entry.firedAt / 1000)
        }, function (response) {
            if (!/^[A-Za-z0-9]{30}$/.test(response.receipt ?? "")) {
                root.forgetPhone(alert);
                root.phoneFailed("Pushover did not return a valid receipt");
                return;
            }
            alert.receipt = response.receipt;
            if (alert.dismissed)
                root.cancelPhone(alert);
        }, function (reason) {
            root.forgetPhone(alert);
            root.phoneFailed(reason);
        });
    }

    // Keep failed syncs pending for the next poll, but report an outage once.
    function phoneSyncFailed(alert: var, reason: string): void {
        alert.busy = false;
        if (!alert.warned) {
            alert.warned = true;
            root.phoneFailed(reason);
        }
    }

    function cancelPhone(alert: var): void {
        if (alert.receipt === "" || alert.busy)
            return;
        alert.busy = true;
        root.phoneRequest("POST", `receipts/${alert.receipt}/cancel.json`, {
            token: alert.token
        }, function () {
            root.forgetPhone(alert);
        }, function (reason) {
            root.phoneSyncFailed(alert, reason);
        });
    }

    // Pushover permits checking each receipt no faster than every five seconds.
    function pollPhone(): void {
        for (const alert of root.phoneAlerts) {
            if (Date.now() >= alert.expiresAt) {
                root.forgetPhone(alert);
                continue;
            }
            if (alert.dismissed) {
                root.cancelPhone(alert);
                continue;
            }
            if (alert.receipt === "" || alert.busy)
                continue;
            alert.busy = true;
            root.phoneRequest("GET", `receipts/${alert.receipt}.json?token=${encodeURIComponent(alert.token)}`, null, function (response) {
                alert.busy = false;
                alert.warned = false;
                if (response.acknowledged === 1) {
                    root.acknowledged(alert.id, alert.firedAt);
                    root.forgetPhone(alert);
                } else if (response.expired === 1) {
                    root.forgetPhone(alert);
                } else if (alert.dismissed) {
                    root.cancelPhone(alert);
                }
            }, function (reason) {
                root.phoneSyncFailed(alert, reason);
            });
        }
    }

    Timer {
        interval: 5000
        running: root.phoneAlerts.length > 0
        repeat: true
        onTriggered: root.pollPhone()
    }

}
