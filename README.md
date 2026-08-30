# David Shih Chun Liu - Hub

Personal hub and portfolio landing page for David Shih Chun Liu. Serves as a
root navigation page with links to projects, demos, and resources.

## Features

- Responsive hero layout with nav
- Dark / light theme toggle
- Ambient audio controls
- Links to key projects and demos
- Dedicated Scout and Copilot Build Ledger page backed by `data/builds.json`

## Build Ledger

Open `build-ledger.html` for the full artifact roster with table sorting and
filters (type, customer, platform, and audience). The public roster is stored
in `data/builds.json`.

## Tech Stack

- HTML5 / CSS3 / Vanilla JavaScript
- Static single-page app

## Run Locally

```bash
python -m http.server 8000
```

Then open http://localhost:8000.
