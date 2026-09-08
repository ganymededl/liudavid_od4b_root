#!/usr/bin/env python3
"""Validate data-only podcast metadata against the current trusted index.html."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Support python -I -S: only this trusted checkout supplies application modules,
# never the artifact directory, PYTHONPATH, user site, or installed packages.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from podcast_metadata import INDEX_PATH, apply_metadata, read_metadata
from podcast_artifact import read_metadata_archive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--metadata-dir", type=Path, help="Local JSON data directory (not an extracted archive)")
    source.add_argument("--metadata-archive", type=Path, help="Downloaded ZIP; members are never extracted")
    parser.add_argument("--check", action="store_true", help="Validate without writing index.html")
    args = parser.parse_args()
    try:
        metadata = (read_metadata_archive(args.metadata_archive) if args.metadata_archive else
                    read_metadata(args.metadata_dir))
        original = INDEX_PATH.read_text(encoding="utf-8")
        updated, changed = apply_metadata(original, metadata)
        if changed and not args.check:
            INDEX_PATH.write_text(updated, encoding="utf-8", newline="\n")
    except (OSError, ValueError) as exc:
        # Do not echo attacker-controlled strings as GitHub workflow commands.
        message = str(exc).replace("\r", " ").replace("\n", " ")
        print(f"Podcast publication rejected: {message}", file=sys.stderr)
        return 1
    print(f"Validated {changed} podcast card changes." if args.check else
          f"Updated {changed} podcast cards." if changed else "No podcast card changes were needed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
