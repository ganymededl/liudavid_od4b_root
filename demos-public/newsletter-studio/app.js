(function () {
  "use strict";

  const NewsletterEmail = typeof module !== "undefined" && module.exports ? require("./email.js") : window.NewsletterEmail;
  const $ = selector => document.querySelector(selector);
  const esc = NewsletterEmail.escapeHtml;
  const STORAGE_KEY = "impact-newsletter-studio:v1";
  const bannerDefaults = {
    bannerMode: "photo",
    bannerUrl: "https://images.unsplash.com/photo-1522071820081-009f0129c71c?fm=jpg&fit=crop&w=1280&h=480&q=85",
    bannerAlt: "Stock photograph of people collaborating around a table; not the CSU team",
    bannerCaption: "People. Purpose. Possibility.",
    bannerShape: "wide"
  };
  const icons = {
    copy: '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V4a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h4"/>',
    download: '<path d="M12 3v12m-4-4 4 4 4-4M4 16v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M16 3v4M8 3v4M3 11h18m-12 5h.01M13 16h.01"/>',
    shield: '<path d="m12 3 8 3v5c0 5-4 8-8 10-4-2-8-5-8-10V6l8-3Z"/><path d="m8 12 3 3 5-6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    sliders: '<path d="M4 6h7m5 0h4M4 12h2m5 0h9M4 18h10m5 0h1"/><circle cx="13.5" cy="6" r="2.5"/><circle cx="8.5" cy="12" r="2.5"/><circle cx="16.5" cy="18" r="2.5"/>',
    desktop: '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M12 17v4m-4 0h8"/>',
    mobile: '<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>',
    sparkles: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Zm7-2v4m-2-2h4"/>',
    masthead: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 10h18M7 15h10m-10 3h6"/>',
    toc: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    leadership: '<path d="M18 21H6a3 3 0 0 1-3-3v-1a5 5 0 0 1 5-5h8a5 5 0 0 1 5 5v1a3 3 0 0 1-3 3Z"/><circle cx="12" cy="5" r="4"/>',
    interview: '<path d="M21 11a8 8 0 0 1-8 8H8l-5 3 1-6a8 8 0 1 1 17-5Z"/><path d="M8 10h8M8 14h5"/>',
    success: '<path d="m3 17 6-6 4 4 8-11m-6 0h6v6M3 21h18"/>',
    practice: '<path d="m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1 3-6Z"/>',
    tip: '<path d="M9 18v-2a7 7 0 1 1 6 0v2M9 18h6m-6 3h6M12 5v2"/>',
    footer: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 6 10 7L22 6"/>',
    up: '<path d="m6 14 6-6 6 6"/>',
    down: '<path d="m6 10 6 6 6-6"/>',
    trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>'
  };
  function icon(name) {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.masthead}</svg>`;
  }
  function fillIcons(container = document) {
    container.querySelectorAll("[data-icon]").forEach(element => { element.innerHTML = icon(element.dataset.icon); });
  }
  const typeInfo = {
    leadership: { label: "Leadership message", eyebrow: "FROM THE DESK OF", description: "Set the tone with a personal note and a few priorities worth remembering.", short: "A voice. A vision. A way forward." },
    interview: { label: "Feature / interview", eyebrow: "IN CONVERSATION", description: "Bring a perspective to life with thoughtful questions, candid answers, and one standout quote.", short: "Good questions. Great perspectives." },
    success: { label: "Success story", eyebrow: "SUCCESS STORY", description: "Turn a customer win into a story the whole team can learn from.", short: "Customer wins worth sharing." },
    practice: { label: "Best practice", eyebrow: "BEST PRACTICE", description: "Share an approach that worked, the results it delivered, and how to repeat it.", short: "What works. And how to repeat it." },
    tip: { label: "Tip of the month", eyebrow: "TIP OF THE MONTH", description: "Make the next great idea easy to try, with practical steps and ready-to-use prompts.", short: "A little advice. A lot of possibility." }
  };
  const F = (key, label, kind = "text", help = "", optional = false) => ({ key, label, kind, help, optional });
  const storyFields = [
    F("title", "Story headline"), F("customer", "Customer name"), F("team", "CSU team", "text", "Include the CSAM and CSA names."),
    F("opportunity", "The opportunity", "textarea"), F("solution", "Solution / approach", "textarea"),
    F("outcomes", "Outcomes / results", "textarea", "One bullet per line. Bullet markers are added for you."),
    F("stats", "Stat callouts", "textarea", "Up to 4, one per line: value | label", true),
    F("quote", "Customer pull quote", "textarea", "No quotation marks needed.", true),
    F("tip", "Take it to your customer", "textarea")
  ];
  const schemas = {
    masthead: [F("name", "Newsletter name"), F("edition", "Edition / month"), F("tagline", "Tagline", "textarea", "A little line with a lot of personality.", true),
      F("bannerMode", "Banner treatment", "select", "Keep the live-text masthead, then add your own people-focused photo or artwork."),
      F("bannerUrl", "Banner image URL", "url", "Paste a direct, publicly accessible JPEG/PNG URL. The sample is a stock team photo, not CSU staff.", true),
      F("bannerShape", "Banner proportions", "select", "Crop before hosting: 1280 × 480 px (wide) or 1280 × 640 px (cinematic). Outlook cannot reliably crop images."),
      F("bannerAlt", "Banner alt text", "text", "Describe the people or scene for readers with images blocked."),
      F("bannerCaption", "Banner caption", "text", "A short editorial line beneath the image.", true)],
    leadership: [F("title", "Section headline"), F("author", "Author name"), F("role", "Author title"), F("headshot", "Headshot URL", "url", "Use a publicly accessible HTTPS image. Renders at 64 × 64 px.", true), F("body", "Leadership message", "textarea", "Separate paragraphs with a blank line."), F("highlights", "This month’s highlights", "textarea", "Aim for 2–4 highlights, one per line.")],
    interview: [F("title", "Feature headline"), F("series", "Series name"), F("byline", "Byline(s)"), F("body", "Introduction", "textarea"), F("exchanges", "Questions & answers", "textarea", "Start each question with Q: and answer with A:. Answers can span multiple lines."), F("quote", "Highlighted answer / pull quote", "textarea", "Copy your favorite answer here. Quotation marks are added automatically.", true), F("closing", "Continues next edition", "textarea")],
    success: storyFields,
    practice: storyFields,
    tip: [F("title", "Tip headline"), F("body", "Introduction", "textarea"), F("listStyle", "List style", "select"), F("items", "Tips / steps", "textarea", "One item per line. Numbers or bullets are added for you."), F("prompts", "Try this prompt", "textarea", "Separate multiple prompt boxes with a blank line.", true)],
    footer: [F("title", "Closing headline"), F("body", "The ask", "textarea"), F("contactName", "Contact name"), F("email", "Contact email", "email", "A valid address enables the email feedback button."), F("tagline", "Closing mantra", "textarea")],
    contributors: [F("title", "Section headline"), F("body", "A note of thanks", "textarea")],
    person: [F("name", "Contributor name"), F("role", "Contribution / role"), F("headshot", "Headshot JPEG URL", "url", "Use a direct hosted image URL. Crop to a square (at least 176 × 176 px).", true), F("alt", "Headshot alt text", "text", "Leave blank to use the contributor's name.", true)]
  };
  const selectOptions = {
    listStyle: [["numbered", "Numbered list"], ["bulleted", "Bulleted list"]],
    bannerMode: [["photo", "Photo / custom artwork + IMPACT masthead"], ["none", "Original gradient masthead only"]],
    bannerShape: [["wide", "Wide editorial · 8:3"], ["cinematic", "Cinematic · 2:1"]]
  };
  function samplePerson(index = 0) {
    return {
      name: `Contributor ${index + 1}`,
      role: ["Editorial lead", "Customer stories", "Technical insights", "Design & production"][index % 4],
      headshot: `https://ganymededl.github.io/liudavid_od4b_root/demos-public/newsletter-studio/assets/contributor-${index % 4 + 1}.jpg`,
      alt: `Illustrated mock JPEG portrait for contributor ${index + 1}; not a real team member`
    };
  }
  function sampleContributors() {
    return { title: "Made possible by our people.", body: "A special thank-you to the storytellers, collaborators, and curious minds who brought this edition to life.", people: Array.from({ length: 4 }, (_, index) => samplePerson(index)) };
  }
  function migrateDraft(data) {
    if (!data || typeof data !== "object") return data;
    if (data.masthead && typeof data.masthead === "object") {
      for (const [key, value] of Object.entries(bannerDefaults)) {
        if (data.masthead[key] === undefined) data.masthead[key] = value;
      }
    }
    if (data.contributors === undefined) data.contributors = sampleContributors();
    return data;
  }
  function sampleSection(type) {
    const samples = {
      leadership: {
        title: "A new season. A shared ambition.", author: "Jordan Lee", role: "General Manager, US SLED Customer Success",
        headshot: "https://placehold.co/128x128/EDE8F5/6A4C93.png?text=JL",
        body: "Team,\n\nThe best part of a new season isn’t the fresh calendar. It’s the possibility of what we can build together. Across SLED, your work is helping communities serve residents better, educators reach more students, and customers turn big ideas into real outcomes.\n\nThis month, we’re celebrating the small steps that lead to meaningful change: a thoughtful customer conversation, a reusable solution, and a teammate willing to share what they’ve learned. Thank you for bringing that energy every day.",
        highlights: "Lead with the mission. Connect every technical milestone to the people it serves.\nMake AI practical. Start with one measurable, responsible use case.\nShare the learning. Your next great idea could be another team’s starting point."
      },
      interview: {
        title: "The human side of customer success", series: "Beyond the Blueprint · Part 01", byline: "In conversation with Avery Brooks · Interview by Morgan Ellis",
        body: "Behind every successful deployment is a conversation that changed the direction. In our new interview series, we’re meeting the people who make those conversations count.",
        exchanges: "Q: What’s the first question you ask a new customer?\nA: What would a genuinely better day look like for your team? It helps us move beyond a product conversation and understand the work that really matters.\n\nQ: How do you turn that answer into a plan?\nA: We choose one outcome, agree on how we’ll measure it, and build a small proof point together. Progress creates trust much faster than a long roadmap.\n\nQ: What advice would you share with a new teammate?\nA: Stay curious a little longer. The most useful insight often comes just after the question you almost didn’t ask.",
        quote: "Progress creates trust much faster than a long roadmap.",
        closing: "Next edition: Avery shares a practical framework for turning discovery into a shared success plan."
      },
      success: {
        title: "Small automation. Outsized impact.", customer: "Cedar Valley County (fictional)", team: "CSAM: Taylor Morgan · CSA: Alex Rivera",
        opportunity: "A lean county IT team was spending hours each week manually reviewing service requests, leaving less time for work that directly supports residents.",
        solution: "The CSU team helped build an Azure-based workflow that classifies requests, routes them to the right owner, and surfaces a simple operational dashboard. A focused pilot proved the approach before a wider rollout.",
        outcomes: "Reduced manual triage time by 40% in the pilot.\nGave service owners a shared view of request status.\nCreated a repeatable blueprint for two additional departments.",
        stats: "40% | less manual triage\n$3K/mo | projected Azure ACR", quote: "Less time moving requests means more time helping the people behind them.",
        tip: "Look for a high-volume process with clear handoffs. A two-week workflow pilot can turn an everyday friction point into a measurable win."
      },
      practice: {
        title: "A better blueprint for cloud confidence", customer: "Pinecrest Public Schools (fictional)", team: "CSAM: Riley Chen · CSA: Jamie Patel",
        opportunity: "The district’s cloud adoption was growing, but ownership, cost visibility, and security reviews varied across teams.",
        solution: "The team introduced a lightweight landing-zone review, standard resource tags, and a monthly cost conversation. A shared checklist made the work repeatable without adding a new layer of process.",
        outcomes: "Established clear owners for all pilot subscriptions.\nImproved cost visibility across instructional workloads.\nDocumented a review checklist other districts can adapt.",
        stats: "100% | pilot subscriptions tagged\n4 teams | one shared checklist", quote: "A shared checklist gave us the confidence to move forward together.",
        tip: "Bring a simple ownership-and-tagging checklist to your next cloud review. Start with one subscription, show the benefit, then scale."
      },
      tip: {
        title: "Make your next Copilot prompt count", body: "A great prompt is a clear brief. Give Copilot the context, the goal, and the shape of a useful answer — then make it a conversation.", listStyle: "numbered",
        items: "Start with the outcome: explain what you’re trying to accomplish and who it’s for.\nAdd the right context: reference approved files or meeting notes you’re authorized to use.\nSpecify the format: ask for a short table, an action list, or a customer-ready summary.\nReview and refine: verify facts and citations before sharing.",
        prompts: "Using my selected meeting notes, draft a follow-up email with three agreed next steps, an owner for each, and any open questions. Flag missing details rather than guessing.\n\nHelp me prepare for a customer success review. From the documents I select, summarize progress against our goals and suggest three questions to explore next."
      }
    };
    return { id: newId(), type, ...samples[type] };
  }
  function newId() {
    return "s-" + (globalThis.crypto?.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + "-" + Math.random().toString(36).slice(2));
  }
  function sampleState() {
    const firstStory = sampleSection("success");
    const secondStory = { ...sampleSection("success"), title: "More time for the student experience", customer: "Lakeshore State University (fictional)", team: "CSAM: Casey Nguyen · CSA: Sam Bennett", opportunity: "Student services staff were navigating disconnected knowledge sources to answer routine questions during peak enrollment.", solution: "A scoped Azure AI Search pilot connected approved public-facing resources and tested grounded answers with a small staff cohort. The team kept human review and clear source citations at the center.", outcomes: "Validated answers against an agreed evaluation set.\nReduced the time staff spent searching for routine information.\nEstablished a responsible AI review before expansion.", stats: "30% | faster information lookup\n3 teams | in the initial pilot", quote: "Better access to trusted information helps us focus on the student in front of us.", tip: "Start with a well-maintained knowledge source, a narrow audience, and a measurable quality bar. Evaluate the answers before expanding access." };
    const thirdStory = { ...sampleSection("success"), title: "Modernizing with the mission in mind", customer: "Summit Regional Transit (fictional)", team: "CSAM: Drew Wallace · CSA: Quinn Parker", opportunity: "An aging reporting environment made it difficult to combine operational data and deliver timely views to transit planners.", solution: "The team mapped priority reports, established a governed data foundation, and piloted a modern analytics workflow with the operations group.", outcomes: "Replaced a manual weekly reporting process with a scheduled pipeline.\nAligned planners around a shared set of service metrics.\nBuilt a phased migration plan based on pilot findings.", stats: "12 hrs | saved each week\n600K/yr | records in the pilot", quote: "We’re spending less time assembling reports and more time understanding what they tell us.", tip: "Ask which recurring report takes the most effort to assemble. It can be an ideal starting point for a focused analytics modernization conversation." };
    return {
      masthead: { name: "IMPACT", edition: "September 2026", tagline: "Real stories. Shared expertise. Extraordinary impact.", ...bannerDefaults },
      contributors: sampleContributors(),
      sections: [sampleSection("leadership"), firstStory, secondStory, thirdStory, sampleSection("practice"), sampleSection("interview"), sampleSection("tip")],
      footer: { title: "Help us make it better.", body: "Great stories deserve to be shared. Have a customer win, a lesson learned, or a tip the team should know? We’d love to hear from you.", contactName: "Morgan Ellis", email: "impact-editor@example.com", tagline: "One team. Shared purpose. Lasting IMPACT." }
    };
  }
  function validDraft(value) {
    if (!value || typeof value !== "object" || !Array.isArray(value.sections)) return false;
    const validGroup = (group, schema) => group && schema.every(field => typeof group[field.key] === "string");
    if (!validGroup(value.masthead, schemas.masthead) || !validGroup(value.footer, schemas.footer)) return false;
    if (!selectOptions.bannerMode.some(([key]) => key === value.masthead.bannerMode) || !selectOptions.bannerShape.some(([key]) => key === value.masthead.bannerShape)) return false;
    if (!validGroup(value.contributors, schemas.contributors) || !Array.isArray(value.contributors.people) || !value.contributors.people.every(person => validGroup(person, schemas.person))) return false;
    const ids = new Set();
    return value.sections.every(section => {
      if (!section || !typeInfo[section.type] || typeof section.id !== "string" || !/^s-[a-zA-Z0-9-]+$/.test(section.id) || ids.has(section.id)) return false;
      ids.add(section.id);
      return validGroup(section, schemas[section.type]) && (section.type !== "tip" || ["numbered", "bulleted"].includes(section.listStyle));
    });
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { sampleState };
    return;
  }

  let startupMessage = "";
  let storageAvailable = true;
  let state;
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      if (parsed.version !== 1 || !validDraft(migrateDraft(parsed.data))) throw new Error("Saved edition has an unsupported format.");
      state = parsed.data;
    }
  } catch (error) {
    storageAvailable = false;
    startupMessage = `Couldn’t restore your saved edition: ${error.message} The sample is shown; the previous saved data has not been changed.`;
  }
  if (!state) state = sampleState();

  let selected = "masthead";
  let previewMode = "desktop";
  let previewTimer;
  let toastTimer;
  let previewHtml = "";
  let naturalHeight = 1000;
  let pendingJump = null;
  const frame = $("#email-preview");
  const previewScroll = $("#preview-scroll");

  function toast(message) {
    clearTimeout(toastTimer);
    $("#toast").textContent = message;
    $("#toast").classList.add("visible");
    toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 6000);
  }
  function save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ version: 1, data: state }));
      storageAvailable = true;
      $("#save-status").classList.remove("error");
      $("#save-status").innerHTML = '<span class="status-dot"></span>All changes saved';
    } catch (error) {
      if (storageAvailable) toast(`Your browser couldn’t save this draft (${error.message}). Download the HTML to keep your work.`);
      storageAvailable = false;
      $("#save-status").classList.add("error");
      $("#save-status").innerHTML = '<span class="status-dot"></span>Not saved · download to keep';
    }
  }
  function currentGroup() {
    return ["masthead", "footer", "contributors"].includes(selected) ? state[selected] : state.sections.find(section => section.id === selected);
  }
  function renderNav() {
    const navItem = (id, title, subtitle, iconName, trailing = "") => `<button type="button" class="nav-item${selected === id ? " active" : ""}" data-section-id="${esc(id)}" aria-current="${selected === id ? "true" : "false"}" title="${esc(title)}">${icon(iconName)}<span><span class="nav-title">${esc(title)}</span>${subtitle ? `<span class="nav-subtitle">${esc(subtitle)}</span>` : ""}</span>${trailing}</button>`;
    $("#section-nav").innerHTML = navItem("masthead", "Masthead", "Your first impression", "masthead") +
      navItem("toc", "Table of contents", "", "toc", '<span class="auto-badge">AUTO</span>') +
      '<div class="nav-separator"></div>' +
      state.sections.map((section, index) => navItem(section.id, section.title || "Untitled section", typeInfo[section.type].label, section.type, `<span class="nav-number">${String(index + 1).padStart(2, "0")}</span>`)).join("") +
      '<div class="nav-separator"></div>' + navItem("contributors", "The contributors", `${state.contributors.people.length} faces behind the edition`, "leadership") + navItem("footer", "The closing note", "Feedback & footer", "footer");
    $("#section-count").textContent = `${state.sections.length} section${state.sections.length === 1 ? "" : "s"}`;
    $("#edition-label").textContent = state.masthead.edition || "Untitled edition";
  }
  function renderField(field, group, prefix = "") {
    const value = group[field.key] || "";
    const common = `id="field-${prefix}${field.key}" data-field="${field.key}" aria-describedby="help-${prefix}${field.key}"`;
    let control;
    if (field.kind === "textarea") control = `<textarea ${common} rows="${field.key === "exchanges" || field.key === "body" ? 7 : 3}">${esc(value)}</textarea>`;
    else if (field.kind === "select") control = `<select ${common}>${selectOptions[field.key].map(([key, label]) => `<option value="${key}"${value === key ? " selected" : ""}>${label}</option>`).join("")}</select>`;
    else control = `<input ${common} type="${field.kind}" value="${esc(value)}"${field.kind === "url" || field.kind === "email" ? ' spellcheck="false"' : ""}>`;
    return `<div class="field"><label for="field-${prefix}${field.key}" class="field-label">${field.label}${field.optional ? '<span class="optional-label">Optional</span>' : ""}</label>${control}<span class="field-help" id="help-${prefix}${field.key}">${esc(field.help)}</span></div>`;
  }
  function guidance(title, body) {
    return `<div class="guidance">${icon("sparkles")}<div><strong>${esc(title)}</strong><p>${esc(body)}</p></div></div>`;
  }
  function renderEditor() {
    const content = $("#editor-content");
    if (selected === "contributors") {
      content.innerHTML = '<span class="editor-type">THE PEOPLE BEHIND THE IMPACT</span><h2 class="editor-title">Give your people the spotlight.</h2><p class="editor-description">A dedicated thank-you at the bottom of every edition. Replace these JPEG placeholders with your team’s headshots when the lineup is ready.</p>' +
        schemas.contributors.map(field => renderField(field, state.contributors)).join("") +
        state.contributors.people.map((person, index) => `<fieldset class="contributor-editor" data-person-index="${index}"><legend>CONTRIBUTOR ${String(index + 1).padStart(2, "0")}</legend>${schemas.person.map(field => renderField(field, person, `person-${index}-`)).join("")}<div class="section-actions"><button class="icon-button" type="button" data-person-action="up" aria-label="Move contributor ${index + 1} up"${index === 0 ? " disabled" : ""}>${icon("up")}</button><button class="icon-button" type="button" data-person-action="down" aria-label="Move contributor ${index + 1} down"${index === state.contributors.people.length - 1 ? " disabled" : ""}>${icon("down")}</button><button class="delete-button" type="button" data-person-action="remove">${icon("trash")}Remove contributor ${index + 1}</button></div></fieldset>`).join("") +
        '<button class="add-section" id="add-contributor" type="button">+ Add a contributor</button>' +
        guidance("A human touch, without fragile layouts", "Four portraits per desktop row, stacked on mobile. Names remain live text when images are blocked. Removing every contributor hides this section.") +
        guidance("Use hosted photos, not sharing-page links", "Add JPEGs to your approved email asset library, then paste their direct URLs. Nothing is uploaded by this app. Local files, base64 images, and sign-in-protected SharePoint links are not reliable in email.");
      validateFields();
      return;
    }
    if (selected === "toc") {
      content.innerHTML = '<span class="editor-type">THE BIG PICTURE</span><h2 class="editor-title">An index. On autopilot.</h2><p class="editor-description">Your section headlines become a clickable, numbered index. Add, remove, or reorder a story and this list takes care of itself.</p>' +
        `<div class="index-preview">${state.sections.map((s, i) => `<div class="index-item"><span>${String(i + 1).padStart(2, "0")}</span>${esc(s.title || "Untitled section")}</div>`).join("") || '<p class="editor-description">Add your first section to start the index.</p>'}</div>` +
        guidance("A quick note on jump links", "Most web and Apple Mail clients support them. Some Outlook and Gmail versions don’t navigate within a message; your index remains readable.");
      return;
    }
    const group = currentGroup();
    const type = selected === "masthead" || selected === "footer" ? selected : group.type;
    const info = type === "masthead" ? { eyebrow: "START HERE", label: "Set the scene.", description: "A bold opening for the stories that matter. Make this edition unmistakably yours." } :
      type === "footer" ? { eyebrow: "THE LAST WORD", label: "Keep the conversation going.", description: "Close with a clear invitation. Give your readers a way to contribute to the next edition." } : typeInfo[type];
    content.innerHTML = `<span class="editor-type">${info.eyebrow}</span><h2 class="editor-title">${info.label}</h2><p class="editor-description">${info.description}</p>` +
      schemas[type].map(field => renderField(field, group)).join("") +
      (type === "masthead" ? '<div class="banner-presets"><button type="button" class="button secondary" id="sample-banner">Use sample people banner</button><button type="button" class="text-button" id="clear-banner">Remove banner image</button></div>' + guidance("Your banner, not an image-only email", "Paste a different hosted banner URL above. The stock people photo is a visual stand-in, not your team. Use approved artwork; keep names, edition, and tagline as live text. Local files and base64 images are intentionally excluded for Outlook reliability.") : "") +
      (type === "masthead" ? `<div class="editor-divider"></div><div class="theme-heading"><h3>Your signature look</h3><span>IMPACT ORIGINAL</span></div><div class="theme-preview"><div class="theme-band"><strong>IMPACT</strong><span>THE MONTHLY EDIT</span></div><div class="theme-colors"><span class="swatch" style="background:#0078d4"></span><span class="swatch" style="background:#5b2c87"></span><span class="swatch" style="background:#f3bc62"></span><span class="swatch" style="background:#f1eff7"></span><span>Built-in brand palette</span></div></div>${guidance("Designed for the inbox", "Email-safe tables and Outlook fallbacks, with a little extra polish for modern clients. The preview shows the actual exported HTML.")}${guidance("A sample, not a case study", "All people, customers, metrics, and contact details in this sample edition are fictional. Replace them with approved content before sending.")}` : "") +
      (group.type ? `<div class="section-actions"><button class="icon-button" type="button" id="move-up" aria-label="Move section up"${state.sections.indexOf(group) === 0 ? " disabled" : ""}>${icon("up")}</button><button class="icon-button" type="button" id="move-down" aria-label="Move section down"${state.sections.indexOf(group) === state.sections.length - 1 ? " disabled" : ""}>${icon("down")}</button><button class="delete-button" id="remove-section" type="button">${icon("trash")}Remove section</button></div>` : "");
    validateFields();
  }
  function validateFields() {
    if (selected === "toc") return;
    const group = currentGroup();
    const emailInput = $("#field-email");
    if (emailInput) setFieldValidity(emailInput, !group.email || Boolean(NewsletterEmail.emailAddress(group.email)), "Enter a valid email address. The feedback button is hidden until this is valid.", schemas.footer.find(f => f.key === "email").help);
    document.querySelectorAll('#editor-content input[data-field="headshot"], #field-bannerUrl').forEach(input => {
      const valid = !input.value.trim() || Boolean(NewsletterEmail.safeImage(input.value));
      const schema = input.dataset.field === "bannerUrl" ? schemas.masthead : selected === "contributors" ? schemas.person : schemas.leadership;
      setFieldValidity(input, valid, "Use a complete HTTP(S) image URL. This image is omitted until the URL is valid.", schema.find(f => f.key === input.dataset.field).help);
    });
    const statsInput = $("#field-stats");
    if (statsInput) {
      const count = group.stats.split(/\r?\n/).filter(x => x.trim()).length;
      setFieldValidity(statsInput, count <= 4, "Only the first 4 stat callouts are exported. Use outcomes for additional metrics.", "Up to 4, one per line: value | label");
    }
  }
  function setFieldValidity(input, valid, message, normalHelp) {
    input.closest(".field").classList.toggle("field-invalid", !valid);
    input.setAttribute("aria-invalid", String(!valid));
    document.getElementById(input.getAttribute("aria-describedby")).textContent = valid ? normalHelp : message;
  }
  function fitPreview() {
    const width = previewMode === "mobile" ? 375 : 640;
    const style = getComputedStyle(previewScroll);
    const available = previewScroll.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    if (available <= 0) return;
    const scale = Math.min(1, available / width);
    frame.style.width = `${width}px`;
    frame.style.transform = `scale(${scale})`;
    $("#preview-frame-wrap").style.width = `${width * scale}px`;
    $("#preview-frame-wrap").style.height = `${naturalHeight * scale}px`;
    $(".preview-size-label").style.maxWidth = `${width * scale}px`;
  }
  function measurePreview() {
    if (!frame.contentDocument?.body) return;
    fitPreview();
    frame.style.height = "1px";
    naturalHeight = Math.max(frame.contentDocument.body.scrollHeight, frame.contentDocument.documentElement.scrollHeight);
    frame.style.height = `${naturalHeight}px`;
    fitPreview();
    if (pendingJump) {
      jumpToSection(pendingJump);
      pendingJump = null;
    }
  }
  function jumpToSection(id) {
    const doc = frame.contentDocument;
    if (!doc?.body) return;
    let target;
    if (id === "masthead") { previewScroll.scrollTop = 0; return; }
    if (id === "toc") target = doc.querySelector('td[bgcolor="#F5F7FB"]');
    else if (id === "footer") target = doc.querySelector('td[bgcolor="#ECEAF5"]');
    else if (id === "contributors") target = doc.getElementById("contributors");
    else {
      const index = state.sections.findIndex(s => s.id === id);
      if (index >= 0) target = doc.getElementById(NewsletterEmail.sectionAnchor(state.sections[index], index));
    }
    if (target) {
      const scale = $("#preview-frame-wrap").getBoundingClientRect().width / (previewMode === "mobile" ? 375 : 640);
      previewScroll.scrollTop = target.getBoundingClientRect().top * scale + 30;
    }
  }
  function refreshPreview() {
    clearTimeout(previewTimer);
    previewHtml = NewsletterEmail.render(state);
    const bytes = new Blob([previewHtml]).size;
    $("#html-size").textContent = `${(bytes / 1024).toFixed(1)} KB${bytes >= 95 * 1024 ? " · clipping risk" : ""}`;
    $("#html-size").classList.toggle("warning", bytes >= 95 * 1024);
    $("#html-size").title = "Gmail may clip messages around 102 KB. Send-platform additions can increase the final size.";
    frame.srcdoc = previewHtml;
  }
  function changed({ rebuild = false, jump = false } = {}) {
    save();
    renderNav();
    if (rebuild) renderEditor();
    if (jump) pendingJump = selected;
    clearTimeout(previewTimer);
    previewTimer = setTimeout(refreshPreview, 120);
  }
  function selectSection(id) {
    selected = id;
    renderNav();
    renderEditor();
    $(".editor-panel").scrollTop = 0;
    jumpToSection(id);
  }
  function moveSection(direction) {
    const index = state.sections.findIndex(s => s.id === selected);
    const nextIndex = index + direction;
    if (index < 0 || nextIndex < 0 || nextIndex >= state.sections.length) return;
    const [section] = state.sections.splice(index, 1);
    state.sections.splice(nextIndex, 0, section);
    changed({ rebuild: true, jump: true });
    const focusTarget = direction < 0 ? $("#move-up") : $("#move-down");
    if (focusTarget && !focusTarget.disabled) focusTarget.focus();
    toast("Section moved. Your index is up to date.");
  }
  function setDevice(mode) {
    previewMode = mode;
    $("#desktop-button").classList.toggle("active", mode === "desktop");
    $("#mobile-button").classList.toggle("active", mode === "mobile");
    $("#desktop-button").setAttribute("aria-pressed", String(mode === "desktop"));
    $("#mobile-button").setAttribute("aria-pressed", String(mode === "mobile"));
    $("#preview-width-label").textContent = mode === "desktop" ? "640 PX" : "375 PX";
    measurePreview();
  }
  function showPane(preview) {
    $(".studio").classList.toggle("preview-active", preview);
    $("#show-editor").setAttribute("aria-pressed", String(!preview));
    $("#show-preview").setAttribute("aria-pressed", String(preview));
    if (preview) requestAnimationFrame(measurePreview);
  }
  function exportHtml() {
    const html = NewsletterEmail.render(state);
    return html;
  }

  fillIcons();
  $("#section-type-options").innerHTML = Object.entries(typeInfo).map(([type, info]) => `<button type="button" class="type-option" data-add-type="${type}">${icon(type)}<span><strong>${info.label}</strong><small>${info.short}</small></span></button>`).join("");
  $("#section-nav").addEventListener("click", event => {
    const button = event.target.closest("[data-section-id]");
    if (button) selectSection(button.dataset.sectionId);
  });
  $("#editor-content").addEventListener("input", event => {
    const input = event.target.closest("[data-field]");
    if (!input) return;
    const personEditor = input.closest("[data-person-index]");
    const group = personEditor ? state.contributors.people[Number(personEditor.dataset.personIndex)] : currentGroup();
    group[input.dataset.field] = input.value;
    if (selected === "masthead" && input.dataset.field === "bannerShape") {
      const sampleCinematic = bannerDefaults.bannerUrl.replace("h=480", "h=640");
      if ([bannerDefaults.bannerUrl, sampleCinematic].includes(group.bannerUrl)) {
        group.bannerUrl = input.value === "cinematic" ? sampleCinematic : bannerDefaults.bannerUrl;
        $("#field-bannerUrl").value = group.bannerUrl;
      }
    }
    validateFields();
    changed();
  });
  $("#editor-content").addEventListener("click", event => {
    if (event.target.closest("#sample-banner")) {
      Object.assign(state.masthead, bannerDefaults);
      changed({ rebuild: true, jump: true });
      toast("Sample people banner restored. Replace it with approved team artwork before sending.");
    }
    if (event.target.closest("#clear-banner")) {
      state.masthead.bannerMode = "none";
      state.masthead.bannerUrl = "";
      changed({ rebuild: true, jump: true });
    }
    if (event.target.closest("#add-contributor")) {
      const index = state.contributors.people.length;
      state.contributors.people.push(samplePerson(index));
      changed({ rebuild: true, jump: true });
      $(`#field-person-${index}-name`).focus();
      toast("Contributor added with a JPEG placeholder.");
    }
    const personAction = event.target.closest("[data-person-action]");
    if (personAction) {
      const index = Number(personAction.closest("[data-person-index]").dataset.personIndex);
      const action = personAction.dataset.personAction;
      if (action === "remove") state.contributors.people.splice(index, 1);
      else {
        const next = index + (action === "up" ? -1 : 1);
        if (next < 0 || next >= state.contributors.people.length) return;
        [state.contributors.people[index], state.contributors.people[next]] = [state.contributors.people[next], state.contributors.people[index]];
      }
      changed({ rebuild: true, jump: true });
      toast(action === "remove" ? "Contributor removed." : "Contributor order updated.");
    }
    if (event.target.closest("#move-up")) moveSection(-1);
    if (event.target.closest("#move-down")) moveSection(1);
    if (event.target.closest("#remove-section")) {
      const index = state.sections.findIndex(s => s.id === selected);
      state.sections.splice(index, 1);
      selected = state.sections[Math.min(index, state.sections.length - 1)]?.id || "masthead";
      changed({ rebuild: true, jump: true });
      toast("Section removed. Your index is up to date.");
    }
  });
  $("#add-section-button").addEventListener("click", () => $("#add-dialog").showModal());
  $("#section-type-options").addEventListener("click", event => {
    const button = event.target.closest("[data-add-type]");
    if (!button) return;
    const section = sampleSection(button.dataset.addType);
    state.sections.push(section);
    selected = section.id;
    $("#add-dialog").close();
    showPane(false);
    changed({ rebuild: true, jump: true });
    $(".editor-panel").scrollTop = 0;
    $("#field-title").focus();
    toast(`${typeInfo[section.type].label} added. Make it yours.`);
  });
  document.querySelectorAll("[data-close-dialog]").forEach(button => button.addEventListener("click", () => document.getElementById(button.dataset.closeDialog).close()));
  $("#reset-button").addEventListener("click", () => $("#confirm-dialog").showModal());
  $("#confirm-reset").addEventListener("click", () => {
    state = sampleState();
    selected = "masthead";
    $("#confirm-dialog").close();
    changed({ rebuild: true, jump: true });
    toast("A fresh sample edition is ready.");
  });
  $("#desktop-button").addEventListener("click", () => setDevice("desktop"));
  $("#mobile-button").addEventListener("click", () => setDevice("mobile"));
  $("#show-editor").addEventListener("click", () => showPane(false));
  $("#show-preview").addEventListener("click", () => showPane(true));
  $("#copy-button").addEventListener("click", async () => {
    const html = exportHtml();
    try {
      if (!navigator.clipboard?.writeText) throw new Error("Clipboard unavailable.");
      await navigator.clipboard.writeText(html);
      toast("Email HTML copied. Paste it into your sending platform’s HTML editor.");
    } catch {
      $("#copy-source").value = html;
      $("#copy-dialog").showModal();
      $("#copy-source").focus();
      $("#copy-source").select();
    }
  });
  $("#download-button").addEventListener("click", () => {
    const html = exportHtml();
    const url = URL.createObjectURL(new Blob([html], { type: "text/html;charset=utf-8" }));
    const link = document.createElement("a");
    const edition = state.masthead.edition.trim().replace(/[^a-zA-Z0-9]+/g, "-").replace(/^-|-$/g, "");
    link.href = url;
    link.download = `IMPACT-${edition || "newsletter"}.html`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
    toast("Your newsletter HTML is ready to send through an HTML-capable platform.");
  });
  frame.addEventListener("load", () => {
    measurePreview();
    // Handle anchors in the tall iframe by scrolling the outer preview canvas.
    frame.contentDocument?.addEventListener("click", event => {
      const anchor = event.target.closest('a[href^="#"]');
      if (!anchor) return;
      event.preventDefault();
      const target = frame.contentDocument.getElementById(anchor.getAttribute("href").slice(1));
      if (!target) return;
      const scale = $("#preview-frame-wrap").getBoundingClientRect().width / (previewMode === "mobile" ? 375 : 640);
      previewScroll.scrollTop = target.getBoundingClientRect().top * scale + 30;
    });
  });
  new ResizeObserver(() => measurePreview()).observe(previewScroll);
  renderNav();
  renderEditor();
  refreshPreview();
  if (startupMessage) {
    $("#save-status").classList.add("error");
    $("#save-status").innerHTML = '<span class="status-dot"></span>Couldn’t restore draft';
    toast(startupMessage);
  } else save();
})();
