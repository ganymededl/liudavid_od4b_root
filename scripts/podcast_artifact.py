#!/usr/bin/env python3
"""Download this run's fixed-name artifact without ever extracting archive paths."""

from __future__ import annotations

import hashlib
import http.client
import io
import os
import re
import stat
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from podcast_metadata import ARTIFACT_FILENAME, MAX_ARTIFACT_BYTES, decode_metadata

ARTIFACT_NAME = "podcast-metadata"
ARCHIVE_FILENAME = "podcast-metadata.zip"
MAX_ARCHIVE_BYTES = 256 * 1024
MAX_API_BYTES = 64 * 1024
DOWNLOAD_SECONDS = 60
SOCKET_TIMEOUT = 10
API_ORIGIN = "https://api.github.com"


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def _positive_id(value: object) -> bool:
    return type(value) is int and 0 < value < 2**63


def _request(opener, url: str, deadline: float, token: str | None = None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError("Artifact download deadline exceeded")
    headers = {"Accept": "application/octet-stream", "Accept-Encoding": "identity"}
    if token is not None:
        if not url.startswith(API_ORIGIN + "/repos/"):
            raise ValueError("Refusing to send credentials outside the GitHub API")
        headers.update({"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"})
    try:
        return opener.open(urllib.request.Request(url, headers=headers),
                           timeout=min(SOCKET_TIMEOUT, remaining))
    except urllib.error.HTTPError as exc:
        exc.close()
        raise


def _read_response(response, limit: int, deadline: float, expected_size: int | None = None) -> bytes:
    if response.status != 200:
        raise ValueError("Unexpected artifact HTTP status")
    if response.headers.get("Content-Encoding", "identity") != "identity":
        raise ValueError("Unexpected HTTP content encoding")
    length = response.headers.get("Content-Length")
    if length is not None:
        if not re.fullmatch(r"[0-9]+", length) or len(length) > 10:
            raise ValueError("Invalid HTTP content length")
        length = int(length)
        if length > limit or (expected_size is not None and length != expected_size):
            raise ValueError("Artifact HTTP size does not match the bounded expected size")
    chunks = []
    count = 0
    while True:
        if time.monotonic() >= deadline:
            raise ValueError("Artifact download deadline exceeded")
        chunk = response.read1(min(64 * 1024, limit + 1 - count))
        if not chunk:
            break
        count += len(chunk)
        if count > limit:
            raise ValueError("Artifact response is oversized")
        chunks.append(chunk)
    if (length is not None and count != length) or (expected_size is not None and count != expected_size):
        raise ValueError("Artifact response is truncated or has an unexpected size")
    return b"".join(chunks)


def _artifact_record(value: object, run_id: int, repository_id: int) -> dict:
    if type(value) is not dict or type(value.get("total_count")) is not int or value["total_count"] != 1:
        raise ValueError("Expected exactly one matching artifact; listing may be missing or ambiguous")
    records = value.get("artifacts")
    if type(records) is not list or len(records) != 1 or type(records[0]) is not dict:
        raise ValueError("Artifact listing is truncated or malformed")
    record = records[0]
    if (record.get("name") != ARTIFACT_NAME or record.get("expired") is not False
            or not _positive_id(record.get("id"))):
        raise ValueError("Artifact identity or expiry is invalid")
    run = record.get("workflow_run")
    if (type(run) is not dict or not _positive_id(run.get("id")) or run["id"] != run_id
            or not _positive_id(run.get("repository_id")) or run["repository_id"] != repository_id):
        raise ValueError("Artifact does not belong to this repository and workflow run")
    size = record.get("size_in_bytes")
    if type(size) is not int or not 0 < size <= MAX_ARCHIVE_BYTES:
        raise ValueError("Artifact archive exceeds the size bound")
    expires = record.get("expires_at")
    if type(expires) is not str or len(expires) > 40:
        raise ValueError("Artifact expiry timestamp is missing")
    expiration = datetime.fromisoformat(expires.replace("Z", "+00:00"))
    if expiration.tzinfo is None or expiration <= datetime.now(timezone.utc):
        raise ValueError("Artifact has expired")
    digest = record.get("digest")
    if digest is not None and (type(digest) is not str or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest)):
        raise ValueError("Unexpected artifact digest format")
    return record


