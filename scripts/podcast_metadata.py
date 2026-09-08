"""Standard-library-only podcast configuration and untrusted metadata boundary."""

from __future__ import annotations

import hashlib
import json
import re
import stat
from dataclasses import dataclass
from datetime import date
from pathlib import Path

INDEX_PATH = Path(__file__).resolve().parents[1] / "index.html"
ARTIFACT_FILENAME = "metadata.json"
SCHEMA_VERSION = 1
MAX_SOURCES = 32
MAX_TITLE_LENGTH = 512
MAX_ARTIFACT_BYTES = 128 * 1024
VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")
SOURCE_ID = re.compile(r"[0-9a-f]{64}")
PLAYLIST_URL = re.compile(r"https://(?:www\.)?youtube\.com/playlist\?list=[A-Za-z0-9_-]{1,128}")
MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
LATEST_FIELDS = ("latestUrl", "latestTitle", "latestDate")


@dataclass(frozen=True)
class Episode:
    title: str
    video_id: str
    display_date: str

    @property
    def watch_url(self) -> str:
        return f"https://www.youtube.com/watch?v={self.video_id}"


@dataclass(frozen=True)
class Podcast:
    name: str
    source: str
    source_id: str
    start: int
    end: int


def js_string(value: str) -> str:
    # JSON escaping alone is insufficient inside an HTML <script> element.
    return (json.dumps(value, ensure_ascii=False)
            .replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
            .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))


def field_match(block: list[str], name: str) -> tuple[int, re.Match]:
    pattern = re.compile(rf'^(\s*{re.escape(name)}:\s*)("(?:[^"\\]|\\.)*")(,?\s*)$')
    matches = [(i, match) for i, line in enumerate(block)
               if (match := pattern.fullmatch(line))]
    if len(matches) != 1:
        raise ValueError(f"Podcast object must have exactly one string field: {name}")
    return matches[0]


def field(block: list[str], name: str) -> str:
    _, match = field_match(block, name)
    value = json.loads(match.group(2))
    if type(value) is not str:
        raise ValueError(f"Podcast field must be a string: {name}")
    return value


def replace_field(block: list[str], name: str, value: str) -> None:
    if name not in LATEST_FIELDS:
        raise ValueError("Only latest episode fields may be replaced")
    index, match = field_match(block, name)
    block[index] = match.group(1) + js_string(value) + match.group(3)


def podcast_blocks(lines: list[str]) -> list[tuple[int, int]]:
    config = [i for i, line in enumerate(lines) if re.fullmatch(r"const CONFIG\s*=\s*\{", line)]
    if len(config) != 1:
        raise ValueError("Expected exactly one const CONFIG object")
    end = next((i for i in range(config[0] + 1, len(lines)) if lines[i] == "};"), None)
    if end is None:
        raise ValueError("CONFIG object is not terminated")
    starts = [i for i in range(config[0] + 1, end)
              if re.fullmatch(r"\s*podcasts:\s*\[", lines[i])]
    if len(starts) != 1:
        raise ValueError("Expected exactly one CONFIG.podcasts array")

    blocks: list[tuple[int, int]] = []
    object_start = None
    for index in range(starts[0] + 1, end):
        stripped = lines[index].strip()
        if stripped == "{" and object_start is None:
            object_start = index
        elif object_start is not None and stripped in {"},", "}"}:
            blocks.append((object_start, index + 1))
            if len(blocks) > MAX_SOURCES:
                raise ValueError("Too many podcast cards")
            object_start = None
        elif object_start is None and stripped in {"]", "],"}:
            return blocks
        elif object_start is None and stripped and not stripped.startswith("//"):
            raise ValueError("Unexpected content in CONFIG.podcasts")
    raise ValueError("CONFIG.podcasts is not terminated")


def configured_podcasts(original: str) -> list[Podcast]:
    if not all(marker in original for marker in ("<!DOCTYPE html>", "</html>")):
        raise ValueError("index.html failed structural validation")
    # Split on LF only: Unicode line separators may legitimately occur in titles.
    lines = original.split("\n")
    podcasts = []
    seen = set()
    for start, end in podcast_blocks(lines):
        block = lines[start:end]
        name = field(block, "name")
        source = field(block, "source")
        if not source:
            continue
        if not PLAYLIST_URL.fullmatch(source):
            raise ValueError("Configured source must be an exact YouTube playlist URL")
        source_id = hashlib.sha256(source.encode("utf-8")).hexdigest()
        if source_id in seen:
            raise ValueError("Duplicate configured podcast source")
        seen.add(source_id)
        for key in LATEST_FIELDS:
            field(block, key)
        podcasts.append(Podcast(name, source, source_id, start, end))
    return podcasts


