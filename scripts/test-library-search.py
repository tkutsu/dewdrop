#!/usr/bin/env python3
"""Check music result grouping through the real library and fuzzy search."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_support import ROOT, shell_env


SHELL = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    function check(ok, message) { if (!ok) throw Error(message); }
    function checkOrder() {
        LauncherMusic.query = "iron maiden";
        const rows = LauncherMusic.results("iron maiden");
        console.log("Iron Maiden results: " + rows.map(row => row.kind + ":" + row.title).join(", "));
        check(rows[0]?.kind === "music-artist" && rows[1]?.kind === "music-album"
            && rows[1]?.title === "Iron Maiden" && rows[2]?.kind === "music-track",
            "the matching artist, self-titled album and songs appear in that order");
    }
    Timer { interval: 10; running: true; onTriggered: {
        try {
            Library.ensure();
            check(Library.loaded, "the library fixture loaded");
            checkOrder();
            LauncherMusic.query = "";
            Library.build([
                "debut/1.flac\\tIron Maiden\\tIron Maiden\\tIron Maiden\\tIron Maiden\\t1980\\t3:00",
                "debut/2.flac\\tIron Maiden\\tIron Maiden\\tIron Maiden\\tPhantom of the Opera\\t1980\\t7:00",
                "live/1.flac\\tIron Maiden\\tIron Maiden\\tLive After Death\\tIron Maiden\\t1985\\t4:00",
                "live/2.flac\\tIron Maiden\\tIron Maiden\\tLive After Death\\tPowerslave\\t1985\\t6:00"
            ].join("\\n"));
            checkOrder();
            check(!LauncherMusic.results("iron maiden").some(row => row.kind === "music-album" && row.title === "Live After Death"),
                "albums matching only through their artist stay under the artist");
            LauncherMusic.open = {"artist:0": true};
            const expanded = LauncherMusic.results("iron maiden");
            check(expanded[1].indent === 1 && expanded[2].indent === 1 && expanded[3].kind === "music-album" && expanded[3].indent === 0,
                "expanded artist children stay together before the standalone album");
            LauncherMusic.open = ({});
            LauncherMusic.query = "maiden phantom";
            check(LauncherMusic.results("maiden phantom")[0]?.title === "Phantom of the Opera",
                "combined artist and track terms still find the song");
            console.log("PASS: real library search grouping");
        } catch (error) { console.log("FAIL: " + error); }
        Qt.quit();
    } }
}
'''

FIXTURE = """debut/1.flac\tIron Maiden\tIron Maiden\tIron Maiden\tIron Maiden\t1980\t3:00
debut/2.flac\tIron Maiden\tIron Maiden\tIron Maiden\tPhantom of the Opera\t1980\t7:00
"""


def main():
    """Exercise real ranking, optionally replaying a captured MPD library first."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, help="also replay an MPD TSV containing Iron Maiden")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="qs-library-search-") as folder:
        target = Path(folder)
        services = target / "services"
        services.mkdir()
        for name in ("Library.qml", "LauncherMusic.qml"):
            shutil.copy(ROOT / "services" / name, services)
        for name in ("Fuzzy.js", "Paths.qml"):
            shutil.copy(ROOT / name, target)
        (services / "Mpd.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: false; property var playlists: []; property var queue: []; property int songPos: -1; signal databaseChanged() }\n')
        (services / "Launcher.qml").write_text('''pragma Singleton
import QtQuick
import "../Fuzzy.js" as Fuzzy
QtObject {
    readonly property int maxResults: 50
    readonly property bool musicMode: false
    function prepTerms(query) { return query.split(/\\s+/).filter(t => t.length).map(t => Fuzzy.prepQuery(t)); }
}
''')
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property var glyph: ({artist: "artist", album: "album", track: "track"}) }\n')
        (target / "Settings.qml").write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ property string home: "{target}"; property string mpdSocket: "" }}\n')
        (target / "shell.qml").write_text(SHELL)
        cache = target / "cache/quickshell/mpd-library.tsv"
        cache.parent.mkdir(parents=True)
        cache.write_text(args.library.read_text() if args.library else FIXTURE)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "Failed to load")
        return 0 if result.returncode == 0 and "PASS: real library search grouping" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
