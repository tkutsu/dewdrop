#!/usr/bin/env python3
"""Check watchdog selection and signal guards with fake processes and commands."""

import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / "scripts/qs-watchdog").read_text()
    functions = "\n".join(re.findall(r"^(?:bar_identity|select_bar|same_bar|render_ticks|restart)\(\) \{.*?^}", source, re.M | re.S))
    with tempfile.TemporaryDirectory(prefix="quickshell-watchdog-test-") as folder:
        target = Path(folder)
        proc = target / "proc"
        bar = str(target / "quickshell")
        config = str(target / "shell.qml")

        def process(pid, start, exe=bar):
            path = proc / str(pid)
            path.mkdir(parents=True, exist_ok=True)
            (path / "exe").symlink_to(exe)
            fields = ["S"] + ["0"] * 49
            fields[19] = str(start)
            (path / "stat").write_text(f"{pid} (name with ) parentheses) " + " ".join(fields) + "\n")

        process(10, 100)
        process(20, 200)
        process(30, 300, str(target / "unrelated"))
        task = proc / "10/task/11"
        task.mkdir(parents=True)
        (task / "comm").write_text("QSGRenderThread\n")
        fields = ["R"] + ["0"] * 49
        fields[11], fields[12] = "120", "30"
        (task / "stat").write_text("11 (QSGRenderThread) " + " ".join(fields) + "\n")
        task = proc / "10/task/12"
        task.mkdir()
        (task / "comm").write_text("unrelated\n")
        (task / "stat").write_text("ignored\n")
        instances = target / "instances.json"
        events = target / "events"

        def run(records, body):
            instances.write_text(json.dumps(records))
            events.write_text("")
            prelude = '''set -eu
BAR_CONFIG=$1 BAR_EXE=$2 fixture_proc=$3 instances=$4 events=$5
started="" pid="" reuse_at=""
qs() {
    if [ "$1" = list ]; then command cat "$instances"; return; fi
    printf 'qs %s\\n' "$*" >>"$events"
    if [ "$reuse_at" = graceful ]; then
        command sed -i 's/ 100 / 101 /' "$fixture_proc/10/stat"
    fi
}
timeout() { shift; "$@"; }
stat() {
    if [[ ${*: -1} = */20 ]]; then printf '%s\\n' "$((UID + 1))"; else command stat "$@"; fi
}
log() { :; }
sleep() { :; }
kill() {
    printf 'signal %s\\n' "$*" >>"$events"
    if [ "$reuse_at" = term ] && [ "$1" = -TERM ]; then
        command sed -i 's/ 100 / 101 /' "$fixture_proc/10/stat"
    fi
}
hyprctl() { printf 'relaunch\\n' >>"$events"; }
'''
            code = prelude + functions.replace("/proc/", "${fixture_proc}/") + "\n" + body
            result = subprocess.run(["bash", "-c", code, "fixture", config, bar, str(proc), str(instances), str(events)], capture_output=True, text=True, timeout=5)
            assert result.returncode == 0, result.stdout + result.stderr
            return events.read_text()

        record = {"config_path": config, "pid": 10}
        run([record], 'select_bar; [ "$pid" = 10 ]; [ "$started" = 100 ]; same_bar; [ "$(render_ticks)" = 150 ]')
        print("PASS: watchdog selects the owned bar and sums render ticks with builtins")
        for records in [[], [{"config_path": "other.qml", "pid": 10}], [record, record], [{"config_path": config, "pid": 20}], [{"config_path": config, "pid": 30}]]:
            run(records, 'if select_bar; then exit 1; fi')
        print("PASS: other configs, ambiguous instances, owners and executables are rejected")
        run([record], 'select_bar; started=101; restart; [ ! -s "$events" ]')
        assert "signal" not in run([record], 'select_bar; reuse_at=graceful; restart')
        (proc / "10/stat").write_text((proc / "10/stat").read_text().replace(" 101 ", " 100 "))
        output = run([record], 'select_bar; reuse_at=term; restart')
        assert "signal -TERM 10" in output and "-KILL" not in output
        (proc / "10/stat").write_text((proc / "10/stat").read_text().replace(" 101 ", " 100 "))
        output = run([record], 'select_bar; restart')
        assert output.count("signal -TERM 10") == 1 and output.count("signal -KILL 10") == 1
        assert output.count("relaunch") == 1
        print("PASS: changed identities block signals; an unchanged frozen fixture can restart")


if __name__ == "__main__":
    main()
