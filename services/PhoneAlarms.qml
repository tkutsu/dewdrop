pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "PhoneCrypto.js" as Crypto

// Local phone delivery, occurrence tracking and bounded rediscovery.
Singleton {
    id: root
    signal failed(reason: string)
    signal acknowledged(id: string, firedAt: real)
    signal finished()

    FileView {
        id: configFile
        path: Paths.data("phone.json")
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: configFile.reload()
    }
    readonly property var config: {
        try { return JSON.parse(configFile.text()); }
        catch (e) { return null; }
    }
    readonly property bool configured: {
        const c = root.config;
        return !!c && /^[a-f0-9]{64}$/.test(c.secret ?? "") && /^[a-f0-9]{32}$/.test(c.pairId ?? "")
            && Number.isInteger(c.port) && c.port > 0 && c.port < 65536
            && Array.isArray(c.homeNetworks) && c.homeNetworks.length > 0
            && c.homeNetworks.every(n => typeof n.ssid === "string" && !!n.ssid && !!n.uuid && !!n.cidr);
    }
    readonly property bool atHome: root.configured && !!Network.current?.known
        && root.config.homeNetworks.some(n => n.ssid === Network.current.name)
    readonly property string phoneWarning: !root.configured
        ? "Phone alerts unavailable: local phone configuration missing or invalid."
        : !root.atHome ? "Phone alerts paused outside home Wi-Fi." : ""
    property var phoneAlerts: []
    property string address: ""
    property string cachedAddress: ""
    property bool busy: false
    property bool outage: false
    property int generation: 0
    property int misses: 0
    property real discoverAfter: 0
    readonly property int lifetimeMs: 600000
    readonly property int reconciliationMs: 30000

    FileView {
        id: addressFile
        path: Paths.cache("phone-address.json")
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(addressFile.text());
                if (saved.pairId === root.config?.pairId)
                    root.cachedAddress = saved.address ?? "";
            } catch (e) {}
        }
    }

    function report(reason: string): void {
        if (!root.atHome || root.outage) return;
        root.outage = true;
        root.failed(reason);
    }

    function hasLive(id: string, firedAt: real): bool {
        return root.phoneAlerts.some(a => a.id === id && a.firedAt === firedAt
            && !a.dismissed && Date.now() < a.expiresAt);
    }

    function notifyPhone(title: string, body: string, entry: var): void {
        if (!root.configured) {
            if (!root.outage) { root.outage = true; root.failed(root.phoneWarning); }
            return;
        }
        if (!root.atHome) return;
        const key = entry.id + ":" + entry.firedAt;
        if (root.phoneAlerts.some(a => a.key === key)) return;
        root.phoneAlerts = root.phoneAlerts.concat([{
            id: entry.id, firedAt: entry.firedAt, key: key, title: title + ": " + body,
            started: false, dismissed: false, due: 0, expiresAt: entry.firedAt + root.lifetimeMs + root.reconciliationMs
        }]);
        root.pump();
    }

    // Keep an in-flight start owned until its following stop has succeeded.
    function dismiss(): void {
        for (const alert of root.phoneAlerts) {
            alert.dismissed = true;
            alert.due = 0;
        }
        root.pump();
    }

    function forget(alert: var): void {
        root.phoneAlerts = root.phoneAlerts.filter(a => a !== alert);
        root.finished();
    }

    onAtHomeChanged: {
        root.generation++;
        root.address = "";
        root.discoverAfter = 0;
        root.misses = 0;
        if (!root.atHome) {
            // Reconcile a possible remote start on return; never replay it.
            for (const alert of root.phoneAlerts) { alert.dismissed = true; alert.due = 0; }
            if (discovery.running) discovery.running = false;
            root.finished();
        } else root.pump();
    }
    onConfigChanged: {
        root.generation++;
        root.address = "";
        root.discoverAfter = 0;
        root.pump();
    }

    // A finite helper probes only this saved home LAN; it opens no desktop listener.
    Process {
        id: discovery
        property int startedGeneration: 0
        property string result: ""
        command: ["python3", Quickshell.shellPath("scripts/phone-discover.py"), Paths.data("phone.json"), root.cachedAddress]
        stdout: StdioCollector { onStreamFinished: discovery.result = text }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (discovery.startedGeneration !== root.generation || !root.atHome) return;
            let found;
            try { found = JSON.parse(discovery.result); } catch (e) { found = {}; }
            if (code === 0 && found.home && /^\d{1,3}(\.\d{1,3}){3}$/.test(found.address ?? "")) {
                root.address = found.address;
                root.cachedAddress = found.address;
                addressFile.setText(JSON.stringify({pairId: root.config.pairId, address: found.address}));
                root.misses = 0;
                cooldown.restart();
            } else {
                root.misses++;
                root.discoverAfter = Date.now() + Math.min(60000, 5000 * Math.pow(2, root.misses - 1));
                root.report("The paired phone is unreachable on home Wi-Fi.");
            }
        }
    }

    // Prove identity again before each command, so a reused address gets no secret.
    function request(data: var, accepted: var, rejected: var): void {
        const c = root.config;
        const gen = root.generation;
        const url = "http://" + root.address + ":" + c.port + "/qs-alarm";
        const nonce = Crypto.sha256(Date.now() + ":" + Math.random() + ":" + Math.random());
        const alive = () => root.atHome && gen === root.generation;
        function send(body, done) {
            Http.send("POST", url, body, {}, 3000, function(xhr) {
                if (!alive()) { rejected("suspended"); return; }
                let reply;
                try { reply = JSON.parse(xhr.responseText); } catch (e) {}
                if (xhr.status !== 200 || !reply || reply.v !== 1 || reply.pairId !== c.pairId) {
                    rejected("The phone listener did not return a valid response.");
                    return;
                }
                done(reply);
            }, rejected);
        }
        send({op: "probe", nonce: nonce}, function(proof) {
            if (proof.nonce !== nonce || proof.proof !== Crypto.sha256(c.secret + ":" + nonce)) {
                rejected("The device at the phone address could not prove its identity.");
                return;
            }
            // Automate briefly leaves HTTP accept while sending each response.
            const delay = commandDelay.createObject(root);
            delay.triggered.connect(function() {
                delay.destroy();
                if (!alive()) { rejected("suspended"); return; }
                send(Object.assign({}, data, {secret: c.secret}), accepted);
            });
            delay.start();
        });
    }
    Component { id: commandDelay; Timer { interval: 150 } }

    function pump(): void {
        const now = Date.now();
        const expired = root.phoneAlerts.filter(a => now >= a.expiresAt);
        if (expired.length) {
            root.phoneAlerts = root.phoneAlerts.filter(a => now < a.expiresAt);
            root.finished();
        }
        if (!root.atHome || root.busy || discovery.running || !root.phoneAlerts.length) return;
        if (!root.address) {
            if (now < root.discoverAfter) return;
            discovery.startedGeneration = root.generation;
            discovery.result = "";
            discovery.running = true;
            return;
        }
        const ready = root.phoneAlerts.filter(a => a.due <= now).sort((a,b) => Number(b.dismissed) - Number(a.dismissed));
        if (!ready.length) return;
        const alert = ready[0];
        // Reconcile the deadline before removing the dismissal entry; clocks can differ.
        const op = alert.dismissed || now >= alert.firedAt + root.lifetimeMs
            ? "stop" : alert.started ? "state" : "ring";
        root.busy = true;
        root.request({op: op, key: alert.key, firedAt: alert.firedAt / 1000, title: alert.title}, function(reply) {
            root.busy = false;
            if (reply.key !== alert.key || reply.firedAt !== alert.firedAt / 1000
                || !["ringing", "dismissed", "stopped", "timed_out", "away", "unknown"].includes(reply.state)) {
                root.retry(alert, "The phone returned an invalid alarm state.");
                return;
            }
            root.outage = false;
            if (reply.state === "dismissed") {
                root.acknowledged(alert.id, alert.firedAt);
                root.forget(alert);
            } else if (["stopped", "timed_out", "away"].includes(reply.state) || op === "stop") {
                root.forget(alert);
            } else {
                // Unknown state after a lost start retries the same occurrence.
                alert.started = reply.state === "ringing";
                alert.due = alert.dismissed ? 0 : Date.now() + 2000;
            }
            cooldown.restart();
        }, function(reason) {
            root.busy = false;
            root.retry(alert, reason);
        });
    }

    function retry(alert: var, reason: string): void {
        alert.due = Date.now() + 2500;
        root.address = "";
        if (reason !== "suspended") root.report(reason);
        cooldown.restart();
    }
    Timer { id: cooldown; interval: 150; onTriggered: root.pump() }
    Timer {
        interval: 500
        running: root.phoneAlerts.length > 0
        repeat: true
        onTriggered: root.pump()
    }
}
