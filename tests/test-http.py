#!/usr/bin/env python3
"""Every request is its own curl: answers, failures, deadlines and secrecy."""

import json
import os
from pathlib import Path
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
if "/slow" in config:
    sys.exit(28)
if "oauth2.googleapis.com/token" in config:
    print('{"access_token":"fixture-renewed-token","expires_in":3600}\\n200', end="")
elif "/unauthorised" in config and "fixture-renewed-token" not in config:
    print('{"error":{"errors":[{"reason":"authError"}]}}\\n401', end="")
elif "/http-error" in config:
    print('{"error":{"errors":[{"reason":"backendError"}]}}\\n503', end="")
else:
    print('{"ok":true}\\n200', end="")
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
    property var last: null
    TestCase { id: test; when: false }
    function check(ok, why) { if (!ok) throw Error(why); console.log("PASS: " + why); }
    function success(reply) { accepted++; last = reply; }
    function failure(why) { failed++; reason = why; }
    function run() {
        test.tryVerify(() => configured, 1000);
        Google.accessToken = "fixture-private-token";
        Google.tokenExpiry = Date.now() + 3600000;

        Http.send("GET", "https://fixture.invalid/read?q=fixture-private-query", null, {Authorization: "Bearer fixture-private-token"}, 2000, success, failure);
        test.tryVerify(() => accepted === 1, 1800);
        check(last.status === 200 && JSON.parse(last.responseText).ok, "a read comes back with its status and body");

        Http.send("POST", "https://fixture.invalid/label", {secret: "fixture-private-body"}, {}, 2000, success, failure);
        test.tryVerify(() => accepted === 2, 1800);
        check(failed === 0, "a write comes back once");

        Http.send("POST", "https://fixture.invalid/move", null, {}, 2000, success, failure);
        test.tryVerify(() => accepted === 3, 1800);
        check(true, "a write with no body comes back too");

        Http.send("GET", "https://fixture.invalid/http-error", null, {}, 2000, success, failure);
        test.tryVerify(() => accepted === 4, 1800);
        check(last.status === 503 && failed === 0, "an HTTP failure is an answer, with its status");

        Http.send("GET", "https://fixture.invalid/unavailable", null, {}, 2000, success, failure);
        test.tryVerify(() => failed === 1, 1800);
        check(reason === "Couldn't connect right now.", "no connection reports a friendly error once");

        Http.send("GET", "https://fixture.invalid/slow", null, {}, 2000, success, failure);
        test.tryVerify(() => failed === 2, 1800);
        check(reason === "The server is taking too long to respond.", "curl's own timeout says the server is slow");

        Http.send("GET", "https://fixture.invalid/hang", null, {}, 300, success, failure);
        test.tryVerify(() => failed === 3, 800);
        check(reason === "The server is taking too long to respond.", "a curl that never lets go is killed at the deadline");
        test.wait(500);
        check(failed === 3 && accepted === 4, "and settles only once");

        Http.send("GET", "file:///etc/passwd", null, {}, 2000, success, failure);
        check(failed === 4, "only http and https are fetched");

        api.send("GET", "https://fixture.invalid/unauthorised", null, success, failure);
        test.tryVerify(() => accepted === 5, 2500);
        check(Google.accessToken === "fixture-renewed-token" && failed === 4 && api.requests === 0,
            "a 401 renews the token and the request goes again behind it");
        console.log("PASS: HTTP lifecycle");
    }
    Timer { interval: 100; running: true; onTriggered: {
        try { root.run(); } catch (error) { console.log("FAIL: " + error + "\n" + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-http-") as folder:
        target = fixture_root(folder)
        services = target / "src/services"
        services.mkdir()
        for name in ("Http", "GoogleAccount", "Google", "GoogleService"):
            (services / f"{name}.qml").write_text((ROOT / f"src/services/{name}.qml").read_text())
        (target / "src/lib/Pages.js").write_text((ROOT / "src/lib/Pages.js").read_text())
        (services / "WallClock.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { signal wokeUp }")
        (services / "Retry.qml").write_text("import QtQuick\nQtObject { property bool active: false; property bool pending: false; signal triggered; function reset() {} function cancel() {} function schedule() {} function retryNow() {} }")
        (services / "TestApi.qml").write_text("pragma Singleton\nimport QtQuick\nGoogleService { polling: false }")
        (target / "src/core/Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string home: ""; function inTerminal(command, title) { return command; } }')
        (target / "src/core/Paths.qml").write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nQtObject { function data(name) { return Quickshell.shellPath(name); } }')
        (target / "gtasks.json").write_text(json.dumps({"client_id": "fixture", "client_secret": "fixture-private-secret", "refresh_token": "fixture-private-refresh"}))
        binary = target / "bin/curl"
        binary.parent.mkdir()
        binary.write_text(FAKE_CURL)
        binary.chmod(0o755)
        (target / "shell.qml").write_text(QML)
        calls = target / "calls.jsonl"
        env = shell_env(target, PATH=str(binary.parent) + os.pathsep + os.environ["PATH"], HTTP_CALLS=str(calls))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Failed to load configuration")
        if result.returncode or "PASS: HTTP lifecycle" not in output or any(error in output for error in errors):
            return 1

        requests = [json.loads(line) for line in calls.read_text().splitlines()]
        config = lambda part: next(call["config"] for call in requests if part in call["config"])
        read = config("/read")
        assert 'request =' not in read and "data-raw" not in read, "a read is a plain GET"
        assert 'header = "Authorization: Bearer fixture-private-token"' in read, read
        label = config("/label")
        assert 'request = "POST"' in label and 'data-raw = "{\\"secret\\":\\"fixture-private-body\\"}"' in label, label
        assert 'header = "Content-Type: application/json"' in label, label
        move = config("/move")
        assert 'request = "POST"' in move and 'header = "Content-Length: 0"' in move and "data-raw" not in move, move
        token = config("oauth2.googleapis.com/token")
        assert "grant_type=refresh_token" in token and "application/x-www-form-urlencoded" in token, token
        assert not any("file:" in call["config"] for call in requests), "a non-http URL never reaches curl"
        assert all(call["args"][0] == "--disable" for call in requests), "user curlrc cannot change requests"
        assert all("--ipv4" not in call["args"] and "--compressed" in call["args"] for call in requests)
        assert all("fixture-private" not in " ".join(call["args"]) for call in requests), "secrets stay out of process arguments"
        assert "fixture-private" not in output, "logs must not contain tokens, bodies, queries or curl stderr"
        assert "outcome=http-error status=503" in output and "outcome=network-error status=0" in output and "exit=7" in output
        assert "outcome=timeout" in output and "outcome=deadline" in output
        assert "outcome=" not in "\n".join(l for l in output.splitlines() if "/read" in l), "a healthy request logs nothing"
        print("PASS: one curl per request, secrets kept out of argv and logs")

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
        Http.send("GET", "https://fixture.invalid/start-error", null, {}, 300,
            () => console.log("FAIL: missing curl succeeded"), () => failures++) }
    Timer { interval: 1400; running: true; onTriggered: {
        console.log(failures === 1 ? "PASS: missing curl settles once" : "FAIL: missing curl stranded callback"); Qt.quit();
    } }
}''')
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=6)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "PASS: missing curl settles once" in output and "outcome=start-error status=0" in output, output
        print("PASS: missing curl is logged as a start failure")
        path.write_text(source)

        if "--real-curl" in sys.argv:
            real_curl(target)
        return 0


def real_curl(target):
    """Prove curl config quoting, redirects, bodies and response framing on a local server."""
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import threading

    requests = []

    class Handler(BaseHTTPRequestHandler):
        def answer(self, body):
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            requests.append(("GET", self.path, self.headers.get("Authorization"), self.headers.get("X-Fixture")))
            if self.path.startswith("/redirect?"):
                self.send_response(302)
                self.send_header("Location", self.path.replace("/redirect?", "/landed?", 1))
                self.end_headers()
                return
            self.answer(b'{"landed":true}\n')

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "-1"))
            body = self.rfile.read(length).decode() if length > 0 else ""
            requests.append(("POST", self.path, self.headers.get("Content-Type"), body, length))
            self.answer(b'{"posted":true}')

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
    property int done: 0
    function next() { if (++done === 3) { console.log("PASS: real curl answered all three"); Qt.quit(); } }
    Timer { interval: 10; running: true; onTriggered: {
        Http.send("GET", "http://127.0.0.1:PORT/redirect?query=fixture-private-query", null,
            {Authorization: "Bearer fixture-private-token", "X-Fixture": 'quote" slash\\ tab\t'}, 3000,
            xhr => { if (xhr.status === 200 && JSON.parse(xhr.responseText).landed) next(); else console.log("FAIL: bad GET"); },
            why => console.log("FAIL: " + why));
        Http.send("POST", "http://127.0.0.1:PORT/modify", {removeLabelIds: ["INBOX", "UNREAD"]}, {}, 3000,
            xhr => { if (xhr.status === 200 && JSON.parse(xhr.responseText).posted) next(); else console.log("FAIL: bad POST"); },
            why => console.log("FAIL: " + why));
        Http.send("POST", "http://127.0.0.1:PORT/move", null, {}, 3000,
            xhr => { if (xhr.status === 200) next(); else console.log("FAIL: bad empty POST"); },
            why => console.log("FAIL: " + why));
    } }
    Timer { interval: 5000; running: true; onTriggered: { console.log("FAIL: real curl stalled"); Qt.quit(); } }
}'''.replace("PORT", str(server.server_port)))
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "PASS: real curl answered all three" in output and "FAIL:" not in output, output
        expected = ("Bearer fixture-private-token", 'quote" slash\\ tab\t')
        gets = [r for r in requests if r[0] == "GET"]
        posts = {r[1]: r for r in requests if r[0] == "POST"}
        assert gets == [("GET", "/redirect?query=fixture-private-query", *expected), ("GET", "/landed?query=fixture-private-query", *expected)], gets
        assert posts["/modify"][2:] == ("application/json", '{"removeLabelIds":["INBOX","UNREAD"]}', 37), posts
        assert posts["/move"][4] == 0, "an empty POST says Content-Length: 0"
        assert "fixture-private" not in output, "real transport must not log credentials or queries"
        print("PASS: real curl keeps URLs, quoted headers, redirects, bodies and response framing")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    raise SystemExit(main())
