#!/usr/bin/env python3
"""Check an external dropdown runner without launching terminals or commands."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ["DROPDOWN_TEST_ROOT"])
args = sys.argv[1:]
case = os.environ["DROPDOWN_TEST_CASE"]
def record(kind):
    with (root / "events").open("a") as output:
        output.write(json.dumps([kind, args]) + "\n")
if Path(sys.argv[0]).name == "kitty":
    record("fallback")
    sys.exit(0)
if args[0] == "quick_access_terminal":
    record("start")
    if case == "startup-fails": sys.exit(1)
    (root / "started").touch()
    (root / "visible").touch()
    if case not in ("delayed", "no-socket"): (root / "runtime/kitty-dropdown-new.sock").touch()
    sys.exit(0)
socket = Path(args[args.index("--to") + 1].removeprefix("unix:"))
if case == "delayed" and (root / "started").exists():
    counter = root / "attempts"
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if count == 3: (root / "runtime/kitty-dropdown-new.sock").touch()
if not socket.exists() or socket.name == "kitty-dropdown-stale.sock": sys.exit(1)
record("split")
'''


def check(runner, case):
    """Exercise socket discovery, startup and fallback using recorded launches."""
    with tempfile.TemporaryDirectory(prefix="qs-dropdown-run-") as folder:
        root = Path(folder)
        (root / "runtime").mkdir()
        (root / "bin").mkdir()
        script = root / "dropdown-run.sh"
        shutil.copy2(runner, script)
        (root / "proc-lib.sh").write_text('dropdown_open() { [ -e "$DROPDOWN_TEST_ROOT/visible" ]; }\n')
        for name in ("kitty", "kitten"):
            command = root / "bin" / name
            command.write_text(MOCK)
            command.chmod(0o755)
        if case in ("visible", "hidden", "stale"):
            name = "stale" if case == "stale" else "existing"
            (root / "runtime" / f"kitty-dropdown-{name}.sock").touch()
        if case == "visible":
            (root / "visible").touch()
        env = dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                   XDG_RUNTIME_DIR=str(root / "runtime"), DROPDOWN_TEST_ROOT=str(root),
                   DROPDOWN_TEST_CASE=case)
        command = ["/usr/bin/true", "argument with spaces"]
        result = subprocess.run(["bash", str(script), "Test title", *command], env=env,
                                capture_output=True, text=True, timeout=8)
        events = [json.loads(line) for line in (root / "events").read_text().splitlines()]
        kinds = [event[0] for event in events]
        expected = {"visible": ["split"], "hidden": ["split", "start"],
                    "missing": ["start", "split"], "delayed": ["start", "split"],
                    "stale": ["start", "split"], "startup-fails": ["start", "fallback"],
                    "no-socket": ["start", "fallback"]}[case]
        assert result.returncode == 0 and kinds == expected, (case, kinds, result.stderr)
        launched = next(args for kind, args in events if kind in ("split", "fallback"))
        assert launched[-3:] == ["Test title", *command], (case, launched)
        if case == "delayed":
            assert int((root / "attempts").read_text()) >= 4
        print(f"PASS: {case}: {' -> '.join(kinds)}")


if __name__ == "__main__":
    runner = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "_scripts/dropdown-run.sh"
    for case in ("visible", "hidden", "missing", "delayed", "stale", "startup-fails", "no-socket"):
        check(runner, case)
