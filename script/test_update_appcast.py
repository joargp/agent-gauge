#!/usr/bin/env python3
"""Tests for update_appcast.py. Run: python3 -I script/test_update_appcast.py"""

import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "update_appcast.py")
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
SIGNATURE = 'sparkle:edSignature="ab+c/=" length="1234"'


class UpdateAppcastTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.appcast = os.path.join(self.dir.name, "appcast.xml")

    def tearDown(self):
        self.dir.cleanup()

    def publish(self, build, version=None, notes=None, check=True):
        version = version or f"0.{build // 1000}.{build % 1000}"
        args = [
            sys.executable, "-I", SCRIPT, self.appcast,
            "--version", version,
            "--build", str(build),
            "--url", f"https://example.com/{version}.zip",
            "--release-page", f"https://example.com/v{version}",
            "--signature", SIGNATURE,
        ]
        if notes is not None:
            path = os.path.join(self.dir.name, "notes.md")
            with open(path, "w", encoding="utf-8") as f:
                f.write(notes)
            args += ["--notes", path]
        return subprocess.run(args, capture_output=True, text=True, check=check)

    def items(self):
        return ET.parse(self.appcast).getroot().find("channel").findall("item")

    def builds(self):
        return sorted(int(i.findtext("sparkle:version", namespaces=NS)) for i in self.items())

    def test_creates_feed_with_signed_enclosure(self):
        self.publish(2000, version="0.2.0")
        [item] = self.items()
        self.assertEqual(item.findtext("sparkle:shortVersionString", namespaces=NS), "0.2.0")
        self.assertEqual(item.findtext("sparkle:minimumSystemVersion", namespaces=NS), "14.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://example.com/0.2.0.zip")
        self.assertEqual(enclosure.get(f"{{{NS['sparkle']}}}edSignature"), "ab+c/=")
        self.assertEqual(enclosure.get("length"), "1234")

    def test_republishing_a_build_replaces_it(self):
        self.publish(2000)
        self.publish(2000)
        self.assertEqual(self.builds(), [2000])

    def test_publishing_older_builds_never_prunes_the_newest(self):
        self.publish(100)
        for build in range(1, 16):
            self.publish(build)
        builds = self.builds()
        self.assertEqual(len(builds), 15)
        self.assertIn(100, builds)
        self.assertNotIn(1, builds)

    def test_keeps_the_fifteen_highest_builds(self):
        for build in range(1, 21):
            self.publish(build)
        self.assertEqual(self.builds(), list(range(6, 21)))

    def test_notes_become_escaped_list_items(self):
        self.publish(2000, notes="## What's Changed\n* Fix `codex` & <rings> by @someone in https://github.com/x/pull/1\n\n**Full Changelog**: https://x\n")
        description = self.items()[0].findtext("description")
        self.assertIn("<li>Fix codex &amp; &lt;rings&gt;</li>", description)
        self.assertNotIn("@someone", description)
        self.assertNotIn("Full Changelog", description)

    def test_keeps_only_the_first_three_notes(self):
        self.publish(2000, notes="* One\n* Two\n* Three\n* Four\n* Five\n")
        description = self.items()[0].findtext("description")
        self.assertIn("<li>Three</li>", description)
        self.assertNotIn("Four", description)
        self.assertEqual(description.count("<li>"), 3)

    def test_rejects_prereleases(self):
        result = self.publish(2000, version="0.2.0-beta", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(os.path.exists(self.appcast))

    def test_rejects_signature_without_length(self):
        args = [sys.executable, "-I", SCRIPT, self.appcast, "--version", "0.2.0", "--build", "2000",
                "--url", "u", "--release-page", "r", "--signature", 'sparkle:edSignature="abc"']
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
