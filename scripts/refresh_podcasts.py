#!/usr/bin/env python3
"""Refresh Personal Hub podcast cards from configured YouTube playlists."""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

INDEX_PATH = Path(__file__).resolve().parents[1] / "index.html"
USER_AGENT = "Mozilla/5.0 (compatible; PersonalHubPodcastRefresh/1.0)"
ATOM = "{http://www.w3.org/2005/Atom}"
YT = "{http://www.youtube.com/xml/schemas/2015}"


@dataclass(frozen=True)
class Episode:
    title: str
    video_id: str
    published: datetime

    @property
    def watch_url(self) -> str:
        return f"https://www.youtube.com/watch?v={self.video_id}"

    @property
    def display_date(self) -> str:
        return f"{self.published:%b} {self.published.day}, {self.published.year}"


def js_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def playlist_id_from_url(source: str) -> str:
    parsed = urllib.parse.urlparse(source)
    if parsed.netloc.lower() not in {"youtube.com", "www.youtube.com", "m.youtube.com"}:
        raise ValueError(f"Source is not a YouTube URL: {source}")
    playlist_ids = urllib.parse.parse_qs(parsed.query).get("list", [])
    if not playlist_ids or not playlist_ids[0]:
        raise ValueError(f"YouTube playlist ID is missing: {source}")
    return playlist_ids[0]


def newest_episode(source: str) -> Episode:
    playlist_id = playlist_id_from_url(source)
    feed_url = "https://www.youtube.com/feeds/videos.xml?playlist_id=" + urllib.parse.quote(playlist_id)
    request = urllib.request.Request(feed_url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = response.read()

    root = ET.fromstring(payload)
    entry = root.find(f"{ATOM}entry")
    if entry is None:
        raise RuntimeError(f"No videos were returned for playlist {playlist_id}")

    title_element = entry.find(f"{ATOM}title")
    video_element = entry.find(f"{YT}videoId")
    published_element = entry.find(f"{ATOM}published")
    if title_element is None or video_element is None or published_element is None:
        raise RuntimeError(f"The YouTube feed was incomplete for playlist {playlist_id}")

    title = (title_element.text or "").strip()
    video_id = (video_element.text or "").strip()
    published_text = (published_element.text or "").strip()
    if not title or not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
        raise RuntimeError(f"The YouTube feed returned invalid episode data for playlist {playlist_id}")

    published = datetime.fromisoformat(published_text.replace("Z", "+00:00"))
    return Episode(title=title, video_id=video_id, published=published)


def field(block: list[str], name: str) -> str:
    pattern = re.compile(rf'^\s*{re.escape(name)}:\s*"(.*)",?\s*$')
    for line in block:
        match = pattern.match(line)
        if match:
            return match.group(1)
    raise ValueError(f"Podcast object is missing {name}")


def replace_field(block: list[str], name: str, value: str) -> bool:
    pattern = re.compile(rf'^(\s*){re.escape(name)}:\s*.*?(,?)\s*$')
    for index, line in enumerate(block):
        match = pattern.match(line)
        if match:
            new_line = f"{match.group(1)}{name}:" + " " * max(1, 13 - len(name)) + js_string(value) + match.group(2)
            if new_line != line:
                block[index] = new_line
                return True
            return False
    raise ValueError(f"Podcast object is missing {name}")


def podcast_blocks(lines: list[str]) -> list[tuple[int, int]]:
    start = next((i for i, line in enumerate(lines) if re.match(r"^\s*podcasts:\s*\[", line)), None)
    if start is None:
        raise ValueError("CONFIG.podcasts was not found")

    blocks: list[tuple[int, int]] = []
    object_start: int | None = None
    for index in range(start + 1, len(lines)):
        stripped = lines[index].strip()
        if stripped == "{" and object_start is None:
            object_start = index
        elif object_start is not None and stripped in {"},", "}"}:
            blocks.append((object_start, index + 1))
            object_start = None
        elif object_start is None and stripped in {"]", "],"}:
            break
    return blocks


def main() -> int:
    original = INDEX_PATH.read_text(encoding="utf-8")
    if "<!DOCTYPE html>" not in original or "const CONFIG" not in original or "</html>" not in original:
        raise ValueError("index.html failed structural validation")

    lines = original.splitlines()
    changes: list[str] = []
    failures: list[str] = []

    # Process from the end so replacing a block never invalidates later indices.
    for start, end in reversed(podcast_blocks(lines)):
        block = lines[start:end]
        name = field(block, "name")
        source = field(block, "source")
        if not source:
            continue

        try:
            episode = newest_episode(source)
            block_changed = False
            block_changed |= replace_field(block, "latestUrl", episode.watch_url)
            block_changed |= replace_field(block, "latestTitle", episode.title)
            block_changed |= replace_field(block, "latestDate", episode.display_date)
            if block_changed:
                lines[start:end] = block
                changes.append(f"{name}: {episode.title} ({episode.display_date})")
        except Exception as exc:  # Keep this card unchanged and process the remaining cards.
            failures.append(f"{name}: {exc}")

    updated = "\n".join(lines) + ("\n" if original.endswith("\n") else "")
    if updated != original:
        INDEX_PATH.write_text(updated, encoding="utf-8", newline="\n")

    if changes:
        print("Updated podcast cards:")
        for change in reversed(changes):
            print(f"- {change}")
    else:
        print("No podcast card changes were needed.")

    if failures:
        print("Cards left unchanged because verification failed:", file=sys.stderr)
        for failure in reversed(failures):
            print(f"- {failure}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
