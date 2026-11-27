pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// JSON requests with one completion and a timeout, leaving API policy to callers.
//
// Each request is its own curl, on a connection of its own. Qt's
// XMLHttpRequest keeps one HTTP/2 connection per host and cannot be told to
// drop it: once that connection died (a suspend, the Wi-Fi going), every
// request to the host waited out its timeout until the bar restarted, and
// abort() cancelled the request but kept the dead connection. A fresh
// process has nothing to inherit, and curl tries IPv6 and IPv4 side by side.
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

    // `accepted` gets {status, responseText} for any HTTP answer, 4xx and 5xx
    // included; `failed(why, 0)` gets no answer at all. Exactly one of them,
    // once, by the deadline.
    function request(method: string, url: string, body: var, headers: var, timeoutMs: int, accepted: var, failed: var): void {
        const id = ++root.sequence;
        const began = Date.now();
        // Host only: paths and queries can contain mail, task ids or search text.
        const host = url.match(/^https?:\/\/([^/?#]+)/i)?.[1]?.replace(/^.*@/, "") ?? "unknown";
        // Only what went wrong is logged; a healthy poll says nothing.
        const log = function (outcome, status, exit) {
            console.log(`[http] id=${id} method=${method} host=${host} outcome=${outcome} status=${status} elapsed_ms=${Date.now() - began}` + (exit === undefined ? "" : ` exit=${exit}`));
        };
        if (!/^https?:\/\//i.test(url)) {
            log("bad-url", 0);
            failed("Couldn't connect right now.", 0);
            return;
        }
        const job = curl.createObject(root, {
            method: method, url: url, body: body ?? "", headers: headers, timeoutMs: timeoutMs
        });
        const timeout = deadline.createObject(root, {interval: timeoutMs});
        let settled = false;
        const finish = function () {
            settled = true;
            timeout.stop();
            timeout.destroy();
        };
        // curl's own --max-time lands first; this is for a curl that never
        // started (Process says nothing then) or never let go.
        timeout.triggered.connect(function () {
            if (settled)
                return;
            finish();
            log(job.launched ? "deadline" : "start-error", 0);
            job.stop();
            failed("The server is taking too long to respond.", 0);
        });
        job.answered.connect(function (status, text, exit) {
            if (settled)
                return;
            finish();
            if (status > 0) {
                if (status < 200 || status >= 300)
                    log("http-error", status, exit);
                accepted({status: status, responseText: text});
            } else {
                const late = exit === 28;
                log(late ? "timeout" : "network-error", 0, exit);
                failed(late ? "The server is taking too long to respond." : "Couldn't connect right now.", 0);
            }
        });
        timeout.start();
        job.running = true;
    }

    Component {
        id: deadline
        Timer {}
    }

    Component {
        id: curl
        Process {
            id: job
            required property string method
            required property string url
            required property string body
            required property var headers
            required property int timeoutMs
            property bool launched: false
            property bool cancelled: false

            // HTTP status (0 for no answer), the body, and curl's exit code.
            signal answered(int status, string text, int exit)

            // --max-time a second inside the deadline, so curl's own timeout
            // (exit 28) is what reports a slow server.
            command: ["curl", "--disable", "--silent", "--globoff", "--compressed",
                "--proto", "=http,https", "--location", "--proto-redir", "=http,https",
                "--connect-timeout", String(Math.max(1, Math.min(10, Math.floor(timeoutMs / 1000) - 1))),
                "--max-time", String(Math.max(1, Math.floor(timeoutMs / 1000) - 1)),
                "--config", "-", "--write-out", "\n%{http_code}"]
            stdinEnabled: true

            // curl config is stdin, so credentials, bodies and private URLs never enter argv.
            function quote(value: string): string {
                return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n").replace(/\t/g, "\\t") + '"';
            }

            function stop(): void {
                job.cancelled = true;
                if (job.running)
                    job.signal(9);
                else
                    job.destroy();
            }

            onStarted: {
                job.launched = true;
                let config = "url = " + job.quote(job.url) + "\n";
                if (job.method !== "GET")
                    config += "request = " + job.quote(job.method) + "\n";
                if (job.body !== "")
                    config += "data-raw = " + job.quote(job.body) + "\n";
                // A write with nothing in it still says so: Google answers a
                // bodiless POST without a length with 411.
                else if (job.method === "POST" || job.method === "PUT" || job.method === "PATCH")
                    config += "header = " + job.quote("Content-Length: 0") + "\n";
                for (const [key, value] of Object.entries(job.headers))
                    config += "header = " + job.quote(key + ": " + value) + "\n";
                job.write(config);
                job.stdinEnabled = false;
            }

            stdout: StdioCollector { id: reply }
            // Not forwarded: curl's stderr may repeat private URLs or headers.
            stderr: StdioCollector {}

            onExited: (code, status) => {
                try {
                    if (!job.cancelled) {
                        const end = reply.text.lastIndexOf("\n");
                        const http = Number(reply.text.slice(end + 1));
                        const answered = status === 0 && code === 0 && end >= 0 && http >= 100 && http <= 599;
                        job.answered(answered ? http : 0, answered ? reply.text.slice(0, end) : "", status === 0 ? code : -1);
                    }
                } finally {
                    job.destroy();
                }
            }
        }
    }
}
