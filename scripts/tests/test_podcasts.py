from __future__ import annotations

import copy
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import types
import unittest
import uuid
from contextlib import redirect_stderr, redirect_stdout
from html.parser import HTMLParser
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import podcast_metadata as metadata
import publish_podcasts as publisher
import refresh_podcasts as extractor


def fixture() -> str:
    cards = []
    for name, source in (
        ("One", "https://www.youtube.com/playlist?list=PLone"),
        ("Two", "https://youtube.com/playlist?list=PLtwo"),
        ("Curated", ""),
    ):
        cards.append(
            '    {\n'
            f'      name: "{name}",\n'
            f'      source: "{source}",\n'
            '      latestUrl: "https://www.youtube.com/watch?v=oldvideo123",\n'
            '      latestTitle: "Old title",\n'
            '      latestDate: "Latest",\n'
            '      host: "Trusted host",\n'
            '      img: "trusted.png"\n'
            '    }'
        )
    return ('<!DOCTYPE html>\n<script>\nconst CONFIG = {\n'
            '  podcasts: [\n' + ",\n".join(cards) + '\n  ],\n'
            '  otherSetting: "Do not change"\n};\n</script>\n</html>\n')


def artifact(original: str, title: str = 'Quotes " & ampersands — 中文 🎙') -> dict:
    podcasts = metadata.configured_podcasts(original)
    return {
        "schema_version": 1,
        "sources": [podcast.source_id for podcast in podcasts],
        "episodes": [{"source_id": podcasts[0].source_id, "title": title,
                      "video_id": "newvideo123", "display_date": "Sep 8, 2026"}],
    }


