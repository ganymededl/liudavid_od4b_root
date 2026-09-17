(function () {
  "use strict";
  const M = window.ReviewModel;
  const E = window.ReviewEmail;
  const esc = window.NewsletterEmail.escapeHtml;
  const $ = selector => document.querySelector(selector);
  const key = "sled-csu-review:v2";
  let state = M.sampleState();
  let selected = "header";
  let previewWidth = 640;
  let height = 1000;
  let toastTimer;
  let previewTimer;
  let loadFailed = false;
  let pendingJump = false;
  let saveMessage = "";
  try {
    const saved = localStorage.getItem(key);
    if (saved) {
      const data = JSON.parse(saved);
      if (!M.validState(data)) throw new Error("Unrecognized draft format.");
      state = data;
    }
  } catch (error) {
    loadFailed = true;
    saveMessage = `Could not restore draft: ${error.message} Existing data is untouched; download your work or explicitly reset.`;
  }
  const frame = $("#email-preview");
  const scroll = $("#preview-scroll");
  function toast(message) {
    clearTimeout(toastTimer);
    $("#toast").textContent = message;
    $("#toast").classList.add("visible");
    toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 6500);
  }
  function save() {
    if (loadFailed) return;
    try {
      localStorage.setItem(key, JSON.stringify(state));
      saveMessage = "";
    } catch (error) { saveMessage = `Draft not saved: ${error.message} Download a draft backup to keep your work.`; }
  }
  function status() {
    $("#save-status").textContent = saveMessage ? "Not saved · back up draft" : "Saved in this browser";
    $("#save-status").classList.toggle("error", Boolean(saveMessage));
    $("#save-status").title = saveMessage;
    const issues = M.validate(state);
    const errors = issues.filter(i => i.level === "error");
    const count = M.readingWords(state);
    const estimate = Math.max(1, Math.ceil(count / 200));
    $("#reading-status").textContent = `${count} content words · ~${estimate} min at 200 wpm`;
    if (count > 400) issues.push({ section: "lead", level: "warning", message: `${count} words: aim for 400 or fewer for an approximately two-minute read. This is an estimate, not a guarantee.` });
    $("#copy-button").disabled = Boolean(errors.length);
    $("#download-button").disabled = Boolean(errors.length);
    $("#export-status").textContent = errors.length ? `${errors.length} item${errors.length === 1 ? "" : "s"} to fix before export` : "Ready to export";
    $("#editorial-checks").innerHTML = issues.length
      ? `<details${errors.length ? " open" : ""}><summary>${errors.length ? "Fix required fields" : "Editorial suggestions"} · ${issues.length}</summary><ul>${issues.map(issue => `<li><button type="button" data-jump="${issue.section}" class="${issue.level}">${esc(issue.message)}</button></li>`).join("")}</ul></details>`
      : '<p class="checks-clear">Fixed structure, valid dates, and working link formats. Confirm facts and permissions before sending.</p>';
  }
  function nav() {
    $("#edition-label").textContent = state.header.edition || "New edition";
    $("#section-nav").innerHTML = M.sections.map((section, index) => `<button type="button" class="nav-item${selected === section.id ? " active" : ""}" data-section-id="${section.id}" aria-current="${selected === section.id ? "true" : "false"}"><span class="nav-number">${String(index + 1).padStart(2, "0")}</span><span><span class="nav-title">${esc(section.title)}</span><span class="nav-subtitle">${section.required ? "Always present" : M.present(state, section.id) ? "Optional · included" : "Optional · omitted"}</span></span></button>`).join("");
  }
  function fieldHtml(field, value, scope, prefix) {
    const id = `${prefix}-${field.key}`;
    const common = `id="${id}" data-field="${field.key}" data-scope="${scope}" aria-describedby="${id}-help"`;
    let control;
    if (field.kind === "textarea") control = `<textarea ${common} rows="3">${esc(value)}</textarea>`;
    else if (field.kind === "select") control = `<select ${common}><option value="names"${value === "names" ? " selected" : ""}>Names and titles only</option><option value="portraits"${value === "portraits" ? " selected" : ""}>Small contributor portraits</option></select>`;
    else if (field.kind === "target") control = `<select ${common}>${M.sections.filter(s => s.id !== "header").map(s => `<option value="${s.id}"${s.id === value ? " selected" : ""}>${esc(s.title)}${M.present(state, s.id) ? "" : " (omitted)"}</option>`).join("")}</select>`;
    else control = `<input ${common} type="${field.kind}" value="${esc(value)}">`;
    return `<div class="field"><label class="field-label" for="${id}">${esc(field.label)}</label>${control}<span class="field-help" id="${id}-help">${esc(field.help)}</span></div>`;
  }
  function editor() {
    const info = M.sections.find(s => s.id === selected);
    const group = state[selected];
    $("#editor-content").innerHTML = `<span class="editor-type">FIXED SECTION ${M.sections.indexOf(info) + 1} / 7</span><h2 class="editor-title">${esc(info.title)}</h2><p class="editor-description">${esc(info.note)}</p>` +
      (!info.required ? `<label class="include-toggle"><input id="include-section" type="checkbox"${group.enabled ? " checked" : ""}> Include this section when it has content</label>` : "") +
      M.schemas[selected].map(f => fieldHtml(f, group[f.key], "section", `field-${selected}`)).join("") +
      (M.rowGroups[selected] || []).map(collection => `<section class="row-collection" aria-label="${esc(collection.title)}"><h3>${esc(collection.title)}</h3>${group[collection.key].map((row, index) => `<fieldset class="contributor-editor" data-collection="${collection.key}" data-row="${index}"><legend>${esc(collection.title)} ${index + 1}</legend>${M.schemas[collection.schema].map(f => fieldHtml(f, row[f.key], collection.key, `field-${collection.key}-${index}`)).join("")}<div class="row-buttons">${selected === "actions" ? '<span class="field-help">Export order: automatic by date</span>' : `<button type="button" class="icon-button" data-row-action="up" aria-label="Move row ${index + 1} up"${index === 0 ? " disabled" : ""}>↑</button><button type="button" class="icon-button" data-row-action="down" aria-label="Move row ${index + 1} down"${index === group[collection.key].length - 1 ? " disabled" : ""}>↓</button>`}<button type="button" class="delete-button" data-row-action="remove" aria-label="Remove ${esc(collection.title)} row ${index + 1}">Remove row</button></div></fieldset>`).join("")}<button class="add-section" type="button" data-add-row="${collection.key}"${collection.max && group[collection.key].length >= collection.max ? " disabled" : ""}>+ Add ${collection.schema === "people" ? "contributor" : "row"}</button></section>`).join("") +
      (selected === "actions" ? '<p class="field-help">Required items always come first. Enter ISO dates with the date picker; events with no next date appear last. Past required dates are marked relative to the issue date, not the reader’s clock.</p>' : "") +
      (selected === "header" ? '<div class="guidance"><div><strong>Keep the promise small.</strong><p>Use 3–4 teasers, including the main win and a required deadline. The next required date is also surfaced automatically below the header. The Microsoft logo is always included.</p></div></div>' : "");
  }
  function fit() {
    const style = getComputedStyle(scroll);
    const width = scroll.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    if (width <= 0) return;
    const scale = Math.min(1, width / previewWidth);
    frame.style.width = `${previewWidth}px`;
    frame.style.transform = `scale(${scale})`;
    $("#preview-frame-wrap").style.width = `${previewWidth * scale}px`;
    $("#preview-frame-wrap").style.height = `${height * scale}px`;
  }
  function measure() {
    if (!frame.contentDocument?.body) return;
    fit();
    frame.style.height = "1px";
    height = Math.max(frame.contentDocument.documentElement.scrollHeight, frame.contentDocument.body.scrollHeight);
    frame.style.height = `${height}px`;
    fit();
    if (pendingJump) { jump(selected); pendingJump = false; }
  }
  function jump(id) {
    const target = frame.contentDocument?.getElementById(id);
    if (target) scroll.scrollTop = target.getBoundingClientRect().top * ($("#preview-frame-wrap").getBoundingClientRect().width / previewWidth) + 30;
  }
  function preview() {
    const html = E.render(state);
    const size = new Blob([html]).size / 1024;
    $("#html-size").textContent = `${size.toFixed(1)} KB${size >= 95 ? " · clipping risk" : ""}`;
    $("#html-size").classList.toggle("warning", size >= 95);
    frame.srcdoc = html;
  }
  function changed(rebuild = false) {
    save();
    nav();
    if (rebuild) editor();
    status();
    clearTimeout(previewTimer);
    previewTimer = setTimeout(preview, 100);
  }
  function select(id) {
    selected = id;
    nav();
    editor();
    $(".editor-panel").scrollTop = 0;
    jump(id);
  }
  function exportHtml() {
    if (M.validate(state).some(i => i.level === "error")) { toast("Fix the required fields before exporting. Your text has not been truncated."); return null; }
    return E.render(state);
  }
  function download(content, filename, type) {
    const url = URL.createObjectURL(new Blob([content], { type }));
    const anchor = document.createElement("a");
    anchor.href = url; anchor.download = filename;
    document.body.append(anchor); anchor.click(); anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
  }
  function setMode(width) {
    previewWidth = width;
    for (const [id, value] of [["desktop-button", 640], ["mobile-button", 375]]) {
      document.getElementById(id).classList.toggle("active", value === width);
      document.getElementById(id).setAttribute("aria-pressed", String(value === width));
    }
    $("#preview-width-label").textContent = `${width} PX`;
    measure();
  }
  document.querySelectorAll("[data-icon]").forEach(element => { element.textContent = ({ copy: "▣", download: "↓", calendar: "▦", shield: "◇", desktop: "▰", mobile: "▯", sparkles: "✧", close: "×", sliders: "≡" })[element.dataset.icon] || ""; });
  $("#section-nav").addEventListener("click", event => { const button = event.target.closest("[data-section-id]"); if (button) select(button.dataset.sectionId); });
  $("#editorial-checks").addEventListener("click", event => { const button = event.target.closest("[data-jump]"); if (button) select(button.dataset.jump); });
  $("#editor-content").addEventListener("input", event => {
    if (event.target.id === "include-section") { state[selected].enabled = event.target.checked; changed(); return; }
    const input = event.target.closest("[data-field]");
    if (!input) return;
    const row = input.closest("[data-row]");
    const group = row ? state[selected][row.dataset.collection][Number(row.dataset.row)] : state[selected];
    group[input.dataset.field] = input.value;
    changed();
  });
  $("#editor-content").addEventListener("click", event => {
    const add = event.target.closest("[data-add-row]");
    if (add) {
      const collection = M.rowGroups[selected].find(c => c.key === add.dataset.addRow);
      const rows = state[selected][collection.key];
      if (collection.max && rows.length >= collection.max) { toast(`Use no more than ${collection.max} rows.`); return; }
      rows.push(M.blankRow(collection.schema));
      changed(true);
      $(`#field-${collection.key}-${rows.length - 1}-${M.schemas[collection.schema][0].key}`).focus();
    }
    const button = event.target.closest("[data-row-action]");
    if (button) {
      const fieldset = button.closest("[data-row]");
      const rows = state[selected][fieldset.dataset.collection];
      const index = Number(fieldset.dataset.row);
      if (button.dataset.rowAction === "remove") rows.splice(index, 1);
      else {
        const other = index + (button.dataset.rowAction === "up" ? -1 : 1);
        if (other < 0 || other >= rows.length) { toast("That row is already at the edge."); return; }
        [rows[index], rows[other]] = [rows[other], rows[index]];
      }
      changed(true);
      toast("Rows updated. Section order remains fixed.");
    }
  });
  $("#desktop-button").addEventListener("click", () => setMode(640));
  $("#mobile-button").addEventListener("click", () => setMode(375));
  for (const [id, show] of [["show-editor", false], ["show-preview", true]]) {
    document.getElementById(id).addEventListener("click", () => {
      $(".studio").classList.toggle("preview-active", show);
      $("#show-editor").setAttribute("aria-pressed", String(!show));
      $("#show-preview").setAttribute("aria-pressed", String(show));
      requestAnimationFrame(measure);
    });
  }
  $("#download-button").addEventListener("click", () => {
    const html = exportHtml();
    if (html) download(html, `SLED-CSU-Review-${state.header.edition.replace(/[^a-zA-Z0-9]+/g, "-") || "edition"}.html`, "text/html;charset=utf-8");
  });
  $("#copy-button").addEventListener("click", async () => {
    const html = exportHtml();
    if (!html) return;
    try { await navigator.clipboard.writeText(html); toast("Email-safe HTML copied. Use your sending platform's HTML source editor."); }
    catch { $("#copy-source").value = html; $("#copy-dialog").showModal(); $("#copy-source").focus(); $("#copy-source").select(); }
  });
  $("#backup-draft").addEventListener("click", () => download(JSON.stringify(state, null, 2), "SLED-CSU-Review-draft.json", "application/json"));
  $("#restore-draft").addEventListener("change", async event => {
    const file = event.target.files[0];
    if (!file) return;
    try {
      if (file.size > 2 * 1024 * 1024) throw new Error("Draft files must be smaller than 2 MB.");
      const restored = JSON.parse(await file.text());
      if (!M.validState(restored)) throw new Error("Use a version 2 Review draft. Classic drafts remain available in the classic editor.");
      if (!window.confirm("Replace the current Review draft with this backup?")) return;
      state = restored; selected = "header"; loadFailed = false;
      changed(true); toast("Draft restored. Review any validation messages before exporting.");
    } catch (error) { toast(`Could not restore draft: ${error.message}`); }
    finally { event.target.value = ""; }
  });
  $("#reset-button").addEventListener("click", () => $("#confirm-dialog").showModal());
  $("#confirm-reset").addEventListener("click", () => {
    state = M.sampleState(); selected = "header"; loadFailed = false;
    $("#confirm-dialog").close(); changed(true); toast("A fresh fictional Review edition is ready. Classic drafts are unchanged.");
  });
  document.querySelectorAll("[data-close-dialog]").forEach(button => button.addEventListener("click", () => document.getElementById(button.dataset.closeDialog).close()));
  frame.addEventListener("load", () => {
    measure();
    frame.contentDocument.addEventListener("click", event => {
      const anchor = event.target.closest('a[href^="#"]');
      if (anchor) { event.preventDefault(); jump(anchor.getAttribute("href").slice(1)); }
    });
  });
  new ResizeObserver(measure).observe(scroll);
  nav(); editor(); status(); preview();
  if (saveMessage) toast(saveMessage);
})();
