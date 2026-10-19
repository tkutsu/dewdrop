#!/usr/bin/env python3
"""feeds-seen.py against made-up Firefox and Chromium histories: videos match
by id however they were linked, stories by link, old visits do not count, and
a database the browser holds locked is still read."""

import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time

SCRIPT = Path(__file__).with_name("feeds-seen.py")
NOW = int(time.time())
DAY = 86400


def firefox(home, visits):
    profile = home / ".mozilla/firefox/abc.default"
    profile.mkdir(parents=True)
    db = sqlite3.connect(profile / "places.sqlite")
    db.execute("pragma journal_mode=wal")
    db.execute("create table moz_places (id integer primary key, url text, last_visit_date integer)")
    db.executemany("insert into moz_places (url, last_visit_date) values (?, ?)",
                   [(url, t * 1_000_000) for url, t in visits])
    db.commit()
    return db


def chromium(home, visits, browser="chromium", profile="Profile 1"):
    profile = home / ".config" / browser / profile
    profile.mkdir(parents=True)
    db = sqlite3.connect(profile / "History")
    db.execute("create table urls (id integer primary key, url text, last_visit_time integer)")
    db.executemany("insert into urls (url, last_visit_time) values (?, ?)",
                   [(url, (t + 11644473600) * 1_000_000) for url, t in visits])
    db.commit()
    db.close()


def main():
    failures = 0

    def check(ok, what):
        nonlocal failures
        print(("ok: " if ok else "FAIL: ") + what)
        failures += not ok

    with tempfile.TemporaryDirectory() as scratch:
        home = Path(scratch)
        fox = firefox(home, [
            ("https://www.youtube.com/watch?v=AAAAAAAAAAA&t=42s", NOW - 3600),
            ("https://example.com/story/", NOW - 7200),
            ("https://www.youtube.com/watch?v=OLDOLDOLDOL", NOW - 30 * DAY),
            ("https://example.com/old-firefox", NOW - 30 * DAY),
        ])
        chromium(home, [
            ("https://youtu.be/BBBBBBBBBBB", NOW - 60),
            ("https://news.ycombinator.com/item?id=7", NOW - 60),
            ("https://example.com/old-chromium", NOW - 30 * DAY),
        ])
        chromium(home, [("https://example.com/brave", NOW - 30 * DAY)], "BraveSoftware/Brave-Browser", "Default")
        chromium(home, [("https://example.com/edge", NOW - 30 * DAY)], "microsoft-edge")
        chromium(home, [("https://example.com/chrome", NOW - 30 * DAY)], "google-chrome", "Default")
        # Held the way a running browser can hold it.
        fox.execute("pragma locking_mode=exclusive")
        fox.execute("insert into moz_places (url, last_visit_date) values (?, ?)",
                    ("https://www.youtube.com/watch?v=CCCCCCCCCCC", (NOW - 10) * 1_000_000))
        fox.commit()

        wanted = [
            "https://www.youtube.com/watch?v=AAAAAAAAAAA",
            "https://www.youtube.com/watch?v=BBBBBBBBBBB",
            "https://www.youtube.com/watch?v=CCCCCCCCCCC",
            "https://www.youtube.com/watch?v=OLDOLDOLDOL",
            "https://www.youtube.com/watch?v=DDDDDDDDDDD",
            "https://example.com/story",
            "https://news.ycombinator.com/item?id=7",
            "https://news.ycombinator.com/item?id=8",
            "https://example.com/old-firefox",
            "https://example.com/old-chromium",
            "https://example.com/brave",
            "https://example.com/edge",
            "https://example.com/chrome",
        ]
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))
        run = subprocess.run([sys.executable, "-I", str(SCRIPT), str(NOW - 7 * DAY), *wanted],
                             env=env, capture_output=True, text=True, timeout=30)
        fox.close()
        seen = set(run.stdout.split())

        check(run.returncode == 0 and run.stderr == "", "runs cleanly: " + run.stderr.strip())
        check(wanted[0] in seen, "video with a timestamp")
        check(wanted[1] in seen, "youtu.be link in Chromium")
        check(wanted[2] in seen, "locked database read through a copy, write-ahead log included")
        check(wanted[3] not in seen, "visit before the window does not count")
        check(wanted[4] not in seen, "unvisited video")
        check(wanted[5] in seen, "story despite a trailing slash")
        check(wanted[6] in seen and wanted[7] not in seen, "comments link")

        run = subprocess.run([sys.executable, "-I", str(SCRIPT), "0", *wanted],
                             env=env, capture_output=True, text=True, timeout=30)
        seen = set(run.stdout.split())
        check(run.returncode == 0 and run.stderr == "", "all-history lookup runs cleanly")
        check(wanted[8] in seen and wanted[9] in seen, "old RSS visits in Firefox and Chromium count")
        check(wanted[10] in seen and wanted[11] in seen and wanted[12] in seen, "Brave, Edge and Chrome histories count")

        # No browsers at all: nothing, quietly.
        empty = Path(scratch) / "empty"
        empty.mkdir()
        run = subprocess.run([sys.executable, "-I", str(SCRIPT), str(NOW), *wanted],
                             env=dict(os.environ, HOME=str(empty), XDG_CONFIG_HOME=str(empty)),
                             capture_output=True, text=True, timeout=30)
        check(run.returncode == 0 and run.stdout == "" and run.stderr == "", "no browsers, no output")

    print("PASS: feeds seen" if failures == 0 else f"RESULT: {failures} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
