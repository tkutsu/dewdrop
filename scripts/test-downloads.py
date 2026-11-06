#!/usr/bin/env python3
"""A new, finished, unopened file counts as a download; opening the folder clears it."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
ShellRoot {
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function names() { return Downloads.unopened.map(f => f.name).sort().join(","); }
        function run() {
            test.tryVerify(() => Downloads.files.length > 0, 3000);
            check(names() === "fresh.bin,old-date.bin,renamed.bin", "only new, finished, unopened top-level files count: " + names());
            Downloads.open();
            check(names() === "", "opening the folder clears them");
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-downloads-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(SHELL)
        downloads = target / "dl"
        downloads.mkdir()
        (target / "settings.json").write_text(json.dumps({"downloadsDir": str(downloads), "fileManager": "true"}))

        now = time.time()
        state = target / "state/quickshell"
        state.mkdir(parents=True)
        (state / "downloads.json").write_text(json.dumps({"seen": now - 60}))

        def fixture(name, content=b"x"):
            path = downloads / name
            path.write_bytes(content)
            return path

        fixture("fresh.bin")
        # Created now, with a server's date on it.
        old = now - 86400
        os.utime(fixture("old-date.bin"), (old, old))
        # A rename moves neither its creation nor its write time.
        fixture("before.bin").rename(downloads / "renamed.bin")
        for name in ("a.zip.part", "b.crdownload", ".hidden", "c.tmp"):
            fixture(name)
        fixture("placeholder.zip", b"")
        (downloads / "folder").mkdir()
        (downloads / "folder/inside.bin").write_bytes(b"x")
        # Read a while after it arrived: opened.
        os.utime(fixture("opened.bin"), (now + 30, now))

        result = subprocess.run(["quickshell", "-p", str(target / "shell.qml")], cwd=target,
                                env=shell_env(target), capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        lines = [line for line in output.splitlines() if "PASS:" in line or "FAIL:" in line]
        print("\n".join(lines))
        seen = json.loads((state / "downloads.json").read_text())["seen"]
        ok = sum("PASS:" in line for line in lines) == 2 and not any("FAIL:" in line for line in lines)
        if not ok or seen <= now:
            print(output)
            raise SystemExit(1)


if __name__ == "__main__":
    main()
