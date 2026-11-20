#!/usr/bin/env python3
"""Exercise stalled Qt requests through the real HTTP and Google callbacks."""

import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

from test_support import fixture_root, shell_env


ROOT = Path(__file__).resolve().parents[1]
FAKE_CURL = '''#!/usr/bin/python3
import json, os, sys, time
config = sys.stdin.read()
with open(os.environ["HTTP_CALLS"], "a") as calls:
    calls.write(json.dumps({"args": sys.argv[1:], "config": config}) + "\\n")
if "/hang" in config:
    time.sleep(30)
if "/unavailable" in config:
    print("fixture-private-stderr", file=sys.stderr)
    sys.exit(7)
if "/unauthorised" in config:
    print('{"error":{"errors":[{"reason":"authError"}]}}\\n401', end="")
elif "/http-error" in config:
    print('{"error":{"errors":[{"reason":"backendError"}]}}\\n503', end="")
else:
    print('{"recovered":true}\\n200', end="")
'''

QML = r'''import QtQuick
import QtTest
import Quickshell
import qs.src.services
ShellRoot {
    id: root
    property bool configured: Google.configured
    property var api: TestApi
    property int accepted: 0
    property int failed: 0
    property string reason: ""
    TestCase { id: test; when: false }
    function check(ok, why) { if (!ok) throw Error(why); console.log("PASS: " + why); }
    function success() { accepted++; }
    function failure(why) { failed++; reason = why; }
    function run() {
        test.tryVerify(() => configured, 1000);
        Google.accessToken = "fixture-private-token";
        Google.tokenExpiry = Date.now() + 3600000;

        Http.send("GET", "https://fixture.invalid/normal", null, {}, 30, success, failure);
        FakeRequest.reply(0, {});
        check(accepted === 1 && failed === 0, "healthy requests finish without recovery");

        api.loaded = true;
        api.refresh();
        check(api.loading && api.trouble === "", "recovery starts inside the existing loading state");
        test.tryVerify(() => !api.loading, 1800);
        check(api.requests === 0 && api.recovered === 1 && api.trouble === "" && api.updatedAt > 0,
            "stalled Qt GET recovers without exposing an error or stranding loading");
        FakeRequest.reply(1, {recovered: false});
        check(api.recovered === 1 && api.requests === 0, "late Qt reply cannot finish a recovered read twice");

        let next = FakeRequest.requests.length;
        Http.send("GET", "https://fixture.invalid/network-error", null, {}, 30, success, failure);
        FakeRequest.reply(next, {}, 0);
        test.tryVerify(() => accepted === 2, 1800);
        check(accepted === 2 && failed === 0, "a Qt network error can recover through a fresh process");

        next = FakeRequest.requests.length;
        Http.send("GET", "https://fixture.invalid/unavailable", null, {}, 30, success, failure);
        test.tryVerify(() => failed === 1, 1800);
        check(accepted === 2 && failed === 1 && reason === "Couldn't connect right now.",
            "exhausted recovery reports a friendly error once");
        FakeRequest.reply(next, {});
        check(accepted === 2 && failed === 1, "late Qt reply cannot erase a recovery failure");

        Http.send("GET", "https://fixture.invalid/hang", null, {}, 30, success, failure);
        test.tryVerify(() => failed === 2, 2200);
        check(failed === 2 && reason === "The server is taking too long to respond.",
            "a hung fallback is killed and completes within its deadline");

        next = FakeRequest.requests.length;
        Http.send("POST", "https://fixture.invalid/write", {secret: "fixture-private-body"}, {}, 30, success, failure);
        test.tryVerify(() => failed === 3, 1000);
        FakeRequest.reply(next, {});
        check(accepted === 2 && failed === 3, "timed-out writes fail once without being replayed");

        api.refresh();
        api.send("GET", "https://fixture.invalid/http-error", null, () => { throw Error("accepted HTTP failure"); });
        test.tryVerify(() => !api.loading, 1800);
        check(api.requests === 0 && api.trouble === "Google said 503" && api.checkFailed,
            "parallel recovery success cannot hide a real HTTP failure");

        api.trouble = "";
        next = FakeRequest.requests.length;
        api.send("GET", "https://fixture.invalid/unauthorised", null, success, failure);
        test.tryVerify(() => FakeRequest.requests.length > next + 1, 1800);
        check(FakeRequest.requests[next + 1]?.url === Google.tokenEndpoint && api.loading,
            "fallback 401 follows the existing shared token refresh");
        FakeRequest.reply(next + 1, {access_token: "fixture-renewed-token", expires_in: 3600});
        FakeRequest.reply(next + 2, {});
        check(accepted === 3 && failed === 3 && api.requests === 0,
            "authenticated recovery settles the original callback chain once");

        next = FakeRequest.requests.length;
        Http.send("GET", "https://fixture.invalid/normal-http-error", null, {}, 30,
            xhr => { check(xhr.status === 503, "HTTP response status is preserved"); success(); }, failure);
        FakeRequest.reply(next, {}, 503);
        check(accepted === 4 && failed === 3, "HTTP failures are returned without a transport replay");
        console.log("PASS: HTTP recovery lifecycle");
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { root.run(); } catch (error) { console.log("FAIL: " + error + "\n" + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    fake = runpy.run_path(str(ROOT / "tests/test-shell-state.py"))["FAKE_HTTP"]
    with tempfile.TemporaryDirectory(prefix="quickshell-http-recovery-") as folder:
        target = fixture_root(folder)
        services = target / "src/services"
        services.mkdir()
        for name in ("Http", "GoogleAccount", "Google", "GoogleService"):
            source = (ROOT / f"src/services/{name}.qml").read_text()
            source = source.replace("new XMLHttpRequest()", "FakeRequest.make()")
            source = source.replace("requestTimeoutMs: 15000", "requestTimeoutMs: 30")
            (services / f"{name}.qml").write_text(source)
        (target / "src/lib/Pages.js").write_text((ROOT / "src/lib/Pages.js").read_text())
        (services / "FakeRequest.qml").write_text(fake)
        (services / "WallClock.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { signal wokeUp }")
        (services / "Retry.qml").write_text("import QtQuick\nQtObject { property bool active: false; property bool pending: false; signal triggered; function reset() {} function cancel() {} function schedule() {} function retryNow() {} }")
        (services / "TestApi.qml").write_text('''pragma Singleton
