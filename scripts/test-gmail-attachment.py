#!/usr/bin/env python3
"""scripts/gmail-attachment: names made safe, taken names numbered, no token in argv."""

import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "gmail-attachment"
loader = importlib.machinery.SourceFileLoader("gmail_attachment", str(SCRIPT))
spec = importlib.util.spec_from_loader("gmail_attachment", loader)
attachment = importlib.util.module_from_spec(spec)
loader.exec_module(attachment)


class AttachmentTests(unittest.TestCase):
    def test_names_are_made_safe(self):
        cases = {
            "report.pdf": "report.pdf",
            "../../.bashrc": "_.._.bashrc",
            ".hidden": "hidden",
            "...": "attachment",
            "": "attachment",
            "a/b\\c.txt": "a_b_c.txt",
            "line\nbreak\x07.txt": "linebreak.txt",
            "  spaced  .pdf ": "spaced  .pdf",
            "Τιμολόγιο.pdf": "Τιμολόγιο.pdf",
        }
        for name, expected in cases.items():
            with self.subTest(name=name):
                safe = attachment.safe_name(name)
                self.assertEqual(safe, expected)
                self.assertNotIn("/", safe)
                self.assertFalse(safe.startswith("."))

    def test_long_names_keep_their_extension(self):
        safe = attachment.safe_name("α" * 300 + ".pdf")
        self.assertTrue(safe.endswith(".pdf"))
        self.assertLessEqual(len(safe.encode()), 200)

    def test_taken_names_are_numbered(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            first = attachment.write_new(folder, "report.pdf", b"one")
            second = attachment.write_new(folder, "report.pdf", b"two")
            third = attachment.write_new(folder, "report.pdf", b"three")
            bare = attachment.write_new(folder, "README", b"x")
            bare2 = attachment.write_new(folder, "README", b"y")
            self.assertEqual([p.name for p in (first, second, third, bare, bare2)],
                             ["report.pdf", "report (2).pdf", "report (3).pdf", "README", "README (2)"])
            self.assertEqual(first.read_bytes(), b"one")
            self.assertEqual(third.read_bytes(), b"three")

    def test_refuses_without_a_token_in_the_environment(self):
        env = {k: v for k, v in os.environ.items() if k != "GMAIL_TOKEN"}
        result = subprocess.run([sys.executable, str(SCRIPT), "m", "a", "f.txt"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("GMAIL_TOKEN", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
