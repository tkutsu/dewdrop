#!/usr/bin/env python3
"""HyprExec writes a command Lua reads and sh runs word for word.

Each call is compiled and run by a real Lua with a stub hl.dsp.exec_cmd, and
the line it gets is run by sh: the words printf prints must be the ones given,
quotes, backslashes, control characters and all.
"""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from test_support import ROOT, fixture_root, shell_env

WORDS = ["it's", 'a "b" \\c', "tab\there", "bell\x07and\x01", "line\nbreak", "α β ✓", "$HOME `x`"]
DIR = "quote's dir"

SHELL = '''import QtQuick
import Quickshell
import "HyprExec.js" as HyprExec
ShellRoot {
    Timer { interval: 10; running: true; onTriggered: {
        console.log("CALL " + JSON.stringify(HyprExec.dispatch(ARGV, '{ workspace = "empty silent" }', "")));
        console.log("CALL " + JSON.stringify(HyprExec.dispatch(["pwd"], "{ float = true }", DIR)));
        Qt.quit();
    } }
}'''

LUA = '''hl = { dsp = { exec_cmd = function(line, rules) io.write(line, "\\0") end } }
local chunk, err = load(io.read("a"))
if not chunk then io.stderr:write(err) os.exit(2) end
chunk()
'''


def main():
    lua = shutil.which("lua5.4") or shutil.which("lua")
    if not lua:
        print("SKIP: no lua")
        return 0
    with tempfile.TemporaryDirectory(prefix="quickshell-hypr-exec-") as folder:
        target = fixture_root(folder)
        shutil.copy(ROOT / "src/lib/HyprExec.js", target / "HyprExec.js")
        argv = ["printf", "[%s]"] + WORDS
        (target / "shell.qml").write_text(SHELL.replace("ARGV", json.dumps(argv)).replace("DIR", json.dumps(str(target / DIR))))
        (target / DIR).mkdir()
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=8)
        calls = [json.loads(line.split("CALL ", 1)[1]) for line in (result.stdout + result.stderr).splitlines() if "CALL " in line]
        if len(calls) != 2:
            print(result.stdout + result.stderr)
            print("FAIL: HyprExec gave no calls")
            return 1
        failures = 0
        for call, expected in zip(calls, ["".join(f"[{w}]" for w in WORDS), str(target / DIR) + "\n"]):
            ran = subprocess.run([lua, "-e", LUA], input=call.encode(), capture_output=True)
            if ran.returncode != 0:
                print(f"FAIL: Lua cannot read {call!r}: {ran.stderr.decode()}")
                failures += 1
                continue
            line = ran.stdout.rstrip(b"\0").decode()
            out = subprocess.run(["sh", "-c", line], capture_output=True, text=True).stdout
            if out != expected:
                print(f"FAIL: sh ran {line!r} as {out!r}, not {expected!r}")
                failures += 1
            else:
                print(f"PASS: {call[:60]}…")
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
