# David Shih Chun Liu - Hub

Personal hub and portfolio landing page for David Shih Chun Liu. Serves as a
root navigation page with links to projects, demos, and resources.

## Features

- Responsive hero layout with nav
- Dark / light theme toggle
- Ambient audio controls
- Links to key projects and demos
- Dedicated Scout, Copilot Cowork, and Copilot CLI Build Ledger page backed by `data/builds.json`

## Build Ledger

Open `build-ledger.html` for the full artifact roster with table sorting and
filters (type, customer, platform, and audience). The roster is stored in
`data/builds.json` and is refreshed from verified Scout, Copilot Cowork, and
local Copilot archive sources.

## Tech Stack

- HTML5 / CSS3 / Vanilla JavaScript
- Static single-page app

## Run Locally

```bash
python -m http.server 8000
```

Then open http://localhost:8000.

## Podcast refresh

The daily workflow retains its two UTC slots (`5 12,13 * * *`), manual trigger,
and `personal-hub-refresh` repository dispatch. Only main-branch runs publish.
The second refresh is a no-op when episodes have not changed.

The extractor has read-only repository access, no retained checkout credentials,
and a hash-locked yt-dlp wheel. A separate fresh runner checks out current main
and uses the GitHub REST API to download this run's uniquely named, non-expired
artifact into a fixed ZIP filename. Authenticated API requests never follow
redirects; the signed storage download receives no GitHub token. Listing, transfer
size, timeout, repository/run identity, and available digest checks fail closed.

**No archive member is ever extracted to disk.** Trusted standard-library code
permits exactly one regular root-level `metadata.json` member and reads its bytes
in memory. It rejects paths, duplicate members, symlinks, encryption, unsupported
compression, and malformed or oversized archives. Both declared and actual
decompressed lengths and the CRC are checked before JSON validation.
It can update only `latestUrl`, `latestTitle`, and `latestDate`; URLs are built
from validated YouTube video IDs. Titles are escaped for the inline script and
rendered as DOM text, not HTML. Failed playlist reads omit their episode record
and preserve the current card; malformed artifacts or changed playlist sources
fail publication. Limits are 32 cards, 512 characters per title, 128 KiB of JSON,
and 256 KiB for the downloaded ZIP.

For a local refresh (Python 3.12):

```bash
python -m pip install --require-hashes --only-binary=:all: -r scripts/requirements-podcasts.txt
python scripts/refresh_podcasts.py
```

To inspect the same data boundary locally:

```bash
python scripts/refresh_podcasts.py --output podcast-output/metadata.json
python -I -S scripts/publish_podcasts.py --metadata-dir podcast-output --check
# Omit --check to apply the validated metadata.
python -m unittest discover -s scripts/tests -v
```

The local `--metadata-dir` mode reads the extractor's plain JSON output directly;
do not unpack downloaded archives for it. The workflow exclusively uses
`--metadata-archive`, which validates the ZIP without extracting any members.
The publisher has `actions: read` solely for this run-scoped REST download.

Dependency updates require reviewing the release and replacing both version and
official wheel SHA-256 in `scripts/requirements-podcasts.txt`; do not restore an
unbounded upgrade. Official workflow actions are also pinned to immutable commits.

Publication still commits only `index.html` directly to main using `GITHUB_TOKEN`
and a non-force push. If main advances after checkout, the push fails instead of
overwriting it; rerun the workflow. Hosting/deployment triggers are unchanged.

No repository settings are changed by this fix. Main can disallow force pushes
and deletion without blocking the daily publisher. Required pull requests,
required checks that do not run on the bot's new commit, or restricted push actors
can block this direct `GITHUB_TOKEN` writer: adopting those protections needs a
separately approved GitHub App with narrowly scoped access/bypass, or a PR-based
publisher with the necessary checks. Do not grant broad bypass just to retain
the schedule.
