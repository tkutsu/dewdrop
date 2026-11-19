pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// JSON requests with one completion and a timeout, leaving API policy to callers.
Singleton {
    id: root

    property int sequence: 0

    function send(method: string, url: string, body: var, headers: var, timeoutMs: int, accepted: var, failed: var): void {
        const encoded = body === null ? null : JSON.stringify(body);
        const requestHeaders = body === null ? headers : Object.assign({}, headers, {"Content-Type": "application/json"});
        root.request(method, url, encoded, requestHeaders, timeoutMs, accepted, failed);
    }

    // OAuth token refresh uses form encoding but shares the same completion/deadline logic.
    function sendForm(url: string, fields: var, timeoutMs: int, accepted: var, failed: var): void {
        const body = Object.entries(fields).map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value)).join("&");
        root.request("POST", url, body, {"Content-Type": "application/x-www-form-urlencoded"}, timeoutMs, accepted, failed);
    }

    function request(method: string, url: string, body: var, headers: var, timeoutMs: int, accepted: var, failed: var): void {
        const id = ++root.sequence;
        const began = Date.now();
        // Host only: paths and queries can contain mail, task ids or search text.
        const host = url.match(/^https?:\/\/([^/?#]+)/i)?.[1]?.replace(/^.*@/, "") ?? "unknown";
        const log = function (transport, outcome, status, exit) {
            console.log(`[http] id=${id} method=${method} host=${host} transport=${transport} outcome=${outcome} status=${status} elapsed_ms=${Date.now() - began}` + (exit === undefined ? "" : ` exit=${exit}`));
        };
        const xhr = new XMLHttpRequest();
        const timeout = deadline.createObject(root, {interval: timeoutMs});
        let settled = false;
        const finish = function () {
            settled = true;
            timeout.stop();
            timeout.destroy();
        };
        const recover = function (why) {
            if (method === "GET" && body === null && /^https?:\/\//i.test(url)) {
                const job = fallback.createObject(root, {
                    url: url, headers: headers, timeoutMs: timeoutMs,
                    accepted: accepted, failed: failed, diagnostic: log
                });
                job.running = true;
            } else {
                failed(why, 0);
            }
        };
        timeout.triggered.connect(function () {
            if (settled)
                return;
            finish();
            xhr.abort();
            log("qt", "timeout", 0);
            recover("The server is taking too long to respond.");
        });
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || settled)
                return;
            finish();
            if (xhr.status === 0) {
                log("qt", "network-error", 0);
                recover("Couldn't connect right now.");
                return;
            }
            if (xhr.status < 200 || xhr.status >= 300)
                log("qt", "http-error", xhr.status);
            accepted(xhr);
        };
        xhr.open(method, url);
        for (const [key, value] of Object.entries(headers))
            xhr.setRequestHeader(key, value);
        timeout.start();
        if (body === null) xhr.send();
        else xhr.send(body);
    }

    Component {
        id: deadline
        Timer {}
    }

    // One fresh IPv4 process escapes Qt's connection state; only GETs arrive here.
    Component {
        id: fallback
        Process {
            id: job
            required property string url
            required property var headers
            required property int timeoutMs
            required property var accepted
            required property var failed
            required property var diagnostic
            property bool completed: false
            property bool launched: false

            command: ["curl", "--disable", "--ipv4", "--silent", "--globoff", "--proto", "=http,https",
                "--location", "--proto-redir", "=http,https",
                "--connect-timeout", String(Math.min(5, timeoutMs / 1000)), "--max-time", String(timeoutMs / 1000),
                "--config", "-", "--write-out", "\n%{http_code}"]
            stdinEnabled: true

            // curl config is stdin, so credentials and private URLs never enter argv.
            function quote(value: string): string {
                return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n").replace(/\t/g, "\\t") + '"';
            }

            onStarted: {
                job.launched = true;
                let config = "url = " + job.quote(job.url) + "\n";
                for (const [key, value] of Object.entries(job.headers))
                    config += "header = " + job.quote(key + ": " + value) + "\n";
                job.write(config);
                job.stdinEnabled = false;
            }

            stdout: StdioCollector { id: reply }
            // Do not forward curl's stderr: it may repeat private URLs or headers.
            stderr: StdioCollector {}

            function finish(code: int, expired: bool): void {
                if (job.completed)
                    return;
                job.completed = true;
                watchdog.stop();
                const end = reply.text.lastIndexOf("\n");
                const status = Number(reply.text.slice(end + 1));
                if (!expired && code === 0 && end >= 0 && status >= 100 && status <= 599) {
                    job.diagnostic("curl-ipv4", status >= 200 && status < 300 ? "recovered" : "http-error", status, code);
                    job.accepted({status: status, responseText: reply.text.slice(0, end)});
                } else {
                    const timedOut = expired || code === 28;
                    job.diagnostic("curl-ipv4", !job.launched ? "start-error" : expired ? "deadline" : timedOut ? "timeout" : "network-error", 0, code < 0 ? undefined : code);
                    job.failed(timedOut ? "The server is taking too long to respond." : "Couldn't connect right now.", 0);
                }
            }

            onExited: (code, status) => {
                try {
                    job.finish(status === 0 ? code : -1, false);
                } finally {
                    job.destroy();
                }
            }

            // Also covers failure to start, for which Process emits no exited signal.
            property Timer watchdog: Timer {
                id: watchdog
                interval: job.timeoutMs + 1000
                running: true
                onTriggered: {
                    job.signal(9);
                    try {
                        job.finish(-1, job.launched);
                    } finally {
                        job.destroy();
                    }
                }
            }
        }
    }
}
