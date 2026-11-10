pragma Singleton

import QtQuick
import Quickshell

// JSON requests with one completion and a timeout, leaving API policy to callers.
Singleton {
    id: root

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
        const xhr = new XMLHttpRequest();
        const timeout = deadline.createObject(root, {interval: timeoutMs});
        let settled = false;
        const finish = function () {
            settled = true;
            timeout.stop();
            timeout.destroy();
        };
        timeout.triggered.connect(function () {
            if (settled)
                return;
            finish();
            xhr.abort();
            failed("Request timed out", 0);
        });
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || settled)
                return;
            finish();
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
}
