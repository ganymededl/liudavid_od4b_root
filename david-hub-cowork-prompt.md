# David Shih Chun Liu — Personal Hub Page
## Cowork Build Prompt

---

Build a self-contained personal hub page as a single HTML file called `index.html`.
This file will be uploaded to OneDrive for Business (OD4B) at:
`Documents/Hub/index.html`
and opened directly in a browser by the owner and teammates (all signed into
Microsoft 365). Zero external dependencies except the Pexels API (photo
backgrounds) and the public Radio Browser API (focus music). No frameworks,
no build step, no backend.

---

## ═══ CONFIG BLOCK ═══

At the very top of the `<script>` section place this exact CONFIG object,
clearly delimited. All customization lives here and nowhere else.

```javascript
// ╔══════════════════════════════════════════════════════════════╗
// ║  CONFIG — edit this block only, touch nothing else          ║
// ╚══════════════════════════════════════════════════════════════╝
const CONFIG = {

  owner: {
    name:     "David Shih Chun Liu",
    nameDisplay: {
      first:  "David",          // rendered light 300 weight
      middle: "Shih Chun",      // rendered gradient accent bold
      last:   "Liu"             // rendered light 300 weight
    },
    role: "Microsoft SLED · Copilot Customer Success Architect"
  },

  // ── LIBRARY CARDS ────────────────────────────────────────────
  // Replace each href with your real OD4B shared folder URL
  // after sharing the folder with your team (view-only)
  libraries: [
    {
      name:  "Games",
      desc:  "Browser games, Copilot Arcade, interactive tools",
      href:  "YOUR_OD4B_URL/Documents/Cowork/games_public",
      icon:  "games",
      color: ["#00d9ff", "#0099cc"]
    },
    {
      name:  "Prompt Engineering",
      desc:  "Agent specs, prompt libraries, templates",
      href:  "YOUR_OD4B_URL/Documents/Cowork/prompts_public",
      icon:  "star",
      color: ["#7b61ff", "#a855f7"]
    },
    {
      name:  "Demos & Artifacts",
      desc:  "Cowork outputs, dashboards, HTML tools",
      href:  "YOUR_OD4B_URL/Documents/Cowork/demos_public",
      icon:  "list",
      color: ["#00ffa3", "#00b377"]
    },
    {
      name:  "Scripts & Automation",
      desc:  "PowerShell, Power Automate, PnP flows",
      href:  "YOUR_OD4B_URL/Documents/Cowork/scripts_public",
      icon:  "code",
      color: ["#ff6b35", "#f59e0b"]
    }
  ],

  // ── TRAVEL PHOTO BACKGROUNDS ─────────────────────────────────
  // City names are used as Pexels search keywords automatically.
  // No photo URLs to manage — Pexels fetches fresh stunning travel
  // photography on every page load. Add / rename cities freely.
  pexels: {
    apiKey: "8NggS47fBRwsewIjcK8geNLsw6mgKhfbmrwnBn33Y92JFbVmPy5Vqoqj",
    photosPerCity: 3,       // how many photos to fetch per city
    rotateSecs:   10,       // seconds between photo transitions
    kenBurnsSecs:  9        // duration of slow zoom on each photo
  },
  cities: [
    "Jakarta Indonesia",
    "London Paris",
    "Northern Spain",
    "Siena Tuscany Italy",
    "Salamanca Spain"
  ],

  // ── RECENT ADDITIONS ─────────────────────────────────────────
  // Update manually as you publish new content
  recent: [
    { title: "Copilot Arcade — 3 games",       date: "Apr 2026", lib: "Games" },
    { title: "CompStat agent system prompt",    date: "Apr 2026", lib: "Prompt Engineering" },
    { title: "EXO bulk MaxReceiveSize scripts", date: "Apr 2026", lib: "Scripts & Automation" }
  ],

  // ── RADIO DEFAULTS ────────────────────────────────────────────
  radio: {
    defaultGenre:  "focus",  // focus|lofi|ambient|chillout|jazz|classical|electronic|taylor
    defaultVolume: 70        // 0–100
  }
};
// ╔══════════════════════════════════════════════════════════════╗
// ║  END CONFIG                                                  ║
// ╚══════════════════════════════════════════════════════════════╝
```