def _signed_url(location: str | None) -> str:
    if type(location) is not str:
        raise ValueError("Artifact download redirect is missing")
    url = urllib.parse.urlsplit(location)
    if (url.scheme != "https" or not url.hostname or url.username is not None
            or url.password is not None or url.port not in (None, 443) or url.fragment):
        raise ValueError("Artifact download redirect must be an HTTPS storage URL")
    # These are GitHub's artifact storage domains, not values from the ZIP.
    if not url.hostname.endswith((".blob.core.windows.net", ".githubusercontent.com")):
        raise ValueError("Artifact download redirected to an unrecognized storage host")
    return location


def download_archive(repository: str, run_id: int, repository_id: int, token: str,
                     runner_temp: Path, *, opener=None) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository identity")
    if not _positive_id(run_id) or not _positive_id(repository_id) or not token:
        raise ValueError("Missing GitHub run identity or credentials")
    if not runner_temp.is_dir() or runner_temp.is_symlink():
        raise ValueError("RUNNER_TEMP must be a trusted existing directory")
    if opener is None:
        opener = urllib.request.build_opener(NoRedirects())
    deadline = time.monotonic() + DOWNLOAD_SECONDS
    base = f"{API_ORIGIN}/repos/{repository}"
    listing = f"{base}/actions/runs/{run_id}/artifacts?name={ARTIFACT_NAME}&per_page=100"
    with _request(opener, listing, deadline, token) as response:
        if response.headers.get("Link"):
            raise ValueError("Paginated artifact listing is ambiguous")
        record = _artifact_record(decode_metadata(_read_response(response, MAX_API_BYTES, deadline)),
                                  run_id, repository_id)
    endpoint = f"{base}/actions/artifacts/{record['id']}/zip"
    try:
        with _request(opener, endpoint, deadline, token):
            raise ValueError("Expected GitHub's signed artifact download redirect")
    except urllib.error.HTTPError as exc:
        try:
            if exc.code != 302:
                raise ValueError("GitHub did not provide an artifact download redirect") from exc
            location = _signed_url(exc.headers.get("Location"))
        finally:
            exc.close()
    # Never reuse the authenticated Request or follow additional redirects.
    with _request(opener, location, deadline) as response:
        data = _read_response(response, MAX_ARCHIVE_BYTES, deadline, record["size_in_bytes"])
    if record.get("digest") and "sha256:" + hashlib.sha256(data).hexdigest() != record["digest"]:
        raise ValueError("Artifact archive digest mismatch")
    destination = runner_temp / ARCHIVE_FILENAME
    # No remote filename, member name, or API URL can influence this output path.
    with destination.open("xb") as stream:
        stream.write(data)
    return destination


