#!/usr/bin/env python3
"""Keep small feed thumbnails on disk, keyed by their remote URL."""

from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def thumbnail(cache, url):
    """Reuse the local image or publish a complete 128 by 72 PNG atomically."""
    if not re.match(r"^https?://", url, re.I):
        return url
    key = hashlib.sha256(url.encode()).hexdigest()
    output = cache / (key + ".png")
    if output.is_file() and output.stat().st_size:
        output.touch()
        return output.as_uri()
    with tempfile.TemporaryDirectory(prefix=".download-", dir=cache) as folder:
        original = Path(folder) / "original"
        rendered = Path(folder) / "thumbnail.png"
        subprocess.run([
            "curl", "--fail", "--location", "--silent", "--show-error",
            "--proto", "=http,https", "--proto-redir", "=http,https",
            "--max-time", "15", "--max-filesize", str(20 * 1024 * 1024),
            "--output", str(original), "--url", url,
        ], check=True, timeout=20, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([
            "magick", "-limit", "memory", "64MiB", "-limit", "map", "128MiB",
            str(original) + "[0]", "-thumbnail", "128x72^", "-gravity", "center",
            "-extent", "128x72", "-strip", str(rendered),
        ], check=True, timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rendered.replace(output)
    return output.as_uri()


def prune(cache):
    """Expire this helper's images after thirty days without a cache hit."""
    cutoff = time.time() - 30 * 86400
    for path in cache.glob("*.png"):
        if re.fullmatch(r"[0-9a-f]{64}\.png", path.name) and path.stat().st_mtime < cutoff:
            path.unlink(missing_ok=True)


def main():
    cache = Path(sys.argv[1]).resolve()
    urls = list(dict.fromkeys(sys.argv[2:]))
    try:
        cache.mkdir(parents=True, exist_ok=True)
        prune(cache)
    except OSError:
        for url in urls:
            print(json.dumps({"url": url, "source": url}), flush=True)
        return
    with ThreadPoolExecutor(max_workers=6) as pool:
        jobs = {pool.submit(thumbnail, cache, url): url for url in urls}
        for job in as_completed(jobs):
            url = jobs[job]
            try:
                source = job.result()
            except (OSError, subprocess.SubprocessError):
                source = url
            print(json.dumps({"url": url, "source": source}), flush=True)


if __name__ == "__main__":
    main()
