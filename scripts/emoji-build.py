#!/usr/bin/env python3
"""Build data/emoji.tsv, the launcher's emoji list, from Unicode's own data.

    scripts/emoji-build.py emoji-test.txt annotations.json annotationsDerived.json

emoji-test.txt is https://unicode.org/Public/emoji/latest/emoji-test.txt, and
the two JSON files are CLDR's English keywords, from unicode-org/cldr-json:
cldr-annotations-full/annotations/en/annotations.json and
cldr-annotations-derived-full/annotationsDerived/en/annotations.json.

One line per emoji, in Unicode's order: the emoji, its name, its keywords
(space separated, without the words the name already has) and its group.
Skin-tone variants are left out, and so is anything newer than --max, the
newest emoji version the installed emoji font draws (Noto 2.051 is 16.0):
past it, rows would show an empty box.
"""

import argparse
import json
import re
import sys

TONES = set(range(0x1F3FB, 0x1F400))
LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.+)$")


def keywords(path):
    with open(path, encoding="utf-8") as f:
        table = json.load(f)
    found = {}
    for block in table.values():
        for emoji, entry in block.get("annotations", {}).items():
            found[emoji] = entry.get("default", [])
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("test")
    parser.add_argument("annotations", nargs="+")
    parser.add_argument("--max", type=float, default=16.0)
    args = parser.parse_args()

    words = {}
    for path in args.annotations:
        words.update(keywords(path))

    group = ""
    out = []
    with open(args.test, encoding="utf-8") as f:
        for line in f:
            if line.startswith("# group:"):
                group = line.split(":", 1)[1].strip()
                continue
            m = LINE.match(line)
            if not m or group == "Component":
                continue
            points, emoji, version, name = m.groups()
            if float(version) > args.max or any(int(p, 16) in TONES for p in points.split()):
                continue
            named = set(re.findall(r"[\w'-]+", name.lower()))
            # CLDR keys its keywords without the variation selector the
            # fully-qualified form carries.
            extra = words.get(emoji) or words.get(emoji.replace("️", "")) or []
            extra = [w for w in extra if w.lower() not in named]
            out.append("\t".join([emoji, name, " ".join(extra), group]))

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
