(function (root) {
  "use strict";
  const field = (key, label, kind = "text", help = "") => ({ key, label, kind, help });
  const sections = [
    { id: "header", title: "Header strip", note: "A promise, not a preamble. Three or four short, linked teasers.", required: true },
    { id: "scoreboard", title: "Scoreboard", note: "One table. Consistent reporting period. No photos or decorative tiles.", required: true },
    { id: "lead", title: "Lead story", note: "One customer. One headline result. Summary, background, win, next step, credit." },
    { id: "leadership", title: "Leadership take", note: "One voice, up to four sentences. Add no more than three priorities." },
    { id: "actions", title: "Deadlines & action items", note: "Required first. Optional and recurring separate. Both sort automatically.", required: true },
    { id: "community", title: "Community", note: "Names, awards, one social mention. No photo roster or extra banners." },
    { id: "signoff", title: "Sign-off", note: "A short quote and the people behind this edition.", required: true }
  ];
  const schemas = {
    header: [field("name", "Issue title"), field("edition", "Month / edition"), field("issueDate", "Issue date", "date", "Used for the due-date callout. Archived editions do not change as time passes."),
      field("bannerUrl", "Optional header image URL", "url", "Leave empty for the compact default. Use pre-cropped 1280 x 240 artwork; avoid pushing the scoreboard down."),
      field("bannerAlt", "Header image description"), field("notice", "Publication note", "textarea", "Keep the fictional-content notice for public demos. Remove only for approved real editions.")],
    scoreboard: [field("period", "Reporting period"), field("asOf", "Data as of", "date", "Make the date and basis of the scoreboard explicit.")],
    lead: [field("title", "Customer / organization — headline"), field("summary", "Summary", "textarea", "1–2 sentences. Lead with the number; distinguish forecast from realized results."),
      field("background", "Background", "textarea", "2–3 short sentences. Only context needed to understand the win."),
      field("win", "The win", "textarea", "Current status plus the next measurable milestone."),
      field("next", "What's next", "textarea", "State the next action and its owner."),
      field("credit", "Team credit", "text", "Name (role), Name (role). No repeated biography or second story.")],
    leadership: [field("author", "This month's voice"), field("role", "Title"), field("body", "Leadership take", "textarea", "At most about four sentences; do not repeat the scoreboard or lead story."),
      field("priorities", "Priorities", "textarea", "Optional. At most three short lines, one priority per line.")],
    actions: [],
    community: [field("welcome", "New hires / transfers", "text", "Name (role), Name (role). Names only."),
      field("awards", "Awards", "textarea", "One line per category: Category — Name, Name."),
      field("social", "Social / culture", "text", "One short mention; link to the details instead of pasting them."),
      field("socialUrl", "Social / culture link", "url")],
    signoff: [field("quote", "Quote", "textarea", "One brief, verified quote. Sample wording is original."),
      field("attribution", "Attribution"), field("portraitMode", "Contributor presentation", "select", "Names-only is the compact default. Small portraits are available only here.")],
    teasers: [field("text", "One-line teaser"), field("target", "Link to section", "target")],
    metrics: [field("metric", "Metric"), field("result", "Result"), field("rank", "Rank / YoY", "text", "Name the geography, comparison, or rank basis. Leave blank if unavailable.")],
    required: [field("item", "Required item"), field("date", "Due date", "date"), field("url", "Access URL", "url"), field("label", "Access link label")],
    optional: [field("event", "Event / meeting"), field("date", "Date / next occurrence", "date", "Enter the next occurrence for recurring meetings. Undated entries appear last."),
      field("time", "Start time", "time"), field("zone", "Time zone", "text", "Required when a start time is supplied; e.g. PT or UTC."),
      field("schedule", "Recurrence / duration", "text", "Optional, e.g. Monthly · 30 minutes."),
      field("location", "Location / organizer"), field("url", "Event / meeting URL", "url")],
    people: [field("name", "Name"), field("role", "Title / contribution"), field("headshot", "Portrait URL", "url", "Optional. Use a square hosted JPEG or PNG."), field("alt", "Portrait alt text")]
  };
  const rowGroups = {
    header: [{ key: "teasers", schema: "teasers", title: "In this issue", max: 4 }],
    scoreboard: [{ key: "rows", schema: "metrics", title: "KPI rows" }],
    actions: [{ key: "required", schema: "required", title: "Required by date" }, { key: "optional", schema: "optional", title: "Optional / Recurring" }],
    signoff: [{ key: "people", schema: "people", title: "Contributors this issue" }]
  };
  const lines = value => String(value || "").split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  const words = value => String(value || "").trim().split(/\s+/).filter(Boolean).length;
  function validDate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.slice(0, 4) === "0000") return false;
    const date = new Date(`${value}T00:00:00Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }
  function safeUrl(value) {
    try {
      const url = new URL(value);
      return ["https:", "http:"].includes(url.protocol) && !url.username && !url.password ? url.href : "";
    } catch { return ""; }
  }
  function sortRows(rows) {
    return rows.map((row, index) => ({ row, index })).sort((a, b) => {
      const dateA = validDate(a.row.date) ? a.row.date : "9999-99-99";
      const dateB = validDate(b.row.date) ? b.row.date : "9999-99-99";
      return dateA.localeCompare(dateB) || (a.row.time || "").localeCompare(b.row.time || "") || a.index - b.index;
    }).map(({ row }) => row);
  }
  function present(state, id) {
    if (id === "lead") return state.lead.enabled && schemas.lead.some(f => state.lead[f.key].trim());
    if (id === "leadership") return state.leadership.enabled && state.leadership.body.trim().length > 0;
    if (id === "community") return state.community.enabled && ["welcome", "awards", "social"].some(key => state.community[key].trim());
    return true;
  }
  function blankRow(schema) {
    return Object.fromEntries(schemas[schema].map(f => [f.key, f.kind === "target" ? "lead" : ""]));
  }
  function sampleState() {
    return {
      version: 2,
      header: {
        name: "THE SLED CSU REVIEW", edition: "September 2026", issueDate: "2026-09-17", bannerUrl: "", bannerAlt: "",
        notice: "PUBLIC DESIGN SAMPLE · All names, organizations, metrics, and dates are fictional.",
        teasers: [{ text: "30% faster service intake: a pilot ready to scale", target: "lead" }, { text: "Five signals from this month's scoreboard", target: "scoreboard" }, { text: "September 24: complete the readiness checklist", target: "actions" }]
      },
      scoreboard: { period: "September · illustrative results", asOf: "2026-09-16", rows: [
        { metric: "Adoption target", result: "112%", rank: "+8 pts YoY" },
        { metric: "Pilot milestones", result: "9 of 10", rank: "+2 vs. last month" },
        { metric: "Customer engagement", result: "86%", rank: "+5 pts YoY" },
        { metric: "New reference stories", result: "4", rank: "Quarter to date" },
        { metric: "Service satisfaction", result: "4.7 / 5", rank: "42 responses" }
      ] },
      lead: { enabled: true, title: "Cedar Valley — less waiting, more serving",
        summary: "30% faster intake in a four-week pilot gives Cedar Valley a practical path to expand resident services.",
        background: "Staff were re-entering the same requests across disconnected queues. The team chose one high-volume workflow and agreed on a baseline before changing it.",
        win: "The pilot now routes requests to the right owner automatically. Two departments are ready for the next rollout.",
        next: "Taylor will confirm the expansion plan and accessibility review by September 28.",
        credit: "Taylor Morgan (CSAM), Alex Rivera (CSA)" },
      leadership: { enabled: true, author: "Jordan Lee", role: "Customer Success Leader",
        body: "Our next step is to turn isolated wins into repeatable habits. Bring one customer outcome and one unresolved blocker to your next review. Ask for help while there is still time to act.",
        priorities: "Validate the next milestone with its owner.\nReuse the pilot checklist before expanding.\nClose the loop on customer feedback." },
      actions: {
        required: [{ item: "Quarter readiness checklist", date: "2026-09-24", url: "https://example.com/readiness", label: "Open checklist" }, { item: "Learning plan confirmation", date: "2026-09-30", url: "https://example.com/learning", label: "Review plan" }],
        optional: [{ event: "Customer discovery workshop", date: "2026-09-22", time: "10:00", zone: "PT", schedule: "45 minutes", location: "Online · Morgan Ellis", url: "https://example.com/workshop" }, { event: "Solution exchange", date: "2026-09-25", time: "09:00", zone: "PT", schedule: "Monthly · 30 minutes", location: "Online · Alex Rivera", url: "https://example.com/exchange" }]
      },
      community: { enabled: true, welcome: "Casey Nguyen (CSA), Drew Wallace (CSAM)", awards: "Customer impact — Jamie Patel, Sam Bennett", social: "Share one photo from this month's team walk.", socialUrl: "https://example.com/community" },
      signoff: { quote: "Make the next step clear, and the next win becomes possible.", attribution: "The sample editorial team", portraitMode: "names",
        people: ["Morgan Ellis", "Taylor Morgan", "Alex Rivera", "Jamie Patel"].map((name, index) => ({
          name, role: ["Editor", "Customer stories", "Technical review", "Production"][index],
          headshot: `https://ganymededl.github.io/liudavid_od4b_root/demos-public/newsletter-studio/assets/contributor-${index + 1}.jpg`,
          alt: `Illustrated mock portrait for fictional contributor ${name}`
        }))
      }
    };
  }
  function validState(state) {
    if (!state || state.version !== 2) return false;
    for (const section of sections) {
      const group = state[section.id];
      if (!group || !schemas[section.id].every(f => typeof group[f.key] === "string")) return false;
      if (!section.required && typeof group.enabled !== "boolean") return false;
      for (const collection of rowGroups[section.id] || []) {
        if (!Array.isArray(group[collection.key]) || !group[collection.key].every(row => row && schemas[collection.schema].every(f => typeof row[f.key] === "string"))) return false;
      }
    }
    return ["names", "portraits"].includes(state.signoff.portraitMode);
  }
  function validate(state) {
    if (!validState(state)) return [{ level: "error", section: "header", message: "Draft format is invalid. Restore a valid version 2 draft." }];
    const issues = [];
    const add = (section, message, level = "error") => issues.push({ section, message, level });
    const need = (section, value, message) => { if (!value.trim()) add(section, message); };
    need("header", state.header.name, "Enter an issue title.");
    need("header", state.header.edition, "Enter the month / edition.");
    if (!validDate(state.header.issueDate)) add("header", "Enter a valid issue date.");
    if (state.header.teasers.length < 3 || state.header.teasers.length > 4) add("header", "Use three or four teasers.");
    for (const teaser of state.header.teasers) {
      need("header", teaser.text, "Every teaser needs text.");
      if (!sections.some(s => s.id === teaser.target && s.id !== "header")) add("header", "Choose a valid teaser destination.");
      else if (!present(state, teaser.target)) add("header", "A teaser points to an omitted section. Change its destination or remove the teaser.");
      if (words(teaser.text) > 16) add("header", "Shorten teasers to about 16 words each.", "warning");
    }
    if (state.header.bannerUrl.trim()) {
      add("header", "A header image adds scroll. The compact, image-free header is recommended.", "warning");
      need("header", state.header.bannerAlt, "Describe the header image for readers with images blocked.");
    }
    need("scoreboard", state.scoreboard.period, "Enter a reporting period.");
    if (!validDate(state.scoreboard.asOf)) add("scoreboard", "Enter a valid scoreboard as-of date.");
    if (!state.scoreboard.rows.length) add("scoreboard", "The scoreboard requires at least one KPI.");
    state.scoreboard.rows.forEach(row => {
      need("scoreboard", row.metric, "Each KPI needs a metric name.");
      need("scoreboard", row.result, "Each KPI needs a result; use 'Pending' if not yet confirmed.");
      if (words(`${row.metric} ${row.result} ${row.rank}`) > 20) add("scoreboard", "Keep each KPI row to one short line.", "warning");
    });
    if (state.scoreboard.rows.length > 8) add("scoreboard", "More than eight KPIs weakens the scan. Keep the most decision-relevant measures.", "warning");
    if (present(state, "lead")) {
      schemas.lead.forEach(f => need("lead", state.lead[f.key], `Complete the lead story's ${f.label.toLowerCase()} field.`));
      if (words(Object.values(state.lead).filter(v => typeof v === "string").join(" ")) > 180) add("lead", "Aim for 180 words or fewer across the lead story.", "warning");
    }
    if (present(state, "leadership")) {
      need("leadership", state.leadership.author, "Name the single leadership voice.");
      need("leadership", state.leadership.role, "Enter the leadership title.");
      if (lines(state.leadership.priorities).length > 3) add("leadership", "Leadership priorities are limited to three lines. Edit them; nothing is silently truncated.");
      const sentences = state.leadership.body.match(/[^.!?]+[.!?]+|[^.!?]+$/g) || [];
      if (sentences.length > 4 || words(state.leadership.body) > 90) add("leadership", "Trim the leadership take to about four sentences / 90 words.", "warning");
    }
    for (const row of state.actions.required) {
      need("actions", row.item, "Every required row needs an item.");
      if (!validDate(row.date)) add("actions", "Every required item needs a valid due date.");
      need("actions", row.url, "Every required item needs an access URL.");
      if (validDate(row.date) && validDate(state.header.issueDate) && row.date < state.header.issueDate) add("actions", `${row.item || "Required item"} is overdue as of this issue. Confirm it still belongs.`, "warning");
    }
    for (const row of state.actions.optional) {
      need("actions", row.event, "Every optional row needs an event name.");
      need("actions", row.location, "Every optional row needs a location or organizer.");
      if (row.date && !validDate(row.date)) add("actions", "Optional event dates must be valid dates or empty.");
      if (!row.date) add("actions", "An optional/recurring event has no next date; it will appear last as 'Date to confirm'.", "warning");
      if (row.time && !/^([01]\d|2[0-3]):[0-5]\d$/.test(row.time)) add("actions", "Use a valid 24-hour start time.");
      if (row.time && !row.zone.trim()) add("actions", "Include a time zone for every start time.");
    }
    if (present(state, "community") && words(`${state.community.welcome} ${state.community.awards} ${state.community.social}`) > 80) add("community", "Keep community to about 80 words; link out for details.", "warning");
    need("signoff", state.signoff.quote, "Add a short sign-off quote.");
    need("signoff", state.signoff.attribution, "Attribute the sign-off quote.");
    if (!state.signoff.people.length) add("signoff", "Credit at least one contributor.");
    state.signoff.people.forEach(person => { need("signoff", person.name, "Every contributor needs a name."); need("signoff", person.role, "Every contributor needs a title or contribution."); });
    for (const section of sections) {
      if (!present(state, section.id)) continue;
      const groups = [{ value: state[section.id], schema: schemas[section.id] }, ...(rowGroups[section.id] || []).flatMap(c => state[section.id][c.key].map(value => ({ value, schema: schemas[c.schema] })))];
      groups.forEach(({ value, schema }) => schema.filter(f => f.kind === "url").forEach(f => {
        if (section.id === "signoff" && f.key === "headshot" && state.signoff.portraitMode !== "portraits") return;
        if (value[f.key].trim() && !safeUrl(value[f.key])) add(section.id, `${f.label} must be a complete HTTP(S) URL without embedded credentials.`);
      }));
    }
    return issues;
  }
  function readingWords(state) {
    // Count reader-visible copy, not URLs, hidden portraits, or omitted sections.
    const text = [state.header.name, state.header.edition, state.header.notice, ...state.header.teasers.map(t => t.text),
      state.scoreboard.period, ...state.scoreboard.rows.flatMap(r => [r.metric, r.result, r.rank]),
      ...state.actions.required.flatMap(r => [r.item, r.date, r.label]),
      ...state.actions.optional.flatMap(r => [r.event, r.date, r.time, r.zone, r.schedule, r.location]),
      state.signoff.quote, state.signoff.attribution, ...state.signoff.people.flatMap(p => [p.name, p.role])];
    for (const id of ["lead", "leadership", "community"]) if (present(state, id)) text.push(...schemas[id].filter(f => f.kind !== "url").map(f => state[id][f.key]));
    return words(text.join(" "));
  }
  const api = { sections, schemas, rowGroups, sampleState, blankRow, validState, validate, validDate, sortRows, safeUrl, present, lines, words, readingWords };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ReviewModel = api;
})(typeof window !== "undefined" ? window : globalThis);
