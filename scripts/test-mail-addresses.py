#!/usr/bin/env python3
"""Exercise resumable Gmail header indexing and the real QML cache reader offline."""

import json
import io
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
import urllib.error
import urllib.parse
from unittest.mock import patch

from test_support import ROOT, copy_shell, shell_env


HELPER = runpy.run_path(str(ROOT / "scripts/gmail-addresses"))


def message(**headers):
    return {"internalDate": "100", "payload": {"headers": [{"name": key, "value": value} for key, value in headers.items()]}}


class Gmail:
    def __init__(self, replies, account="me@example.com", history="100"):
        self.replies = list(replies)
        self.account, self.history = account, history
        self.calls = []

    def get(self, path, **params):
        self.calls.append((path, params))
        if path == "/profile":
            return {"emailAddress": self.account, "historyId": self.history}
        expected, reply = self.replies.pop(0)
        assert expected == path, (expected, path)
        if isinstance(reply, Exception):
            raise reply
        return reply


class AddressesTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="gmail-addresses-")
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "index.sqlite"
        self.index = HELPER["Index"](self.path)
        self.addCleanup(lambda: self.index.db.close())

    def test_lists_resume_and_incremental_history(self):
        gmail = Gmail([
            ("/messages", {"messages": [{"id": "one"}, {"id": "two"}], "nextPageToken": "page &?"}),
            ("/messages/one", message(From='"Sample, Robin" <RSAMPLE@example.com>', To="Me <me@example.com>")),
        ])
        result = self.index.sync("grant", gmail, limit=1)
        self.assertTrue(result["more"])
        self.assertEqual(result["scanned"], 1)
        self.assertEqual(gmail.calls[1][1]["includeSpamTrash"], "true")
        self.assertEqual(gmail.calls[2][1]["format"], "metadata")
        self.assertEqual(set(gmail.calls[2][1]["metadataHeaders"]), {"From", "Sender", "Reply-To", "To", "Cc", "Bcc"})

        self.index.db.close()
        self.index = HELPER["Index"](self.path)
        gmail = Gmail([
            ("/messages/two", message(Cc="Other <other@example.org>", Bcc="hidden@example.net")),
            ("/messages", {"messages": [{"id": "one"}, {"id": "three"}]}),
            ("/messages/three", message(Sender="sender@example.org", **{"Reply-To": "reply@example.org"})),
            ("/history", {"historyId": "200", "history": [{"messagesAdded": [{"message": {"id": "four"}}]}]}),
            ("/messages/four", message(From="arrival@example.org")),
        ])
        result = self.index.sync("grant", gmail)
        self.assertFalse(result["more"])
        self.assertEqual(result["scanned"], 4)
        self.assertEqual(len(result["entries"]), 7)
        self.assertEqual(next(e["name"] for e in result["entries"] if e["address"] == "rsample@example.com"), "Sample, Robin")
        self.assertEqual(next(params["pageToken"] for path, params in gmail.calls if path == "/messages"), "page &?")
        self.assertEqual(next(params["startHistoryId"] for path, params in gmail.calls if path == "/history"), "100")
        gmail = Gmail([("/history", {"historyId": "210"})])
        self.index.sync("grant", gmail)
        self.assertEqual(gmail.calls[1][1]["startHistoryId"], "200")
        self.assertFalse(any(path.startswith("/messages") for path, _ in gmail.calls))

    def test_failure_and_deleted_message_resume(self):
        gmail = Gmail([
            ("/messages", {"messages": [{"id": "one"}, {"id": "two"}]}),
            ("/messages/one", message(From="saved@example.org")),
            ("/messages/two", urllib.error.HTTPError("fixture", 503, "Offline", {}, None)),
        ])
        with self.assertRaises(urllib.error.HTTPError):
            self.index.sync("grant", gmail)
        self.assertEqual(self.index.snapshot("grant")["scanned"], 1)
        gmail = Gmail([
            ("/messages/two", urllib.error.HTTPError("fixture", 404, "Deleted", {}, None)),
            ("/history", {"historyId": "110"}),
        ])
        result = self.index.sync("grant", gmail)
        self.assertFalse(result["more"])
        self.assertEqual(result["scanned"], 2)
        self.assertEqual(len(result["entries"]), 1)

    def test_history_pages_and_expired_history(self):
        self.index.sync("grant", Gmail([("/messages", {}), ("/history", {"historyId": "110"})]))
        gmail = Gmail([
            ("/history", {"nextPageToken": "more", "historyId": "120", "history": [{"messagesAdded": [{"message": {"id": "one"}}]}]}),
            ("/messages/one", message(From="first@example.org")),
        ])
        self.assertTrue(self.index.sync("grant", gmail, limit=1)["more"])
        gmail = Gmail([("/history", {"historyId": "120"})])
        self.assertFalse(self.index.sync("grant", gmail)["more"])
        self.assertEqual(gmail.calls[1][1]["startHistoryId"], "110")
        self.assertEqual(gmail.calls[1][1]["pageToken"], "more")
        gmail = Gmail([
            ("/history", urllib.error.HTTPError("fixture", 404, "Expired", {}, None)),
            ("/messages", {"messages": [{"id": "one"}, {"id": "two"}]}),
            ("/messages/two", message(From="new@example.org")),
            ("/history", {"historyId": "300"}),
        ], history="300")
        self.assertFalse(self.index.sync("grant", gmail)["more"])
        self.assertFalse(any(path == "/messages/one" for path, _ in gmail.calls))

    def test_account_isolation_and_reconsent(self):
        self.index.sync("old-grant", Gmail([
            ("/messages", {"messages": [{"id": "one"}]}),
            ("/messages/one", message(From="private@example.org")),
            ("/history", {"historyId": "110"}),
        ]))
        self.assertEqual(self.index.snapshot("new-grant")["entries"], [])
        other = self.index.sync("new-grant", Gmail([("/messages", {}), ("/history", {"historyId": "110"})], account="other@example.com"))
        self.assertEqual(other["entries"], [])
        restored = self.index.sync("renewed-grant", Gmail([("/history", {"historyId": "120"})]))
        self.assertEqual(restored["entries"][0]["address"], "private@example.org")

    def test_parsing(self):
        parsed = list(HELPER["addresses_of"](message(
            From='=?UTF-8?B?Sm9zw6k=?= <JOSE@example.org>',
            To='Team: "Doe, Jane" <jane@example.org>, second@example.org;',
            Cc="broken, nobody, x@localhost", Subject="not-an-address@example.org")))
        self.assertIn(("jose@example.org", "José"), parsed)
        self.assertIn(("jane@example.org", "Doe, Jane"), parsed)
        self.assertEqual(len(parsed), 3)

    def test_request_encoding_and_header_only_fetch(self):
        with patch("urllib.request.urlopen", return_value=io.BytesIO(b"{}")) as opened:
            HELPER["Gmail"]("fixture-token").get("/messages/id", format="metadata",
                metadataHeaders=HELPER["HEADERS"], pageToken="page &?")
        request = opened.call_args.args[0]
        params = urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query)
        self.assertEqual(request.get_header("Authorization"), "Bearer fixture-token")
        self.assertNotIn("fixture-token", request.full_url)
        self.assertEqual(params["metadataHeaders"], list(HELPER["HEADERS"]))
        self.assertEqual(params["pageToken"], ["page &?"])
        self.assertEqual(params["format"], ["metadata"])