---

## ═══ VISUAL DESIGN ═══

### Typography
- Font: **Space Grotesk** loaded from Google Fonts
  `https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700`
- Owner name split treatment:
  - "David" → `font-weight: 300`, `color: rgba(244,244,248,0.65)`
  - "Shih Chun" → `font-weight: 700`, CSS gradient text:
    `background: linear-gradient(90deg, #00d9ff, #00ffa3);
     -webkit-background-clip: text; -webkit-text-fill-color: transparent`
  - "Liu" → `font-weight: 300`, `color: rgba(244,244,248,0.65)`
- Section labels: `8px`, `font-weight: 700`, `letter-spacing: 0.12em`,
  `text-transform: uppercase`, `color: rgba(244,244,248,0.28)`
- Card names: `11px font-weight: 700`, `letter-spacing: -0.1px`
- All body: Space Grotesk, sentence case always

### Color palette — dark mode default
```
--bg:       #060609
--bg2:      #0d0d14
--c1:       #00d9ff   (cyan accent)
--c2:       #00ffa3   (emerald accent)
--c3:       #7b61ff   (purple accent)
--t1:       #f4f4f8
--t2:       rgba(244,244,248,0.50)
--t3:       rgba(244,244,248,0.25)
--glass:    rgba(6,6,9,0.68)
--card:     rgba(255,255,255,0.04)
--cardh:    rgba(255,255,255,0.08)
--border:   rgba(255,255,255,0.07)
--border2:  rgba(0,217,255,0.22)
```

### Light mode (toggled via data-light attribute on root div)
```
--bg:       #f0f2f8
--t1:       #0a0a14
--t2:       rgba(10,10,20,0.55)
--glass:    rgba(240,242,248,0.85)
--card:     rgba(255,255,255,0.78)
--border:   rgba(0,0,0,0.08)
```
Theme persisted to `localStorage` key `"dsc-theme"`.

### Scanline texture overlay
Full-viewport `::before` pseudo-element, `z-index: 3`, `pointer-events: none`:
```css
background: repeating-linear-gradient(
  0deg, transparent, transparent 2px,
  rgba(0,0,0,0.03) 2px, rgba(0,0,0,0.03) 4px
);
```

---

## ═══ LAYOUT STRUCTURE ═══

```
┌─────────────────────────────────────────────┐
│  NAV: logo+name  |  music widget  | theme   │  ← compact, glassmorphism
├─────────────────────────────────────────────┤
│                                             │
│  HERO: city pill · name · rule · tagline    │  ← over travel photo BG
│        skill pills                          │
│                                             │
├─────────────────────────────────────────────┤
│  LIBRARIES GRID  (2×2 auto-fit, min 132px)  │
├─────────────────────────────────────────────┤
│  RECENT ADDITIONS  (auto-fit, min 165px)    │
├─────────────────────────────────────────────┤
│  SLIDE DOTS  (city indicator)               │
└─────────────────────────────────────────────┘
```

---

## ═══ TRAVEL PHOTO SLIDESHOW ═══

### Pexels fetch strategy
On page load, for each city in `CONFIG.cities`:
```javascript
fetch(`https://api.pexels.com/v1/search?query=${encodeURIComponent(city)
  }&orientation=landscape&per_page=${CONFIG.pexels.photosPerCity}&page=1`, {
  headers: { Authorization: CONFIG.pexels.apiKey }
})
```
- Collect all returned photo URLs (`src.landscape` or `src.original`)
- Build a flat array: `[ {city, url}, {city, url}, ... ]`
- Shuffle the full array
- Rotate through every `CONFIG.pexels.rotateSecs` seconds

