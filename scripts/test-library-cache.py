#!/usr/bin/env python3
"""Check that the music library is cached from mpd and read back while mpd is down."""

from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import ROOT, shell_env


SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
ShellRoot {
    TestCase { id: test; when: false }
    function check(ok, message) { if (!ok) throw Error(message); }
    Timer { interval: 10; running: true; onTriggered: {
        try {
            test.wait(50);
            check(!Library.loaded && !Library.loading, "the cache is not read at startup");
            Library.ensure();
            test.tryVerify(() => !Library.loading, 2000);
            check(Library.loaded && Library.tracks.length === 1 && Library.tracks[0].title === "Cached Song",
                "with mpd down the library comes from the cache");

            Mpd.connected = true;
            check(!Library.loaded, "mpd coming up drops the cached copy");
            Library.ensure();
            test.tryVerify(() => !Library.loading, 2000);
            check(Library.loaded && Library.tracks[0].title === "Live Song", "with mpd up the library is dumped");
            console.log("PASS: library cache");
        } catch (error) { console.log("FAIL: " + error); }
        Qt.quit();
    } }
}
'''

LIVE = "a/live.flac\tArtist\tArtist\tAlbum\tLive Song\t2001\t3:00\n"
CACHED = "a/cached.flac\tArtist\tArtist\tAlbum\tCached Song\t2001\t3:00\n"


def main():
    """Run the real Library against a cache file and a stand-in mpc."""
    with tempfile.TemporaryDirectory(prefix="quickshell-library-cache-") as folder:
        target = Path(folder)
        services = target / "services"
        services.mkdir()
        shutil.copy(ROOT / "services/Library.qml", services)
        shutil.copy(ROOT / "Fuzzy.js", target)
        shutil.copy(ROOT / "Paths.qml", target)
        (services / "Mpd.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "    property bool connected: false\n"
            "    signal databaseChanged()\n"
            "}\n")
        (target / "Settings.qml").write_text(
            f'pragma Singleton\nimport QtQuick\nQtObject {{ property string home: "{target}"; property string mpdSocket: "" }}\n')
        (target / "shell.qml").write_text(SHELL)

        cache = target / "cache/quickshell/mpd-library.tsv"
        cache.parent.mkdir(parents=True)
        cache.write_text(CACHED)
        bin_dir = target / "bin"
        bin_dir.mkdir()
        mpc = bin_dir / "mpc"
        mpc.write_text(f"#!/bin/sh\nprintf '%s' '{LIVE}'\n")
        mpc.chmod(0o755)

        env = shell_env(target, PATH=f"{bin_dir}:{shell_env(target)['PATH']}")
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=env,
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "Failed to load")
        ok = result.returncode == 0 and "PASS: library cache" in output and not any(e in output for e in errors)
        if ok and cache.read_text() != LIVE:
            print("FAIL: the dump was not written to the cache")
            ok = False
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