QML = '''import QtQuick
import QtTest
import Quickshell
import qs.services
ShellRoot {
    TestCase { id: test; when: false }
    function check(ok, why) { if (!ok) throw Error(why); }
    Timer { interval: 10; running: true; onTriggered: {
        try {
            MailAddresses.ensure();
            test.tryVerify(() => MailAddresses.cached && !MailAddresses.loading, 3000);
            check(MailAddresses.entries[0]?.address === "cached@example.org", "saved addresses load offline");
            check(MailAddresses.entries[0]?.fields[0][1] === "cached@example.org", "cached fields are prepared for fuzzy matching");
            check(MailAddresses.trouble === "Offline", "token failure leaves cached addresses usable");
            Google.offline = false;
            MailAddresses.triedAt = 0;
            MailAddresses.ensure();
            test.tryVerify(() => !MailAddresses.loading && MailAddresses.entries[0]?.address === "fresh@example.org", 3000);
            check(MailAddresses.scanned === 2 && !MailAddresses.more && !MailAddresses.trouble,
                "a successful worker publishes addresses and clears the retry state");
            Google.ready();
            check(MailAddresses.entries.length === 0, "a new sign-in drops the previous account's in-memory suggestions");
            console.log("PASS: mailbox address cache reader");
        } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}'''


def check_qml():
    with tempfile.TemporaryDirectory(prefix="qs-mail-addresses-") as folder:
        target = Path(folder)
        copy_shell(target)
        env = shell_env(target)
        cache = Path(env["XDG_CACHE_HOME"]) / "quickshell/gmail-addresses.sqlite"
        cache.parent.mkdir(parents=True)
        creds = Path(env["XDG_DATA_HOME"]) / "quickshell/gtasks.json"
        creds.parent.mkdir(parents=True)
        creds.write_text(json.dumps({"client_id": "fixture", "refresh_token": "fixture"}))
        index = HELPER["Index"](cache)
        index.sync(HELPER["credential_key"](creds), Gmail([
            ("/messages", {"messages": [{"id": "one"}]}),
            ("/messages/one", message(From="Cached <cached@example.org>")),
            ("/history", {"historyId": "110"}),
        ]))
        index.db.close()
        helper = target / "scripts/gmail-addresses"
        real = target / "scripts/gmail-addresses-real"
        helper.rename(real)
        helper.write_text('import json, os, runpy, sys\n'
            'from pathlib import Path\n'
            'if "--cached" in sys.argv:\n'
            '    runpy.run_path(str(Path(__file__).with_name("gmail-addresses-real")), run_name="__main__")\n'
            'else:\n'
            '    assert os.environ.get("GMAIL_TOKEN") == "fixture-token"\n'
            '    assert "fixture-token" not in sys.argv\n'
            '    print(json.dumps({"entries": [{"address": "fresh@example.org", "name": "Fresh", "at": 100}], "scanned": 2, "more": False}))\n')
        (target / "services/Google.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { '
            'property bool configured: true; property bool needsConsent: false; property string file: "gtasks.json"; '
            'property bool offline: true; property string accessToken: "fixture-token"; property real tokenExpiry: 0; signal ready; '
            'function authorised(done, fail) { if (offline) fail("Offline"); else done(); } }')
        (target / "services/Launcher.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { '
            'property bool shown: false; property bool mailMode: false }')
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env, capture_output=True, text=True, timeout=6)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "Failed to load configuration")
        return result.returncode == 0 and "PASS: mailbox address cache reader" in output and not any(e in output for e in errors)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AddressesTest)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if outcome.wasSuccessful() and check_qml() else 1)
