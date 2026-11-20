#!/usr/bin/env python3
"""Build assets/emoji.json, the launcher's emoji list, from Unicode's data.

Each emoji comes with its CLDR keywords, the ones phone keyboards search, so
"lol" finds 😂 and "fire" finds 🔥, and the words of its group ("animal",
"food"). Skin-tone variants are left out: one row per emoji.

Run again when a new Unicode release adds some:
    python3 -I scripts/emoji-data.py
"""

import json
import pathlib
import re
import urllib.request
import xml.etree.ElementTree as ET

TEST = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr/main/common/{}/en.xml"
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "emoji.json"
TONES = set(range(0x1F3FB, 0x1F400))


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as reply:
        return reply.read().decode("utf-8")


# Keywords by emoji, without the variation selector CLDR leaves off.
def annotations():
    words = {}
    for kind in ("annotations", "annotationsDerived"):
        for node in ET.fromstring(fetch(CLDR.format(kind))).iter("annotation"):
            if node.get("type") != "tts" and node.text:
                words.setdefault(node.get("cp"), []).extend(w.strip() for w in node.text.split("|"))
    return words


def main():
    words = annotations()
    rows, group, sub = [], "", ""
    for line in fetch(TEST).splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
        elif line.startswith("# subgroup:"):
            sub = line.split(":", 1)[1].strip()
        m = re.match(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$", line)
        if not m or group == "Component":
            continue
        char, name = m.groups()
        if any(ord(c) in TONES for c in char):
            continue
        # Group words that say something: "smileys emotion face smiling",
        # but not "other" or "symbol" twice over.
        extra = re.split(r"[\s&-]+", f"{group} {sub}".lower())
        seen, keys = {name.lower()}, []
        for w in words.get(char.replace("️", ""), []) + extra:
            w = w.lower()
            if w and w not in seen and w != "other":
                seen.add(w)
                keys.append(w)
        rows.append([char, name, " ".join(keys)])

    OUT.write_text("[\n" + ",\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n]\n")
    print(f"{len(rows)} emoji to {OUT}")


main()
