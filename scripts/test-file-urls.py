#!/usr/bin/env python3
"""Check real cover lookup and image loading through encoded local paths."""

import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
import qs.services
import "FileUrl.js" as FileUrl
ShellRoot {
    property var player: Mpd
    FloatingWindow {
        implicitWidth: 300; implicitHeight: 100
        CoverArt { id: sleeve; width: 60; dir: ALBUM_DIR }
        Image { id: image; source: FileUrl.fromPath(IMAGE_PATH); width: 30; height: 30 }
        TestCase { id: test; when: false }
    }
    function check(ok, message) { if (!ok) throw Error(message); console.log("PASS: " + message); }
    function localPath(url) {
        return decodeURIComponent(String(url)).replace(/^file:\\/+/, "/");
    }
    function until(predicate, message) {
        const deadline = Date.now() + 2000;
        while (!predicate() && Date.now() < deadline) test.wait(10);
        check(predicate(), message);
    }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            const encoded = FileUrl.fromPath(IMAGE_PATH);
            check(encoded.includes("%23") && encoded.includes("%3F") && encoded.includes("%25") && encoded.includes("%20"),
                "file URLs encode fragments, queries, percent signs and spaces");
            check(FileUrl.fromPath("") === "", "empty paths stay empty");
            until(() => image.status === Image.Ready, "an image with URL punctuation and Unicode loads");
            until(() => localPath(sleeve.cover) === IMAGE_PATH && sleeve.testArt.status === Image.Ready, "CoverArt finds and loads a named cover in an encoded folder");
            Mpd.file = "album #?%20 α/song.flac";
            until(() => localPath(Mpd.cover) === IMAGE_PATH, "MPD finds the current album's cover through the same helper");
            sleeve.dir = "";
            check(sleeve.cover === "", "clearing a folder does not retain the previous cover");
            sleeve.dir = LOOSE_DIR;
            until(() => localPath(sleeve.cover) === LOOSE_PATH && sleeve.testArt.status === Image.Ready, "CoverArt's fallback lookup also accepts URL punctuation");
            sleeve.dir = PLAIN_DIR;
            until(() => localPath(sleeve.cover) === PLAIN_PATH && sleeve.testArt.status === Image.Ready, "switching back to an ordinary folder loads its cover");
            console.log("PASS: file URLs");
        } catch (error) { console.log("FAIL: " + error + "\\n" + error.stack); }
        Qt.quit();
    } }
}'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-file-urls-") as folder:
        target = Path(folder)
        copy_shell(target)
        source = (target / "components/CoverArt.qml").read_text().replace("id: root", "id: root\n    property alias testArt: art", 1)
        (target / "components/CoverArt.qml").write_text(source)
        album = target / "album #?%20 α"
        album.mkdir()
        cover = album / "cover.png"
        loose = target / "loose #?% β"
        loose.mkdir()
        fallback = loose / "sleeve #?%.png"
        plain = target / "plain"
        plain.mkdir()
        ordinary = plain / "cover.png"
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff\xff")) + chunk(b"IEND", b"")
        cover.write_bytes(png)
        fallback.write_bytes(png)
        ordinary.write_bytes(png)
        (target / "Settings.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property string musicDir: ' + json.dumps(str(target) + "/") + '; property string mpdSocket: ""; property string font: "Sans"; property string monoFont: "Monospace"; property bool reduceMotion: false; property bool reduceTransparency: false }')
        (target / "services/Audio.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool connected: true; function level(value, muted) { return ""; } }')
        (target / "components/MpdLink.qml").write_text('import QtQuick\nItem { property string path; property bool active: true; property bool connected: false; signal line(string text); function write(text) {} function wake() {} function dialNow() {} }')
        source = SHELL
        for key, path in {"ALBUM_DIR": str(album) + "/", "IMAGE_PATH": str(cover), "LOOSE_DIR": str(loose) + "/", "LOOSE_PATH": str(fallback), "PLAIN_DIR": str(plain) + "/", "PLAIN_PATH": str(ordinary)}.items():
            source = source.replace(key, json.dumps(path))
        (target / "shell.qml").write_text(source)
        result = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target), capture_output=True, text=True, timeout=8)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("FAIL:", "ReferenceError:", "TypeError:", "Unable to assign", "Cannot open:", "Error decoding")
        return 0 if result.returncode == 0 and "PASS: file URLs" in output and not any(error in output for error in errors) else 1


if __name__ == "__main__":
    raise SystemExit(main())
