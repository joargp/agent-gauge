#!/usr/bin/env python3
"""Adds a release to the Sparkle appcast (the update feed the app reads).

Modelled on Ghostty's dist/macos/update_appcast_tag.py.

    update_appcast.py APPCAST --version 0.2.0 --build 2000 \
        --url https://github.com/.../AgentGauge-0.2.0.zip \
        --release-page https://github.com/.../releases/tag/v0.2.0 \
        --signature 'sparkle:edSignature="..." length="..."' \
        [--notes NOTES.md]

APPCAST is created when missing. An existing item with the same build number
is replaced, and only the KEEP highest build numbers are kept. --signature is the output
of Sparkle's sign_update for the exact file at --url. --notes is the GitHub
release body; its first MAX_NOTES bullet points become the "What's new" list
in the app.
"""

import argparse
import html
import re
import shlex
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
KEEP = 15
# The app shows these in a small popover row; the full notes stay on GitHub.
MAX_NOTES = 3
MINIMUM_SYSTEM_VERSION = "14.0"


def sparkle(tag):
    return f"{{{SPARKLE_NS}}}{tag}"


def parse_signature(text):
    """Turns 'sparkle:edSignature="abc" length="123"' into a dict."""
    attrs = {}
    for pair in shlex.split(text.strip()):
        key, _, value = pair.partition("=")
        if not value:
            sys.exit(f"Unexpected sign_update output: {text!r}")
        if key.startswith("sparkle:"):
            key = sparkle(key.split(":", 1)[1])
        attrs[key] = value
    if sparkle("edSignature") not in attrs or "length" not in attrs:
        sys.exit(f"sign_update output lacks a signature or length: {text!r}")
    return attrs


def bullet_points(markdown):
    """Bullet lines of a GitHub release body, without credits and links."""
    points = []
    for line in markdown.splitlines():
        match = re.match(r"^\s*[-*]\s+(.*\S)\s*$", line)
        if not match:
            continue
        text = match.group(1)
        # GitHub's generated notes end each line with "by @user in <url>".
        text = re.sub(r"\s+by @\S+ in https?://\S+$", "", text)
        text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)  # [text](url) -> text
        text = re.sub(r"[`*_]", "", text)
        if text:
            points.append(text)
    return points[:MAX_NOTES]


def description(version, notes, release_page):
    items = "".join(f"<li>{html.escape(n)}</li>" for n in notes)
    body = f"<ul>{items}</ul>" if items else ""
    link = html.escape(release_page, quote=True)
    return f'<h2>Agent Gauge {html.escape(version)}</h2>{body}<p><a href="{link}">Release notes</a></p>'


def new_appcast():
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Agent Gauge"
    ET.SubElement(channel, "link").text = "https://joargp.github.io/agent-gauge/"
    ET.SubElement(channel, "description").text = "Updates for Agent Gauge"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def build_number(item):
    """Sparkle orders updates by build number, so pruning must too. Items
    without a readable one sort first and are pruned first."""
    try:
        return int(item.findtext(sparkle("version")))
    except (TypeError, ValueError):
        return -1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("appcast")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--release-page", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--notes")
    args = parser.parse_args()

    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        sys.exit(f"Only plain releases go in the feed, not {args.version!r}")
    if not args.build.isdigit():
        sys.exit(f"Build number must be a number, not {args.build!r}")

    ET.register_namespace("sparkle", SPARKLE_NS)
    try:
        tree = ET.parse(args.appcast)
    except FileNotFoundError:
        tree = new_appcast()
    channel = tree.getroot().find("channel")

    # Two items with one build number make Sparkle pick either, and the
    # signature check fails for the wrong one.
    for item in channel.findall("item"):
        if item.findtext(sparkle("version")) == args.build:
            channel.remove(item)

    notes = []
    if args.notes:
        with open(args.notes, encoding="utf-8") as f:
            notes = bullet_points(f.read())

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Agent Gauge {args.version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, sparkle("version")).text = args.build
    ET.SubElement(item, sparkle("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    ET.SubElement(item, sparkle("fullReleaseNotesLink")).text = args.release_page
    ET.SubElement(item, "description").text = description(args.version, notes, args.release_page)
    enclosure = ET.SubElement(item, "enclosure", {"url": args.url, "type": "application/octet-stream"})
    for key, value in parse_signature(args.signature).items():
        enclosure.set(key, value)

    # Keep the highest builds, not the latest published: republishing an older
    # release must never push the newest one out of the feed.
    items = sorted(channel.findall("item"), key=build_number)
    for old in items[:-KEEP]:
        channel.remove(old)

    ET.indent(tree, space="  ")
    tree.write(args.appcast, xml_declaration=True, encoding="utf-8")
    print(f"Added Agent Gauge {args.version} (build {args.build}) to {args.appcast}")


if __name__ == "__main__":
    main()
