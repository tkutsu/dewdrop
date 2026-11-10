#!/usr/bin/env python3
"""Viewed feed thumbnails survive popup teardown and Qt image-cache eviction."""

from pathlib import Path
from test_support import fixture_root
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import runpy
import subprocess
import sys
import tempfile
import threading
import time

from test_support import ROOT, copy_shell, shell_env

class Images(BaseHTTPRequestHandler):
    requests = 0
    offline = False
    def do_GET(self):
        Images.requests += 1
        if Images.offline:
            self.send_error(503)
            return
        time.sleep(0.5)
        self.send_response(200)
        self.send_header('Content-Type', 'image/svg+xml')
        self.end_headers()
        try:
            self.wfile.write(b'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="72"><rect width="128" height="72" fill="red"/></svg>')
        except BrokenPipeError:
            pass
    def log_message(self, *args): pass

QML = '''import QtQuick
import QtTest
import Quickshell
import qs.src.core
import qs.src.services
import qs.src.components
ShellRoot {
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 800
        Loader { id: loader; sourceComponent: FeedsPopup {} }
        Component { id: pressure; Image { sourceSize: Qt.size(2048, 2048); asynchronous: true } }
        TestCase {
            id: test; when: false
            function find(item, predicate) {
                if (predicate(item)) return item;
                for (const child of item.children) {
                    const found = find(child, predicate);
                    if (found) return found;
                }
                return null;
            }
            function image() { return find(loader.item, i => i.status !== undefined && i.sourceSize !== undefined); }
            function run() {
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                FEED_ITEMS
                if (!Feeds.unfolded("SECTION")) Feeds.toggle("SECTION");
                tryVerify(() => image() && image().status === Image.Ready, 3000);
                if (!image().source.toString().startsWith("file:"))
                    throw Error("thumbnails must load from a persistent local cache");
                Feeds.sources = Feeds.sources.slice();
                Feeds.videos = Feeds.videos.slice();
                wait(10);
                loader.active = false;
                wait(10);
                // Fill the released-pixmap cache without touching the feed data.
                for (let i = 0; i < 8; i++) {
                    const big = pressure.createObject(test, {source: Qt.resolvedUrl("pressure.svg?" + i)});
                    tryVerify(() => big.status === Image.Ready, 3000);
                    big.destroy();
                    wait(10);
                }
                loader.active = true;
                wait(100);
                if (!image() || image().status !== Image.Ready)
                    throw Error("previously loaded thumbnail disappears on reopen and downloads again");
                Feeds.toggle("SECTION");
                wait(30);
                Feeds.toggle("SECTION");
                wait(100);
                if (!image() || image().status !== Image.Ready)
                    throw Error("previously loaded thumbnail disappears after folding the feed");
                Feeds.sources = [];
                Feeds.videos = [];
                wait(10);
                console.log("PASS: thumbnail survives popup destruction and image-cache eviction");
            }
        }
        Timer { interval: 300; running: true; onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''

def run_case(server, section):
    Images.offline = False
    downloads_before = Images.requests
    with tempfile.TemporaryDirectory(prefix='qs-feed-thumbnails-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'settings.json').write_text('{"feedUrls": []}')
        popup = runpy.run_path(str(ROOT / 'tests/test-popup-standards.py'))['POPUP']
        (target / 'src/components/Popup.qml').write_text(popup)
        (target / 'pressure.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="2048" height="2048"><rect width="2048" height="2048" fill="blue"/></svg>')
        url = f'http://127.0.0.1:{server.server_port}/thumb.svg'
        feed_items = ('Feeds.videos = [{id: "video", title: "Video", channel: "Channel", duration: 120, '
                      'published: Date.now(), thumb: "IMAGE_URL", url: ""}];' if section == 'videos' else
                      'Feeds.sources = [{url: "rss", title: "Stories", items: [{id: "story", title: "Story", '
                      'published: Date.now(), thumb: "IMAGE_URL", url: ""}]}];')
        (target / 'shell.qml').write_text(QML.replace('FEED_ITEMS', feed_items)
                                         .replace('SECTION', section).replace('IMAGE_URL', url))
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target), capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        print(output)
        downloads = Images.requests - downloads_before
        print(f'{section} thumbnail downloads: {downloads}')
        errors = ('FAIL:', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Unable to assign',
                  'Cannot assign', 'Failed to load configuration', 'not placed in the graphics scene')
        passed = (result.returncode == 0 and 'PASS: thumbnail survives' in output
                  and downloads == 1 and not any(error in output for error in errors))
        if not passed:
            return False
        cached = list((target / 'cache/quickshell/feed-thumbnails').glob('*.png'))
        if len(cached) != 1:
            print('FAIL: one thumbnail must be saved on disk')
            return False
        Images.offline = True
        restarted = subprocess.run(['qs', '-p', str(target), '--no-color'], env=shell_env(target),
                                   capture_output=True, text=True, timeout=15)
        restarted_output = restarted.stdout + restarted.stderr
        print(restarted_output)
        no_download = Images.requests - downloads_before == 1
        print(f'{section}: restarted offline with {Images.requests - downloads_before - 1} new downloads')
        return (restarted.returncode == 0 and 'PASS: thumbnail survives' in restarted_output
                and no_download and not any(error in restarted_output for error in errors))


def main():
    with ThreadingHTTPServer(('127.0.0.1', 0), Images) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        sections = sys.argv[1:] or ['videos', 'rss']
        results = [run_case(server, section) for section in sections]
        server.shutdown()
        return 0 if all(results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