### Ken Burns effect
Each active slide gets:
```css
animation: kenBurns CONFIG.pexels.kenBurnsSecs s ease-out forwards;
@keyframes kenBurns { from { transform: scale(1) } to { transform: scale(1.06) } }
```
Animation resets (force reflow) on each slide transition so every photo
gets the full zoom regardless of order.

### Vignette overlay (above slides, below content)
```css
background: linear-gradient(180deg,
  rgba(6,6,9,0.75) 0%,
  rgba(6,6,9,0.05) 35%,
  rgba(6,6,9,0.05) 58%,
  rgba(6,6,9,0.88) 100%
);
```

### City pill in hero
- Updates with city name on each slide transition
- Re-triggers a letter-spacing expand animation (`0.20em → 0.10em`) on change
- Styled: `background: rgba(0,217,255,0.07)`, `border: 0.5px solid rgba(0,217,255,0.18)`,
  `color: #00d9ff`, `font-size: 9px`, `font-weight: 600`, `letter-spacing: 0.10em`,
  `text-transform: uppercase`, `border-radius: 4px`, `padding: 4px 10px`

### Fallback
If Pexels API is unreachable (network error, rate limit), fall back silently
to a curated array of 5 hardcoded Unsplash photo URLs (permanent photo IDs,
not source.unsplash.com) covering the same city themes. Page never shows a
broken background.

### Slide dots
Row of dot indicators at page bottom. Active dot: wider pill shape
(`width: 16px`, `border-radius: 2px`, `background: #00d9ff`,
`box-shadow: 0 0 6px rgba(0,217,255,0.4)`). Clickable to jump to city.

---

## ═══ NAV BAR ═══

Compact single-row. `padding: 14px 24px`.
`background: var(--glass)`, `backdrop-filter: blur(20px)`,
`border-bottom: 0.5px solid var(--border)`.

### Logo (left)
- 28×28px rounded rect (`border-radius: 8px`),
  `background: linear-gradient(135deg, #00d9ff, #00ffa3)`
- Icon inside: stacked-layers SVG (3 horizontal lines offset),
  `stroke: #000`, `stroke-width: 1.8`, no fill
- Name `12px font-weight: 600` + role subtitle `9px color: var(--t2)`

### Right side controls (in order left→right)
1. **Music widget pill** (see RADIO section below)
2. **Theme toggle** — circular icon button `28×28px border-radius: 50%`,
   moon icon in dark mode, sun icon in light mode

---

## ═══ MUSIC WIDGET ═══

Floating pill in nav top-right. This is the "cool" centerpiece.

### Container
```css
background: rgba(13,13,20,0.82);
backdrop-filter: blur(24px);
border: 0.5px solid rgba(0,217,255,0.22);
border-radius: 40px;
padding: 5px 14px 5px 5px;
box-shadow: 0 0 0 1px rgba(0,217,255,0.06),
            0 2px 20px rgba(0,217,255,0.08);
```

### Play/Pause button
- 28×28px circle, `background: linear-gradient(135deg, #00d9ff, #00ffa3)`
- Icon: play triangle in dark mode (▶), pause bars when playing
- Hover: `transform: scale(1.08)`, `box-shadow: 0 0 12px rgba(0,217,255,0.35)`

### Audio visualizer bars (replaces vinyl disc)
3 vertical bars side by side, `width: 2.5px`, `border-radius: 2px`,
`background: linear-gradient(180deg, #00d9ff, #00ffa3)`.
When **playing**: each bar animates independently:
```css
bar1: animation: bounce1 0.7s ease-in-out infinite alternate;
bar2: animation: bounce2 0.5s ease-in-out infinite alternate;
bar3: animation: bounce3 0.9s ease-in-out infinite alternate;
@keyframes bounce1 { from { height: 3px } to { height: 13px } }
@keyframes bounce2 { from { height: 6px } to { height: 10px } }
@keyframes bounce3 { from { height: 2px } to { height: 14px } }
```
When **paused/stopped**: all bars collapse to `height: 3px`, no animation.

