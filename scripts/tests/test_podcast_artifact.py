from __future__ import annotations

import hashlib
import io
import json
import shutil
import stat
import struct
import sys
import time
import unittest
import urllib.error
import urllib.request
import uuid
import warnings
import zipfile
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import podcast_artifact as artifact_io
import podcast_metadata as metadata
import publish_podcasts as publisher
from test_podcasts import artifact, fixture


def make_zip(entries, compression=zipfile.ZIP_DEFLATED, *, stream=None, comment=b""):
    stream = stream if stream is not None else io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(stream, "w", compression=compression) as archive:
            archive.comment = comment
            for name, data in entries:
                archive.writestr(name, data, compress_type=compression)
    return stream.getvalue()


class Response(io.BytesIO):
    def __init__(self, data, headers=None, status=200):
        super().__init__(data)
        self.status = status
        self.headers = {"Content-Length": str(len(data))} if headers is None else headers


class Opener:
    def __init__(self, *responses):
        self.responses = iter(responses)
        self.requests = []

    def open(self, request, timeout):
        self.requests.append((request, timeout))
        result = next(self.responses)
        if isinstance(result, Exception):
            raise result
        return result


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.directory = SCRIPTS / "tests" / f".scratch-{uuid.uuid4().hex}"
        self.directory.mkdir()
        self.original = fixture()
        self.metadata = artifact(self.original)
        self.payload = json.dumps(self.metadata).encode("utf-8")
        self.zip = make_zip([("metadata.json", self.payload)])
        self.token = "test-only-not-a-real-token"
        self.storage = "https://productionresultssa1.blob.core.windows.net/container/file.zip?sig=test"

    def tearDown(self):
        shutil.rmtree(self.directory)

    def record(self, data=None):
        data = self.zip if data is None else data
        return {
            "id": 789, "name": "podcast-metadata", "expired": False,
            "size_in_bytes": len(data), "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
            "expires_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
            "workflow_run": {"id": 123, "repository_id": 456},
            # Neither of these attacker-influenced fields may become a destination or endpoint.
            "archive_download_url": "https://attacker.invalid/should-not-be-used",
            "filename": "../../scripts/publish_podcasts.py",
        }

    def listing(self, record=None):
        return {"total_count": 1, "artifacts": [self.record() if record is None else record]}

    def redirect(self, url=None, code=302):
        error = urllib.error.HTTPError("https://api.github.com/repos/owner/repo/actions/artifacts/789/zip",
                                       code, "Redirect", {"Location": url or self.storage}, io.BytesIO())
        self.addCleanup(error.close)
        return error

    def opener(self, listing=None, response=None, redirect=None):
        return Opener(Response(json.dumps(self.listing() if listing is None else listing).encode()),
                      self.redirect() if redirect is None else redirect,
                      Response(self.zip) if response is None else response)

    def download(self, opener):
        return artifact_io.download_archive("owner/repo", 123, 456, self.token, self.directory, opener=opener)

    def test_root_metadata_round_trip_without_extraction(self):
        for compression in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            data = make_zip([("metadata.json", self.payload)], compression)
            with mock.patch.object(zipfile.ZipFile, "extract", side_effect=AssertionError("No extraction")):
                with mock.patch.object(zipfile.ZipFile, "extractall", side_effect=AssertionError("No extraction")):
                    self.assertEqual(artifact_io.decode_archive(data), self.metadata)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_actions_style_streaming_zip_descriptor(self):
        class Streaming(io.BytesIO):
            def seek(self, *args):
                raise io.UnsupportedOperation("nonseekable stream")

        data = make_zip([("metadata.json", self.payload)], stream=Streaming())
        self.assertEqual(struct.unpack_from("<H", data, 6)[0] & 8, 8)
        self.assertEqual(artifact_io.decode_archive(data), self.metadata)

    def test_member_paths_absolute_names_and_nulls_rejected_without_writes(self):
        sentinel = self.directory / "trusted-script.py"
        sentinel.write_text("trusted code", encoding="utf-8")
        names = (
            "../metadata.json", "safe/../../../liudavid_od4b_root/liudavid_od4b_root/scripts/AUDIT_MARKER.txt",
            "/home/runner/work/repo/scripts/publish_podcasts.py", r"C:\repo\scripts\publish_podcasts.py",
            r"..\scripts\publish_podcasts.py", "./metadata.json", "nested/metadata.json", "metadata.json/",
            "scripts/publish_podcasts.py", "METADATA.JSON",
        )
        for name in names:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(make_zip([(name, self.payload)]))
        embedded_null = make_zip([("metadata.jsonX", self.payload)]).replace(b"metadata.jsonX", b"metadata.json\x00")
        with self.assertRaises(ValueError):
            artifact_io.decode_archive(embedded_null)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "trusted code")
        self.assertEqual(list(self.directory.iterdir()), [sentinel])

    def test_missing_duplicate_and_additional_members_rejected(self):
        for entries in ([], [("metadata.json", self.payload)] * 2,
                        [("metadata.json", self.payload), ("scripts/publish_podcasts.py", b"attack")],
                        [("metadata.json", self.payload), ("nested/", b"")]):
            with self.subTest(entries=len(entries)):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(make_zip(entries))

    def test_symlinks_directories_devices_and_unknown_member_types_rejected(self):
        for mode in (stat.S_IFLNK, stat.S_IFDIR, stat.S_IFIFO, stat.S_IFSOCK, stat.S_IFCHR, stat.S_IFBLK):
            member = zipfile.ZipInfo("metadata.json")
            member.create_system = 3
            member.external_attr = (mode | 0o644) << 16
            with self.subTest(mode=mode):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(make_zip([(member, self.payload)]))
        member = zipfile.ZipInfo("metadata.json")
        member.external_attr = 0x10
        with self.assertRaises(ValueError):
            artifact_io.decode_archive(make_zip([(member, self.payload)]))
        member.create_system = 15
        member.external_attr = (stat.S_IFREG | 0o644) << 16
        with self.assertRaises(ValueError):
            artifact_io.decode_archive(make_zip([(member, self.payload)]))

    def test_encryption_and_unexpected_compression_rejected(self):
        central = self.zip.index(b"PK\x01\x02")
        for flag in (1, 0x40, 0x2000):
            encrypted = bytearray(self.zip)
            struct.pack_into("<H", encrypted, 6, flag)
            struct.pack_into("<H", encrypted, central + 8, flag)
            with self.subTest(flag=flag):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(bytes(encrypted))
        for compression in (zipfile.ZIP_BZIP2, zipfile.ZIP_LZMA):
            with self.subTest(compression=compression):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(make_zip([("metadata.json", self.payload)], compression))

    def test_declared_and_actual_decompressed_size_bounds_and_bombs(self):
        for payload in (self.payload + b" " * metadata.MAX_ARTIFACT_BYTES,
                        self.payload + b" " * (10 * 1024 * 1024)):
            bomb = make_zip([("metadata.json", payload)])
            self.assertLess(len(bomb), artifact_io.MAX_ARCHIVE_BYTES)
            with self.assertRaises(ValueError):
                artifact_io.decode_archive(bomb)
            # A false size and prefix CRC can fool ZipExtFile's truncating reads.
            deceptive = bytearray(bomb)
            central = deceptive.index(b"PK\x01\x02")
            struct.pack_into("<L", deceptive, 22, len(self.payload))
            struct.pack_into("<L", deceptive, central + 24, len(self.payload))
            struct.pack_into("<L", deceptive, 14, zlib.crc32(self.payload))
            struct.pack_into("<L", deceptive, central + 16, zlib.crc32(self.payload))
            with self.assertRaises(ValueError):
                artifact_io.decode_archive(bytes(deceptive))

    def test_json_and_archive_exact_size_boundaries(self):
        payload = self.payload + b" " * (metadata.MAX_ARTIFACT_BYTES - len(self.payload))
        member = zipfile.ZipInfo("metadata.json")
        member.extra = struct.pack("<HH", 0xCAFE, 59996) + b"x" * 59996
        baseline = make_zip([(member, payload)], zipfile.ZIP_STORED)
        comment = b"x" * (artifact_io.MAX_ARCHIVE_BYTES - len(baseline))
        boundary = make_zip([(member, payload)], zipfile.ZIP_STORED, comment=comment)
        self.assertEqual(len(boundary), artifact_io.MAX_ARCHIVE_BYTES)
        self.assertEqual(artifact_io.decode_archive(boundary), self.metadata)
        with self.assertRaises(ValueError):
            artifact_io.decode_archive(boundary + b"x")
        with self.assertRaises(ValueError):
            artifact_io.decode_archive(make_zip([("metadata.json", payload + b" ")]))

    def test_bad_zip_headers_crc_truncation_and_json_rejected(self):
        bad_crc = bytearray(self.zip)
        central = bad_crc.index(b"PK\x01\x02")
        struct.pack_into("<L", bad_crc, 14, 0)
        struct.pack_into("<L", bad_crc, central + 16, 0)
        inconsistent_name = self.zip.replace(b"metadata.json", b"metadata.jsoX", 1)
        for data in (b"", b"not a zip", self.zip[:-10], bytes(bad_crc), inconsistent_name,
                     make_zip([("metadata.json", b"{malformed")])):
            with self.subTest(data=data[:20]):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(data)

    def test_split_disk_inconsistent_counts_and_trailing_archive_data_rejected(self):
        footer = len(self.zip) - 22
        for offset, value in ((4, 1), (6, 1), (8, 2), (10, 2)):
            malformed = bytearray(self.zip)
            struct.pack_into("<H", malformed, footer + offset, value)
            with self.subTest(offset=offset):
                with self.assertRaises(ValueError):
                    artifact_io.decode_archive(bytes(malformed))
        with self.assertRaises(ValueError):
            artifact_io.decode_archive(self.zip + b"trailing hidden data")

    def test_publisher_archive_validation_never_modifies_trusted_scripts(self):
        trusted = self.directory / "trusted"
        scripts = trusted / "scripts"
        scripts.mkdir(parents=True)
        index = trusted / "index.html"
        index.write_text(self.original, encoding="utf-8")
        script = scripts / "publish_podcasts.py"
        script.write_text("trusted publisher sentinel", encoding="utf-8")
        archive = self.directory / "podcast-metadata.zip"
        malicious = make_zip([
            ("metadata.json", self.payload),
            ("safe/../../../trusted/scripts/publish_podcasts.py", b"malicious replacement"),
        ])
        for data, expected in ((malicious, 1), (self.zip, 0)):
            archive.write_bytes(data)
            with mock.patch.object(publisher, "INDEX_PATH", index):
                with mock.patch.object(sys, "argv", ["publish_podcasts.py", "--metadata-archive", str(archive)]):
                    with mock.patch("sys.stdout", new=io.StringIO()), mock.patch("sys.stderr", new=io.StringIO()):
                        self.assertEqual(publisher.main(), expected)
            self.assertEqual(script.read_text(encoding="utf-8"), "trusted publisher sentinel")
            self.assertEqual(index.read_text(encoding="utf-8"), self.original if expected else
                             metadata.apply_metadata(self.original, self.metadata)[0])
        self.assertEqual(sorted(path.relative_to(trusted).as_posix() for path in trusted.rglob("*")),
                         ["index.html", "scripts", "scripts/publish_podcasts.py"])

    def test_download_scopes_identity_and_writes_only_fixed_archive(self):
        opener = self.opener()
        path = self.download(opener)
        self.assertEqual(path, self.directory / "podcast-metadata.zip")
        self.assertEqual(path.read_bytes(), self.zip)
        self.assertEqual(list(self.directory.iterdir()), [path])
        requests = [request for request, _ in opener.requests]
        self.assertEqual(requests[0].full_url,
                         "https://api.github.com/repos/owner/repo/actions/runs/123/artifacts?name=podcast-metadata&per_page=100")
        self.assertEqual(requests[1].full_url, "https://api.github.com/repos/owner/repo/actions/artifacts/789/zip")
        self.assertEqual(requests[2].full_url, self.storage)
        for request in requests[:2]:
            self.assertEqual(request.get_header("Authorization"), "Bearer " + self.token)
        self.assertIsNone(requests[2].get_header("Authorization"))
        self.assertNotIn(self.token, str(requests[2].header_items()))
        self.assertTrue(all(0 < timeout <= 10 for _, timeout in opener.requests))

    def test_listing_missing_ambiguous_truncated_wrong_run_or_expired_rejected(self):
        for listing in ({}, {"total_count": 0, "artifacts": []},
                        {"total_count": 2, "artifacts": [self.record()]},
                        {"total_count": 1, "artifacts": []},
                        {"total_count": True, "artifacts": [self.record()]},
                        {"total_count": 1, "artifacts": [self.record(), self.record()]}):
            with self.subTest(listing=listing):
                with self.assertRaises(ValueError):
                    self.download(self.opener(listing=listing))
        for key, value in (
            ("name", "another-artifact"), ("expired", True), ("expired", 0),
            ("id", "../../bad"), ("id", True), ("size_in_bytes", True),
            ("size_in_bytes", artifact_io.MAX_ARCHIVE_BYTES + 1),
            ("workflow_run", {"id": 124, "repository_id": 456}),
            ("workflow_run", {"id": 123, "repository_id": 457}),
            ("expires_at", "2000-01-01T00:00:00Z"), ("expires_at", None),
            ("digest", "not-a-sha256"),
        ):
            with self.subTest(key=key, value=value):
                record = self.record()
                record[key] = value
                with self.assertRaises(ValueError):
                    self.download(self.opener(listing=self.listing(record)))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_pagination_and_oversized_api_responses_rejected(self):
        for response in (
            Response(json.dumps(self.listing()).encode(), {"Link": '<https://example.invalid>; rel="next"'}),
            Response(b"x" * (artifact_io.MAX_API_BYTES + 1)),
            Response(b'{"total_count":1,"total_count":1,"artifacts":[]}'),
        ):
            with self.assertRaises(ValueError):
                self.download(Opener(response))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_no_redirect_can_forward_api_credentials(self):
        request = urllib.request.Request("https://api.github.com/repos/owner/repo", headers={
            "Authorization": "Bearer " + self.token})
        handler = artifact_io.NoRedirects()
        for code in (301, 302, 303, 307, 308):
            self.assertIsNone(handler.redirect_request(request, None, code, "redirect", {},
                                                      "https://attacker.invalid/"))
        with self.assertRaises(ValueError):
            artifact_io._request(self.opener(), self.storage, time.monotonic() + 10, self.token)
        opener = self.opener(response=self.redirect("https://attacker.invalid/final"))
        with self.assertRaises(urllib.error.HTTPError):
            self.download(opener)
        self.assertEqual(len(opener.requests), 3)
        self.assertIsNone(opener.requests[-1][0].get_header("Authorization"))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_invalid_storage_redirects_rejected_without_storage_requests(self):
        for url in ("http://productionresultssa1.blob.core.windows.net/file",
                    "https://attacker.invalid/file", "https://user:password@a.blob.core.windows.net/file",
                    "https://a.blob.core.windows.net:444/file", "file:///etc/passwd",
                    "https://a.blob.core.windows.net.attacker.invalid/file",
                    "https://a.blob.core.windows.net/file#fragment"):
            opener = self.opener(redirect=self.redirect(url))
            with self.subTest(url=url):
                with self.assertRaises(ValueError):
                    self.download(opener)
                self.assertEqual(len(opener.requests), 2)

    def test_archive_transfer_size_digest_encoding_and_truncation_rejected(self):
        for response in (
            Response(self.zip[:-1], {}),
            Response(self.zip[:-1], {"Content-Length": str(len(self.zip))}),
            Response(self.zip + b"x", {}),
            Response(b"x" * (artifact_io.MAX_ARCHIVE_BYTES + 1), {}),
            Response(self.zip, {"Content-Encoding": "gzip"}),
            Response(self.zip, {"Content-Length": "invalid"}),
            Response(self.zip, status=206),
            Response(b"x" * len(self.zip)),
        ):
            with self.subTest(headers=response.headers):
                with self.assertRaises(ValueError):
                    self.download(self.opener(response=response))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_fixed_destination_cannot_overwrite_existing_file(self):
        destination = self.directory / artifact_io.ARCHIVE_FILENAME
        destination.write_bytes(b"existing sentinel")
        with self.assertRaises(FileExistsError):
            self.download(self.opener())
        self.assertEqual(destination.read_bytes(), b"existing sentinel")

    def test_deadline_enforced_before_network_and_during_stream(self):
        with self.assertRaises(ValueError):
            artifact_io._request(self.opener(), self.storage, time.monotonic() - 1)
        with self.assertRaises(ValueError):
            artifact_io._read_response(Response(self.zip), artifact_io.MAX_ARCHIVE_BYTES, time.monotonic() - 1)


if __name__ == "__main__":
    unittest.main()
