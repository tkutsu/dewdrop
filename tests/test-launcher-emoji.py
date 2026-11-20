#!/usr/bin/env python3
"""Find emoji by name and keyword in the launcher's : mode, and copy one."""

import subprocess
import tempfile
from pathlib import Path

from test_support import copy_shell, shell_env


QML = r'''import QtQuick
import Quickshell
import qs.src.core
import qs.src.services
ShellRoot {
    function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
    function first(q) { Launcher.query = q; return Launcher.results[0]?.emoji; }
    function top(q, n) { Launcher.query = q; return Launcher.results.slice(0, n).map(r => r.emoji); }
    property int step: 0
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: { try {
            if (step++ === 0) {
                Launcher.show();
                Launcher.query = ":";
                check(Launcher.classifyQuery(":").mode === ":", "a colon starts emoji mode");
                check(Launcher.queryIcon === Theme.glyph.launcherEmoji, "the query line shows the emoji glyph");
                check(Launcher.hintGroups[0].some(m => m.prefix === ":" && m.hint === "emoji"), "the hints list it with web, email and music");
                return;
            }
            if (!Launcher.results.length && step < 30) return;
            check(Launcher.results.length === Launcher.maxResults && Launcher.results[0].kind === "emoji", "a bare colon lists emoji");
            check(top(":lol", 3).includes("😂"), "a keyword finds it: lol");
            check(first(":puppy") === "🐶", "a keyword finds it: puppy");
            check(first(":fire") === "🔥", "the plain name wins: fire");
            check(first(":heart") === "❤️", "the plain name wins: heart");
            check(first(":thumbs up") === "👍", "every word has to match: thumbs up");
            check(first(":greece") === "🇬🇷", "a flag by its country");
            check(top(":lit", 3).includes("🔥"), "slang keywords count: lit");
            check(!top(":cat", 50).includes("😂"), "letters scattered across keywords do not match");
            Launcher.query = ":zzqx";
            check(Launcher.results.length === 0, "nothing matches nonsense");

            Launcher.query = ":rocket";
            Launcher.activate(0, "queue");
            check(!Launcher.shown && Launcher.frecency("emoji:🚀") > 0, "Enter copies, closes and remembers");
            Launcher.show();
            Launcher.query = ":";
            check(Launcher.results[0].emoji === "🚀", "the last pick heads the bare list");
            console.log("PASS: emoji complete"); Qt.quit();
        } catch (e) { console.log("FAIL: " + e + "\n" + e.stack); Qt.quit(); } }
    }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-launcher-emoji-") as folder:
        target = Path(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        # Copying is wl-copy; the fixture has no Wayland to copy to.
        bin_dir = target / "bin"
        bin_dir.mkdir()
        (bin_dir / "wl-copy").write_text("#!/bin/sh\ncat >/dev/null\n")
        (bin_dir / "wl-copy").chmod(0o755)
        env = shell_env(target)
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Unable to assign", "Binding loop")
        assert result.returncode == 0 and "PASS: emoji complete" in output and not any(e in output for e in errors), output


if __name__ == "__main__":
    main()
