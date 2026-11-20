#!/usr/bin/env python3
"""A filesystem on LUKS or LVM counts on the disk under it, and the system disk
still leads, as on a plain partition."""

import subprocess
import tempfile

from test_support import fixture_root, copy_shell, shell_env

QML = r'''import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.services
ShellRoot {
    function check(ok, message) { console.log((ok ? "PASS: " : "FAIL: ") + message); }
    Process {
        id: real
        command: ["sh", "-c", Sys.diskScript]
        stdout: StdioCollector { id: out }
        onExited: code => {
            check(code === 0 && out.text.split("\n").every(l => l === "" || l.split("\t").length >= 4),
                  "the disk script runs here and every line has its fields");
            Qt.quit();
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            const stat = "1 2 3 4 5 6 7 8 9 10 11";
            Sys.parseDf("/dev/sda2 /data 500 100\n/dev/mapper/cryptroot / 1000 400\n/dev/nvme0n1p1 /boot 100 50\n/dev/mapper/vg-home /home 2000 1000\n");
            Sys.parseDisks(`nvme0n1\t\t${stat}\tFast\nsda\t\t${stat}\tSlow\n`
                + "dm\tdm-0\tcryptroot\t nvme0n1p2\n"
                + "dm\tdm-2\tcryptlvm\t sda1\n"
                + "dm\tdm-1\tvg-home\t dm-2\n");
            const [first, second] = Sys.drives;
            check(first?.name === "nvme0n1" && first.total === 1100 && first.free === 450,
                  "a LUKS root counts on its disk, which leads: " + JSON.stringify(first));
            check(second?.name === "sda" && second.total === 2500 && second.free === 1100,
                  "LVM on LUKS counts on the disk two layers down: " + JSON.stringify(second));
            real.running = true;
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="qs-sys-disks-") as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / "shell.qml").write_text(QML)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines() if "PASS" in line or "FAIL" in line or "rror" in line))
        assert output.count("PASS:") == 3 and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
