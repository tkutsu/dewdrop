#!/usr/bin/env python3
"""Check current-queue controls, library search, and music-mode startup."""

from pathlib import Path
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
    property var rows: Launcher.results
    property var temporaryRows: []
    property bool watching: false
    onRowsChanged: if (watching) {
        for (const row of rows)
            if (row.kind === "note" || row.kind === "music-start")
                temporaryRows.push(row.title);
    }
    function check(ok, message) { if (!ok) throw Error(message); }
    function closeMode() { watching = false; Launcher.query = ""; test.wait(10); }
    Timer { interval: 10; running: true; onTriggered: {
        try {
            const queue = [
                {pos: 0, title: "First", artist: "Artist", album: "Album", file: "album/first.flac"},
                {pos: 1, title: "Current", artist: "Artist", album: "Album", file: "album/current.flac"},
                {pos: 2, title: "Last", artist: "Artist", album: "Album", file: "album/last.flac"}
            ];
            Mpd.connected = true;
            Mpd.queue = queue;
            Mpd.songPos = 1;
            Mpd.state = "play";
            Launcher.query = "#";
            test.wait(10);
            check(rows.length === 3 && rows.every(row => row.kind === "music-queue"), "bare hash shows the current queue immediately");
            check(Launcher.index === 1 && rows[1].glyph === Theme.glyph.paused && rows.filter(row => row.glyph).length === 1, "only the current track has a playback icon");
            check(Library.reads === 0, "queue browsing does not load the library");
            check(LauncherMusic.coverDir === "/music/album/", "queue selections show their artwork directory");
            Mpd.musicDir = "";
            check(LauncherMusic.coverDir === "", "queue artwork stays unavailable without MPD's directory");
            Mpd.musicDir = "/changed music/";
            check(LauncherMusic.coverDir === "/changed music/album/", "queue artwork follows MPD's directory");
            Mpd.musicDir = "/music/";
            check(!LauncherMusic.activate(Launcher.selected, "queue") && Mpd.state === "pause", "activating the playing row pauses and keeps the launcher open");
            check(rows[1].glyph === Theme.glyph.playing && rows.filter(row => row.glyph).length === 1, "only the paused current track shows the play icon");
            check(!LauncherMusic.activate(Launcher.selected, "queue") && Mpd.commands.join(",") === "pause,resume", "play resumes the paused current track");
            LauncherMusic.activate(Launcher.selected, "play");
            check(Mpd.commands.length === 2, "playing the current track again does not restart it");
            Launcher.index = 2;
            check(!LauncherMusic.activate(Launcher.selected, "play") && Mpd.commands[2] === "play 2", "choosing another track plays its existing queue position");
            check(Mpd.queue === queue && Mpd.queue.length === 3, "play and pause preserve the queue");
            Mpd.songPos = 0; test.wait(10);
            check(Launcher.index === 2, "playback updates do not move a selection being browsed");
            check(rows[0].glyph === Theme.glyph.paused && rows[1].glyph === "" && rows[2].glyph === "", "the playback icon follows the current song");
            const removed = rows[0];
            Mpd.queue = queue.slice(1);
            LauncherMusic.activate(removed, "play");
            check(Mpd.commands.length === 3, "removed queue entries cannot activate a different track");

            closeMode();
            Mpd.queue = [];
            Mpd.connected = false;
            temporaryRows = [];
            watching = true;
            Launcher.query = "#";
            test.wait(30);
            Mpd.connected = true;
            test.wait(30);
            Mpd.queue = queue;
            Mpd.songPos = 1;
            test.wait(30);
            check(rows[0]?.kind === "music-queue" && Launcher.index === 1 && temporaryRows.length === 0,
                "an arriving queue selects the current track without a startup flash");

            closeMode();
            Library.loaded = false;
            temporaryRows = [];
            watching = true;
            Launcher.query = "#song";
            test.wait(180);
            check(rows[0]?.kind === "music-track" && Library.reads === 1, "typing after hash searches the library");
            check(temporaryRows.length === 0, "quick library read flashes a temporary row: " + temporaryRows.join(", "));
            watching = false;
            Launcher.query = "#fixture"; test.wait(80);
            check(rows[0]?.kind === "music-playlist", "stored playlists remain searchable");
            Launcher.query = "#"; test.wait(10);
            check(rows[0]?.kind === "music-queue" && Launcher.index === 1, "clearing a search returns directly to the current queue");

            Library.loaded = false;
            const reads = Library.reads;
            Launcher.query = "# "; test.wait(180);
            check(rows.length === Library.tracks.length && rows.every(row => row.kind === "music-track"),
                "hash followed by a space shows every library track with a nonempty queue");
            check(Library.reads === reads + 1 && !LauncherMusic.queueSelectionPending,
                "explicit library browsing loads tracks without selecting the current queue song");
            Launcher.index = 4;
            Mpd.songPos = 2; Mpd.queue = queue.slice(); test.wait(10);
            check(Launcher.index === 4 && rows.every(row => row.kind === "music-track"),
                "queue updates keep explicit library browsing and its selection");
            Launcher.query = "#   "; test.wait(10);
            check(rows.length === Library.tracks.length && rows.every(row => row.kind === "music-track"),
                "extra spaces keep the complete library visible");
            Launcher.query = "# song"; test.wait(80);
            check(rows.length === 1 && rows[0].title === "Library song", "typing after a space searches the library");
            Mpd.songPos = 1;
            Launcher.query = "#"; test.wait(10);
            check(rows.every(row => row.kind === "music-queue") && Launcher.index === 1,
                "removing the space restores the queue and selects the current song");

            closeMode();
            Library.loaded = false;
            Mpd.connected = false;
            temporaryRows = [];
            watching = true;
            Launcher.query = "#song";
            test.wait(30);
            Mpd.connected = true;
            test.wait(180);
            check(rows[0]?.kind === "music-track" && temporaryRows.length === 0,
                "quick MPD connection does not flash start music or a loading row");

            closeMode();
            Library.loaded = false;
            Mpd.connected = false;
            Mpd.queue = [];
            Launcher.query = "#";
            test.wait(300);
            check(rows[0]?.kind === "music-start", "stopped MPD still offers start music after settling");

            closeMode();
            Mpd.connected = true;
            Launcher.query = "#";
            test.wait(300);
            check(rows.length === Library.tracks.length && rows.every(row => row.kind === "music-track"),
                "an empty queue shows every library track");
            check(rows[0].title === "Library song" && rows[0].indent === 0,
                "library fallback uses actionable top-level track rows");
            Mpd.queue = queue;
            test.wait(10);
            check(rows.every(row => row.kind === "music-queue"), "an arriving queue replaces the library fallback");
            Library.loaded = false;
            Mpd.queue = [];
            test.wait(180);
            check(rows.length === Library.tracks.length && rows.every(row => row.kind === "music-track"),
                "clearing the queue while browsing loads the library fallback");

            closeMode();
            Library.loaded = false;
            Library.delay = 1000;
            Mpd.connected = true;
            Launcher.query = "#song";
            test.wait(300);
            check(rows[0]?.title === "reading the library", "slow library reads still show their status");

            closeMode();
            Mpd.connected = false;
            Library.loaded = false;
            Launcher.query = "#";
            test.wait(20);
            closeMode();
            test.wait(300);
            check(LauncherMusic.results("").length === 0, "leaving music mode cancels pending status");
            console.log("PASS: music-mode entry, queue playback and library search");
        } catch (error) { console.log("FAIL: " + error); }
        Qt.quit();
    } }
}
'''


def main():
    """Run the real music-mode service with delayed, isolated dependencies."""
    with tempfile.TemporaryDirectory(prefix="quickshell-launcher-music-") as folder:
        target = Path(folder)
        services = target / "services"
        services.mkdir()
        (services / "LauncherMusic.qml").write_text((ROOT / "services/LauncherMusic.qml").read_text())
        mocks = {
            "Launcher": '''property string query: ""
                readonly property string musicPrefix: "#"
                property int index: 0
                readonly property bool musicMode: query.startsWith("#")
                readonly property int maxResults: 50
                readonly property var classification: classifyQuery(query)
                readonly property var results: musicMode ? LauncherMusic.results(classification.text) : []
                readonly property var selected: results[index] ?? null
                function classifyQuery(text) { return {text: text.slice(1).trim()}; }
                function prepTerms(text) { return text.toLowerCase().split(" "); }
                function matchScore(terms, fields) { return terms.every(term => fields[0][0].toLowerCase().includes(term)) ? 1 : null; }
                function noteRow(glyph, title) { return {kind: "note", glyph, title}; }
                onQueryChanged: LauncherMusic.route(query.startsWith("#"), classifyQuery(query).text)''',
            "Mpd": '''property bool connected: false
                property string musicDir: "/music/"
                property bool starting: false
                property var queue: []
                property int songPos: -1
                property string state: "stop"
                readonly property string stateIcon: state
                property var commands: []
                function pause() { commands = commands.concat("pause"); state = "pause"; }
                function toggle() { commands = commands.concat("resume"); state = "play"; }
                function playAt(pos) { commands = commands.concat("play " + pos); songPos = pos; state = "play"; }
                property var playlists: ["fixture playlist"]''',
            "Library": '''property bool loaded: false
                property bool loading: false
                property bool failed: false
                property int reads: 0
                property int delay: 80
                property var tracks: Array.from({length: 60}, (_, at) => ({title: at ? "Track " + at : "Library song", artist: "Artist", album: 0, time: "3:00"}))
                function search(query) { return query === "song" ? [{kind: "track", at: 0, score: 1}] : []; }
                function albumName(at) { return "Album"; }
                function coverDir(kind, at) { return "/music/album/"; }
                function ensure() { if (!loaded && !loading) { reads++; loading = true; ready.restart(); } }
                property Timer ready: Timer { interval: delay; onTriggered: { loaded = true; loading = false; } }''',
        }
        for name, body in mocks.items():
            (services / f"{name}.qml").write_text("pragma Singleton\nimport QtQuick\nimport qs.services\nQtObject {\n" + body + "\n}\n")
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { readonly property var glyph: ({playing: "play", paused: "pause", track: "track", playlist: "playlist"}) }\n')
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {}\n')
        (target / "shell.qml").write_text(SHELL)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "Failed to load")
        return 0 if result.returncode == 0 and "PASS: music-mode entry" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
