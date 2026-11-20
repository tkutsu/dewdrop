#!/usr/bin/env python3
"""A sign-in made in a terminal (gtasks-auth run by hand, as the bar's messages
say to) is taken up without a restart: written fresh, and written over."""

import json
import os
import subprocess
import tempfile
import threading
import time

from test_support import fixture_root, copy_shell, shell_env

QML = '''import QtQuick
import Quickshell
import qs.src.services
ShellRoot {
    property int ticks: 0
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            ticks++;
            console.log("STATE " + ticks + " configured=" + Google.configured + " dead=" + Google.tokenDead);
            if (ticks === 2)
                Google.tokenDead = true;
            if (ticks >= 24)
                Qt.quit();
        }
    }
}
'''


def write(path, token):
    """As gtasks-auth does: a temporary file in the same folder, then a rename over."""
    temporary = path.with_name("gtasks-tmp")
    temporary.write_text(json.dumps({"client_id": "id", "client_secret": "secret", "refresh_token": token}))
    os.replace(temporary, path)


def main():
    with tempfile.TemporaryDirectory(prefix="qs-google-watch-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        data = target / "data/quickshell"
        data.mkdir(parents=True, exist_ok=True)
        path = data / "gtasks.json"
        write(path, "first")

        def sign_in_again():
            time.sleep(2.5)
            write(path, "second")

        threading.Thread(target=sign_in_again, daemon=True).start()
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        states = [line.split("STATE ", 1)[1] for line in output.splitlines() if "STATE " in line]
        print("\n".join(states))
        assert any("configured=true dead=true" in s for s in states), "the token never read as dead"
        assert states and "configured=true dead=false" in states[-1], \
            "a sign-in written over the file was not taken up:\n" + output


if __name__ == "__main__":
    main()