def decode_archive(data: bytes) -> object:
    if not 0 < len(data) <= MAX_ARCHIVE_BYTES:
        raise ValueError("Artifact archive is empty or oversized")
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = archive.infolist()
            if len(members) != 1:
                raise ValueError("Archive must contain exactly one metadata.json member")
            footer_offset = len(data) - 22 - len(archive.comment)
            footer = struct.unpack_from("<4s4H2LH", data, footer_offset)
            signature, disk, central_disk, disk_count, total_count, central_size, central_offset, _ = footer
            if (signature != b"PK\x05\x06" or disk != 0 or central_disk != 0
                    or disk_count != 1 or total_count != 1 or central_offset != archive.start_dir
                    or central_offset + central_size != footer_offset):
                raise ValueError("ZIP footer must describe one complete single-disk archive")
            member = members[0]
            mode = member.external_attr >> 16
            if (member.filename != ARTIFACT_FILENAME or member.orig_filename != ARTIFACT_FILENAME
                    or member.is_dir() or member.create_system not in (0, 3)
                    or stat.S_IFMT(mode) not in (0, stat.S_IFREG) or member.external_attr & 0x10):
                raise ValueError("Archive member must be a regular root-level metadata.json")
            if (member.flag_bits & ~(0x800 | 0x8 | 0x6)
                    or member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    or member.extract_version > 20):
                raise ValueError("Encrypted or unsupported ZIP member")
            if (not 0 < member.file_size <= MAX_ARTIFACT_BYTES
                    or not 0 < member.compress_size <= MAX_ARCHIVE_BYTES or member.header_offset != 0):
                raise ValueError("ZIP member sizes or offset exceed permitted bounds")

            header = struct.unpack_from("<4s5H3L2H", data)
            signature, version, flags, method, _, _, crc, compressed, size, name_length, extra_length = header
            start = 30 + name_length + extra_length
            end = start + member.compress_size
            if (signature != b"PK\x03\x04" or version > 20 or flags != member.flag_bits
                    or method != member.compress_type or data[30:30 + name_length] != b"metadata.json"
                    or start > len(data) or end > archive.start_dir):
                raise ValueError("ZIP local header is inconsistent with its sole member")
            if flags & 0x8:
                if (crc not in (0, member.CRC) or compressed not in (0, member.compress_size)
                        or size not in (0, member.file_size)):
                    raise ValueError("ZIP streaming header has inconsistent size placeholders")
                descriptor = data[end:archive.start_dir]
                if descriptor.startswith(b"PK\x07\x08"):
                    descriptor = descriptor[4:]
                if len(descriptor) != 12 or struct.unpack("<3L", descriptor) != (
                        member.CRC, member.compress_size, member.file_size):
                    raise ValueError("ZIP data descriptor is inconsistent")
            elif (end != archive.start_dir or (crc, compressed, size) != (
                    member.CRC, member.compress_size, member.file_size)):
                raise ValueError("ZIP contains unexpected data or inconsistent local sizes")

            # ZipExtFile truncates output to the declared size, so independently
            # bound raw decompression and verify the *actual* end of the stream.
            payload = data[start:end]
            if method == zipfile.ZIP_DEFLATED:
                inflater = zlib.decompressobj(-zlib.MAX_WBITS)
                payload = inflater.decompress(payload, MAX_ARTIFACT_BYTES + 1)
                if not inflater.eof or inflater.unused_data or inflater.unconsumed_tail:
                    raise ValueError("ZIP deflate stream is oversized, truncated, or has trailing data")
            if (len(payload) > MAX_ARTIFACT_BYTES or len(payload) != member.file_size
                    or zlib.crc32(payload) != member.CRC):
                raise ValueError("ZIP actual member size or CRC mismatch")
            return decode_metadata(payload)
    except (zipfile.BadZipFile, NotImplementedError, struct.error, zlib.error) as exc:
        raise ValueError("Malformed or unsupported podcast ZIP archive") from exc


def read_metadata_archive(path: Path) -> object:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_ARCHIVE_BYTES:
        raise ValueError("Artifact archive must be a bounded regular file")
    with path.open("rb") as stream:
        return decode_archive(stream.read(MAX_ARCHIVE_BYTES + 1))


def main() -> int:
    try:
        download_archive(os.environ["GITHUB_REPOSITORY"], int(os.environ["GITHUB_RUN_ID"]),
                         int(os.environ["GITHUB_REPOSITORY_ID"]), os.environ["GH_TOKEN"],
                         Path(os.environ["RUNNER_TEMP"]))
    except (KeyError, OSError, ValueError, http.client.HTTPException) as exc:
        # URLs can contain signed credentials; never echo HTTP exception details.
        print(f"Podcast artifact download rejected ({type(exc).__name__}).", file=sys.stderr)
        return 1
    print("Downloaded this run's bounded podcast ZIP without extracting any files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
