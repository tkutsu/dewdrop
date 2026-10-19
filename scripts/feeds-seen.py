#!/usr/bin/env python3
"""Say which of the feeds' links a browser has opened since a given time.

    feeds-seen.py SINCE URL...

SINCE is in Unix seconds. Prints each URL that some Firefox or Chromium-family
profile's history has a visit to since then, one a line; a history file not
written since then is not opened. A YouTube video
counts however its link was dressed (a timestamp, a playlist): videos are
matched by id. Nothing leaves the machine and only the given links are looked
for; the rest of the history is never read out.

A running browser may hold its database locked; then a copy is read.
"""

import os
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, urlsplit, urlunsplit

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")

FIREFOX = [HOME / ".mozilla/firefox", CONFIG / "mozilla/firefox"]
CHROMIUM = [CONFIG / name for name in ("chromium", "google-chrome", "google-chrome-beta",
                                       "BraveSoftware/Brave-Browser", "vivaldi", "microsoft-edge")]
# Chromium counts microseconds from 1601.
WINDOWS_EPOCH = 11644473600


def video(url):
    parts = urlsplit(url)
    if parts.netloc.endswith("youtube.com") and parts.path == "/watch":
        return parse_qs(parts.query).get("v", [""])[0]
    if parts.netloc == "youtu.be":
        return parts.path.strip("/")
    return ""


def plain(url):
    """One spelling for the links that differ only by scheme, fragment or a
    trailing slash."""
    parts = urlsplit(url)
    return urlunsplit(("https", parts.netloc.lower(), parts.path.rstrip("/"), parts.query, ""))


def histories():
    for base in FIREFOX:
        yield from (("firefox", p) for p in sorted(base.glob("*/places.sqlite")))
    for base in CHROMIUM:
        for profile in sorted(base.glob("*")):
            if profile.name == "Default" or profile.name.startswith("Profile "):
                yield ("chromium", profile / "History")


def visited(kind, path, since, wanted):
    """The URLs in this history visited since `since` that might be wanted:
    every YouTube watch link, and the wanted links in their usual spellings."""
    if kind == "firefox":
        table, column, stamp = "moz_places", "last_visit_date", since * 1_000_000
    else:
        table, column, stamp = "urls", "last_visit_time", (since + WINDOWS_EPOCH) * 1_000_000
    spellings = set()
    for url in wanted:
        for scheme in ("https", "http"):
            base = urlunsplit((scheme,) + tuple(urlsplit(url))[1:])
            spellings.update((base, base + "/"))
    marks = ",".join("?" * len(spellings))
    query = (f"select url from {table} where {column} >= ? and "
             f"(url like '%youtube.com/watch?%' or url like '%youtu.be/%' or url in ({marks}))")
    with tempfile.TemporaryDirectory() as scratch:
        try:
            db = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=0.5)
            rows = db.execute(query, [stamp, *spellings]).fetchall()
        except sqlite3.OperationalError:
            # Locked by the browser: read a copy, with its write-ahead log so
            # the latest visits come too.
            for suffix in ("", "-wal"):
                if Path(f"{path}{suffix}").exists():
                    shutil.copy2(f"{path}{suffix}", Path(scratch) / f"history{suffix}")
            db = sqlite3.connect(Path(scratch) / "history")
            rows = db.execute(query, [stamp, *spellings]).fetchall()
        db.close()
    return [row[0] for row in rows]


def main():
    if len(sys.argv) < 3:
        return
    since = int(sys.argv[1])
    wanted = sys.argv[2:]
    seen_videos = set()
    seen_links = set()
    for kind, path in histories():
        if not path.is_file() or path.stat().st_size == 0:
            continue
        # Untouched since then, it holds no visit since then: skip the open,
        # and the copy a running browser's lock would cost.
        if since > 0 and max(p.stat().st_mtime for p in (path, Path(f"{path}-wal"), Path(f"{path}-journal"))
                             if p.exists()) < since:
            continue
        try:
            for url in visited(kind, path, since, wanted):
                if video(url):
                    seen_videos.add(video(url))
                seen_links.add(plain(url))
        except (sqlite3.Error, OSError) as error:
            print(f"feeds-seen: {path}: {error}", file=sys.stderr)
    for url in wanted:
        if (video(url) and video(url) in seen_videos) or plain(url) in seen_links:
            print(url)


if __name__ == "__main__":
    main()
