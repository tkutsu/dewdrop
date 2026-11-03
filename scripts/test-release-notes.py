#!/usr/bin/env python3
"""Official release fixtures, note failures, caching, and read-status preservation."""

import json
from pathlib import Path
import subprocess
import tempfile

from test_support import ROOT, copy_shell, shell_env


QML = r'''import QtQuick
import Quickshell
import qs
import qs.services
import "ReleaseNotes.js" as Notes
ShellRoot {
    function check(ok, why) { if (!ok) throw Error(why); }
    Timer { id: finish; interval: 200; onTriggered: Qt.quit() }
    Timer { interval: 400; running: true; onTriggered: {
        try {
            const f = FIXTURES;
            check(Notes.examine(f.v030, true).breaking, "real Quickshell migration");
            check(!Notes.examine(f.v032, true).breaking, "real Quickshell bug fixes");
            check(Notes.examine(Notes.article(f.hypr55), false).excerpt.includes("ignore_window"), "real article preserves option names");
            check(Notes.examine(Notes.article(f.hypr57), false).breaking,
                "Hyprland 0.57 declares .conf removal outside a breaking-changes heading");
            check(!Notes.examine("<h2>No breaking changes</h2><p>Enjoy.</p>", false).breaking, "negative heading");
            check(!Notes.examine("## Breaking Changes\nNone.\n## Fixes\nA fix.", true).breaking, "negative section");
            check(!Notes.examine("## Breaking Changes\n## Fixes\nA fix.", true).breaking, "empty section");
            check(!Notes.examine("## Fixes\nFixed networking breaking.", true).breaking, "ordinary prose");
            check(!Notes.examine("<p>No breaking changes! Configs are still supported.</p>", false).breaking,
                "ordinary support statements stay unmarked");
            check(!Notes.examine("<h2>Fixes</h2><p>Removed an unused allocation.</p><p>Fixed support for configs.</p>", false).breaking,
                "implementation removals and support fixes stay unmarked");
            check(Notes.examine("Config files are no longer supported.", true).breaking,
                "Markdown retirement declaration without a heading");
            check(Notes.examine("<p>Support for the legacy renderer has been dropped.</p>", false).breaking,
                "explicit dropped-support statement");
            check(Notes.examine("<p>" + "intro ".repeat(200) + "</p><h2>Migration Guide</h2><p>Rename an option.</p>", false).breaking,
                "classification precedes preview truncation");
            check(!Notes.examine(Notes.article("<nav><h2>Breaking Changes</h2>Unrelated</nav><article><h2>Fixes</h2>Fixed</article>"), false).breaking,
                "navigation excluded");
            check(!Notes.examine("<html>Something changed</html>", true).valid, "unexpected changelog format");
            check(!Notes.release(f.sources[0], "https://example.com/releases/tag/v1.0.0", "", ""), "foreign release rejected");
            check(Notes.release(f.sources[0], "https://github.com/quickshell-mirror/quickshell/releases/tag/v0.3.0", '<a href="https://evil.example/changelog.md">Notes</a>', "").notesUrl === "",
                "foreign changelog rejected");

            Feeds.sources = [Feeds.parseStories(f.quickshell, f.sources[0]), Feeds.parseStories(f.hyprland, f.sources[1])]
                .map((s, i) => Object.assign({url: f.sources[i]}, s));
            function item(tag) { return [].concat(...Feeds.sources.map(s => s.items)).find(i => i.release.tag === tag); }
            const id = item("v0.3.0").id;
            const originalUrl = item("v0.3.0").url;
            check(item("v0.3.0").title === "Quickshell v0.3.0", "project in row title");
            check(Number.isFinite(item("v0.3.0").published), "Atom updated fallback");
            Feeds.markSeen([item("v0.3.0")]);
            Feeds.releaseEntries[item("v0.57.0").id] = {updated: item("v0.57.0").release.updated,
                checkedAt: Date.now(), status: "ready", breaking: false};
            let fail32 = true, fail30 = false;
            const calls = [];
            Feeds.httpStub = function(method, url, body, headers, timeout, accepted, failed) {
                calls.push(url);
                if ((url.includes("v0.3.2") && fail32) || (url.includes("v0.3.0") && fail30)) { failed("Offline", 0); return; }
                const text = url.endsWith("rss.xml") ? f.news : url.includes("v0.3.0") ? f.v030
                    : url.includes("v0.3.2") ? f.v032 : url.endsWith("update55") ? f.hypr55
                    : url.endsWith("update57") ? f.hypr57 : "";
                accepted({status: text ? 200 : 404, responseText: text});
            };
            Feeds.enrichReleases();
            check(item("v0.3.0").release.breaking && item("v0.55.0").release.breaking, "both projects enriched");
            check(item("v0.57.0").release.breaking && item("v0.57.0").release.excerpt.includes(".conf configs are no longer supported"),
                "cached false result is replaced with the Hyprland 0.57 warning and its actual declaration");
            check(item("v0.56.0").release.status === "ready" && !item("v0.56.0").release.breaking, "No breaking changes is ordinary");
            check(item("v0.56.2").release.status === "ready", "patch without news remains checked");
            check(item("v0.3.2").release.status === "unavailable", "failed lookup is unknown");
            check(Feeds.count === 5 && item("v0.3.0").id === id && item("v0.3.0").url === originalUrl && !Feeds.unseen(item("v0.3.0")),
                "enrichment preserves identity, count, URL, and seen state");
            const before = calls.length;
            Feeds.enrichReleases();
            check(calls.length === before, "success cache and failure cooldown");
            Feeds.releaseEntries[item("v0.3.2").id].checkedAt = 0;
            fail32 = false;
            Feeds.enrichReleases();
            check(item("v0.3.2").release.status === "ready" && !item("v0.3.2").release.breaking, "failed notes recover");
            const afterRecovery = calls.length;
            item("v0.3.0").release.updated = "changed upstream";
            Feeds.enrichReleases();
            check(calls.length === afterRecovery + 1 && calls[calls.length - 1].startsWith("https://raw.githubusercontent.com/"),
                "upstream update refetches the original changelog");
            Feeds.releaseEntries[id].checkedAt = 0;
            fail30 = true;
            Feeds.enrichReleases();
            check(item("v0.3.0").release.status === "unavailable" && item("v0.3.0").release.breaking,
                "last successful warning survives transient failure");
            Feeds.sources = [Object.assign({}, Feeds.sources[1], {items: [item("v0.56.2")]})];
            Feeds.enrichReleases();
            check(Object.keys(Feeds.releaseEntries).length === 1, "cache prunes absent releases");
            console.log("PASS: release notes");
        } catch(e) { console.log("FAIL: " + e + "\n" + e.stack); }
        finish.start();
    } }
}'''