def validate_episode(episode: Episode) -> None:
    if type(episode.video_id) is not str or not VIDEO_ID.fullmatch(episode.video_id):
        raise ValueError("Invalid episode video_id")
    title = episode.title
    if (type(title) is not str or not 1 <= len(title) <= MAX_TITLE_LENGTH or not title.strip()
            or any(0xD800 <= ord(c) <= 0xDFFF or (ord(c) < 32 and c not in "\t\r\n") for c in title)):
        raise ValueError("Invalid episode title")
    value = episode.display_date
    if type(value) is not str:
        raise ValueError("Invalid episode display_date type")
    if value == "Latest":
        return
    match = re.fullmatch(r"([A-Z][a-z]{2}) ([1-9]|[12][0-9]|3[01]), ([1-9][0-9]{3})", value)
    if not match or match.group(1) not in MONTHS:
        raise ValueError("Invalid episode display_date")
    date(int(match.group(3)), MONTHS.index(match.group(1)) + 1, int(match.group(2)))


def exact_keys(value: object, keys: set[str]) -> None:
    if type(value) is not dict or value.keys() != keys:
        raise ValueError("Unexpected metadata object fields")


def validate_metadata(metadata: object, podcasts: list[Podcast]) -> dict[str, Episode]:
    exact_keys(metadata, {"schema_version", "sources", "episodes"})
    if type(metadata["schema_version"]) is not int or metadata["schema_version"] != SCHEMA_VERSION:
        raise ValueError("Unsupported metadata schema_version")
    sources = metadata["sources"]
    if type(sources) is not list or len(sources) > MAX_SOURCES:
        raise ValueError("Invalid metadata sources list")
    if any(type(source) is not str or not SOURCE_ID.fullmatch(source) for source in sources):
        raise ValueError("Invalid metadata source identifier")
    if len(set(sources)) != len(sources):
        raise ValueError("Duplicate metadata source identifiers")
    if set(sources) != {podcast.source_id for podcast in podcasts}:
        raise ValueError("Podcast sources changed or metadata contains unknown sources; rerun extraction")
    records = metadata["episodes"]
    if type(records) is not list or len(records) > MAX_SOURCES:
        raise ValueError("Invalid metadata episodes list")
    episodes = {}
    for record in records:
        exact_keys(record, {"source_id", "title", "video_id", "display_date"})
        source_id = record["source_id"]
        if type(source_id) is not str or source_id not in sources:
            raise ValueError("Unknown episode source identifier")
        if source_id in episodes:
            raise ValueError("Duplicate episode source identifier")
        episode = Episode(record["title"], record["video_id"], record["display_date"])
        validate_episode(episode)
        episodes[source_id] = episode
    return episodes


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("Duplicate JSON object key")
        value[key] = item
    return value


def _invalid_constant(value: str) -> None:
    raise ValueError("Nonstandard JSON constant")


def decode_metadata(data: bytes) -> object:
    if len(data) > MAX_ARTIFACT_BYTES:
        raise ValueError("Metadata artifact is oversized")
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=_unique_object,
                          parse_constant=_invalid_constant)
    except (UnicodeError, RecursionError) as exc:
        raise ValueError("Metadata must be bounded UTF-8 JSON") from exc


def read_metadata(directory: Path) -> object:
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("Metadata data directory is missing or is a symlink")
    entries = directory.iterdir()
    first = next(entries, None)
    if first is None or next(entries, None) is not None or first.name != ARTIFACT_FILENAME:
        raise ValueError("Metadata directory must contain only metadata.json")
    info = first.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_ARTIFACT_BYTES:
        raise ValueError("Metadata must be a bounded regular file")
    with first.open("rb") as stream:
        return decode_metadata(stream.read(MAX_ARTIFACT_BYTES + 1))


def apply_metadata(original: str, metadata: object) -> tuple[str, int]:
    podcasts = configured_podcasts(original)
    episodes = validate_metadata(metadata, podcasts)
    lines = original.split("\n")
    changed = 0
    for podcast in podcasts:
        episode = episodes.get(podcast.source_id)
        if episode is None:
            continue  # Omitted records are failed playlist reads; preserve the current card.
        block = lines[podcast.start:podcast.end]
        before = block.copy()
        for key, value in zip(LATEST_FIELDS, (episode.watch_url, episode.title, episode.display_date)):
            replace_field(block, key, value)
        if block != before:
            lines[podcast.start:podcast.end] = block
            changed += 1
    return "\n".join(lines), changed
