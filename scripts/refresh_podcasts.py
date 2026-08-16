#!/usr/bin/env python3
"""Refresh Personal Hub podcast cards from their exact YouTube playlists."""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from yt_dlp import YoutubeDL

INDEX_PATH = Path(__file__).resolve().parents[1] / "index.html"
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


@dataclass(frozen=True)
class Episode:
    title: str
    video_id: str
    display_date: str

    @property
    def watch_url(self) -> str:
        return f"https://www.youtube.com/watch?v={self.video_id}"


def js_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def date_from_entry(entry: dict) -> str:
    timestamp = entry.get("timestamp") or entry.get("release_timestamp")
    if timestamp:
        published = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
        return f"{published:%b} {published.day}, {published.year}"

    upload_date = str(entry.get("upload_date") or "")
    if re.fullmatch(r"\d{8}", upload_date):
        published = datetime.strptime(upload_date, "%Y%m%d")
        return f"{published:%b} {published.day}, {published.year}"

    # YouTube sometimes omits dates from playlist extraction and blocks a second
    # video-details request on GitHub runners. Never retain a stale or guessed date.
    return "Latest"


def newest_episode(source: str) -> Episode:
    """Read item #1 directly from the configured YouTube playlist."""
    if not re.match(r"^https://(www\.)?youtube\.com/playlist\?", source):
        raise ValueError(f"Source is not a YouTube playlist URL: {source}")

    options = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extract_flat": "in_playlist",
        "playlist_items": "1",
        "lazy_playlist": True,
        "socket_timeout": 30,
        "retries": 3,
        "extractor_retries": 3,
    }

    with YoutubeDL(options) as downloader:
        playlist = downloader.extract_info(source, download=False)

    entries = [entry for entry in (playlist.get("entries") or []) if entry]
    if not entries:
        raise RuntimeError("The playlist returned no first entry")

    entry = entries[0]
    video_id = str(entry.get("id") or "").strip()
    title = str(entry.get("title") or "").strip()
    if not VIDEO_ID.fullmatch(video_id) or not title:
        raise RuntimeError("The playlist returned an invalid video ID or title")

    return Episode(title=title, video_id=video_id, display_date=date_from_entry(entry))


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
            new_line = (
                f"{match.group(1)}{name}:"
                + " " * max(1, 13 - len(name))
                + js_string(value)
                + match.group(2)
            )
            if new_line != line:
                block[index] = new_line
                return True
            return False
    raise ValueError(f"Podcast object is missing {name}")


def podcast_blocks(lines: list[str]) -> list[tuple[int, int]]:
    start = next(
        (i for i, line in enumerate(lines) if re.match(r"^\s*podcasts:\s*\[", line)),
        None,
    )
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
        except Exception as exc:
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
        for failure in reversed(failures):
            print(f"::warning title=Podcast verification failed::{failure}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