### Station info
- Station name: `10px font-weight: 600`, truncated with ellipsis, `max-width: 100px`
- Genre/country: `8px color: var(--t2)`
- "change" link: `8px color: #00d9ff`, opens genre picker modal on click

### Volume slider
`width: 44px`, `accent-color: #00d9ff`, inline after "change" link.
Volume persisted to `localStorage` key `"dsc-volume"`.

### First-play behaviour
First click on Play — before any station has been selected — opens the
**Genre Picker modal** instead of attempting playback.

---

## ═══ RADIO SYSTEM ═══

### Radio Browser API
- Mirror rotation: `de1`, `de2`, `at1` `.api.radio-browser.info`
- Selected mirror chosen randomly on each fetch

### Genre Picker modal
Triggered by first Play click or "change" link. Styled:
- `background: #0d0d14`, `border: 0.5px solid rgba(0,217,255,0.22)`,
  `border-radius: 18px`, `padding: 22px`, `width: 300px`
- Title `14px font-weight: 700`, subtitle `9px uppercase tracked`
- 2-column grid of genre buttons

8 genre options:
| # | Label | Search method |
|---|-------|---------------|
| 1 | Focus mix | tags: ambient, lofi, chillout, focus, study (rotated) |
| 2 | Lo-fi beats | tag: lofi |
| 3 | Ambient | tag: ambient |
| 4 | Chillout | tag: chillout |
| 5 | Jazz | tag: jazz |
| 6 | Classical | tag: classical |
| 7 | Electronic | tags: electronic, synthwave, downtempo (rotated) |
| 8 | Taylor Swift ♥ | name search: taylor+swift, post-filter name contains both |

Taylor Swift button styling:
```css
border-color: rgba(192,132,252,0.35);
background: linear-gradient(135deg,
  rgba(123,97,255,0.10), rgba(212,83,126,0.10));
```
Heart symbol `♥` in `color: #c084fc`.

Selected genre button: `border-color: #00d9ff`, `background: rgba(0,217,255,0.07)`.

"Done" button: full width, `background: linear-gradient(135deg, #00d9ff, #00ffa3)`,
`color: #000`, `font-weight: 700`, `text-transform: uppercase`.

### Fetch strategy
```
Tag genres:
  /json/stations/search?tag=X&codec=MP3&hidebroken=true
  &order=votes&reverse=true&limit=40
  → filter out stations whose name or tags match /(talk|news|podcast|comedy)/i
  → shuffle top 12, play back-to-back

Taylor Swift:
  /json/stations/search?name=taylor+swift&codec=MP3
  &hidebroken=true&order=votes&reverse=true&limit=40
  → post-filter: name must contain "taylor" AND "swift" (case-insensitive)
  → shuffle, play back-to-back
```

### Auto-advance
- On `audio error` → next station after 350ms
- On `audio stalled` → next station after 4000ms
- On `audio ended` → next station immediately
- Queue exhausted → re-fetch and re-shuffle same genre

### SomaFM fallback
If Radio Browser API unreachable, use bundled list:
```javascript
[
  { n: "SomaFM Groove Salad",    u: "https://ice1.somafm.com/groovesalad-256-mp3" },
  { n: "SomaFM Drone Zone",      u: "https://ice1.somafm.com/dronezone-256-mp3"  },
  { n: "SomaFM Deep Space One",  u: "https://ice1.somafm.com/deepspaceone-256-mp3" },
  { n: "SomaFM Fluid",           u: "https://ice1.somafm.com/fluid-256-mp3"      }
]
```

