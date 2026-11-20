#!/usr/bin/env python3
"""thumb.sh previews any text file as text, keeps keys hidden and pretty-prints JSON."""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from test_support import ROOT

SCRIPT = ROOT / "scripts/thumb.sh"


def preview(path, *line):
    result = subprocess.run([str(SCRIPT), str(path), *map(str, line)], capture_output=True, text=True, timeout=20,
                            env=dict(os.environ, XDG_CACHE_HOME=str(path.parent / "cache")))
    kind, _, body = result.stdout.partition("\n")
    return kind, body


def check(ok, message):
    if not ok:
        raise SystemExit("FAIL: " + message)
    print("PASS: " + message)


def main():
    with tempfile.TemporaryDirectory(prefix="qs-thumb-text-") as folder:
        root = Path(folder)

        records = [{"id": n, "note": "x" * 3000} for n in range(40)]
        jsonl = root / "events.jsonl"
        jsonl.write_text("".join(json.dumps(r) + "\n" for r in records))
        kind, body = preview(jsonl)
        check(kind == "text" and body.startswith('{\n  "id": 0,'), "JSON Lines preview as text, a record pretty-printed")
        check(len(body.splitlines()) <= 80, "the pretty head keeps to eighty lines")

        kind, body = preview(jsonl, 12)
        check(kind == "text 9" and body.splitlines()[8].startswith('{"id": 11,'), "around a line, JSON Lines keep the file's own lines")

        document = root / "config.json"
        document.write_text(json.dumps({"name": "dewdrop", "nested": {"a": [1, 2]}}))
        kind, body = preview(document)
        check(kind == "text" and '"nested": {' in body and body.count("\n") > 3, "a JSON document is pretty-printed")

        huge = root / "huge.json"
        huge.write_text(json.dumps({"rows": ["y" * 100] * 2000}))
        kind, body = preview(huge)
        check(kind == "text" and body.startswith('{"rows": ['), "a document past the first page falls back to its raw head")

        subtitles = root / "film.srt"
        subtitles.write_text("1\n00:00:01,000 --> 00:00:02,000\nHello there\n\n2\n00:00:03,000 --> 00:00:04,000\nAgain\n")
        kind, body = preview(subtitles)
        check(kind == "text" and "Hello there" in body, "subtitles, filed under application/, preview as text")

        key = root / "id_fixture"
        key.write_text("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\n-----END OPENSSH PRIVATE KEY-----\n")
        kind, body = preview(key)
        check(kind == "" and body == "", "a private key shows nothing")

        # Every armoured private key, whatever `file` files it under.
        filler = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7\n" * 3
        for name, label in (("pkcs8.pem", "PRIVATE KEY"), ("rsa.pem", "RSA PRIVATE KEY"),
                            ("ec.key", "EC PRIVATE KEY"), ("locked.pem", "ENCRYPTED PRIVATE KEY"),
                            ("secret.asc", "PGP PRIVATE KEY BLOCK")):
            other = root / name
            other.write_text(f"-----BEGIN {label}-----\n{filler}-----END {label}-----\n")
            check(preview(other) == ("", ""), f"a {label.lower()} shows nothing")

        prose = root / "keys.md"
        prose.write_text("Never paste your private key anywhere.\n")
        check(preview(prose)[0] == "text", "text that only mentions a private key still previews")

        blob = root / "blob.bin"
        blob.write_bytes(bytes(range(256)) * 4)
        check(preview(blob) == ("", ""), "a binary shows nothing")

        plain = root / "notes.txt"
        plain.write_text("first\nsecond\n")
        check(preview(plain) == ("text", "first\nsecond\n"), "plain text is unchanged")

        if shutil.which("jq"):
            bare = root / "bin"
            bare.mkdir()
            for tool in ("file", "head", "expand", "sed", "cut", "mkdir", "stat", "sha1sum"):
                (bare / tool).symlink_to(shutil.which(tool))
            result = subprocess.run([shutil.which("bash"), str(SCRIPT), str(document)], capture_output=True, text=True, timeout=20,
                                    env=dict(os.environ, PATH=str(bare), XDG_CACHE_HOME=str(root / "cache")))
            check(result.stdout.startswith("text\n{\"name\""), "without jq, JSON previews raw")

    print("PASS: thumb text complete")


if __name__ == "__main__":
    main()
