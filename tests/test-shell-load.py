#!/usr/bin/env python3
"""Compile the real shell entry point and its imports without desktop actions."""

from pathlib import Path
import os
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


QML = '''ShellRoot {
    Timer {
        interval: 20; running: true
        onTriggered: {
            const entry = Qt.createComponent(Qt.resolvedUrl("entry.qml"));
            if (entry.status === Component.Ready)
                console.log("PASS: real shell entry point compiles");
            else
                console.log("FAIL: " + entry.errorString());
            Qt.quit();
        }
    }
}
'''


def main():
    display = os.environ.get("WAYLAND_DISPLAY")
    if not display:
        print("SKIP: a Wayland connection is needed to compile PanelWindow")
        return
    with tempfile.TemporaryDirectory(prefix="dewdrop-load-") as folder:
        target = Path(folder)
        copy_shell(target)
        entry = (ROOT / "shell.qml").read_text()
        imports = "\n".join(line for line in entry.splitlines() if line.startswith("import "))
        (target / "entry.qml").write_text(entry)
        (target / "shell.qml").write_text(imports + "\n" + QML)
        display = str(Path(os.environ["XDG_RUNTIME_DIR"]) / display)
        env = shell_env(target, QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=display)
        done = subprocess.run(["qs", "-p", str(target), "--no-color"],
                              env=env, capture_output=True, text=True, timeout=20)
        output = done.stdout + done.stderr
        print(output, end="")
        assert done.returncode == 0 and "PASS: real shell entry point compiles" in output, output
        assert "FAIL:" not in output and "Failed to load configuration" not in output, output


if __name__ == "__main__":
    main()