RESTORE = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    Timer { interval: 400; running: true; onTriggered: {
        const entries = Object.values(Feeds.releaseEntries);
        console.log(entries.length === 1 && entries[0].status === "ready"
            ? "PASS: release cache survives restart" : "FAIL: release cache restore");
        Qt.quit();
    } }
}'''


def main():
    fixtures = json.loads((ROOT / "scripts/fixtures/release-notes.json").read_text())
    with tempfile.TemporaryDirectory(prefix="qs-release-notes-") as tmp:
        target = Path(tmp)
        copy_shell(target)
        (target / "settings.json").write_text('{"feedUrls": []}\n')
        service = target / "services/Feeds.qml"
        source = service.read_text().replace('Http.send("GET", job.urls[i]', 'root.httpStub("GET", job.urls[i]')
        service.write_text(source.replace('    property var videos: []',
            '    property var httpStub: null\n    property var videos: []'))
        for qml, marker in [(QML.replace("FIXTURES", json.dumps(fixtures)), "PASS: release notes"),
                            (RESTORE, "PASS: release cache survives restart")]:
            (target / "shell.qml").write_text(qml)
            run = subprocess.run(["qs", "-p", str(target), "--no-color"], env=shell_env(target),
                                 capture_output=True, text=True, timeout=20)
            output = run.stdout + run.stderr
            print(output)
            assert run.returncode == 0 and marker in output and "FAIL:" not in output, output


if __name__ == "__main__":
    main()
