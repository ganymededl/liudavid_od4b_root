#!/usr/bin/env python3
"""Extract podcast metadata; without --output, also refresh the local index.html."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from podcast_metadata import (
    INDEX_PATH, MAX_ARTIFACT_BYTES, MONTHS, PLAYLIST_URL, SCHEMA_VERSION,
    Episode, Podcast, apply_metadata, configured_podcasts, validate_episode, validate_metadata,
)


class PlaylistReadError(RuntimeError):
    pass


def date_from_entry(entry: dict) -> str:
    timestamp = entry.get("timestamp") or entry.get("release_timestamp")
    if timestamp:
        published = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
    else:
        upload_date = str(entry.get("upload_date") or "")
        if not re.fullmatch(r"[0-9]{8}", upload_date):
            return "Latest"
        published = datetime.strptime(upload_date, "%Y%m%d")
    return f"{MONTHS[published.month - 1]} {published.day}, {published.year}"


def newest_episode(source: str) -> Episode:
    """Read item #1 directly from the configured YouTube playlist."""
    # The publisher never imports this module or the network/dependency stack.
    from yt_dlp import YoutubeDL
    from yt_dlp.utils import DownloadError

    if not PLAYLIST_URL.fullmatch(source):
        raise ValueError("Source is not an exact YouTube playlist URL")
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
    try:
        with YoutubeDL(options) as downloader:
            playlist = downloader.extract_info(source, download=False)
            if not isinstance(playlist, dict):
                raise ValueError("The playlist returned no metadata")
            entry = next((item for item in (playlist.get("entries") or []) if item), None)
        if not isinstance(entry, dict):
            raise ValueError("The playlist returned no first entry")
        video_id = entry.get("id")
        title = entry.get("title")
        if type(video_id) is not str or type(title) is not str:
            raise ValueError("The playlist returned an invalid video ID or title")
        episode = Episode(title.strip(), video_id.strip(), date_from_entry(entry))
        validate_episode(episode)
        return episode
    except (DownloadError, OSError, ValueError, OverflowError) as exc:
        raise PlaylistReadError(str(exc)) from exc


def collect_metadata(podcasts: list[Podcast]) -> dict:
    records = []
    for podcast in podcasts:
        try:
            episode = newest_episode(podcast.source)
        except PlaylistReadError as exc:
            message = f"{podcast.name}: {exc}".replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::warning title=Podcast verification failed::{message}", file=sys.stderr)
            continue
        records.append({"source_id": podcast.source_id, "title": episode.title,
                        "video_id": episode.video_id, "display_date": episode.display_date})
    metadata = {"schema_version": SCHEMA_VERSION,
                "sources": [podcast.source_id for podcast in podcasts], "episodes": records}
    validate_metadata(metadata, podcasts)
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write metadata JSON only; do not edit index.html")
    args = parser.parse_args()
    original = INDEX_PATH.read_text(encoding="utf-8")
    metadata = collect_metadata(configured_podcasts(original))
    if args.output:
        encoded = (json.dumps(metadata, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        if len(encoded) > MAX_ARTIFACT_BYTES:
            raise ValueError("Extracted metadata exceeds artifact size limit")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(encoded)
        print(f"Extracted {len(metadata['episodes'])} podcast episodes.")
    else:
        updated, changed = apply_metadata(original, metadata)
        if updated != original:
            INDEX_PATH.write_text(updated, encoding="utf-8", newline="\n")
        print(f"Updated {changed} podcast cards." if changed else "No podcast card changes were needed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
