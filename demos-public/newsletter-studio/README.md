# The SLED CSU Review — Newsletter Studio

Open `index.html` to populate a fixed monthly Review and export email-safe HTML. No install, account, or backend is needed. `sample.html` is the complete fictional example.

## Seven sections, one editorial hierarchy

| Section | Fixed shape |
| --- | --- |
| Header strip | Issue title, edition, 3–4 linked teasers, Microsoft logo. An automatically derived next-required/overdue callout surfaces action early. |
| Scoreboard | Metric / Result / Rank or YoY. Add or remove rows, not columns. Reporting period and as-of date are required. No images. |
| Lead story | One headline plus Summary, Background, The win, What's next, Team credit. Omit the whole section if there is no lead. |
| Leadership take | One author/title and a short message, with at most three priority lines. Optional. |
| Deadlines & action items | Required: Item / Due date / Access link. Optional/recurring: Event / Date and time / Location or organizer. Sorted within each group. |
| Community | Names-only welcome, award lines by category, one social mention/link. Optional. No headshots or decorative banners. |
| Sign-off | Short quote and attribution; contributor names and titles. Optional small contributor portraits only here. |

There are no add-section or reorder-section controls in the Review. Optional sections can be unchecked or left empty; headings disappear from the output. Their saved content is retained. Update teasers that point to omitted sections before exporting.

Required structural errors block Copy HTML and Download HTML rather than truncating text or discarding rows. Editorial suggestions are non-blocking: shorten leadership to about four sentences/90 words, the lead to 180 words, community to 80 words, and the edition to around 400 words. The displayed reading estimate uses 200 words per minute and is not a reading-speed guarantee.

## Dates, actions, and facts

Use the date pickers for unambiguous dates. Required items need a real due date and an access URL. Optional events may be undated (displayed last as "Date to confirm"); for recurring events, provide the next occurrence and describe the recurrence. Events on the same date sort by their entered local start time. Include a time-zone label with any start time; cross-zone times are not converted. Equal sort keys keep their original row order.

The header callout and overdue labels use the **issue date**, not the viewer's current date. Archived editions therefore remain stable. Empty action groups state that no items are listed; required sections are not padded with fictional deadlines.

Use explicit rank geography and comparison periods. Distinguish forecast upside from realized revenue; do not combine them. Use the correct metric name and scale (for example, a five-point satisfaction score is not NPS). Verify quote attribution, numerical claims, deadline applicability, and links before sending.

## Branding, images, and compatibility

The default is a compact blue-purple header with the official Microsoft logo. Optional header artwork is still supported, but adds scroll and receives an editorial warning. Pre-crop it to 1280 x 240 px. Contributor portraits use hosted square images; the sample JPEGs are original illustrations, not real staff photographs. Names-only sign-off is the compact default.

The email uses presentation tables, inline fallbacks, real accessible data tables, and a 640 px Outlook wrapper. The header gradient has conditional VML; mobile styles reduce padding without changing the three-column data-table shape. Text wraps on narrow screens instead of hiding columns. Portrait rounding and gradients are enhancements. Dark-mode styles are basic protections, not a guarantee against every client's forced inversion. Internal jump links vary by mail client.

The preview is actual output HTML but not an Outlook Word-engine emulator. Use an HTML-capable sending platform or approved Outlook insertion workflow; normal Outlook compose does not accept pasted HTML source. Remote images can be blocked. No image or document upload takes place. Drafts remain in this browser.

## Draft preservation and classic editor

Review drafts use a new storage key, `sled-csu-review:v2`. Existing flexible IMPACT drafts remain untouched under their original key and are accessible through **Open classic editor / previous drafts** (`legacy.html`). They are not automatically squeezed into the new structure because that would discard content.

**Back up draft** downloads editable JSON, including incomplete work. **Restore draft JSON** accepts a version 2 Review backup after confirmation; HTML exports are not editable draft backups. If a stored draft is unreadable, the app preserves it and does not overwrite it until an explicit reset or restore.

The classic editor continues to use `app.js` and `email.js`. The Review uses `review-model.js` (schema, defaults, validation, sorting), `review-email.js` (renderer), and `review-app.js` / `review.css` (editor). `email.js` supplies shared HTML escaping.

## Sample and maintenance

The public sample uses fictional names, metrics, dates, and customer stories, never source newsletter attachments or a browser's saved draft. Keep the publication note for public demos. Remove it only for an approved real edition.

```sh
node build-sample.cjs
node review.test.cjs
```

`make-portraits.ps1` regenerates four original JPEG illustrations using Windows System.Drawing. The official logo is hosted by Microsoft; default contributor illustrations are hosted with the public demo. Replace default image URLs if moving to another deployment.

## Editorial decisions

The critique's core point is hierarchy, not removing culture. The compact scoreboard communicates performance; the single larger lead headline communicates significance; short actions and community lines make everything else scannable. A separate large illustration for each section would reintroduce the problem.

The supplied order places the full deadlines section fifth. The automatic header callout makes the most urgent required item visible immediately without violating that order. Further refinements worth considering: an owner within each action's item text, a linked full-story archive rather than adding secondary stories, and a recurring monthly KPI definition checklist. Avoid automatically summing unrelated KPIs or treating estimated opportunity values as attained results.