### Persistence
- Selected genre → `localStorage` key `"dsc-genre"`
- Volume → `localStorage` key `"dsc-volume"`

---

## ═══ LIBRARY CARDS ═══

4-card responsive grid: `grid-template-columns: repeat(auto-fit, minmax(132px, 1fr))`,
`gap: 8px`.

Each card:
```css
background: var(--card);
backdrop-filter: blur(14px);
border: 0.5px solid var(--border);
border-top: 0.5px solid rgba(255,255,255,0.10);  /* top-edge light reflection */
border-radius: 14px;
padding: 15px;
transition: background 0.18s, transform 0.15s, border-color 0.2s;
```
Hover: `translateY(-3px)`, `border-color: rgba(0,217,255,0.18)`
Active: `scale(0.97)`

Card icon: 34×34px rounded rect (`border-radius: 10px`), gradient from CONFIG,
inline SVG icon inside (`15×15px`, `fill: #000`).

Card CTA row: `"Browse"` text + right-arrow SVG, `9px font-weight: 600`,
`color: #00d9ff`, `text-transform: uppercase`, `letter-spacing: 0.03em`.
Arrow `translateX(3px)` on card hover.

Icon SVGs (inline, no external icon font):
- `games` → grid of 4 squares
- `star` → 5-point star path
- `list` → 3 horizontal lines
- `code` → `</>` angle brackets path

Each card is a plain `<a href="...">` tag — the `href` comes from
`CONFIG.libraries[n].href`. Clicking navigates directly to the OD4B
shared folder URL in the same tab.

---

## ═══ RECENT ADDITIONS ═══

Below library grid. `grid-template-columns: repeat(auto-fit, minmax(165px, 1fr))`,
`gap: 6px`.

Each item: small card with a 4×4px colored dot + title + `"date · lib"` metadata.
Dot colors match the library card icon gradient start color.

---

## ═══ TECHNICAL REQUIREMENTS ═══

- **Single file**: one `index.html`, no companion CSS or JS files.
- **Zero npm / zero build**: vanilla ES2020, no frameworks, no bundler.
- **Font**: loaded via single Google Fonts `<link>` tag in `<head>`.
  Space Grotesk 300;400;500;600;700.
- **No emoji** anywhere — all icons are inline SVG paths.
- **CSS custom properties** for every color. Zero hardcoded hex values
  outside the `:root` block.
- **No `position: fixed`** — use normal flow + `position: absolute`
  within a containing block for the slide backdrop.
- **Responsive**: works at 375px mobile through 1440px desktop.
  Grid collapses gracefully. Nav music widget truncates station name
  on narrow viewports.
- **No placeholder TODOs** — deliver a complete, immediately runnable file.
- **localStorage keys used**:
  - `"dsc-theme"` → `"light"` or `"dark"`
  - `"dsc-genre"` → genre id string
  - `"dsc-volume"` → number 0–100
- **Pexels attribution**: Pexels API terms require a "Photos provided by Pexels"
  credit somewhere on the page. Add a small `8px color: var(--t3)` line in the
  footer: `Photos provided by Pexels`.
- **Error states**: if Pexels fetch fails → silent fallback to hardcoded
  Unsplash photo IDs (5 travel photos, no source.unsplash.com).
  If Radio Browser unreachable → SomaFM fallback array above.
  Page must never show a broken state.
- **Comment structure**: JS sectioned with headers:
  `// ── CONFIG ──`, `// ── THEME ──`, `// ── SLIDES ──`,
  `// ── RADIO ──`, `// ── RENDER ──`
- **`<!-- CONFIG: edit above this line -->** comment after closing brace
  of CONFIG object.

---

## ═══ DELIVERABLE ═══

One complete file: `index.html`

Immediately openable in any modern browser with no setup.
Upload to `OneDrive/Documents/Hub/index.html` and share the file link
with teammates — they click, browser renders, dark mode + travel photos
+ music all work out of the box.
