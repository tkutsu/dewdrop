pragma Singleton

import QtQuick
import Quickshell

// JSON requests with one completion and a timeout, leaving API policy to callers.
Singleton {
    id: root

    function send(method: string, url: string, body: var, headers: var, timeoutMs: int, accepted: var, failed: var): void {
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
        if (body !== null)
            xhr.setRequestHeader("Content-Type", "application/json");
        timeout.start();
        xhr.send(body === null ? null : JSON.stringify(body));
    }

    Component {
        id: deadline
        Timer {}
    }
}