class PodcastTests(unittest.TestCase):
    def setUp(self):
        self.original = fixture()
        self.artifact = artifact(self.original)
        self.directory = SCRIPTS / "tests" / f".scratch-{uuid.uuid4().hex}"
        self.directory.mkdir()

    def tearDown(self):
        shutil.rmtree(self.directory)

    def assert_rejected(self, value):
        with self.assertRaises(ValueError):
            metadata.apply_metadata(self.original, value)

    def test_normal_apply_changes_only_approved_fields_and_is_idempotent(self):
        updated, count = metadata.apply_metadata(self.original, self.artifact)
        self.assertEqual(count, 1)
        changed_lines = [(old, new) for old, new in zip(self.original.split("\n"), updated.split("\n"))
                         if old != new]
        self.assertEqual(len(changed_lines), 3)
        for (old, new), field in zip(changed_lines, metadata.LATEST_FIELDS):
            self.assertTrue(old.strip().startswith(field + ":"))
            self.assertTrue(new.strip().startswith(field + ":"))
        self.assertEqual(metadata.apply_metadata(updated, self.artifact), (updated, 0))
        podcasts = metadata.configured_podcasts(updated)
        block = updated.split("\n")[podcasts[0].start:podcasts[0].end]
        self.assertEqual(metadata.field(block, "latestTitle"), self.artifact["episodes"][0]["title"])
        self.assertEqual(metadata.field(block, "latestUrl"), "https://www.youtube.com/watch?v=newvideo123")
        with self.assertRaises(ValueError):
            metadata.replace_field(block, "source", "https://attacker.invalid/")

    def test_no_episodes_preserves_entire_page(self):
        self.artifact["episodes"] = []
        self.assertEqual(metadata.apply_metadata(self.original, self.artifact), (self.original, 0))

    def test_current_page_with_identical_episodes_is_unchanged(self):
        original = metadata.INDEX_PATH.read_text(encoding="utf-8")
        podcasts = metadata.configured_podcasts(original)
        records = []
        for podcast in podcasts:
            block = original.split("\n")[podcast.start:podcast.end]
            records.append({
                "source_id": podcast.source_id,
                "title": metadata.field(block, "latestTitle"),
                "video_id": metadata.field(block, "latestUrl").removeprefix(
                    "https://www.youtube.com/watch?v="),
                "display_date": metadata.field(block, "latestDate"),
            })
        value = {"schema_version": 1, "sources": [podcast.source_id for podcast in podcasts],
                 "episodes": records}
        self.assertEqual(metadata.apply_metadata(original, value), (original, 0))

    def test_extraction_failed_playlist_and_curated_card_preserved(self):
        episodes = [metadata.Episode("New", "newvideo123", "Latest"),
                    extractor.PlaylistReadError("Unavailable\n::error::not a command")]
        with mock.patch.object(extractor, "newest_episode", side_effect=episodes) as reader:
            with redirect_stderr(io.StringIO()) as warnings:
                result = extractor.collect_metadata(metadata.configured_podcasts(self.original))
        self.assertEqual(reader.call_count, 2)
        self.assertEqual(len(result["sources"]), 2)
        self.assertEqual(len(result["episodes"]), 1)
        self.assertIn("%0A::error::", warnings.getvalue())
        self.assertEqual(len(warnings.getvalue().splitlines()), 1)
        updated, count = metadata.apply_metadata(self.original, result)
        self.assertEqual(count, 1)
        original_blocks = metadata.podcast_blocks(self.original.split("\n"))
        updated_blocks = metadata.podcast_blocks(updated.split("\n"))
        for index in (1, 2):
            start, end = original_blocks[index]
            new_start, new_end = updated_blocks[index]
            self.assertEqual(self.original.split("\n")[start:end], updated.split("\n")[new_start:new_end])

    def test_unexpected_extractor_failure_is_fatal(self):
        with mock.patch.object(extractor, "newest_episode", side_effect=TypeError("bug")):
            with self.assertRaises(TypeError):
                extractor.collect_metadata(metadata.configured_podcasts(self.original))

    def test_first_playlist_entry_and_downloader_options(self):
        source = metadata.configured_podcasts(self.original)[0].source
        downloader = mock.MagicMock()
        downloader.__enter__.return_value = downloader
        downloader.extract_info.return_value = {"entries": [
            {"id": "newvideo123", "title": " New title ", "upload_date": "20260908"},
            {"id": "oldvideo123", "title": "Not first", "upload_date": "20260909"},
        ]}
        constructor = mock.Mock(return_value=downloader)
        fake_utils = types.SimpleNamespace(DownloadError=type("DownloadError", (Exception,), {}))
        with mock.patch.dict(sys.modules, {"yt_dlp": types.SimpleNamespace(YoutubeDL=constructor),
                                          "yt_dlp.utils": fake_utils}):
            episode = extractor.newest_episode(source)
        self.assertEqual(episode, metadata.Episode("New title", "newvideo123", "Sep 8, 2026"))
        downloader.extract_info.assert_called_once_with(source, download=False)
        options = constructor.call_args.args[0]
        self.assertEqual(options["playlist_items"], "1")
        self.assertEqual(options["extract_flat"], "in_playlist")
        self.assertTrue(options["skip_download"])

    def test_missing_or_invalid_first_entry_is_playlist_failure(self):
        downloader = mock.MagicMock()
        downloader.__enter__.return_value = downloader
        fake_utils = types.SimpleNamespace(DownloadError=type("DownloadError", (Exception,), {}))
        source = metadata.configured_podcasts(self.original)[0].source
        for playlist in (None, {}, {"entries": []},
                         {"entries": [{"id": "bad", "title": "Bad"}]},
                         {"entries": [{"id": "newvideo123", "title": ""}]},
                         {"entries": [{"id": "newvideo123", "title": "T", "upload_date": "20260230"}]}):
            with self.subTest(playlist=playlist):
                downloader.extract_info.return_value = playlist
                with mock.patch.dict(sys.modules, {"yt_dlp": types.SimpleNamespace(
                        YoutubeDL=mock.Mock(return_value=downloader)), "yt_dlp.utils": fake_utils}):
                    with self.assertRaises(extractor.PlaylistReadError):
                        extractor.newest_episode(source)

    def test_dates_from_entries(self):
        for entry, expected in (
            ({}, "Latest"),
            ({"upload_date": "unknown"}, "Latest"),
            ({"upload_date": "20240229"}, "Feb 29, 2024"),
            ({"timestamp": 1709164800}, "Feb 29, 2024"),
            ({"release_timestamp": 1709164800}, "Feb 29, 2024"),
        ):
            with self.subTest(entry=entry):
                self.assertEqual(extractor.date_from_entry(entry), expected)

    def test_top_level_schema_and_types(self):
        for value in (None, [], True, "text", 1):
            with self.subTest(value=value):
                self.assert_rejected(value)
        for key, value in (
            ("schema_version", True), ("schema_version", 1.0), ("schema_version", 2),
            ("schema_version", "1"), ("sources", None), ("sources", {}),
            ("sources", [True]), ("sources", ["not-a-source"]), ("episodes", {}),
            ("episodes", [None]), ("episodes", ["record"]),
            ("episodes", self.artifact["episodes"] * (metadata.MAX_SOURCES + 1)),
            ("sources", self.artifact["sources"] * (metadata.MAX_SOURCES + 1)),
        ):
            with self.subTest(key=key, value=value):
                bad = copy.deepcopy(self.artifact)
                bad[key] = value
                self.assert_rejected(bad)
        for key in self.artifact:
            bad = copy.deepcopy(self.artifact)
            del bad[key]
            self.assert_rejected(bad)
        bad = copy.deepcopy(self.artifact)
        bad["index_html"] = "<script>arbitrary content</script>"
        self.assert_rejected(bad)

    def test_record_keys_types_and_bounds(self):
        for key, values in {
            "source_id": [True, [], None, "0" * 64],
            "title": [None, 12, True, [], "", " \t", "\x00", "\ud800",
                      "x" * (metadata.MAX_TITLE_LENGTH + 1)],
            "video_id": [None, 123, True, "short", "longvideo123", "newvideo12!",
                         "newvideo123\n", "https://evil.invalid/", '"><img src=x>'],
            "display_date": [None, True, 20260908, "Curated", "September 8, 2026",
                             "Sep 08, 2026", "Feb 29, 2025", "Feb 30, 2024",
                             "Dec 32, 2026", "Jan 0, 2026", "Jan 1, 0000",
                             "Latest\n", "<img src=x>", "2026-09-08"],
        }.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    bad = copy.deepcopy(self.artifact)
                    bad["episodes"][0][key] = value
                    self.assert_rejected(bad)
        for key in self.artifact["episodes"][0]:
            bad = copy.deepcopy(self.artifact)
            del bad["episodes"][0][key]
            self.assert_rejected(bad)
        for key in ("latestUrl", "source", "name", "code"):
            bad = copy.deepcopy(self.artifact)
            bad["episodes"][0][key] = "attacker controlled"
            self.assert_rejected(bad)

    def test_duplicates_unknown_sources_and_changed_config(self):
        for field in ("sources", "episodes"):
            bad = copy.deepcopy(self.artifact)
            bad[field].append(bad[field][0])
            self.assert_rejected(bad)
        bad = copy.deepcopy(self.artifact)
        bad["sources"].append("0" * 64)
        self.assert_rejected(bad)
        for changed in (
            self.original.replace("list=PLone", "list=PLdifferent"),
            self.original.replace('source: ""', 'source: "https://youtube.com/playlist?list=PLnew"'),
            self.original.replace('source: "https://www.youtube.com/playlist?list=PLone"', 'source: ""'),
        ):
            with self.subTest(changed=changed):
                with self.assertRaises(ValueError):
                    metadata.apply_metadata(changed, self.artifact)

    def test_current_configuration_other_edits_are_preserved(self):
        current = self.original.replace('Do not change', 'Changed on main while extracting')
        current = current.replace('Trusted host', 'Current trusted host')
        updated, _ = metadata.apply_metadata(current, self.artifact)
        self.assertIn('Changed on main while extracting', updated)
        self.assertIn('Current trusted host', updated)

    def test_malformed_json_duplicate_keys_encoding_constants_and_size(self):
        for raw in (b"", b"not json", b'{"schema_version":1,}', b"\xff",
                    b'{"schema_version":1,"schema_version":1}', b'{"nested":{"a":1,"a":2}}',
                    b'{"value":NaN}', b'{"value":Infinity}', b'{"value":-Infinity}',
                    b"[" * 2000 + b"]" * 2000, b" " * (metadata.MAX_ARTIFACT_BYTES + 1)):
            with self.subTest(raw=raw[:80]):
                with self.assertRaises(ValueError):
                    metadata.apply_metadata(self.original, metadata.decode_metadata(raw))

    def test_data_directory_requires_one_bounded_regular_file(self):
        with self.assertRaises(ValueError):
            metadata.read_metadata(self.directory)
        path = self.directory / metadata.ARTIFACT_FILENAME
        path.write_text(json.dumps(self.artifact), encoding="utf-8")
        self.assertEqual(metadata.read_metadata(self.directory), self.artifact)
        extra = self.directory / "unexpected.py"
        extra.write_text("raise RuntimeError('must not run')", encoding="utf-8")
        with self.assertRaises(ValueError):
            metadata.read_metadata(self.directory)
        extra.unlink()
        path.write_bytes(b"x" * (metadata.MAX_ARTIFACT_BYTES + 1))
        with self.assertRaises(ValueError):
            metadata.read_metadata(self.directory)
        path.unlink()
        path.mkdir()
        with self.assertRaises(ValueError):
            metadata.read_metadata(self.directory)

    def test_symlink_artifact_rejected_where_supported(self):
        target = self.directory / "target.json"
        target.write_text("{}", encoding="utf-8")
        data = self.directory / "data"
        data.mkdir()
        try:
            (data / metadata.ARTIFACT_FILENAME).symlink_to(target)
        except OSError:
            self.skipTest("Symlink creation is not available on this host")
        with self.assertRaises(ValueError):
            metadata.read_metadata(data)

    def test_nonregular_artifact_rejected_without_following_it(self):
        path = self.directory / metadata.ARTIFACT_FILENAME
        path.write_text(json.dumps(self.artifact), encoding="utf-8")
        for mode in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFSOCK):
            with self.subTest(mode=mode):
                with mock.patch.object(Path, "lstat", return_value=types.SimpleNamespace(
                        st_mode=mode, st_size=100)):
                    with self.assertRaises(ValueError):
                        metadata.read_metadata(self.directory)

    def test_extractor_output_only_and_default_local_refresh(self):
        index = self.directory / "index.html"
        index.write_text(self.original, encoding="utf-8")
        output = self.directory / "data" / metadata.ARTIFACT_FILENAME
        with mock.patch.object(extractor, "INDEX_PATH", index):
            with mock.patch.object(extractor, "collect_metadata", return_value=self.artifact):
                with mock.patch.object(sys, "argv", ["refresh_podcasts.py", "--output", str(output)]):
                    with redirect_stdout(io.StringIO()):
                        self.assertEqual(extractor.main(), 0)
                self.assertEqual(index.read_text(encoding="utf-8"), self.original)
                self.assertEqual(metadata.read_metadata(output.parent), self.artifact)
                with mock.patch.object(sys, "argv", ["refresh_podcasts.py"]):
                    with redirect_stdout(io.StringIO()):
                        self.assertEqual(extractor.main(), 0)
                self.assertEqual(index.read_text(encoding="utf-8"),
                                 metadata.apply_metadata(self.original, self.artifact)[0])

    def test_publisher_isolated_from_installed_packages_and_artifact_code(self):
        poison = self.directory / "poison"
        poison.mkdir()
        for name in ("yt_dlp.py", "podcast_metadata.py", "sitecustomize.py"):
            (poison / name).write_text("raise RuntimeError('untrusted import executed')", encoding="utf-8")
        environment = dict(os.environ, PYTHONPATH=str(poison))
        clean = self.directory / "data"
        clean.mkdir()
        (clean / metadata.ARTIFACT_FILENAME).write_text(json.dumps(self.artifact), encoding="utf-8")
        trusted = self.directory / "trusted"
        trusted_scripts = trusted / "scripts"
        trusted_scripts.mkdir(parents=True)
        for name in ("publish_podcasts.py", "podcast_metadata.py", "podcast_artifact.py"):
            shutil.copyfile(SCRIPTS / name, trusted_scripts / name)
        index = trusted / "index.html"
        index.write_text(self.original, encoding="utf-8")
        command = [sys.executable, "-I", "-S", "-B", str(trusted_scripts / "publish_podcasts.py"),
                   "--metadata-dir", str(clean)]
        for arguments, expected in ((["--check"], "Validated 1"), ([], "Updated 1"),
                                    ([], "No podcast card changes")):
            result = subprocess.run(command + arguments, cwd=poison, env=environment,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(expected, result.stdout)
            self.assertEqual(index.read_text(encoding="utf-8"), self.original if arguments else
                             metadata.apply_metadata(self.original, self.artifact)[0])

    def test_publisher_validation_failure_leaves_file_unchanged(self):
        index = self.directory / "index.html"
        index.write_text(self.original, encoding="utf-8")
        data = self.directory / "data"
        data.mkdir()
        bad = copy.deepcopy(self.artifact)
        bad["episodes"].append({"source_id": bad["sources"][1], "title": "Bad",
                                "video_id": "invalid", "display_date": "Latest"})
        (data / metadata.ARTIFACT_FILENAME).write_text(json.dumps(bad), encoding="utf-8")
        with mock.patch.object(publisher, "INDEX_PATH", index):
            with mock.patch.object(sys, "argv", ["publish_podcasts.py", "--metadata-dir", str(data)]):
                with redirect_stderr(io.StringIO()) as errors:
                    self.assertEqual(publisher.main(), 1)
        self.assertIn("rejected", errors.getvalue())
        self.assertEqual(index.read_text(encoding="utf-8"), self.original)

    def test_invalid_trusted_config_fails_closed(self):
        for bad in (
            self.original.replace("const CONFIG", "const OTHER"),
            self.original.replace("  ],", ""),
            self.original.replace('name: "One",', 'name: 123,'),
            self.original.replace("https://youtube.com/playlist?list=PLtwo",
                                  "https://www.youtube.com/playlist?list=PLone"),
            self.original.replace("https://youtube.com/playlist?list=PLtwo",
                                  "https://youtube.com.evil.invalid/playlist?list=PLtwo"),
        ):
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    metadata.configured_podcasts(bad)

    def test_adversarial_titles_round_trip_without_new_html_elements(self):
        class Tags(HTMLParser):
            def __init__(self):
                super().__init__()
                self.tags = []

            def handle_starttag(self, tag, attrs):
                self.tags.append(tag)

        titles = (
            '</script><script>globalThis.pwned=true</script><img src=x onerror="evil()">',
            '</ScRiPt><!-- &amp; "quotes" \'single\' \\ ${globalThis.pwned=true}',
            'Unicode 中文 🎙 café \u2028 \u2029 & < >\nnew line\rreturn\ttab',
        )
        baseline = Tags()
        baseline.feed(self.original)
        for title in titles:
            with self.subTest(title=title):
                literal = metadata.js_string(title)
                self.assertEqual(json.loads(literal), title)
                self.assertNotIn("<", literal)
                self.assertNotIn(">", literal)
                self.assertNotIn("&", literal)
                updated, _ = metadata.apply_metadata(self.original, artifact(self.original, title))
                tags = Tags()
                tags.feed(updated)
                self.assertEqual(tags.tags, baseline.tags)
                self.assertEqual(metadata.apply_metadata(updated, artifact(self.original, title)), (updated, 0))

    @unittest.skipUnless(shutil.which("node"), "Node is not available")
    def test_actual_inline_javascript_and_render_use_inert_dom_text(self):
        original = metadata.INDEX_PATH.read_text(encoding="utf-8")
        title = '</script><img src=x onerror="globalThis.pwned=true"> &amp; "quoted" 中文 🎙 \u2028 \u2029'
        data = artifact(original, title)
        updated, _ = metadata.apply_metadata(original, data)
        script = updated.split("<script>", 1)[1].split("</script>", 1)[0]
        config = script[script.index("const CONFIG = {"):script.index("\n};") + len("\n};")]
        render = script[script.index("// ── RENDER: podcasts"):script.index("// ── SLIDES")]
        program = r"""
const fs = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const input = JSON.parse(fs.readFileSync(0, "utf8"));
new vm.Script(input.script);
const cards = [];
const document = {
  getElementById(id) {
    assert.equal(id, "podcasts");
    return {appendChild(card) { cards.push(card); }};
  },
  createElement(tag) {
    assert.equal(tag, "div");
    const nodes = {};
    return {
      set innerHTML(value) {
        assert.ok(!value.includes(input.title));
        assert.ok(!value.includes("globalThis.pwned"));
        assert.ok(value.includes('<span class="pod-latest-title"></span>'));
        assert.ok(value.includes('<span class="pod-date"></span>'));
      },
      querySelector(selector) {
        return nodes[selector] ||= {};
      }
    };
  }
};
const context = {document, ICONS: {play: "", arrow: ""}};
vm.runInNewContext(input.config + "\n" + input.render, context);
assert.equal(context.pwned, undefined);
assert.equal(cards[0].querySelector(".pod-latest-title").textContent, input.title);
assert.equal(cards[0].querySelector(".pod-date").textContent, "Sep 8, 2026");
assert.equal(cards[0].querySelector(".pod-latest").href, "https://www.youtube.com/watch?v=newvideo123");
console.log("Actual inline script parses; podcast renderer uses inert text and validated URL.");
"""
        result = subprocess.run(
            ["node", "-e", program], input=json.dumps(
                {"title": title, "script": script, "config": config, "render": render}),
            capture_output=True, text=True, encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