import QtQuick
GoogleService {
    polling: false
    property int recovered: 0
    onFetch: send("GET", "https://fixture.invalid/recover?query=fixture-private-query", null, body => recovered++)
}''')
        (target / "src/core/Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string home: ""; function inTerminal(command, title) { return command; } }')
        (target / "src/core/Paths.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function data(name) { return Quickshell.shellPath(name); } }')
        (target / "gtasks.json").write_text(json.dumps({"client_id": "fixture", "client_secret": "fixture", "refresh_token": "fixture"}))
        binary = target / "bin/curl"
        binary.parent.mkdir()
        binary.write_text(FAKE_CURL)
        binary.chmod(0o755)
        (target / "shell.qml").write_text(QML)
        calls = target / "calls.jsonl"
        env = shell_env(target, PATH=str(binary.parent) + os.pathsep + os.environ["PATH"], HTTP_CALLS=str(calls))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Failed to load configuration")
        if result.returncode or "PASS: HTTP recovery lifecycle" not in output or any(error in output for error in errors):
            return 1
        requests = [json.loads(line) for line in calls.read_text().splitlines()]
        assert len(requests) == 7, "only failed reads may launch one fallback each"
        assert all("--ipv4" in call["args"] and "--max-time" in call["args"] for call in requests)
        assert all(call["args"][0] == "--disable" for call in requests), "user curlrc cannot change recovery"
        assert all("fixture-private" not in " ".join(call["args"]) for call in requests), "secrets stay out of process arguments"
        assert "Authorization: Bearer fixture-private-token" in requests[0]["config"]
        assert "fixture-private" not in output, "logs must not contain tokens, bodies, queries or curl stderr"
        assert "outcome=recovered" in output and "outcome=timeout" in output and "exit=7" in output
        print("PASS: recovery is bounded, read-only and keeps credentials out of logs and argv")

        # A missing executable has no exited signal; its deadline must still settle.
        path = services / "Http.qml"
        source = path.read_text()
        path.write_text(source.replace('["curl",', '["fixture-missing-curl",'))
        (target / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    property int failures: 0
    Timer { interval: 10; running: true; onTriggered:
        Http.send("GET", "https://fixture.invalid/start-error", null, {}, 30,
            () => console.log("FAIL: missing curl succeeded"), () => failures++) }
    Timer { interval: 1400; running: true; onTriggered: {
        console.log(failures === 1 ? "PASS: missing curl settles once" : "FAIL: missing curl stranded callback"); Qt.quit();
    } }
}''')
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=4)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "PASS: missing curl settles once" in output and "outcome=start-error" in output, output
        assert "outcome=start-error status=0" in output and "FAIL:" not in output, output
        print("PASS: missing curl is logged as a start failure, not a network timeout")
        path.write_text(source)

        if "--real-curl" in sys.argv:
            real_curl(target)
        return 0


def real_curl(target):
    """Prove curl config quoting, headers and response framing on a local server."""
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import threading

    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append((self.path, self.headers.get("Authorization"), self.headers.get("X-Fixture")))
            if self.path.startswith("/redirect?"):
                self.send_response(302)
                self.send_header("Location", self.path.replace("/redirect?", "/recover?", 1))
                self.end_headers()
                return
            body = b'{"recovered":true}\n'
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        (target / "shell.qml").write_text(r'''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    Timer { interval: 10; running: true; onTriggered: {
        Http.send("GET", "http://127.0.0.1:PORT/redirect?query=fixture-private-query", null,
            {Authorization: "Bearer fixture-private-token", "X-Fixture": 'quote" slash\\ tab\t'}, 1000,
            xhr => {
                console.log(xhr.status === 200 && JSON.parse(xhr.responseText).recovered
                    ? "PASS: real curl recovered a stalled Qt read" : "FAIL: bad real curl response"); Qt.quit();
            }, why => { console.log("FAIL: " + why); Qt.quit(); });
    } }
    Timer { interval: 4000; running: true; onTriggered: { console.log("FAIL: real curl stalled"); Qt.quit(); } }
}'''.replace("PORT", str(server.server_port)))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=6)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "PASS: real curl recovered a stalled Qt read" in output and "FAIL:" not in output, output
        expected = ("Bearer fixture-private-token", 'quote" slash\\ tab\t')
        assert requests == [("/redirect?query=fixture-private-query", *expected), ("/recover?query=fixture-private-query", *expected)], "curl must preserve URLs and headers through redirects"
        assert "fixture-private" not in output, "real transport must not log credentials or queries"
        print("PASS: real curl preserves private URLs, quoted headers, redirects and response bodies")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    raise SystemExit(main())
