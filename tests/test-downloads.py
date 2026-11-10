#!/usr/bin/env python3
"""A new, finished, unopened file counts as a download; opening the folder clears it and floats its window."""

import json
import os
from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile
import time

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.services
import qs.src.modules as Modules
ShellRoot {
    FloatingWindow {
        implicitWidth: 100; implicitHeight: 40
        Modules.Downloads { id: module; anchors.top: parent.top; anchors.left: parent.left }
    }
    TestCase { id: test; when: false
        function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
        function names() { return Downloads.unopened.map(f => f.name).sort().join(","); }
        function run() {
            test.tryVerify(() => Downloads.files.length > 0, 3000);
            check(names() === "fresh.bin,old-date.bin,renamed.bin", "only new, finished, unopened top-level files count: " + names());
            check(!module.quiet && Downloads.label === "3", "the module is out with a count of three");
            check(module.tooltip === "renamed.bin\\nold-date.bin\\nfresh.bin", "the tooltip names them, newest first: " + module.tooltip);
            test.mouseClick(module, module.width / 2, 10, Qt.RightButton);
            check(names() === "" && module.quiet && Downloads.label === "", "a right click clears them");
            check(module.tooltip === "Downloads", "the tooltip falls back to the module's name");
            test.wait(500);
            test.mouseClick(module, module.width / 2, 10, Qt.LeftButton);
            test.wait(300);
        }
    }
    Timer { interval: 100; running: true; onTriggered: { try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); } Qt.quit(); } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-downloads-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(SHELL)
        # Awkward on purpose: the path crosses a shell and a Lua string.
        downloads = target / "it's dl"
        downloads.mkdir()
        (target / "settings.json").write_text(json.dumps({"downloadsDir": str(downloads), "fileManager": f"touch {target / 'opened'}"}))

        # Stands in for Hyprland: keeps what it was asked and runs the command.
        service = target / "src/services/Downloads.qml"
        service.write_text(service.read_text().replace("import Quickshell.Hyprland\n", "")
                           .replace("Hyprland.dispatch(", "FakeHyprland.dispatch("))
        (target / "src/services/FakeHyprland.qml").write_text(f"""pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
QtObject {{
    property FileView log: FileView {{ path: {json.dumps(str(target / 'dispatched'))} }}
    function dispatch(request) {{
        log.setText(request);
        Quickshell.execDetached(["sh", "-c", JSON.parse(request.split("exec_cmd(")[1].split(", {{ float")[0])]);
    }}
}}
""")

        now = time.time()
        state = target / "state/quickshell"
        state.mkdir(parents=True, exist_ok=True)
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
        ok = sum("PASS:" in line for line in lines) == 5 and not any("FAIL:" in line for line in lines)
        # The file manager is detached, so it can finish just after the shell.
        for _ in range(20):
            if (target / "opened").exists():
                break
            time.sleep(0.1)
        floats = (target / "dispatched").exists() and "float = true" in (target / "dispatched").read_text()
        if not ok or seen <= now or not (target / "opened").exists() or not floats:
            print(output)
            raise SystemExit(1)


if __name__ == "__main__":
    main()
